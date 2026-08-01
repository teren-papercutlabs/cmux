import assert from 'node:assert/strict';
import test from 'node:test';
import {
  MachineStateWhyProvider,
  resolveNextUp,
} from '../src/next-up.mjs';

const collectedAt = '2026-08-01T06:00:00.000Z';

function agent({
  id,
  status = 'needs-you',
  createdAt,
  summary = 'decision required',
  jumpSessionId,
}) {
  return {
    id,
    name: id[0].toUpperCase() + id.slice(1),
    status,
    jump: jumpSessionId ? { sessionId: jumpSessionId, tmuxSession: `${id}-tmux` } : null,
    attention: createdAt ? {
      sessionId: jumpSessionId ?? `${id}-session`,
      status: 'question',
      summary,
      createdAt,
    } : null,
  };
}

test('recommends needs-you only, then uses priority and oldest wait as tiebreakers', () => {
  const snapshot = {
    schemaVersion: 1,
    collectedAt,
    counts: { total: 5, needsYou: 4, running: 1, idle: 0 },
    agents: [
      agent({ id: 'running', status: 'running', jumpSessionId: 'running-session' }),
      agent({ id: 'oldest', createdAt: '2026-08-01T05:20:00.000Z', jumpSessionId: 'oldest-session' }),
      agent({ id: 'lead', createdAt: '2026-08-01T05:58:00.000Z', jumpSessionId: 'lead-session' }),
      agent({ id: 'understudy', createdAt: '2026-08-01T05:10:00.000Z', jumpSessionId: 'understudy-session' }),
      agent({ id: 'unranked', createdAt: '2026-08-01T05:30:00.000Z', jumpSessionId: 'unranked-session' }),
    ],
  };

  const result = resolveNextUp(snapshot, {
    now: new Date(collectedAt),
    priorityBySessionId: {
      'lead-session': '1A',
      'understudy-session': '1B',
    },
  });

  assert.deepEqual(result.items.map((item) => item.agentId), [
    'lead', 'understudy', 'oldest', 'unranked',
  ]);
  assert.equal(result.items[0].priority, '1A');
  assert.equal(result.items[0].jumpSessionId, 'lead-session');
  assert.equal(result.items[0].why.label, 'needs you');
  assert.match(result.items[0].why.line, /decision required/i);
  assert.equal(result.items[0].waitSeconds, 120);
  assert.equal(result.processingCount, 1);
  assert.equal(result.items.some((item) => item.agentId === 'running'), false);
});

test('never recommends processing or ranked-only sessions', () => {
  const result = resolveNextUp({
    schemaVersion: 1,
    collectedAt,
    counts: { total: 2, needsYou: 0, running: 1, idle: 1 },
    agents: [
      agent({ id: 'lead', status: 'running', jumpSessionId: 'lead-session' }),
      agent({ id: 'idle', status: 'idle', jumpSessionId: 'idle-session' }),
    ],
  }, {
    now: new Date(collectedAt),
    priorityBySessionId: { 'lead-session': '1A' },
  });

  assert.deepEqual(result.items, []);
  assert.equal(result.processingCount, 1);
  assert.equal(result.idleCount, 1);
});

test('renders an ambiguous needs-you record as uncertain without an LLM call', () => {
  const whyProvider = new MachineStateWhyProvider();
  const result = resolveNextUp({
    schemaVersion: 1,
    collectedAt,
    counts: { total: 1, needsYou: 1, running: 0, idle: 0 },
    agents: [agent({
      id: 'ambiguous',
      createdAt: '2026-08-01T05:59:00.000Z',
      summary: '',
      jumpSessionId: 'ambiguous-session',
    })],
  }, { now: new Date(collectedAt), whyProvider });

  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].classification, 'uncertain');
  assert.equal(result.items[0].why.label, 'uncertain');
  assert.equal(result.items[0].why.confidence, 0);
  assert.match(result.items[0].why.line, /machine state needs review/i);
});

test('classifier provider slot can sharpen only uncertain records', () => {
  const calls = [];
  const whyProvider = {
    provide(context) {
      calls.push(context.agent.id);
      return {
        label: 'approval needed',
        confidence: 0.72,
        line: 'Waiting for a ruling',
      };
    },
  };
  const result = resolveNextUp({
    schemaVersion: 1,
    collectedAt,
    counts: { total: 2, needsYou: 2, running: 0, idle: 0 },
    agents: [
      agent({ id: 'specific', createdAt: '2026-08-01T05:50:00.000Z', summary: 'tests failed', jumpSessionId: 'specific-session' }),
      agent({ id: 'ambiguous', createdAt: '2026-08-01T05:55:00.000Z', summary: '', jumpSessionId: 'ambiguous-session' }),
    ],
  }, { now: new Date(collectedAt), whyProvider });

  assert.deepEqual(calls, ['ambiguous']);
  assert.equal(result.items.find((item) => item.agentId === 'ambiguous').classification, 'actionable');
  assert.equal(result.items.find((item) => item.agentId === 'specific').why.label, 'needs you');
});

test('unknown waiting timestamps sort last instead of masquerading as oldest', () => {
  const result = resolveNextUp({
    schemaVersion: 1,
    collectedAt,
    counts: { total: 2, needsYou: 2, running: 0, idle: 0 },
    agents: [
      agent({ id: 'unknown', createdAt: 'not-a-date', jumpSessionId: 'unknown-session' }),
      agent({ id: 'known', createdAt: '2026-08-01T05:59:00.000Z', jumpSessionId: 'known-session' }),
    ],
  }, { now: new Date(collectedAt) });

  assert.deepEqual(result.items.map((item) => item.agentId), ['known', 'unknown']);
  assert.equal(result.items[1].waitSeconds, 0);
});
