#!/usr/bin/env node
import { CmuxClient } from './cmux.mjs';
import { assertSnapshot, buildFleetSnapshot } from './project.mjs';
import { Cockpit, render } from './render.mjs';
import { LiveSources } from './sources.mjs';

const sources = new LiveSources();
const cmux = new CmuxClient();

async function collect() {
  return assertSnapshot(buildFleetSnapshot(await sources.collect()));
}

function usage() {
  process.stdout.write(`PcL fleet cockpit for cmux

Usage:
  pcl-fleet snapshot [--json]   Read and render the real current fleet once
  pcl-fleet cockpit            Run the updating keyboard cockpit in this pane
  pcl-fleet launch             Create/focus the cockpit workspace through cmux
  pcl-fleet jump <agent>       Create/focus one agent workspace through cmux
  pcl-fleet doctor             Verify PcL sources and cmux socket connectivity

Environment:
  CMUX_CLI                     cmux CLI or tagged scripts/cmux-debug-cli.sh
  CMUX_SOCKET_PATH             explicit cmux unix socket
  PCL_FLEET_POLL_MS            cockpit refresh interval (default 10000)
  PCL_FLEET_NEAR_WALL_HEADROOM near-wall remaining percent (default 15)
`);
}

async function main() {
  const [command = 'help', ...args] = process.argv.slice(2);
  if (command === 'help' || command === '--help' || command === '-h') return usage();
  if (command === 'snapshot') {
    const snapshot = await collect();
    if (args.includes('--json')) process.stdout.write(`${JSON.stringify(snapshot, null, 2)}\n`);
    else process.stdout.write(`${render(snapshot)}\n`);
    return;
  }
  if (command === 'cockpit') {
    await new Cockpit({ collect, cmux }).start();
    return;
  }
  if (command === 'launch') {
    const workspace = await cmux.launchCockpit();
    process.stdout.write(`${JSON.stringify({ ok: true, workspace })}\n`);
    return;
  }
  if (command === 'jump') {
    const agentId = args[0];
    if (!agentId) throw new Error('jump requires an agent id');
    const snapshot = await collect();
    const agent = snapshot.agents.find((candidate) => candidate.id === agentId);
    if (!agent) throw new Error(`active agent not found: ${agentId}`);
    const workspace = await cmux.focusAgent(agent);
    process.stdout.write(`${JSON.stringify({ ok: true, agent: agent.id, workspace })}\n`);
    return;
  }
  if (command === 'doctor') {
    const snapshot = await collect();
    await cmux.ping();
    process.stdout.write(`${JSON.stringify({
      ok: true,
      fleet: snapshot.counts,
      cmuxSocket: process.env.CMUX_SOCKET_PATH ?? 'default',
      collectedAt: snapshot.collectedAt,
    }, null, 2)}\n`);
    return;
  }
  throw new Error(`unknown command: ${command}`);
}

main().catch((error) => {
  process.stderr.write(`pcl-fleet: ${error.message}\n`);
  if (process.env.PCL_FLEET_DEBUG === '1' && error.stack) process.stderr.write(`${error.stack}\n`);
  process.exitCode = 1;
});
