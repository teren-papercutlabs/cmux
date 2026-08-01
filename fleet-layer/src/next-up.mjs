function text(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function dateMs(value) {
  const parsed = Date.parse(value ?? '');
  return Number.isFinite(parsed) ? parsed : null;
}

function priorityRank(value) {
  if (value === '1A') return 0;
  if (value === '1B') return 1;
  return 2;
}

function specificMachineWhy(agent) {
  const summary = text(agent.attention?.summary);
  if (!summary) return null;
  return { label: 'needs you', confidence: 1, line: summary };
}

export class MachineStateWhyProvider {
  provide() {
    return {
      label: 'uncertain',
      confidence: 0,
      line: 'Machine state needs review',
    };
  }
}

export function resolveNextUp(snapshot, options = {}) {
  if (snapshot?.schemaVersion !== 1 || !Array.isArray(snapshot?.agents)) {
    throw new Error('unsupported or invalid fleet snapshot');
  }
  const now = options.now instanceof Date ? options.now : new Date();
  const nowMs = now.getTime();
  const priorityBySessionId = options.priorityBySessionId ?? {};
  const whyProvider = options.whyProvider ?? new MachineStateWhyProvider();

  const items = snapshot.agents
    .filter((agent) => agent.status === 'needs-you' && agent.attention?.sessionId)
    .map((agent) => {
      const machineWhy = specificMachineWhy(agent);
      const why = machineWhy ?? whyProvider.provide({ agent, snapshot });
      const createdAtMs = dateMs(agent.attention.createdAt);
      const waitSeconds = createdAtMs !== null
        ? Math.max(0, Math.floor((nowMs - createdAtMs) / 1000))
        : 0;
      return {
        agentId: agent.id,
        agentName: agent.name,
        sessionId: agent.attention.sessionId,
        jumpSessionId: agent.jump?.sessionId ?? null,
        tmuxSession: agent.jump?.tmuxSession ?? null,
        priority: priorityBySessionId[agent.attention.sessionId]
          ?? priorityBySessionId[agent.jump?.sessionId]
          ?? null,
        classification: why.confidence > 0 ? 'actionable' : 'uncertain',
        why,
        waitingSince: agent.attention.createdAt ?? null,
        waitSeconds,
      };
    });

  items.sort((left, right) =>
    priorityRank(left.priority) - priorityRank(right.priority)
    || (dateMs(left.waitingSince) ?? Number.POSITIVE_INFINITY)
      - (dateMs(right.waitingSince) ?? Number.POSITIVE_INFINITY)
    || left.agentId.localeCompare(right.agentId));

  return {
    schemaVersion: 1,
    collectedAt: snapshot.collectedAt,
    items,
    processingCount: snapshot.agents.filter((agent) => agent.status === 'running').length,
    idleCount: snapshot.agents.filter((agent) => agent.status === 'idle').length,
  };
}
