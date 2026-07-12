import { access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseJsonStdout, run } from './command.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '..', '..');
const MARKER_PREFIX = 'pcl-agent:';

function safeTmuxName(value) {
  if (!/^[A-Za-z0-9_.:-]+$/.test(value)) {
    throw new Error(`unsafe tmux session name: ${JSON.stringify(value)}`);
  }
  return value;
}

function arrayFromEnvelope(value) {
  const data = value?.data ?? value;
  if (Array.isArray(data)) return data;
  for (const key of ['workspaces', 'items', 'result']) {
    if (Array.isArray(data?.[key])) return data[key];
  }
  return [];
}

function workspaceFields(raw) {
  return {
    id: raw.id ?? raw.workspace_id ?? raw.workspaceId ?? raw.ref,
    title: raw.title ?? raw.name ?? '',
    description: raw.description ?? raw.subtitle ?? '',
    selected: Boolean(raw.selected ?? raw.is_selected ?? raw.isSelected),
  };
}

export class CmuxClient {
  constructor(options = {}) {
    this.command = options.command ?? process.env.CMUX_CLI ?? 'cmux';
    this.env = options.env ?? process.env;
    this.run = options.run ?? run;
  }

  async invoke(args, timeoutMs = 10_000) {
    return this.run(this.command, args, { timeoutMs, env: this.env });
  }

  async ping() {
    await this.invoke(['ping']);
    return true;
  }

  async listWorkspaces() {
    const result = await this.invoke(['list-workspaces', '--json']);
    return arrayFromEnvelope(parseJsonStdout(result, 'cmux list-workspaces')).map(workspaceFields);
  }

  async findAgentWorkspace(agentId) {
    const marker = `${MARKER_PREFIX}${agentId}`;
    const workspaces = await this.listWorkspaces();
    return workspaces.find((workspace) => workspace.description.includes(marker)
      || workspace.title.includes(`[${marker}]`)) ?? null;
  }

  async createAgentWorkspace(agent) {
    if (!agent.jump?.tmuxSession) throw new Error(`${agent.id} has no pane-backed live session`);
    const tmux = safeTmuxName(agent.jump.tmuxSession);
    const marker = `${MARKER_PREFIX}${agent.id}`;
    const title = `PcL · ${agent.name}`;
    const command = `exec tmux attach-session -t ${tmux}`;
    const result = await this.invoke([
      'new-workspace',
      '--cwd', REPO_ROOT,
      '--command', command,
      '--description', marker,
    ], 15_000);
    const output = result.stdout.trim();
    let id = '';
    try {
      const parsed = JSON.parse(output);
      id = parsed?.data?.id ?? parsed?.id ?? parsed?.workspace_id ?? '';
    } catch {
      id = output.match(/workspace(?::|\s)+([\w:-]+)/i)?.[1] ?? '';
    }
    const workspace = id ? { id } : await this.findAgentWorkspace(agent.id);
    if (!workspace?.id) throw new Error(`cmux created ${title} but returned no workspace id`);
    try {
      await this.invoke(['rename-workspace', '--workspace', workspace.id, title]);
    } catch {
      // The marker is the identity. A cosmetic rename must not block focus.
    }
    return workspace;
  }

  async focusAgent(agent) {
    const workspace = await this.findAgentWorkspace(agent.id)
      ?? await this.createAgentWorkspace(agent);
    await this.invoke(['select-workspace', '--workspace', workspace.id]);
    return workspace;
  }

  async launchCockpit() {
    const marker = 'pcl-fleet-cockpit';
    const existing = (await this.listWorkspaces()).find((workspace) =>
      workspace.description.includes(marker));
    if (existing) {
      await this.invoke(['select-workspace', '--workspace', existing.id]);
      return existing;
    }
    const bin = path.join(REPO_ROOT, 'fleet-layer', 'bin', 'pcl-fleet');
    await access(bin);
    const command = `exec ${bin} cockpit`;
    await this.invoke([
      'new-workspace', '--cwd', REPO_ROOT,
      '--command', command,
      '--description', marker,
    ], 15_000);
    const created = (await this.listWorkspaces()).find((workspace) =>
      workspace.description.includes(marker));
    if (!created) throw new Error('cmux did not expose the created cockpit workspace');
    await this.invoke(['select-workspace', '--workspace', created.id]);
    return created;
  }
}
