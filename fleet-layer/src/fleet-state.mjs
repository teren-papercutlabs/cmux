import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { parseJsonStdout, run } from './command.mjs';
import { SESSION_SQL } from './sources.mjs';

function nullable(value) {
  return value == null || value === '' ? null : String(value);
}

function isPrincipalMain(row) {
  return row.session_type === 'persistent-channel'
    || String(row.session_tag ?? '').startsWith('telegram:dm:');
}

export function projectFleetState(raw) {
  const sessions = Array.isArray(raw.sessions) ? raw.sessions : [];
  return {
    collectedAt: raw.collectedAt ?? new Date().toISOString(),
    sessions: sessions.map((row) => ({
      sessionId: String(row.session_id),
      agentName: nullable(row.owner_agent ?? row.direct_agent) ?? 'unknown',
      displayName: nullable(row.tmux_session ?? row.session_tag) ?? String(row.session_id).slice(0, 8),
      lifecycleState: nullable(row.state) ?? 'unknown',
      runtime: nullable(row.runtime) ?? 'unknown',
      tmuxSession: nullable(row.tmux_session),
      sessionTag: nullable(row.session_tag),
      sessionType: nullable(row.session_type),
      signalStatus: nullable(row.signal_status) ?? '',
      signalNeedsReply: Boolean(row.signal_needs_reply),
      signalSummary: nullable(row.signal_summary) ?? '',
      signalCreatedAt: nullable(row.signal_created_at),
      lastToolCallAt: nullable(row.last_tool_call_at),
      isMain: isPrincipalMain(row),
    })),
    warnings: Array.isArray(raw.warnings) ? raw.warnings : [],
  };
}

/**
 * Resolve how to reach the marshal CLI. The TUI can run on a machine that has
 * no local marshal (teren's MBA): a per-machine config or env override names a
 * command prefix (e.g. ssh to the Studio) instead of the bare binary.
 * Precedence: ALTITUDE_MARSHAL_CMD env (space-split) -> marshalCmd array in
 * ~/.config/altitude/fleet.json -> local "marshal".
 */
export function marshalCommand(env = process.env, readConfig = defaultReadFleetConfig) {
  const fromEnv = env.ALTITUDE_MARSHAL_CMD;
  if (typeof fromEnv === 'string' && fromEnv.trim().length > 0) return fromEnv.trim().split(/\s+/);
  const config = readConfig();
  if (config && Array.isArray(config.marshalCmd) && config.marshalCmd.length > 0
      && config.marshalCmd.every((part) => typeof part === 'string' && part.length > 0)) {
    return [...config.marshalCmd];
  }
  return ['marshal'];
}

function defaultReadFleetConfig() {
  try {
    return JSON.parse(readFileSync(join(homedir(), '.config', 'altitude', 'fleet.json'), 'utf8'));
  } catch {
    return null;
  }
}

/**
 * Build the actual invocation from the resolved command parts. An ssh prefix
 * needs the REMOTE command collapsed into one shell-quoted string — ssh joins
 * argv with spaces and hands it to the remote shell, so unquoted SQL gets
 * re-parsed there ("zsh: parse error").
 */
export function buildMarshalInvocation(commandParts, marshalArgs) {
  return buildRemoteInvocation(commandParts, commandParts[commandParts.length - 1], marshalArgs);
}

/** Same host resolution as the marshal command, but for any binary on that
 *  host (e.g. tmux, which holds live attach state the DB does not have). */
export function buildRemoteInvocation(commandParts, bin, args) {
  if (commandParts[0] === 'ssh' && commandParts.length >= 3) {
    const sshOptionsAndTarget = commandParts.slice(1, -1);
    const quote = (value) => `'${String(value).replaceAll("'", "'\\''")}'`;
    return {
      bin: 'ssh',
      args: [...sshOptionsAndTarget, [bin, ...args].map(quote).join(' ')],
    };
  }
  return { bin, args };
}

/** The set of tmux session names currently ATTACHED on the fleet host, or
 *  null when the query fails (callers fail OPEN to unfiltered rather than
 *  rendering an empty menu off a transient error). */
async function attachedTmuxSessions(invoke, commandParts, timeoutMs) {
  try {
    const { bin, args } = buildRemoteInvocation(
      commandParts,
      'tmux',
      ['list-sessions', '-F', '#{session_name}|#{session_attached}'],
    );
    const result = await invoke(bin, args, { timeoutMs });
    const attached = new Set();
    for (const line of String(result.stdout ?? '').split('\n')) {
      const separator = line.lastIndexOf('|');
      if (separator > 0 && line.slice(separator + 1).trim() !== '0') {
        attached.add(line.slice(0, separator));
      }
    }
    return attached;
  } catch {
    return null;
  }
}

export async function getFleetState(options = {}) {
  if (options.sources) return projectFleetState(await options.sources.collect());
  const invoke = options.run ?? run;
  const { bin, args } = buildMarshalInvocation(
    options.marshalCommand ?? marshalCommand(),
    ['db', 'query', '--sql', SESSION_SQL],
  );
  const result = await invoke(bin, args, {
    timeoutMs: options.timeoutMs ?? 30_000,
  });
  const parsed = parseJsonStdout(result, 'marshal db query');
  const state = projectFleetState({
    collectedAt: new Date().toISOString(),
    sessions: parsed && Object.hasOwn(parsed, 'data') ? parsed.data : parsed,
  });
  // teren-ruled 2026-08-03: the menu shows only sessions whose tmux session is
  // currently ATTACHED (his live surfaces). Attach state lives in the tmux
  // server, not the DB. Fail open on a tmux query error.
  const attached = await attachedTmuxSessions(
    invoke,
    options.marshalCommand ?? marshalCommand(),
    options.timeoutMs ?? 30_000,
  );
  if (attached === null) {
    return { ...state, warnings: [...state.warnings, 'attach filter unavailable: showing all tmux sessions'] };
  }
  return {
    ...state,
    sessions: state.sessions.filter((session) => session.tmuxSession && attached.has(session.tmuxSession)),
  };
}
