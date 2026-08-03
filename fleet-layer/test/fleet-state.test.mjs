import assert from 'node:assert/strict';
import test from 'node:test';
import { projectFleetState } from '../src/fleet-state.mjs';

test('projects one selectable row per session and carries last_tool_call_at', () => {
  const state = projectFleetState({
    collectedAt: '2026-08-03T04:00:00Z',
    sessions: [{
      session_id: 'session-1', owner_agent: 'xianxing', state: 'working',
      tmux_session: 'xianxing-worker', session_tag: 'worker', session_type: 'clone', runtime: 'codex',
      signal_status: 'question', signal_needs_reply: false, signal_summary: 'Pick A or B',
      signal_created_at: '2026-08-03T03:50:00Z', last_tool_call_at: '2026-08-03T03:55:00Z',
    }],
  });
  assert.equal(state.sessions.length, 1);
  assert.equal(state.sessions[0].lastToolCallAt, '2026-08-03T03:55:00Z');
  assert.equal(state.sessions[0].signalStatus, 'question');
  assert.equal(state.sessions[0].displayName, 'xianxing-worker');
});

test('recognizes principal mains from typed session metadata rather than their display title', () => {
  const state = projectFleetState({
    collectedAt: '2026-08-03T04:00:00Z',
    sessions: [{
      session_id: 'opaque-id', owner_agent: 'xianxing', state: 'idle', tmux_session: 'friendly-title',
      session_tag: 'telegram:dm:276672685', session_type: 'persistent-channel', runtime: 'cc',
    }],
  });
  assert.equal(state.sessions[0].isMain, true);
});

test('marshalCommand: env override wins, then config marshalCmd, then local marshal', async () => {
  const { marshalCommand } = await import('../src/fleet-state.mjs');
  assert.deepEqual(
    marshalCommand({ ALTITUDE_MARSHAL_CMD: 'ssh -o BatchMode=yes pcloffice@studio marshal' }, () => null),
    ['ssh', '-o', 'BatchMode=yes', 'pcloffice@studio', 'marshal'],
  );
  assert.deepEqual(
    marshalCommand({}, () => ({ marshalCmd: ['ssh', 'studio', 'marshal'] })),
    ['ssh', 'studio', 'marshal'],
  );
  assert.deepEqual(marshalCommand({}, () => null), ['marshal']);
  assert.deepEqual(marshalCommand({}, () => ({ marshalCmd: [] })), ['marshal']);
});

test('buildMarshalInvocation quotes the remote command for ssh, passes locals through', async () => {
  const { buildMarshalInvocation } = await import('../src/fleet-state.mjs');
  const local = buildMarshalInvocation(['marshal'], ['db', 'query', '--sql', 'SELECT 1']);
  assert.deepEqual(local, { bin: 'marshal', args: ['db', 'query', '--sql', 'SELECT 1'] });

  const sql = "SELECT 'a)b'\nFROM x";
  const remote = buildMarshalInvocation(['ssh', '-o', 'BatchMode=yes', 'user@host', 'marshal'], ['db', 'query', '--sql', sql]);
  assert.equal(remote.bin, 'ssh');
  assert.deepEqual(remote.args.slice(0, 3), ['-o', 'BatchMode=yes', 'user@host']);
  const remoteCommand = remote.args[3];
  assert.ok(remoteCommand.startsWith("'marshal' 'db' 'query' '--sql' '"));
  assert.ok(remoteCommand.includes("'\\''a)b'\\''"));
});
