import type { MenuAdapter } from "./adapter";
import { formatDuration, idleLabel, MAINS_TOGGLE_ID, type MenuRow, type MenuState } from "./model";
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

type BodyEntry = {
  sessionID?: string;
  draw: (screenRow: number) => void;
};

function clip(text: string, width: number): string { return text.slice(0, Math.max(0, width)); }
function pad(text: string, width: number): string { return clip(text, width).padEnd(Math.max(0, width)); }

function titleFor(row: MenuRow): string {
  return row.agentName === row.displayName ? row.displayName : `${row.agentName} · ${row.displayName}`;
}

function priorityLine(state: MenuState, priority: "1A" | "1B", id: string | undefined): string {
  if (!id) return `${priority}  ${t("unassigned")}`;
  // The priority payload carries resume checkpoint ids, which are tmux session
  // names — the fleet's sessionId is a UUID, so match either.
  const row = state.rows.find((item) => item.sessionId === id || item.tmuxSession === id);
  if (!row) return `${priority}  ${t("notLive")}`;
  const stateLabel = row.lifecycleState === "working" ? t("working") : row.lifecycleState;
  const needLabel = row.needsYou ? t("needsYouShort") : t("noNeed");
  return `${priority}  ${titleFor(row)}  ${stateLabel} · ${needLabel} · ${idleLabel(row)}`;
}

function drawSessionRow(
  adapter: MenuAdapter,
  screenRow: number,
  item: MenuRow,
  selected: boolean,
  oldest: boolean,
): void {
  const width = adapter.width;
  const duration = item.needsYou ? formatDuration(item.waitSeconds) : idleLabel(item);
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
    mainsExpanded?: boolean;
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
  adapter.drawRow(line++, clip(`${priorityLine(state, "1A", priorities["1A"])}  · ⌘1`, width), { fg: COLOR.text, bg: COLOR.canvas });
  adapter.drawRow(line++, clip(`${priorityLine(state, "1B", priorities["1B"])}  · ⌘2`, width), { fg: COLOR.muted, bg: COLOR.canvas });
  adapter.drawRow(line++, "", { bg: COLOR.canvas });

  const body: BodyEntry[] = [];
  body.push({
    draw: (screenRow) => adapter.drawRow(screenRow, `${t("needsYou")}  ${state.needsYou.length}`, {
      fg: COLOR.muted, bg: COLOR.canvas, bold: true,
    }),
  });
  if (state.needsYou.length === 0) {
    body.push({ draw: (screenRow) => adapter.drawRow(screenRow, `  ${t("nothingNeedsYou")}`, { fg: COLOR.green, bg: COLOR.canvas }) });
  } else {
    state.needsYou.forEach((item, index) => {
      body.push({
        sessionID: item.sessionId,
        draw: (screenRow) => drawSessionRow(adapter, screenRow, item, item.sessionId === selectedID, index === 0),
      });
      if (item.sessionId === selectedID) {
        body.push({
          sessionID: item.sessionId,
          draw: (screenRow) => adapter.drawRow(screenRow, clip(`    ${item.signalSummary || t("waitingForReply")}`, width), {
            fg: COLOR.muted, bg: COLOR.selection,
          }),
        });
      }
    });
  }

  body.push({ draw: (screenRow) => adapter.drawRow(screenRow, "", { bg: COLOR.canvas }) });
  body.push({
    draw: (screenRow) => adapter.drawRow(screenRow, `${t("everythingElse")}  ${state.everythingElse.length} · ${t("descendingIdle")}`, {
      fg: COLOR.muted, bg: COLOR.canvas, bold: true,
    }),
  });
  if (state.everythingElse.length === 0) {
    body.push({ draw: (screenRow) => adapter.drawRow(screenRow, `  ${t("noOtherSessions")}`, { fg: COLOR.quiet, bg: COLOR.canvas }) });
  } else {
    for (const item of state.everythingElse) {
      body.push({
        sessionID: item.sessionId,
        draw: (screenRow) => drawSessionRow(adapter, screenRow, item, item.sessionId === selectedID, false),
      });
      if (item.sessionId === selectedID) {
        const detail = `${item.lifecycleState} · ${item.runtime} · ${t("idle")} ${idleLabel(item)} · ${item.sessionId.slice(0, 8)}`;
        body.push({
          sessionID: item.sessionId,
          draw: (screenRow) => adapter.drawRow(screenRow, clip(`    ${detail}`, width), { fg: COLOR.muted, bg: COLOR.selection }),
        });
      }
    }
  }

  // MAINS: a separate FOLDED section one extra step away (decision 23). The
  // toggle line itself is a selection stop; mains rows render only expanded.
  if (state.mains.length > 0) {
    const mainsExpanded = options.mainsExpanded ?? false;
    body.push({ draw: (screenRow) => adapter.drawRow(screenRow, "", { bg: COLOR.canvas }) });
    body.push({
      sessionID: MAINS_TOGGLE_ID,
      draw: (screenRow) => {
        const chevron = mainsExpanded ? "▾" : "▸";
        const hint = mainsExpanded ? t("mainsCollapseHint") : t("mainsExpandHint");
        adapter.drawRow(screenRow, `${chevron} ${t("mains")}  ${state.mains.length} · ${hint}`, {
          fg: COLOR.muted,
          bg: selectedID === MAINS_TOGGLE_ID ? COLOR.selection : COLOR.canvas,
          bold: true,
        });
      },
    });
    if (mainsExpanded) {
      for (const item of state.mains) {
        body.push({
          sessionID: item.sessionId,
          draw: (screenRow) => drawSessionRow(adapter, screenRow, item, item.sessionId === selectedID, false),
        });
        if (item.sessionId === selectedID) {
          const detail = `${item.lifecycleState} · ${item.runtime} · ${t("idle")} ${idleLabel(item)} · ${item.sessionId.slice(0, 8)}`;
          body.push({
            sessionID: item.sessionId,
            draw: (screenRow) => adapter.drawRow(screenRow, clip(`    ${detail}`, width), { fg: COLOR.muted, bg: COLOR.selection }),
          });
        }
      }
    }
  }

  const footerLine = Math.max(0, adapter.height - 1);
  const errorLine = options.error ? Math.max(line, footerLine - 1) : null;
  const bodyEnd = errorLine ?? footerLine;
  const bodyHeight = Math.max(0, bodyEnd - line);
  const selectedIndex = body.findIndex((entry) => entry.sessionID === selectedID);
  const centeredStart = selectedIndex < 0 ? 0 : selectedIndex - Math.floor(bodyHeight / 2);
  const viewportStart = Math.max(0, Math.min(centeredStart, Math.max(0, body.length - bodyHeight)));
  const visibleBody = body.slice(viewportStart, viewportStart + bodyHeight);
  visibleBody.forEach((entry, index) => {
    const screenRow = line + index;
    entry.draw(screenRow);
    if (entry.sessionID) rowByScreenLine.set(screenRow, entry.sessionID);
  });
  // Paint the unused band below the body so the canvas is full-bleed instead
  // of the terminal background showing through.
  for (let screenRow = line + visibleBody.length; screenRow < bodyEnd; screenRow += 1) {
    adapter.drawRow(screenRow, "", { bg: COLOR.canvas });
  }

  if (options.error && errorLine !== null && errorLine < footerLine) {
    adapter.drawRow(errorLine, clip(options.error, width), { fg: COLOR.red, bg: COLOR.canvas });
  }
  adapter.drawRow(footerLine, clip(t("footer"), width), { fg: COLOR.quiet, bg: COLOR.canvas, dim: true });
  adapter.commit();
  return { rowByScreenLine };
}
