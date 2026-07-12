import assert from 'node:assert/strict';
import test from 'node:test';
import { CmuxClient } from '../src/cmux.mjs';

function result(stdout = '') {
  return { code: 0, stdout, stderr: '', command: 'cmux', args: [] };
}

test('jump selects an existing marked workspace', async () => {
  const calls = [];
  const client = new CmuxClient({
    run: async (_command, args) => {
      calls.push(args);
      if (args[0] === 'workspace' && args[1] === 'list') {
        return result(JSON.stringify({ data: [{ id: 'workspace:7', description: 'pcl-agent:rasim' }] }));
      }
      return result();
    },
  });
  await client.focusAgent({ id: 'rasim', jump: { tmuxSession: 'rasim-main-teren' } });
  assert.deepEqual(calls, [
    ['workspace', 'list', '--json'],
    ['workspace', 'select', '--workspace', 'workspace:7'],
  ]);
});

test('jump refuses unsafe tmux names before constructing a command', async () => {
  const client = new CmuxClient({
    run: async (_command, args) => {
      if (args[0] === 'workspace' && args[1] === 'list') return result(JSON.stringify({ data: [] }));
      return result();
    },
  });
  await assert.rejects(
    client.focusAgent({ id: 'rasim', jump: { tmuxSession: 'x; touch /tmp/no' } }),
    /unsafe tmux session name/,
  );
});
