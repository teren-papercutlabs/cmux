import { describe, expect, test } from "bun:test";
import { mapMouseEvent } from "../src/adapter";

describe("OpenTUI adapter event mapping", () => {
  test("maps hover, press-drag-release, and click coordinates without leaking OpenTUI types", () => {
    expect(mapMouseEvent({ name: "over", x: 7, y: 4 })).toEqual({ kind: "hover", column: 7, row: 4 });
    expect(mapMouseEvent({ name: "down", x: 7, y: 4, button: 0 })).toEqual({ kind: "press", column: 7, row: 4 });
    expect(mapMouseEvent({ name: "drag", x: 10, y: 6, button: 0 })).toEqual({ kind: "drag", column: 10, row: 6 });
    expect(mapMouseEvent({ name: "up", x: 10, y: 6, button: 0 })).toEqual({ kind: "release", column: 10, row: 6 });
    expect(mapMouseEvent({ name: "click", x: 12, y: 8, button: 0 })).toEqual({ kind: "click", column: 12, row: 8 });
  });
});
