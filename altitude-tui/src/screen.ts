import type { MenuAdapter } from "./adapter";
import { formatDuration, type MenuRow, type MenuState } from "./model";
import { t } from "./strings";

const COLOR = {
  canvas: "#0c0c0c",
  text: "#eaf0f3",
  muted: "#82878c",
  quiet: "#555b60",
  accent: "#5b97d3",
  selection: "#16354a",
  amber: "#ffcd6d",
  green: "#3dd68c",
  red: "#ff9592",
};

export type PriorityMap = { "1A"?: string; "1B"?: string };

export interface DrawResult {
  rowByScreenLine: Map<number, string>;
}

function clip(text: string, width: number): string { return text.slice(0, Math.max(0, width)); }
function pad(text: string, width: number): string { return clip(text, width).padEnd(Math.max(0, width)); }

function titleFor(row: MenuRow): string {
  return row.agentName === row.displayName ? row.displayName : `${row.agentName} · ${row.displayName}`;
}

function priorityLabel(state: MenuState, id: string | undefined): string {
  if (!id) return t("unassigned");
  const row = state.rows.find((item) => item.sessionId === id);
  return row ? titleFor(row) : t("notLive");
}

function drawSessionRow(
  adapter: MenuAdapter,
  screenRow: number,
  item: MenuRow,
  selected: boolean,
  oldest: boolean,
): void {
  const width = adapter.width;
  const duration = formatDuration(item.needsYou ? item.waitSeconds : item.idleSeconds);
  const marker = selected ? "›" : " ";
  const status = item.lifecycleState === "working" ? t("busy") : item.runtime;
  const suffix = `${status.padStart(6)}  ${duration.padStart(5)}`;
  const available = Math.max(1, width - suffix.length - 4);
  adapter.drawRow(screenRow, pad(`${marker} ${clip(titleFor(item), available)}`, width - suffix.length) + suffix, {
    fg: oldest ? COLOR.amber : COLOR.text,
    bg: selected ? COLOR.selection : COLOR.canvas,
    bold: selected,
  });
}

export function drawMenu(
  adapter: MenuAdapter,
  state: MenuState,
  options: {
    selectedID?: string;
    arrival?: string | null;
    error?: string | null;
    priorities?: PriorityMap;
    now?: Date;
  } = {},
): DrawResult {
  const now = options.now ?? new Date();
  const width = Math.max(24, adapter.width);
  const selectedID = options.selectedID;
  const rowByScreenLine = new Map<number, string>();
  let line = 0;
  adapter.beginFrame();

  const clock = now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  const hint = t("returnHint");
  const headerRight = `${clock}  ${hint}`;
  adapter.drawRow(line++, pad(t("menuTitle"), width - headerRight.length) + headerRight, {
    fg: COLOR.text, bg: COLOR.canvas, bold: true,
  });
  if (options.arrival) adapter.drawRow(line++, clip(options.arrival, width), { fg: COLOR.accent, bg: COLOR.canvas });
  else adapter.drawRow(line++, "", { bg: COLOR.canvas });

  const priorities = options.priorities ?? {};
  adapter.drawRow(line++, clip(`1A  ${priorityLabel(state, priorities["1A"])}  · ⌘1`, width), { fg: COLOR.text, bg: COLOR.canvas });
  adapter.drawRow(line++, clip(`1B  ${priorityLabel(state, priorities["1B"])}  · ⌘2`, width), { fg: COLOR.muted, bg: COLOR.canvas });
  adapter.drawRow(line++, "", { bg: COLOR.canvas });

  adapter.drawRow(line++, `${t("needsYou")}  ${state.needsYou.length}`, { fg: COLOR.muted, bg: COLOR.canvas, bold: true });
  if (state.needsYou.length === 0) {
    adapter.drawRow(line++, `  ${t("nothingNeedsYou")}`, { fg: COLOR.green, bg: COLOR.canvas });
  } else {
    state.needsYou.forEach((item, index) => {
      rowByScreenLine.set(line, item.sessionId);
      drawSessionRow(adapter, line++, item, item.sessionId === selectedID, index === 0);
      if (item.sessionId === selectedID) {
        adapter.drawRow(line++, clip(`    ${item.signalSummary || t("waitingForReply")}`, width), {
          fg: COLOR.muted, bg: COLOR.selection,
        });
      }
    });
  }

  adapter.drawRow(line++, "", { bg: COLOR.canvas });
  adapter.drawRow(line++, `${t("everythingElse")}  ${state.everythingElse.length} · ${t("descendingIdle")}`, {
    fg: COLOR.muted, bg: COLOR.canvas, bold: true,
  });
  if (state.everythingElse.length === 0) {
    adapter.drawRow(line++, `  ${t("noOtherSessions")}`, { fg: COLOR.quiet, bg: COLOR.canvas });
  } else {
    for (const item of state.everythingElse) {
      rowByScreenLine.set(line, item.sessionId);
      drawSessionRow(adapter, line++, item, item.sessionId === selectedID, false);
      if (item.sessionId === selectedID) {
        const detail = `${item.lifecycleState} · ${item.runtime} · idle ${formatDuration(item.idleSeconds)} · ${item.sessionId.slice(0, 8)}`;
        adapter.drawRow(line++, clip(`    ${detail}`, width), { fg: COLOR.muted, bg: COLOR.selection });
      }
    }
  }

  if (options.error) adapter.drawRow(Math.min(adapter.height - 2, line++), clip(options.error, width), { fg: COLOR.red, bg: COLOR.canvas });
  const footer = t("footer");
  adapter.drawRow(Math.max(line, adapter.height - 1), clip(footer, width), { fg: COLOR.quiet, bg: COLOR.canvas, dim: true });
  adapter.commit();
  return { rowByScreenLine };
}
