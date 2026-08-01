import assert from 'node:assert/strict';
import test from 'node:test';
import {
  OfficeFleetSource,
  parseOfficeSnapshot,
  resolveOfficeCommand,
} from '../src/transport.mjs';

function commandResult(value) {
  return {
    command: 'office', args: [], code: 0, signal: null,
    stdout: `${JSON.stringify(value)}\n`, stderr: '',
  };
}

const snapshot = {
  schemaVersion: 1,
  collectedAt: '2026-07-13T03:00:00.000Z',
  counts: {
    total: 1, autonomous: 1, needsYou: 0, running: 1, idle: 0,
    nearWall: 0, autonomousPercent: 100,
  },
  agents: [{
    id: 'rasim', name: 'Rasim', status: 'running', autonomous: true,
    jump: { sessionId: 'session-1', tmuxSession: 'rasim-main-teren' },
  }],
  warnings: [],
};

test('Office adapter reads one complete viewer snapshot in quiet machine mode', async () => {
  const calls = [];
  const source = new OfficeFleetSource({
    command: '/Users/teren/.local/bin/office',
    viewerId: '276672685',
    env: { HOME: '/Users/teren' },
    timeoutMs: 41_000,
    run: async (command, args, options) => {
      calls.push({ command, args, options });
      return commandResult({ ok: true, data: snapshot });
    },
  });

  assert.deepEqual(await source.collect(), snapshot);
  assert.deepEqual(calls, [{
    command: '/Users/teren/.local/bin/office',
    args: [
      '--machine', 'run', '--', 'pcl', 'fleet', 'snapshot',
      '--viewer-id', '276672685',
    ],
    options: {
      timeoutMs: 41_000,
      env: { HOME: '/Users/teren', OFFICE_SKIP_UPDATE: '1' },
    },
  }]);
});

test('Office adapter rejects truncated or internally inconsistent snapshots', () => {
  assert.throws(
    () => parseOfficeSnapshot(commandResult({ ok: true, data: {
      ...snapshot,
      counts: { ...snapshot.counts, total: 2 },
    } })),
    /internally inconsistent/,
  );
});

test('Office adapter rejects unsafe viewer ids before invoking Office', () => {
  assert.throws(
    () => new OfficeFleetSource({ viewerId: '276; rm -rf /' }),
    /unsafe viewer id/,
  );
});

test('Office discovery prefers override, then the current home installation, then PATH', () => {
  assert.equal(resolveOfficeCommand({ env: { PCL_OFFICE_CLI: '/custom/office' } }), '/custom/office');
  assert.equal(resolveOfficeCommand({
    env: {}, homeDir: '/Users/teren', exists: (candidate) => candidate === '/Users/teren/.local/bin/office',
  }), '/Users/teren/.local/bin/office');
  assert.equal(resolveOfficeCommand({ env: {}, homeDir: '/missing', exists: () => false }), 'office');
});
