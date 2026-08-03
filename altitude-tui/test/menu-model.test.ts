import { describe, expect, test } from "bun:test";
import {
  advanceSelection,
  deriveMenuState,
  describeArrival,
  type FleetSession,
} from "../src/model";

const now = new Date("2026-08-03T04:00:00.000Z");

function session(overrides: Partial<FleetSession> & Pick<FleetSession, "sessionId">): FleetSession {
  return {
    sessionId: overrides.sessionId,
    agentName: overrides.agentName ?? "xianxing",
    displayName: overrides.displayName ?? overrides.sessionId,
    lifecycleState: overrides.lifecycleState ?? "idle",
    runtime: overrides.runtime ?? "cc",
    tmuxSession: overrides.tmuxSession ?? overrides.sessionId,
    sessionTag: overrides.sessionTag ?? "worker",
    sessionType: overrides.sessionType ?? "worker",
    signalStatus: overrides.signalStatus ?? "",
    signalNeedsReply: overrides.signalNeedsReply ?? false,
    signalSummary: overrides.signalSummary ?? "",
    signalCreatedAt: overrides.signalCreatedAt ?? null,
    lastToolCallAt: overrides.lastToolCallAt ?? null,
    isMain: overrides.isMain ?? false,
    ...overrides,
  };
}

describe("Altitude menu state", () => {
  test("idle uses the newest signal or tool call and sorts all sessions descending", () => {
    const state = deriveMenuState([
      session({
        sessionId: "new-signal",
        signalCreatedAt: "2026-08-03T03:58:00.000Z",
        lastToolCallAt: "2026-08-03T03:10:00.000Z",
      }),
      session({
        sessionId: "new-tool",
        signalCreatedAt: "2026-08-03T02:00:00.000Z",
        lastToolCallAt: "2026-08-03T03:55:00.000Z",
      }),
      session({ sessionId: "oldest", lastToolCallAt: "2026-08-03T01:00:00.000Z" }),
      session({ sessionId: "busy", lifecycleState: "working", lastToolCallAt: now.toISOString() }),
    ], { now });

    expect(state.everythingElse.map((row) => row.sessionId)).toEqual([
      "oldest", "new-tool", "new-signal", "busy",
    ]);
    expect(state.everythingElse.find((row) => row.sessionId === "new-signal")?.idleSeconds).toBe(120);
    expect(state.everythingElse.find((row) => row.sessionId === "new-tool")?.idleSeconds).toBe(300);
    expect(state.everythingElse.at(-1)?.idleSeconds).toBe(0);
  });

  test("needs-you requires an explicit signal, suppresses mains only there, and keeps every row selectable", () => {
    const main = session({
      sessionId: "teren-main",
      isMain: true,
      signalStatus: "blocked",
      signalCreatedAt: "2026-08-03T03:00:00.000Z",
      signalSummary: "principal main wait",
    });
    const question = session({
      sessionId: "question",
      signalStatus: "question",
      signalCreatedAt: "2026-08-03T03:40:00.000Z",
      signalSummary: "Pick A or B",
    });
    const needsReply = session({
      sessionId: "reply",
      signalNeedsReply: true,
      signalCreatedAt: "2026-08-03T03:50:00.000Z",
      signalSummary: "Acknowledge the path",
    });
    const working = session({ sessionId: "working", lifecycleState: "working" });
    const state = deriveMenuState([main, question, needsReply, working], { now });

    expect(state.needsYou.map((row) => row.sessionId)).toEqual(["question", "reply"]);
    expect(state.everythingElse.map((row) => row.sessionId)).toContain("teren-main");
    expect(state.rows.map((row) => row.sessionId)).toEqual([
      "question", "reply", "teren-main", "working",
    ]);
    expect(state.rows.every((row) => row.selectable)).toBeTrue();
  });

  test("selection wraps and expansion follows the selected row inline", () => {
    const ids = ["one", "two", "three"];
    expect(advanceSelection(ids, "one", -1)).toBe("three");
    expect(advanceSelection(ids, "three", 1)).toBe("one");
    expect(advanceSelection(ids, undefined, 1)).toBe("one");
  });

  test("arrival reports one since-you-left delta and stable snapshots stay quiet", () => {
    const before = deriveMenuState([session({ sessionId: "done" })], { now });
    const after = deriveMenuState([session({
      sessionId: "waiting",
      signalStatus: "question",
      signalCreatedAt: now.toISOString(),
    })], { now });
    expect(describeArrival(before, after)).toContain("done finished");
    expect(describeArrival(after, after)).toBeNull();
  });
});
