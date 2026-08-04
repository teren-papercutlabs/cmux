import { readFile } from "node:fs/promises";
import { createCliRenderer, TextAttributes, TextRenderable, type CliRenderer, type KeyEvent, type MouseEvent } from "@opentui/core";
import { t } from "./strings";

export type AdapterMouseEvent = {
  kind: "hover" | "press" | "drag" | "release" | "click";
  column: number;
  row: number;
};

type MouseLike = { type?: string; name?: string; x: number; y: number; button?: number };

export function mapMouseEvent(event: MouseLike): AdapterMouseEvent | null {
  const name = event.type ?? event.name;
  const kind = name === "over" || name === "move" ? "hover"
    : name === "down" ? "press"
    : name === "drag" ? "drag"
    : name === "up" || name === "drag-end" || name === "drop" ? "release"
    : name === "click" ? "click"
    : null;
  return kind ? { kind, column: event.x, row: event.y } : null;
}

export type DrawStyle = { fg?: string; bg?: string; bold?: boolean; dim?: boolean };
export type AdapterKey = { name: string; ctrl: boolean; meta: boolean; shift: boolean; sequence: string };

export interface MenuAdapter {
  readonly width: number;
  readonly height: number;
  beginFrame(): void;
  drawRow(row: number, text: string, style?: DrawStyle): void;
  drawCell(row: number, column: number, text: string, style?: DrawStyle): void;
  commit(): void;
  onDrag(handler: (event: AdapterMouseEvent) => void): void;
  onMouse(handler: (event: AdapterMouseEvent) => void): void;
  onKey(handler: (event: AdapterKey) => void): void;
  onResize(handler: () => void): void;
  destroy(): void;
}

type Cell = { row: number; column: number; text: string; style: DrawStyle };

class OpenTUIAdapter implements MenuAdapter {
  private cells: Cell[] = [];
  private renderables: TextRenderable[] = [];
  private mouseHandlers: Array<(event: AdapterMouseEvent) => void> = [];
  private dragHandlers: Array<(event: AdapterMouseEvent) => void> = [];
  private readonly screen: TextRenderable;

  constructor(private readonly renderer: CliRenderer) {
    this.screen = new TextRenderable(renderer, {
      id: "altitude-menu-hit-surface",
      width: "100%",
      height: "100%",
      content: "",
      onMouse: (event) => this.dispatchMouse(event),
    });
    renderer.root.add(this.screen);
  }

  get width(): number { return this.renderer.width; }
  get height(): number { return this.renderer.height; }

  beginFrame(): void { this.cells = []; }

  drawRow(row: number, text: string, style: DrawStyle = {}): void {
    // Full-bleed: pad every row to the surface width so the style background
    // covers the whole line — otherwise the terminal's own (translucent)
    // background bleeds through around each text run.
    this.cells.push({ row, column: 0, text: text.padEnd(this.width).slice(0, this.width), style });
  }

  drawCell(row: number, column: number, text: string, style: DrawStyle = {}): void {
    if (column >= this.width) return;
    this.cells.push({ row, column, text: text.slice(0, Math.max(0, this.width - column)), style });
  }

  commit(): void {
    while (this.renderables.length < this.cells.length) {
      const index = this.renderables.length;
      const row = new TextRenderable(this.renderer, {
        id: `altitude-menu-cell-${index}`,
        position: "absolute",
        height: 1,
        content: "",
        onMouse: (event) => this.dispatchMouse(event),
      });
      this.renderer.root.add(row);
      this.renderables.push(row);
    }
    for (let index = 0; index < this.renderables.length; index += 1) {
      const renderable = this.renderables[index];
      const cell = this.cells[index];
      if (!cell) {
        renderable.visible = false;
        continue;
      }
      renderable.visible = true;
      renderable.x = cell.column;
      renderable.y = cell.row;
      renderable.width = Math.max(1, cell.text.length);
      renderable.content = cell.text;
      renderable.fg = cell.style.fg;
      renderable.bg = cell.style.bg;
      renderable.attributes = (cell.style.bold ? TextAttributes.BOLD : 0)
        | (cell.style.dim ? TextAttributes.DIM : 0);
    }
    this.renderer.requestRender();
  }

  onDrag(handler: (event: AdapterMouseEvent) => void): void { this.dragHandlers.push(handler); }
  onMouse(handler: (event: AdapterMouseEvent) => void): void { this.mouseHandlers.push(handler); }
  onKey(handler: (event: AdapterKey) => void): void {
    this.renderer.keyInput.on("keypress", (key: KeyEvent) => handler({
      name: key.name,
      ctrl: key.ctrl,
      meta: key.meta,
      shift: key.shift,
      sequence: key.sequence,
    }));
  }
  onResize(handler: () => void): void { this.renderer.on("resize", handler); }
  destroy(): void { this.renderer.destroy(); }

  private dispatchMouse(event: MouseEvent): void {
    const mapped = mapMouseEvent(event);
    if (!mapped) return;
    for (const handler of this.mouseHandlers) handler(mapped);
    if (mapped.kind === "press" || mapped.kind === "drag" || mapped.kind === "release") {
      for (const handler of this.dragHandlers) handler(mapped);
    }
  }
}

export async function createAdapter(): Promise<MenuAdapter> {
  const renderer = await createCliRenderer({
    clearOnShutdown: true,
    enableMouseMovement: true,
    targetFps: 30,
  });
  process.stdout.write(`\u001b]0;${t("windowTitle")}\u0007`);
  return new OpenTUIAdapter(renderer);
}

function controlCLI(): string {
  return process.env.CMUX_BUNDLED_CLI_PATH ?? process.env.CMUX_CLI ?? "cmux";
}

async function runControl(args: string[]): Promise<void> {
  const processHandle = Bun.spawn([controlCLI(), ...args], { stdout: "ignore", stderr: "pipe" });
  const status = await processHandle.exited;
  if (status !== 0) throw new Error((await new Response(processHandle.stderr).text()).trim() || `${t("controlExited")} ${status}`);
}

async function readControl(args: string[]): Promise<string> {
  const processHandle = Bun.spawn([controlCLI(), ...args], { stdout: "pipe", stderr: "pipe" });
  const status = await processHandle.exited;
  if (status !== 0) throw new Error((await new Response(processHandle.stderr).text()).trim() || `${t("controlExited")} ${status}`);
  return new Response(processHandle.stdout).text();
}

/** Fields a surface may legitimately be addressed by. Matching the whole
 *  serialized surface would let a cwd or command substring steal the match
 *  and focus an unrelated pane. */
const SURFACE_NAME_KEYS = [
  "title", "name", "tabTitle", "displayName",
  "checkpointId", "resumeCheckpointId", "sessionId", "tmuxSession",
] as const;

export function surfaceNameCandidates(surface: Record<string, unknown>): string[] {
  return SURFACE_NAME_KEYS
    .map((key) => surface[key])
    .filter((value): value is string => typeof value === "string" && value.length > 0);
}

function normalizedName(value: string): string {
  // Tab titles carry seat/transport prefixes ("[1A] ", "[mosh] ") that the
  // fleet layer's session names do not.
  return value.toLowerCase().replace(/^\[\d+[a-z]\] /, "").replace(/^\[mosh\] /, "");
}

export function surfaceMatches(surface: Record<string, unknown>, query: string, exact: boolean): boolean {
  const needle = query.toLowerCase();
  return surfaceNameCandidates(surface).some((candidate) => {
    const name = normalizedName(candidate);
    return exact ? name === needle : name.includes(needle);
  });
}

async function findSurface(query: string): Promise<{ workspaceID: string; panelID: string } | null> {
  const tree = JSON.parse(await readControl(["--json", "--id-format", "uuids", "tree", "--all"])) as {
    windows?: Array<{ workspaces?: Array<{ id?: string; panes?: Array<{ surfaces?: Array<Record<string, unknown>> }> }> }>;
  };
  for (const exact of [true, false]) {
    for (const window of tree.windows ?? []) {
      for (const workspace of window.workspaces ?? []) {
        for (const pane of workspace.panes ?? []) {
          for (const surface of pane.surfaces ?? []) {
            const panelID = typeof surface.id === "string" ? surface.id : null;
            if (panelID && workspace.id && surfaceMatches(surface, query, exact)) {
              return { workspaceID: workspace.id, panelID };
            }
          }
        }
      }
    }
  }
  return null;
}

/** Anoint the session's surface into a seat (decision 27: membership IS the
 *  seat; the app moves it into Priority and displaces the old holder). */
export async function anointSession(query: string, role: "1A" | "1B"): Promise<void> {
  const found = await findSurface(query);
  if (!found) throw new Error(`${t("noSurfaceFor")} ${query}`);
  await runControl([
    "tab-action",
    "--action", role === "1A" ? "anoint-1a" : "anoint-1b",
    "--surface", found.panelID,
    "--workspace", found.workspaceID,
  ]);
}

/** Uses cmux's existing control-socket CLI; this program creates no IPC service. */
export async function jumpToSession(query: string): Promise<void> {
  const tree = JSON.parse(await readControl(["--json", "--id-format", "uuids", "tree", "--all"])) as {
    windows?: Array<{ workspaces?: Array<{ id?: string; panes?: Array<{ surfaces?: Array<Record<string, unknown>> }> }> }>;
  };
  // Exact name match first; substring on named fields only as fallback.
  for (const exact of [true, false]) {
    for (const window of tree.windows ?? []) {
      for (const workspace of window.workspaces ?? []) {
        for (const pane of workspace.panes ?? []) {
          for (const surface of pane.surfaces ?? []) {
            const panelID = typeof surface.id === "string" ? surface.id : null;
            if (panelID && workspace.id && surfaceMatches(surface, query, exact)) {
              await runControl(["focus-panel", "--workspace", workspace.id, "--panel", panelID]);
              return;
            }
          }
        }
      }
    }
  }
  await runControl(["find-window", "--content", "--select", query]);
}

/** Esc returns through a host-written workspace/panel target via the same control CLI. */
export async function returnToPreviousSurface(): Promise<void> {
  const path = process.env.ALTITUDE_RETURN_TARGET_FILE;
  if (!path) return;
  const target = JSON.parse(await readFile(path, "utf8")) as { workspaceId: string; panelId: string };
  await runControl(["focus-panel", "--workspace", target.workspaceId, "--panel", target.panelId]);
}
