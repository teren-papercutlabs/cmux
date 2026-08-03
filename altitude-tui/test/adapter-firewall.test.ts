import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

// The adapter firewall: OpenTUI's API surface may be touched ONLY through
// src/adapter.ts, so an upstream rename breaks exactly one file. This test can
// go red: add `import "@opentui/core"` to any other src file and it fails.
describe("OpenTUI adapter firewall", () => {
  test("only adapter.ts imports @opentui inside src/", () => {
    const srcDir = join(import.meta.dir, "..", "src");
    const offenders = readdirSync(srcDir)
      .filter((name) => name.endsWith(".ts"))
      .filter((name) => name !== "adapter.ts")
      .filter((name) => readFileSync(join(srcDir, name), "utf8").includes("@opentui"));
    expect(offenders).toEqual([]);
  });
});
