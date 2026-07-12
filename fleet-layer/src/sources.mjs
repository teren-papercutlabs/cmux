import { parseJsonStdout, run } from './command.mjs';

export const SESSION_SQL = `
WITH open_lifecycle AS (
  SELECT
    l.session_id,
    l.parent_session_id,
    l.originated_by,
    l.root_persistent_id,
    l.state,
    l.state_changed_at,
    l.created_at,
    s.agent_name AS direct_agent,
    s.tmux_session,
    s.session_tag,
    s.session_type,
    s.runtime,
    s.last_activity_at,
    COALESCE(root.agent_name, parent.agent_name, origin.agent_name, s.agent_name) AS owner_agent,
    latest_signal.status AS signal_status,
    COALESCE(latest_signal.needs_reply, false) AS signal_needs_reply,
    latest_signal.summary AS signal_summary,
    latest_signal.created_at AS signal_created_at,
    latest_token.account_name,
    latest_token.runtime AS account_runtime,
    latest_token.captured_at AS account_captured_at
  FROM dev.session_lifecycle l
  JOIN public.sessions s ON s.id = l.session_id AND s.ended_at IS NULL
  LEFT JOIN public.sessions root ON root.id = l.root_persistent_id
  LEFT JOIN public.sessions parent ON parent.id = l.parent_session_id
  LEFT JOIN public.sessions origin ON origin.id = l.originated_by
  LEFT JOIN LATERAL (
    SELECT sig.status, sig.needs_reply, sig.summary, sig.created_at
    FROM dev.session_signals sig
    WHERE sig.session_id = l.session_id
    ORDER BY sig.created_at DESC
    LIMIT 1
  ) latest_signal ON true
  LEFT JOIN LATERAL (
    SELECT ste.account_name, ste.runtime, ste.captured_at
    FROM dev.session_token_events ste
    WHERE ste.session_id = l.session_id AND ste.account_name IS NOT NULL
    ORDER BY ste.captured_at DESC
    LIMIT 1
  ) latest_token ON true
  WHERE l.state <> 'exited'
)
SELECT * FROM open_lifecycle
ORDER BY owner_agent NULLS LAST, state_changed_at DESC`;

function unwrapData(value) {
  return value && Object.hasOwn(value, 'data') ? value.data : value;
}

export function parseAgentRoster(stdout) {
  const agents = [];
  for (const line of stdout.split(/\r?\n/)) {
    const parts = line.split('|').map((part) => part.trim());
    if (parts.length !== 5 || parts[0] === 'ID' || parts[0].startsWith('-')) continue;
    const [id, name, , runtime, active] = parts;
    if (!id || active.toLowerCase() !== 'yes') continue;
    agents.push({ id, name, runtime, active: true });
  }
  if (agents.length === 0) throw new Error('pcl agents list contained no active agent rows');
  return agents;
}

export function parseQuota(stdout) {
  const rows = [];
  const pattern = /^\s*(\S+)\s+5h\s+([0-9.]+)%\s+7d\s+([0-9.]+)%/;
  for (const line of stdout.split(/\r?\n/)) {
    const match = line.match(pattern);
    if (!match) continue;
    rows.push({
      key: match[1],
      fiveHourUsed: Number(match[2]),
      weeklyUsed: Number(match[3]),
    });
  }
  if (rows.length === 0) throw new Error('pcl burn quota contained no quota rows');
  return rows;
}

export function parseAuth(stdout) {
  const rows = [];
  const pattern = /^\s*(?:codex\/)?([\w/-]+)\s+\[([^\]]+)\]/;
  for (const line of stdout.split(/\r?\n/)) {
    const match = line.match(pattern);
    if (match) rows.push({ account: match[1], status: match[2].trim() });
  }
  return rows;
}

export class LiveSources {
  constructor(options = {}) {
    this.run = options.run ?? run;
    // PcL's resident CLI families can serialize behind live fleet work. A
    // 15-second cap false-failed three healthy sources together during the
    // final Studio smoke. Keep the poll non-overlapping, but allow one bounded
    // collection up to 30 seconds before declaring it stale.
    this.timeoutMs = options.timeoutMs ?? 30_000;
  }

  async collect() {
    const startedAt = new Date().toISOString();
    const specs = {
      roster: ['pcl', ['agents', 'list']],
      sessions: ['marshal', ['db', 'query', '--sql', SESSION_SQL]],
      loops: ['pcl', ['loop', 'list', '--status', 'active']],
      quota: ['pcl', ['burn', 'quota']],
      auth: ['pcl', ['auth', 'claude', 'status']],
    };
    const entries = await Promise.all(Object.entries(specs).map(async ([name, [command, args]]) => {
      try {
        const result = await this.run(command, args, { timeoutMs: this.timeoutMs });
        return [name, { ok: true, result }];
      } catch (error) {
        return [name, { ok: false, error }];
      }
    }));
    const raw = Object.fromEntries(entries);

    const required = ['roster', 'sessions', 'loops', 'quota'];
    const failedRequired = required.filter((name) => !raw[name].ok);
    if (failedRequired.length) {
      const detail = failedRequired.map((name) => `${name}: ${raw[name].error.message}`).join('; ');
      throw new Error(`required fleet sources failed: ${detail}`);
    }

    const sessionJson = parseJsonStdout(raw.sessions.result, 'marshal db query');
    const loopJson = parseJsonStdout(raw.loops.result, 'pcl loop list');
    return {
      collectedAt: new Date().toISOString(),
      startedAt,
      // `pcl agents list` currently renders its human table on stderr even on
      // exit 0. Keep marshal DB JSON strictly stdout-only; accept the roster's
      // documented live table from whichever stream actually carries it.
      roster: parseAgentRoster(raw.roster.result.stdout || raw.roster.result.stderr),
      sessions: unwrapData(sessionJson),
      loops: unwrapData(loopJson),
      quota: parseQuota(raw.quota.result.stdout || raw.quota.result.stderr),
      auth: raw.auth.ok ? parseAuth(raw.auth.result.stdout || raw.auth.result.stderr) : [],
      warnings: Object.entries(raw)
        .filter(([, value]) => !value.ok)
        .map(([name, value]) => `${name}: ${value.error.message}`),
    };
  }
}
