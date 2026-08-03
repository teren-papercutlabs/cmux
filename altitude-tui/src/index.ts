import { createAdapter, jumpToSession, returnToPreviousSurface } from "./adapter";
import { advanceSelection, deriveMenuState, describeArrival, type FleetSession, type MenuState } from "./model";
import { drawMenu, type PriorityMap } from "./screen";
import { getFleetState } from "../../fleet-layer/src/fleet-state.mjs";

const POLL_MS = 4_000;
const adapter = await createAdapter();
let state: MenuState = { needsYou: [], everythingElse: [], rows: [] };
let selectedID: string | undefined;
let arrival: string | null = null;
let error: string | null = null;
let drawing = false;
let screenRows = new Map<number, string>();

function priorities(): PriorityMap {
  try { return JSON.parse(process.env.ALTITUDE_PRIORITY_JSON ?? "{}") as PriorityMap; }
  catch { return {}; }
}

function redraw(): void {
  screenRows = drawMenu(adapter, state, { selectedID, arrival, error, priorities: priorities() }).rowByScreenLine;
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
    if (!selectedID || !state.rows.some((row) => row.sessionId === selectedID)) selectedID = state.rows[0]?.sessionId;
    error = fleet.warnings?.[0] ?? null;
  } catch (caught) {
    error = caught instanceof Error ? caught.message : String(caught);
  } finally {
    drawing = false;
    redraw();
  }
}

async function jump(): Promise<void> {
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

adapter.onKey((key) => {
  if (key.name === "escape") void returnToPreviousSurface().catch((caught) => { error = String(caught); redraw(); });
  else if (key.name === "up" || key.name === "k") { selectedID = advanceSelection(state.rows.map((row) => row.sessionId), selectedID, -1); redraw(); }
  else if (key.name === "down" || key.name === "j") { selectedID = advanceSelection(state.rows.map((row) => row.sessionId), selectedID, 1); redraw(); }
  else if (key.name === "return" || key.name === "enter") void jump();
  else if (key.name === "q" && key.ctrl) adapter.destroy();
});
adapter.onMouse((event) => {
  if (event.kind !== "press" && event.kind !== "click") return;
  const id = screenRows.get(event.row);
  if (id) { selectedID = id; redraw(); }
});
adapter.onResize(redraw);

await poll();
setInterval(() => void poll(), POLL_MS);
setInterval(redraw, 1_000);
