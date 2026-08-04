import { anointSession, createAdapter, jumpToSession, returnToPreviousSurface } from "./adapter";
import {
  advanceSelection,
  deriveMenuState,
  describeArrival,
  MAINS_TOGGLE_ID,
  selectableIds,
  type FleetSession,
  type MenuState,
} from "./model";
import { drawMenu, type PriorityMap } from "./screen";
import { getFleetState } from "../../fleet-layer/src/fleet-state.mjs";

const POLL_MS = 4_000;
const adapter = await createAdapter();
let state: MenuState = { needsYou: [], everythingElse: [], mains: [], rows: [] };
let selectedID: string | undefined;
let mainsExpanded = false;
let arrival: string | null = null;
let error: string | null = null;
let drawing = false;
let screenRows = new Map<number, string>();
let pollTimer: ReturnType<typeof setInterval> | undefined;
let tickTimer: ReturnType<typeof setInterval> | undefined;

function priorities(): PriorityMap {
  try { return JSON.parse(process.env.ALTITUDE_PRIORITY_JSON ?? "{}") as PriorityMap; }
  catch { return {}; }
}

function redraw(): void {
  screenRows = drawMenu(adapter, state, {
    selectedID, arrival, error, priorities: priorities(), mainsExpanded,
  }).rowByScreenLine;
}

async function poll(): Promise<void> {
  if (drawing) return;
  drawing = true;
  try {
    const fleet = await getFleetState() as { sessions: FleetSession[]; warnings?: string[] };
    const next = deriveMenuState(fleet.sessions);
    const nextArrival = state.rows.length === 0 ? null : describeArrival(state, next);
    if (nextArrival) arrival = nextArrival;
    state = next;
    const ids = selectableIds(state, mainsExpanded);
    if (!selectedID || !ids.includes(selectedID)) selectedID = ids[0];
    error = fleet.warnings?.[0] ?? null;
  } catch (caught) {
    error = caught instanceof Error ? caught.message : String(caught);
  } finally {
    drawing = false;
    redraw();
  }
}

function toggleMains(): void {
  mainsExpanded = !mainsExpanded;
  if (!mainsExpanded && selectedID && state.mains.some((row) => row.sessionId === selectedID)) {
    selectedID = MAINS_TOGGLE_ID;
  }
  redraw();
}

async function jump(): Promise<void> {
  if (selectedID === MAINS_TOGGLE_ID) { toggleMains(); return; }
  const row = state.rows.find((item) => item.sessionId === selectedID);
  if (!row) return;
  try {
    await jumpToSession(row.tmuxSession ?? row.displayName ?? row.sessionId);
    error = null;
  } catch (caught) {
    error = caught instanceof Error ? caught.message : String(caught);
    redraw();
  }
}

async function anoint(role: "1A" | "1B"): Promise<void> {
  if (selectedID === MAINS_TOGGLE_ID) return;
  const row = state.rows.find((item) => item.sessionId === selectedID);
  if (!row) return;
  try {
    await anointSession(row.tmuxSession ?? row.displayName ?? row.sessionId, role);
    error = null;
    arrival = `${row.displayName} → ${role}`;
  } catch (caught) {
    error = caught instanceof Error ? caught.message : String(caught);
  }
  redraw();
}

function move(delta: number): void {
  selectedID = advanceSelection(selectableIds(state, mainsExpanded), selectedID, delta);
  redraw();
}

function shutdown(): void {
  if (pollTimer !== undefined) clearInterval(pollTimer);
  if (tickTimer !== undefined) clearInterval(tickTimer);
  adapter.destroy();
  process.exit(0);
}

adapter.onKey((key) => {
  if (key.name === "escape") void returnToPreviousSurface().catch((caught) => { error = String(caught); redraw(); });
  else if (key.name === "up" || key.name === "k") move(-1);
  else if (key.name === "down" || key.name === "j") move(1);
  else if (key.name === "m" && !key.ctrl) toggleMains();
  else if ((key.name === "1" || key.name === "2") && !key.ctrl) void anoint(key.name === "1" ? "1A" : "1B");
  else if (key.name === "return" || key.name === "enter") void jump();
  else if (key.name === "q" && key.ctrl) shutdown();
});
adapter.onMouse((event) => {
  if (event.kind !== "press" && event.kind !== "click") return;
  const id = screenRows.get(event.row);
  if (id === MAINS_TOGGLE_ID) { selectedID = id; toggleMains(); return; }
  if (id) { selectedID = id; redraw(); }
});
adapter.onResize(redraw);

await poll();
pollTimer = setInterval(() => void poll(), POLL_MS);
tickTimer = setInterval(redraw, 1_000);
