import assert from 'node:assert/strict';
import test from 'node:test';
import { assertSnapshot, buildFleetSnapshot } from '../src/project.mjs';

const input = {
  collectedAt: '2026-07-13T00:00:00.000Z',
  roster: [
    { id: 'rasim', name: 'Rasim', runtime: 'cc' },
    { id: 'kleya', name: 'Kleya', runtime: 'cc' },
    { id: 'edna', name: 'Edna', runtime: 'cc' },
  ],
  sessions: [
    {
      session_id: 'rasim-main', owner_agent: 'rasim', state: 'working',
      tmux_session: 'rasim-main-teren', session_tag: 'telegram:dm:teren',
      runtime: 'claude', account_name: 'tokens-1', account_runtime: 'claude',
      account_captured_at: '2026-07-13T00:00:00Z',
      signal_needs_reply: false,
    },
    {
      session_id: 'rasim-child', owner_agent: 'rasim', state: 'working',
      tmux_session: 'rasim-worker', runtime: 'codex', signal_needs_reply: false,
    },
    {
      session_id: 'kleya-main', owner_agent: 'kleya', state: 'working',
      tmux_session: 'kleya-main-teren', session_tag: 'telegram:dm:teren',
      runtime: 'claude', account_name: 'tokens-2', account_runtime: 'claude',
      account_captured_at: '2026-07-13T00:00:00Z',
      signal_needs_reply: true, signal_status: 'question',
      signal_summary: 'principal decision required', signal_created_at: '2026-07-13T00:00:00Z',
    },
  ],
  loops: [{ targetSessionId: 'rasim-child', status: 'active' }],
  quota: [
    { key: 'cc/tokens-1', fiveHourUsed: 10, weeklyUsed: 40 },
    { key: 'cc/tokens-2', fiveHourUsed: 90, weeklyUsed: 70 },
  ],
  warnings: [],
};

test('projects sessions to entities and makes needs-you the status override', () => {
  const snapshot = assertSnapshot(buildFleetSnapshot(input));
  assert.deepEqual(snapshot.counts, {
    total: 3, autonomous: 1, needsYou: 1, running: 1, idle: 1,
    nearWall: 1, autonomousPercent: 33,
  });
  const rasim = snapshot.agents.find((agent) => agent.id === 'rasim');
  const kleya = snapshot.agents.find((agent) => agent.id === 'kleya');
  const edna = snapshot.agents.find((agent) => agent.id === 'edna');
  assert.equal(rasim.autonomous, true);
  assert.equal(rasim.ownedSessionCount, 2);
  assert.equal(rasim.jump.tmuxSession, 'rasim-main-teren');
  assert.equal(rasim.quota.headroom, 60);
  assert.equal(kleya.status, 'needs-you');
  assert.equal(kleya.quota.nearWall, true);
  assert.equal(edna.status, 'idle');
  assert.equal(edna.quota, null);
});

test('refuses an empty fleet snapshot', () => {
  assert.throws(() => assertSnapshot({ schemaVersion: 1, agents: [], counts: {} }), /no active agents/);
});
