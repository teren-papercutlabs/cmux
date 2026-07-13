import { existsSync } from 'node:fs';
import { access } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseJsonStdout, run } from './command.mjs';
import { resolveOfficeCommand, safeViewerId } from './transport.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '..', '..');
const MARKER_PREFIX = 'pcl-fleet:office';

function safeTmuxName(value) {
  if (!/^[A-Za-z0-9_.:-]+$/.test(value)) {
    throw new Error(`unsafe tmux session name: ${JSON.stringify(value)}`);
  }
  return value;
}

function safeIdentityValue(label, value) {
  const text = String(value ?? '');
  if (!text || !/^[A-Za-z0-9_.:-]+$/.test(text)) {
    throw new Error(`unsafe ${label}: ${JSON.stringify(value)}`);
  }
  return text;
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", `'"'"'`)}'`;
}

function agentMarker(agent, viewerId) {
  const agentId = safeIdentityValue('agent id', agent.id);
  const sessionId = safeIdentityValue('session id', agent.jump?.sessionId);
  const tmux = safeTmuxName(agent.jump?.tmuxSession);
  return `${MARKER_PREFIX};agent=${agentId};viewer=${viewerId};session=${sessionId};tmux=${tmux}`;
}

export function resolveCmuxCommand(options = {}) {
  const env = options.env ?? process.env;
  if (env.CMUX_CLI) return env.CMUX_CLI;
  const home = options.homeDir ?? os.homedir();
  const exists = options.exists ?? existsSync;
  const candidates = [
    path.join(home, 'Applications', 'cmux.app', 'Contents', 'Resources', 'bin', 'cmux'),
    '/Applications/cmux.app/Contents/Resources/bin/cmux',
  ];
  return candidates.find((candidate) => exists(candidate)) ?? 'cmux';
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

function transportProcessNames(value, output = []) {
  if (Array.isArray(value)) {
    for (const item of value) transportProcessNames(item, output);
    return output;
  }
  if (!value || typeof value !== 'object') return output;
  for (const [key, nested] of Object.entries(value)) {
    if (['name', 'path', 'command', 'executable', 'argv'].includes(key)) {
      if (Array.isArray(nested)) output.push(nested.join(' '));
      else if (typeof nested === 'string') output.push(nested);
    }
    transportProcessNames(nested, output);
  }
  return output;
}

export class CmuxClient {
  constructor(options = {}) {
    this.env = options.env ?? process.env;
    this.command = options.command ?? resolveCmuxCommand({
      env: this.env,
      homeDir: options.homeDir ?? os.homedir(),
      exists: options.exists ?? existsSync,
    });
    this.run = options.run ?? run;
    this.viewerId = safeViewerId(options.viewerId ?? this.env.PCL_FLEET_VIEWER_ID);
    this.officeCommand = options.officeCommand ?? resolveOfficeCommand({
      env: this.env,
      homeDir: options.homeDir ?? os.homedir(),
      exists: options.exists ?? existsSync,
    });
  }

  async invoke(args, timeoutMs = 10_000) {
    return this.run(this.command, args, { timeoutMs, env: this.env });
  }

  async ping() {
    await this.invoke(['ping']);
    return true;
  }

  async listWorkspaces() {
    const result = await this.invoke(['workspace', 'list', '--json']);
    return arrayFromEnvelope(parseJsonStdout(result, 'cmux list-workspaces')).map(workspaceFields);
  }

  async findAgentWorkspace(agent) {
    const marker = agentMarker(agent, this.viewerId);
    const workspaces = await this.listWorkspaces();
    return workspaces.find((workspace) => workspace.description.includes(marker)
      || workspace.title.includes(`[${marker}]`)) ?? null;
  }

  async transportWorkspaceIsLive(workspace) {
    const result = await this.invoke([
      '--json', 'top', '--workspace', workspace.id, '--processes',
    ], 15_000);
    const payload = parseJsonStdout(result, 'cmux top');
    return transportProcessNames(payload).some((name) => /(^|[/\s-])mosh(?:-client)?($|[\s])/i.test(name));
  }

  async closeWorkspace(workspace) {
    await this.invoke(['workspace', 'close', '--workspace', workspace.id]);
  }

  async createAgentWorkspace(agent) {
    if (!agent.jump?.tmuxSession) throw new Error(`${agent.id} has no pane-backed live session`);
    const tmux = safeTmuxName(agent.jump.tmuxSession);
    const marker = agentMarker(agent, this.viewerId);
    const title = `PcL · ${agent.name}`;
    const command = `exec ${shellQuote(this.officeCommand)} attach ${shellQuote(tmux)}`;
    const result = await this.invoke([
      'workspace', 'create', '--json',
      '--name', title,
      '--cwd', REPO_ROOT,
      '--command', command,
      '--description', marker,
    ], 15_000);
    const output = result.stdout.trim();
    let id = '';
    try {
      const parsed = JSON.parse(output);
      id = parsed?.data?.id ?? parsed?.id ?? parsed?.workspace_ref
        ?? parsed?.workspace_id ?? parsed?.data?.workspace_ref ?? parsed?.data?.workspace_id ?? '';
    } catch {
      id = output.match(/workspace(?::|\s)+([\w:-]+)/i)?.[1] ?? '';
    }
    const workspace = id ? { id } : await this.findAgentWorkspace(agent);
    if (!workspace?.id) throw new Error(`cmux created ${title} but returned no workspace id`);
    try {
      await this.invoke(['workspace', 'rename', '--workspace', workspace.id, title]);
    } catch {
      // The marker is the identity. A cosmetic rename must not block focus.
    }
    return workspace;
  }

  async focusAgent(agent) {
    let workspace = await this.findAgentWorkspace(agent);
    if (workspace && !await this.transportWorkspaceIsLive(workspace)) {
      await this.closeWorkspace(workspace);
      workspace = null;
    }
    workspace ??= await this.createAgentWorkspace(agent);
    await this.invoke(['workspace', 'select', '--workspace', workspace.id]);
    return workspace;
  }

  async launchCockpit() {
    const marker = `pcl-fleet-cockpit;viewer=${this.viewerId}`;
    const existing = (await this.listWorkspaces()).find((workspace) =>
      workspace.description.includes(marker));
    if (existing) {
      await this.invoke(['workspace', 'select', '--workspace', existing.id]);
      return existing;
    }
    const bin = path.join(REPO_ROOT, 'fleet-layer', 'bin', 'pcl-fleet');
    await access(bin);
    const preservedEnv = {
      CMUX_CLI: this.command,
      PCL_OFFICE_CLI: this.officeCommand,
    };
    for (const key of ['CMUX_SOCKET_PATH', 'CMUX_TAG', 'CMUX_BUNDLE_ID', 'CMUX_BUNDLED_CLI_PATH']) {
      if (this.env[key]) preservedEnv[key] = this.env[key];
    }
    const envArgs = Object.entries(preservedEnv)
      .map(([key, value]) => shellQuote(`${key}=${value}`))
      .join(' ');
    const command = `exec env ${envArgs} ${shellQuote(bin)} cockpit --viewer-id ${shellQuote(this.viewerId)}`;
    await this.invoke([
      'workspace', 'create', '--json', '--name', 'PcL Fleet Cockpit', '--cwd', REPO_ROOT,
      '--command', command,
      '--description', marker,
    ], 15_000);
    const created = (await this.listWorkspaces()).find((workspace) =>
      workspace.description.includes(marker));
    if (!created) throw new Error('cmux did not expose the created cockpit workspace');
    await this.invoke(['workspace', 'select', '--workspace', created.id]);
    return created;
  }
}
