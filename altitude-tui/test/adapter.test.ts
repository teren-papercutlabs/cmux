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

describe("jump target matching", () => {
  const { surfaceMatches } = require("../src/adapter");
  const surface = {
    id: "u-1",
    title: "[1A] [mosh] edna-tgg",
    cwd: "/Users/teren/edna-notes",
    command: "office a edna-tgg",
  };
  test("matches named fields, with prefixes stripped", () => {
    expect(surfaceMatches(surface, "edna-tgg", true)).toBeTrue();
  });
  test("a cwd or command substring can never steal the match", () => {
    // "edna" appears in cwd and command of an unrelated surface; only NAMED
    // fields may match, so a surface named otherwise must not.
    const unrelated = { id: "u-2", title: "kleya-hive-drive", cwd: "/Users/teren/edna-notes", command: "tail edna.log" };
    expect(surfaceMatches(unrelated, "edna", false)).toBeFalse();
  });
});
