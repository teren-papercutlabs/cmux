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

export async function getFleetState(options = {}) {
  if (options.sources) return projectFleetState(await options.sources.collect());
  const invoke = options.run ?? run;
  const result = await invoke('marshal', ['db', 'query', '--sql', SESSION_SQL], {
    timeoutMs: options.timeoutMs ?? 30_000,
  });
  const parsed = parseJsonStdout(result, 'marshal db query');
  return projectFleetState({
    collectedAt: new Date().toISOString(),
    sessions: parsed && Object.hasOwn(parsed, 'data') ? parsed.data : parsed,
  });
}
