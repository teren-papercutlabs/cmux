# Fleet cockpit v1 verification receipt

Date: 2026-07-13 SGT. WB `c02ff745-aa1c-46e3-a246-227a3161a805`.

Disposition update: Rasim main accepted the verified socket-driven spine and classified the native fork compilation as Teren-Mac downstream verification by design. The exact five-minute build/run path is now `BUILD-ON-YOUR-MAC.md`; the Studio toolchain finding below remains as a truthful environment receipt, not an open code blocker.

## Source and origin

- PcL fork: `git@github.com:teren-papercutlabs/cmux.git`
- Upstream remote: `https://github.com/manaflow-ai/cmux.git`
- Solution shape landed first: `1961f7ed91122ac819f55bd98257432e7787b20b`
- Fleet layer: `652c80f6b5793021e5b5311629381d32df2bf29d`
- Canonical socket verbs + render alignment: `f6530a9e81540c4119b92eba4eab08e8aae47cb3`
- All three commits were pushed to `origin/main` before this receipt.

## Tests and live state

`npm test --prefix fleet-layer`: 7/7 pass.

Live `fleet-layer/bin/pcl-fleet snapshot --json` result during verification:

```json
{
  "total": 18,
  "autonomous": 1,
  "needsYou": 3,
  "running": 7,
  "idle": 8,
  "nearWall": 0,
  "autonomousPercent": 6
}
```

The autonomous entity was Rasim because loop `7ec2ab9e-6b99-4ab7-b52a-dbbd7d74f260` targeted an owned child session. The rendered roster came from `pcl agents list`; status/lineage from the live session tables; attention from latest Pharos signals; quota from live account bindings + `pcl burn quota`. No fixture data was present in the running cockpit.

## cmux integration

The signed upstream v0.64.17 app was installed at `~/Applications/cmux.app` solely to exercise the unchanged socket contract while the Studio native-build blocker below remains. Its bundled CLI reported `cmux 0.64.17 (97) [9ed29d81a]`.

Automation-mode socket: `~/.local/state/cmux/cmux-501.sock`. `cmux ping` returned `PONG`.

`pcl-fleet launch` created and selected:

```text
workspace:5  PcL Fleet Cockpit  description=pcl-fleet-cockpit
surface:5    exec .../fleet-layer/bin/pcl-fleet cockpit
```

`cmux read-screen --workspace workspace:5 --surface surface:5` showed the real 18-agent fleet. The header led with `AUTONOMOUS 1/18 · 6%`, followed by `NEEDS YOU 3`, then the per-agent state/autonomy/quota/pane table. A second read after the poll interval showed a newer collection timestamp, proving the running cmux pane refreshed live.

## Jump verification

Two consumer paths passed:

1. `pcl-fleet jump rasim` created `workspace:4`, description `pcl-agent:rasim`, attached to `rasim-main-teren`, selected it, and `read-screen` showed the live Claude Code pane.
2. From the cockpit itself, `cmux send-key --surface surface:5 enter` exercised the operator's Enter path on selected agent Edna. It created and selected `workspace:6`, description `pcl-agent:edna`; the selected surface title was `edna-main-amelia` on `ttys086`.

The second proof is the v1 acceptance path: keyboard action from the rendered cockpit through the fleet layer, cmux CLI/socket, workspace creation, and real tmux attach.

## UI review

Actual render reviewed through cmux's Ghostty screen buffer. macOS display capture was unavailable in this headless Studio session (`screencapture: could not create image from display`), so pixel-level screenshot evidence is unavailable.

ui-review verdict — cmux `workspace:5` / `surface:5` (desktop opened: yes; mobile: n/a, native terminal surface)

- readability/contrast: PASS — needs-you, running, idle, armed, quota, and unavailable states use distinct readable terminal styles.
- rendering correctness: PASS — Unicode bar/rules render correctly; no raw markup, mojibake, emoji icons, or dropped rows.
- nav/interactivity: PASS — arrows/refresh/quit are explicit; Enter was exercised end-to-end into Edna's pane; no fake control.
- comprehensibility: PASS — north star, counts, column names, attention summaries, pane availability, and controls are visible without external explanation.
- redaction calibration: PASS — internal attention summaries are present; no credential values are read or rendered.
- responsive/layout: PASS at the live terminal width — 18 rows fit without mid-word wrapping; long summaries truncate. Mobile is not a supported surface.
- system consistency: PASS — uses the host terminal's Ghostty colors/font and cmux workspace primitives; no parallel native design system.
- review-tooling integrity: N/A.

Overall: SHIP for the fleet-layer spine.

## Native fork build blocker

`./scripts/setup.sh` completed after installing Zig 0.16.0_1 and fetched/cached GhosttyKit successfully.

`./scripts/reload.sh --tag pcl-fleet --launch` then failed before compilation:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

Canonical host state:

- `xcode-select -p` → `/Library/Developer/CommandLineTools`
- `/Applications/Xcode*.app` → no match
- `swift --version` → Apple Swift 6.3.1
- `xcodebuild` is Apple's CLT stub, not a usable Xcode installation

The Studio cannot compile the native fork. Installing full Xcode.app is explicitly out of scope for this production host. Native compilation and run verification therefore move to Teren's full-Xcode Mac using `BUILD-ON-YOUR-MAC.md`; the fleet-layer spine and unchanged socket contract were already consumer-verified against a signed native cmux build.
