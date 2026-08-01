#!/usr/bin/env node
import { CmuxClient, COCKPIT_PROCESS_NAME } from './cmux.mjs';
import { assertSnapshot, buildFleetSnapshot } from './project.mjs';
import { resolveNextUp } from './next-up.mjs';
import { Cockpit, render } from './render.mjs';
import { LiveSources } from './sources.mjs';
import { OfficeFleetSource, safeViewerId } from './transport.mjs';

function fleetSource(transportName, viewerId) {
  if (transportName === 'office') {
    return new OfficeFleetSource({ viewerId });
  }
  if (transportName === 'local') {
    const local = new LiveSources();
    local.kind = 'local';
    return local;
  }
  throw new Error(`unknown fleet transport: ${transportName}`);
}

async function collect(selected) {
  if (selected.kind === 'office') return selected.collect();
  return assertSnapshot(buildFleetSnapshot(await selected.collect()));
}

function parseArgs(args) {
  const positional = [];
  let viewerId = process.env.PCL_FLEET_VIEWER_ID;
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === '--viewer-id') {
      viewerId = args[index + 1];
      index += 1;
    } else {
      positional.push(args[index]);
    }
  }
  return { positional, viewerId: safeViewerId(viewerId) };
}

function usage() {
  process.stdout.write(`PcL fleet cockpit for cmux

Usage:
  pcl-fleet snapshot --viewer-id <id> [--json]
  pcl-fleet next-up --viewer-id <id> [--priority-json <json>]
  pcl-fleet cockpit --viewer-id <id>
  pcl-fleet launch --viewer-id <id>
  pcl-fleet jump <agent> --viewer-id <id>
  pcl-fleet doctor --viewer-id <id>

Environment:
  CMUX_CLI                     cmux CLI or tagged scripts/cmux-debug-cli.sh
  CMUX_SOCKET_PATH             explicit cmux unix socket
  PCL_FLEET_TRANSPORT          office (default) or local (Studio-only)
  PCL_FLEET_VIEWER_ID          optional default for the required --viewer-id
  PCL_OFFICE_CLI               Office CLI path (default ~/.local/bin/office or PATH)
  PCL_FLEET_POLL_MS            cockpit refresh interval (default 10000)
  PCL_FLEET_NEAR_WALL_HEADROOM near-wall remaining percent (default 15)
`);
}

async function main() {
  const [command = 'help', ...rawArgs] = process.argv.slice(2);
  if (command === 'help' || command === '--help' || command === '-h') return usage();
  const { positional: args, viewerId } = parseArgs(rawArgs);
  const transportName = process.env.PCL_FLEET_TRANSPORT ?? 'office';
  const selectedSource = fleetSource(transportName, viewerId);
  const cmux = new CmuxClient({ viewerId });
  const collectSnapshot = () => collect(selectedSource);
  if (command === 'snapshot') {
    const snapshot = await collectSnapshot();
    if (args.includes('--json')) process.stdout.write(`${JSON.stringify(snapshot, null, 2)}\n`);
    else process.stdout.write(`${render(snapshot)}\n`);
    return;
  }
  if (command === 'next-up') {
    const priorityFlagIndex = args.indexOf('--priority-json');
    const priorityBySessionId = priorityFlagIndex >= 0
      ? JSON.parse(args[priorityFlagIndex + 1] ?? '{}')
      : {};
    const snapshot = await collectSnapshot();
    process.stdout.write(`${JSON.stringify(resolveNextUp(snapshot, { priorityBySessionId }))}\n`);
    return;
  }
  if (command === 'cockpit') {
    process.title = COCKPIT_PROCESS_NAME;
    await new Cockpit({ collect: collectSnapshot, cmux }).start();
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
    const snapshot = await collectSnapshot();
    const agent = snapshot.agents.find((candidate) => candidate.id === agentId);
    if (!agent) throw new Error(`active agent not found: ${agentId}`);
    const workspace = await cmux.focusAgent(agent);
    process.stdout.write(`${JSON.stringify({ ok: true, agent: agent.id, workspace })}\n`);
    return;
  }
  if (command === 'doctor') {
    const snapshot = await collectSnapshot();
    await cmux.ping();
    process.stdout.write(`${JSON.stringify({
      ok: true,
      transport: transportName,
      viewerId,
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
