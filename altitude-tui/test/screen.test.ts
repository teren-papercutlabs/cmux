import { describe, expect, test } from "bun:test";
import type { MenuAdapter } from "../src/adapter";
import { deriveMenuState, type FleetSession } from "../src/model";
import { drawMenu } from "../src/screen";

class RecordingAdapter implements MenuAdapter {
  readonly width = 80;
  readonly height = 12;
  readonly rows: Array<{ row: number; text: string }> = [];
  beginFrame(): void { this.rows.length = 0; }
  drawRow(row: number, text: string): void { this.rows.push({ row, text }); }
  drawCell(): void {}
  commit(): void {}
  onDrag(): void {}
  onMouse(): void {}
  onKey(): void {}
  onResize(): void {}
  destroy(): void {}
}

function session(index: number): FleetSession {
  return {
    sessionId: `session-${index}`,
    agentName: "agent",
    displayName: `session-${index}`,
    lifecycleState: "working",
    runtime: "codex",
    tmuxSession: `session-${index}`,
    sessionTag: null,
    sessionType: null,
    signalStatus: "progress",
    signalNeedsReply: false,
    signalSummary: "",
    signalCreatedAt: new Date(index * 1_000).toISOString(),
    lastToolCallAt: null,
    isMain: false,
  };
}

describe("menu viewport", () => {
  test("keeps the selected row visible and never draws below the terminal", () => {
    const adapter = new RecordingAdapter();
    const state = deriveMenuState(Array.from({ length: 20 }, (_, index) => session(index)), {
      now: new Date(30_000),
    });

    drawMenu(adapter, state, { selectedID: "session-19", now: new Date(30_000) });

    expect(adapter.rows.some(({ text }) => text.includes("session-19"))).toBe(true);
    expect(Math.max(...adapter.rows.map(({ row }) => row))).toBeLessThan(adapter.height);
  });

  test("mains render folded by default and only expand on request", () => {
    class TallAdapter extends RecordingAdapter { override readonly height = 24; }
    const adapter = new TallAdapter();
    const main: FleetSession = { ...session(0), sessionId: "kleya-main", displayName: "kleya-main", isMain: true };
    const state = deriveMenuState([session(1), main], { now: new Date(30_000) });

    drawMenu(adapter, state, { selectedID: "session-1", now: new Date(30_000) });
    const folded = adapter.rows.map(({ text }) => text).join("\n");
    expect(folded).toContain("MAINS  1");
    expect(folded).not.toContain("kleya-main");

    drawMenu(adapter, state, { selectedID: "session-1", now: new Date(30_000), mainsExpanded: true });
    const expanded = adapter.rows.map(({ text }) => text).join("\n");
    expect(expanded).toContain("kleya-main");
  });
});
