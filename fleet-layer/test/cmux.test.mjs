import assert from 'node:assert/strict';
import test from 'node:test';
import { CmuxClient, resolveCmuxCommand } from '../src/cmux.mjs';

function result(stdout = '') {
  return { code: 0, stdout, stderr: '', command: 'cmux', args: [] };
}

const agent = {
  id: 'rasim',
  name: 'Rasim',
  jump: {
    sessionId: 'b8e42c14-a910-4f67-b982-4655f7b29353',
    tmuxSession: 'rasim-main-teren',
  },
};

const marker = 'pcl-fleet:office;agent=rasim;viewer=276672685;session=b8e42c14-a910-4f67-b982-4655f7b29353;tmux=rasim-main-teren';

test('jump reuses an exact marked workspace while its mosh transport is alive', async () => {
  const calls = [];
  const client = new CmuxClient({
    viewerId: '276672685',
    officeCommand: '/Users/teren/.local/bin/office',
    run: async (_command, args) => {
      calls.push(args);
      if (args[0] === 'workspace' && args[1] === 'list') {
        return result(JSON.stringify({ data: [{ id: 'workspace:7', description: marker }] }));
      }
      if (args[0] === '--json' && args[1] === 'top') {
        return result(JSON.stringify({ windows: [{ processes: [{ name: 'mosh-client' }] }] }));
      }
      return result();
    },
  });
  await client.focusAgent(agent);
  assert.deepEqual(calls, [
    ['workspace', 'list', '--json'],
    ['--json', 'top', '--workspace', 'workspace:7', '--processes'],
    ['workspace', 'select', '--workspace', 'workspace:7'],
  ]);
});

test('jump recreates an exact marked workspace after its mosh transport exits', async () => {
  const calls = [];
  const client = new CmuxClient({
    viewerId: '276672685',
    officeCommand: '/Users/teren/.local/bin/office',
    run: async (_command, args) => {
      calls.push(args);
      if (args[0] === 'workspace' && args[1] === 'list') {
        return result(JSON.stringify({ data: [{ id: 'workspace:dead', description: marker }] }));
      }
      if (args[0] === '--json' && args[1] === 'top') {
        return result(JSON.stringify({ windows: [{ processes: [{ name: 'zsh' }] }] }));
      }
      if (args[0] === 'workspace' && args[1] === 'create') {
        return result(JSON.stringify({ data: { id: 'workspace:new' } }));
      }
      return result();
    },
  });

  const workspace = await client.focusAgent(agent);
  assert.equal(workspace.id, 'workspace:new');
  assert.deepEqual(calls.map((args) => args.slice(0, 2)), [
    ['workspace', 'list'],
    ['--json', 'top'],
    ['workspace', 'close'],
    ['workspace', 'create'],
    ['workspace', 'rename'],
    ['workspace', 'select'],
  ]);
  const create = calls.find((args) => args[0] === 'workspace' && args[1] === 'create');
  assert.equal(create[create.indexOf('--command') + 1],
    "exec '/Users/teren/.local/bin/office' attach 'rasim-main-teren'");
  assert.equal(create[create.indexOf('--description') + 1], marker);
});

test('jump identity does not reuse a workspace for a different session target', async () => {
  const calls = [];
  const client = new CmuxClient({
    viewerId: '276672685',
    officeCommand: 'office',
    run: async (_command, args) => {
      calls.push(args);
      if (args[0] === 'workspace' && args[1] === 'list') {
        return result(JSON.stringify({ data: [{
          id: 'workspace:old',
          description: marker.replace(agent.jump.sessionId, '00000000-0000-0000-0000-000000000000'),
        }] }));
      }
      if (args[0] === 'workspace' && args[1] === 'create') {
        return result(JSON.stringify({ data: { id: 'workspace:new' } }));
      }
      return result();
    },
  });
  const workspace = await client.focusAgent(agent);
  assert.equal(workspace.id, 'workspace:new');
  assert.equal(calls.some((args) => args[0] === '--json' && args[1] === 'top'), false);
});

test('jump refuses unsafe tmux names before constructing a command', async () => {
  const calls = [];
  const client = new CmuxClient({
    viewerId: '276672685',
    run: async (_command, args) => {
      calls.push(args);
      return result();
    },
  });
  await assert.rejects(
    client.focusAgent({
      id: 'rasim',
      jump: { sessionId: agent.jump.sessionId, tmuxSession: 'x; touch /tmp/no' },
    }),
    /unsafe tmux session name/,
  );
  assert.deepEqual(calls, []);
});

test('launch persists viewer, installed CLI, tag socket, and Office paths into cockpit', async () => {
  const calls = [];
  let lists = 0;
  const client = new CmuxClient({
    viewerId: '276672685',
    command: '/Users/teren/Applications/cmux.app/Contents/Resources/bin/cmux',
    officeCommand: '/Users/teren/.local/bin/office',
    env: {
      CMUX_SOCKET_PATH: '/tmp/cmux-debug-pcl-fleet.sock',
      CMUX_TAG: 'pcl-fleet',
    },
    run: async (_command, args) => {
      calls.push(args);
      if (args[0] === 'workspace' && args[1] === 'list') {
        lists += 1;
        return result(JSON.stringify({ data: lists === 1 ? [] : [{
          id: 'workspace:cockpit',
          description: 'pcl-fleet-cockpit;viewer=276672685',
        }] }));
      }
      return result();
    },
  });

  await client.launchCockpit();
  const create = calls.find((args) => args[0] === 'workspace' && args[1] === 'create');
  const command = create[create.indexOf('--command') + 1];
  assert.match(command, /'CMUX_CLI=\/Users\/teren\/Applications\/cmux\.app\/Contents\/Resources\/bin\/cmux'/);
  assert.match(command, /'CMUX_SOCKET_PATH=\/tmp\/cmux-debug-pcl-fleet\.sock'/);
  assert.match(command, /'CMUX_TAG=pcl-fleet'/);
  assert.match(command, /'PCL_OFFICE_CLI=\/Users\/teren\/\.local\/bin\/office'/);
  assert.match(command, /cockpit --viewer-id '276672685'$/);
});

test('cmux discovery prefers override, then the current home app bundle, then PATH', () => {
  assert.equal(resolveCmuxCommand({ env: { CMUX_CLI: '/custom/cmux' } }), '/custom/cmux');
  assert.equal(resolveCmuxCommand({
    env: {}, homeDir: '/Users/teren',
    exists: (candidate) => candidate === '/Users/teren/Applications/cmux.app/Contents/Resources/bin/cmux',
  }), '/Users/teren/Applications/cmux.app/Contents/Resources/bin/cmux');
  assert.equal(resolveCmuxCommand({ env: {}, homeDir: '/missing', exists: () => false }), 'cmux');
});
