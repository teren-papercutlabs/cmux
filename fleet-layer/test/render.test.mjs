import assert from 'node:assert/strict';
import test from 'node:test';
import { Cockpit, render, renderOffline } from '../src/render.mjs';

const snapshot = {
  schemaVersion: 1,
  collectedAt: '2026-07-13T03:00:00.000Z',
  counts: {
    total: 1, autonomous: 0, autonomousPercent: 0,
    needsYou: 0, running: 1, idle: 0, nearWall: 0,
  },
  agents: [{
    id: 'rasim', name: 'Rasim', status: 'running', autonomous: false,
    jump: { sessionId: 'session-1', tmuxSession: 'rasim-main-teren' },
    quota: null,
  }],
  warnings: [],
};

test('cockpit retains the last complete snapshot and reports its stale age', async () => {
  let now = 1_000;
  let calls = 0;
  const cockpit = new Cockpit({
    cmux: {},
    now: () => now,
    collect: async () => {
      calls += 1;
      if (calls === 1) return snapshot;
      throw new Error('Studio unreachable');
    },
  });
  cockpit.paint = () => {};

  await cockpit.refresh();
  now = 13_400;
  await cockpit.refresh();

  assert.equal(cockpit.snapshot, snapshot);
  assert.equal(cockpit.lastCompleteAt, 1_000);
  assert.equal(cockpit.lastFailureAt, 13_400);
  const output = render(cockpit.snapshot, 0, cockpit.message, {
    state: 'stale', ageMs: now - cockpit.lastCompleteAt,
  });
  assert.match(output, /STALE · last complete snapshot 12s ago/);
  assert.match(output, /refresh failed: Studio unreachable/);
});

test('cockpit has an explicit offline state before any complete snapshot', () => {
  assert.equal(
    renderOffline('refresh failed: Office timed out', 3_500),
    'OFFLINE · no complete snapshot · failed 3s ago\nrefresh failed: Office timed out',
  );
});
