import { t } from "./strings";

export interface FleetSession {
  sessionId: string;
  agentName: string;
  displayName: string;
  lifecycleState: string;
  runtime: string;
  tmuxSession: string | null;
  sessionTag: string | null;
  sessionType: string | null;
  signalStatus: string;
  signalNeedsReply: boolean;
  signalSummary: string;
  signalCreatedAt: string | null;
  lastToolCallAt: string | null;
  isMain: boolean;
}

export interface MenuRow extends FleetSession {
  idleSeconds: number;
  waitSeconds: number;
  selectable: true;
  needsYou: boolean;
}

export interface MenuState {
  needsYou: MenuRow[];
  everythingElse: MenuRow[];
  rows: MenuRow[];
}

function epoch(value: string | null): number | null {
  if (!value) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function newestActivity(session: FleetSession): number | null {
  const values = [epoch(session.signalCreatedAt), epoch(session.lastToolCallAt)]
    .filter((value): value is number => value !== null);
  return values.length > 0 ? Math.max(...values) : null;
}

function isExplicitNeed(session: FleetSession): boolean {
  return session.signalNeedsReply || session.signalStatus === "question" || session.signalStatus === "blocked";
}

export function deriveMenuState(
  sessions: FleetSession[],
  options: { now?: Date } = {},
): MenuState {
  const now = (options.now ?? new Date()).getTime();
  const rows = sessions.map<MenuRow>((session) => {
    const activity = newestActivity(session);
    const signal = epoch(session.signalCreatedAt);
    return {
      ...session,
      idleSeconds: activity === null ? 0 : Math.max(0, Math.floor((now - activity) / 1000)),
      waitSeconds: signal === null ? 0 : Math.max(0, Math.floor((now - signal) / 1000)),
      selectable: true,
      needsYou: !session.isMain && isExplicitNeed(session),
    };
  });
  const needsYou = rows
    .filter((row) => row.needsYou)
    .sort((a, b) => b.waitSeconds - a.waitSeconds || a.displayName.localeCompare(b.displayName));
  const everythingElse = rows
    .filter((row) => !row.needsYou)
    .sort((a, b) => b.idleSeconds - a.idleSeconds || a.displayName.localeCompare(b.displayName));
  return { needsYou, everythingElse, rows: [...needsYou, ...everythingElse] };
}

export function advanceSelection(ids: string[], selected: string | undefined, delta: number): string | undefined {
  if (ids.length === 0) return undefined;
  const index = selected === undefined ? -1 : ids.indexOf(selected);
  const base = index < 0 ? (delta < 0 ? 0 : -1) : index;
  return ids[(base + delta + ids.length) % ids.length];
}

export function describeArrival(before: MenuState, after: MenuState): string | null {
  const oldIds = new Set(before.rows.map((row) => row.sessionId));
  const newIds = new Set(after.rows.map((row) => row.sessionId));
  const arrived = after.rows.filter((row) => !oldIds.has(row.sessionId));
  const finished = before.rows.filter((row) => !newIds.has(row.sessionId));
  const changedNeeds = after.needsYou.length - before.needsYou.length;
  if (arrived.length === 0 && finished.length === 0 && changedNeeds === 0) return null;
  const parts: string[] = [];
  if (arrived.length > 0) parts.push(`${arrived.length} ${t("arrived")}`);
  if (finished.length > 0) parts.push(`${finished.map((row) => row.displayName).join(", ")} ${t("finished")}`);
  if (changedNeeds > 0) parts.push(`${changedNeeds} ${t("nowNeedsYou")}`);
  return `${t("sinceYouLeft")} · ${parts.join(" · ")}`;
}

export function formatDuration(seconds: number): string {
  if (seconds < 60) return "<1m";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
  return `${Math.floor(seconds / 86400)}d`;
}
