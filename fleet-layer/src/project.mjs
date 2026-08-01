function text(value) {
  return typeof value === 'string' ? value : '';
}

function dateMs(value) {
  const parsed = Date.parse(value ?? '');
  return Number.isFinite(parsed) ? parsed : 0;
}

function normalizeRuntime(value) {
  const runtime = text(value).toLowerCase();
  if (runtime === 'claude') return 'cc';
  return runtime;
}

function quotaFor(row, quotaRows) {
  if (!row?.accountName) return null;
  const runtime = normalizeRuntime(row.accountRuntime || row.runtime);
  const account = row.accountName.replace(/^codex\//, '');
  const candidates = runtime === 'codex'
    ? [`codex/codex/${account}`, `codex/${account}`]
    : [`cc/${account}`];
  const match = quotaRows.find((quota) => candidates.includes(quota.key));
  if (!match) return null;
  const headroom = Math.max(0, 100 - Math.max(match.fiveHourUsed, match.weeklyUsed));
  return { ...match, headroom };
}

function normalizeSession(raw) {
  return {
    sessionId: text(raw.session_id ?? raw.sessionId),
    ownerAgent: text(raw.owner_agent ?? raw.ownerAgent),
    directAgent: text(raw.direct_agent ?? raw.directAgent),
    parentSessionId: text(raw.parent_session_id ?? raw.parentSessionId),
    originatedBy: text(raw.originated_by ?? raw.originatedBy),
    rootPersistentId: text(raw.root_persistent_id ?? raw.rootPersistentId),
    state: text(raw.state),
    stateChangedAt: raw.state_changed_at ?? raw.stateChangedAt ?? null,
    lastActivityAt: raw.last_activity_at ?? raw.lastActivityAt ?? null,
    tmuxSession: text(raw.tmux_session ?? raw.tmuxSession),
    sessionTag: text(raw.session_tag ?? raw.sessionTag),
    sessionType: text(raw.session_type ?? raw.sessionType),
    runtime: normalizeRuntime(raw.runtime),
    signalStatus: text(raw.signal_status ?? raw.signalStatus),
    signalNeedsReply: Boolean(raw.signal_needs_reply ?? raw.signalNeedsReply),
    signalSummary: text(raw.signal_summary ?? raw.signalSummary),
    signalCreatedAt: raw.signal_created_at ?? raw.signalCreatedAt ?? null,
    accountName: text(raw.account_name ?? raw.accountName),
    accountRuntime: normalizeRuntime(raw.account_runtime ?? raw.accountRuntime),
    accountCapturedAt: raw.account_captured_at ?? raw.accountCapturedAt ?? null,
  };
}

function targetSessionIds(loop) {
  const ids = new Set();
  const walk = (value) => {
    if (!value || typeof value !== 'object') return;
    for (const [key, nested] of Object.entries(value)) {
      if (['targetSessionId', 'target_session_id', 'sessionId', 'session_id'].includes(key)
          && typeof nested === 'string') ids.add(nested);
      else walk(nested);
    }
  };
  walk(loop);
  return ids;
}

function jumpScore(session) {
  if (!session.tmuxSession) return -1;
  let score = 0;
  if (session.sessionTag.startsWith('telegram:dm:')) score += 1000;
  if (session.sessionType === 'persistent-channel') score += 500;
  if (session.state === 'working') score += 100;
  score += Math.min(dateMs(session.lastActivityAt) / 1e12, 99);
  return score;
}

function accountScore(session) {
  if (!session.accountName) return 0;
  return dateMs(session.accountCapturedAt);
}

export function buildFleetSnapshot(input, options = {}) {
  const nearWallHeadroom = options.nearWallHeadroom
    ?? Number(process.env.PCL_FLEET_NEAR_WALL_HEADROOM ?? 15);
  const sessions = input.sessions.map(normalizeSession).filter((session) => session.ownerAgent);
  const sessionOwners = new Map(sessions.map((session) => [session.sessionId, session.ownerAgent]));
  const autonomousOwners = new Set();
  for (const loop of input.loops ?? []) {
    for (const id of targetSessionIds(loop)) {
      const owner = sessionOwners.get(id);
      if (owner) autonomousOwners.add(owner);
    }
  }

  const agents = input.roster.map((rosterAgent) => {
    const owned = sessions.filter((session) => session.ownerAgent === rosterAgent.id);
    const needsReply = owned
      .filter((session) => session.signalNeedsReply)
      .sort((a, b) => dateMs(b.signalCreatedAt) - dateMs(a.signalCreatedAt))[0];
    const hasWorking = owned.some((session) => session.state === 'working');
    const status = needsReply ? 'needs-you' : hasWorking ? 'running' : 'idle';
    const jumpTarget = owned.slice().sort((a, b) => jumpScore(b) - jumpScore(a))[0];
    const accountSource = owned.slice().sort((a, b) => accountScore(b) - accountScore(a))[0];
    const quota = quotaFor(accountSource, input.quota);
    const autonomous = autonomousOwners.has(rosterAgent.id);
    return {
      id: rosterAgent.id,
      name: rosterAgent.name,
      runtime: rosterAgent.runtime,
      status,
      autonomous,
      ownedSessionCount: owned.length,
      jump: jumpTarget && jumpScore(jumpTarget) >= 0 ? {
        sessionId: jumpTarget.sessionId,
        tmuxSession: jumpTarget.tmuxSession,
      } : null,
      attention: needsReply ? {
        sessionId: needsReply.sessionId,
        status: needsReply.signalStatus,
        summary: needsReply.signalSummary,
        createdAt: needsReply.signalCreatedAt,
      } : null,
      quota: quota ? {
        account: quota.key,
        fiveHourUsed: quota.fiveHourUsed,
        weeklyUsed: quota.weeklyUsed,
        headroom: quota.headroom,
        nearWall: quota.headroom <= nearWallHeadroom,
      } : null,
    };
  });

  const rank = { 'needs-you': 0, running: 1, idle: 2 };
  agents.sort((a, b) => rank[a.status] - rank[b.status] || a.id.localeCompare(b.id));
  const counts = {
    total: agents.length,
    autonomous: agents.filter((agent) => agent.autonomous).length,
    needsYou: agents.filter((agent) => agent.status === 'needs-you').length,
    running: agents.filter((agent) => agent.status === 'running').length,
    idle: agents.filter((agent) => agent.status === 'idle').length,
    nearWall: agents.filter((agent) => agent.quota?.nearWall).length,
  };
  counts.autonomousPercent = counts.total
    ? Math.round((counts.autonomous / counts.total) * 100)
    : 0;

  return {
    schemaVersion: 1,
    collectedAt: input.collectedAt,
    counts,
    agents,
    warnings: input.warnings ?? [],
  };
}

export function assertSnapshot(snapshot) {
  if (snapshot.schemaVersion !== 1) throw new Error('unsupported fleet snapshot schema');
  if (!Array.isArray(snapshot.agents) || snapshot.agents.length === 0) {
    throw new Error('fleet snapshot has no active agents');
  }
  const countSum = snapshot.counts.needsYou + snapshot.counts.running + snapshot.counts.idle;
  if (countSum !== snapshot.counts.total || snapshot.counts.total !== snapshot.agents.length) {
    throw new Error('fleet status counts are internally inconsistent');
  }
  const autonomy = snapshot.agents.filter((agent) => agent.autonomous).length;
  if (autonomy !== snapshot.counts.autonomous) {
    throw new Error('fleet autonomy count is internally inconsistent');
  }
  return snapshot;
}
