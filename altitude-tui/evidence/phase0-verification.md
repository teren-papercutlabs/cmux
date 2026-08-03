# Phase 0 OpenTUI drag spike verification

Verified on 2026-08-03 in a real GhosttyKit terminal surface (`surface:1`, tty `ttys083`) inside the isolated tagged cmux Debug app `altitude-p41-spike`. No principal application or window was used.

## Versions

- Bun: `1.3.14` (package manager and runtime, exact-pinned)
- `@opentui/core`: `0.4.5` (exact-pinned)
- GhosttyKit: `bb30526cdab8f5fb08ae43e404e3aacc40d3ffc3`

## Evidence

`phase0-events.jsonl` was written by the OpenTUI process from its `onMouse` callback while Ghostty delivered a programmatic input trace through the existing Debug Ghostty surface harness:

- hover without a button: frames 2-3 (`over`, `move`)
- click mapping: frame 4 maps terminal `x=21,y=18` to grid cell `51,37`
- press-drag-release: frame 4 `down`, frames 5-23 `drag`, frame 24 `up`
- pan: horizontal viewport offset advances once per drag event from 30 to 11
- synchronized output: the single `draw()` commit increments one frame per callback; the evidence sequence is contiguous from frame 2 through frame 24 with no duplicated or missing frame while offset changes

The harness invoked Ghostty's actual `ghostty_surface_mouse_pos` and `ghostty_surface_mouse_button` path against the live OpenTUI process. It did not inject terminal escape sequences or bypass Ghostty.
