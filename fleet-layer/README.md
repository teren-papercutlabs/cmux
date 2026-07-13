# PcL fleet cockpit

Mission control for the autonomous PcL fleet, hosted inside cmux. The primary read is the percentage of active agents with a registered autonomous loop. `needs-you` is the exception queue.

This is a dependency-free Node sidecar. On Teren's Mac it reads one viewer-scoped,
complete snapshot from the Studio through the Office CLI, then controls local cmux
through the supported CLI/unix socket. It does not copy Studio database credentials
to the Mac and does not write fleet state.

## What v1 shows

- active agent entities, with child sessions folded into their root owner;
- `running`, `idle`, or `needs-you` from lifecycle + latest Pharos signal;
- `ARMED` only when `pcl loop list --status active` targets an owned session;
- quota headroom from the owned session's account binding + `pcl burn quota`;
- a pane-ready indicator and keyboard jump to the existing tmux session.

## Studio build and live run

The native build requires the full Xcode app. `xcodebuild` existing as the
Command Line Tools stub is not sufficient:

```bash
xcode-select -p
xcodebuild -version
```

The first command must resolve inside `Xcode.app`; the second must print an
Xcode version rather than `requires Xcode`.

For external Terminal-driven `doctor` / `launch`, set cmux Settings →
Automation → Socket Control Mode to **Automation mode**. That mode accepts
same-macOS-user automation without opening the socket to other local users.
The default **cmux processes only** mode is also safe: run
`fleet-layer/bin/pcl-fleet cockpit` from an existing cmux terminal instead of
using `launch` externally.

```bash
git clone --recurse-submodules git@github.com:teren-papercutlabs/cmux.git ~/pcl/cmux
cd ~/pcl/cmux
./scripts/setup.sh
./scripts/reload.sh --tag pcl-fleet --launch

CMUX_TAG=pcl-fleet CMUX_CLI="$PWD/scripts/cmux-debug-cli.sh" \
  fleet-layer/bin/pcl-fleet doctor
CMUX_TAG=pcl-fleet CMUX_CLI="$PWD/scripts/cmux-debug-cli.sh" \
  fleet-layer/bin/pcl-fleet launch
```

The tagged helper selects `/tmp/cmux-debug-pcl-fleet.sock` and the CLI bundled with the matching app. Do not use an untagged debug build.

Run a source-only Studio smoke without cmux:

```bash
PCL_FLEET_TRANSPORT=local fleet-layer/bin/pcl-fleet snapshot --json
```

The snapshot must contain a non-empty `agents` array and internally consistent `counts`. It is real live state, not a fixture.

## Teren's Mac: Office bridge

Prerequisites: the PcL fork build of cmux, Node 22+, and the Office CLI with
`--machine` support. Office remains the only machine boundary: snapshot refreshes
use its SSH transport and jumps use its existing mosh attach path. The MBA does not
need PcL database credentials, local Studio tmux sessions, or local `pcl`/`marshal`
installations.

```bash
cd ~/pcl/cmux
fleet-layer/bin/pcl-fleet snapshot --viewer-id 276672685 --json
fleet-layer/bin/pcl-fleet launch --viewer-id 276672685
```

The refresh command is fixed argv, not interpolated shell text:

```bash
office --machine run -- pcl fleet snapshot --viewer-id 276672685
```

Machine mode skips Office's updater/background fetch and routine logger writes,
so the 10-second cockpit poll does not grow `~/.office/logs/office.log`. The
subprocess has a 45-second outer timeout and an 8 MiB output cap. A refresh is
accepted only after the full snapshot passes its schema/count invariants.

`PCL_OFFICE_CLI` overrides Office discovery. Otherwise the fleet layer uses
`~/.local/bin/office` when present, then falls back to `office` on `PATH`.
`--viewer-id` is required and becomes part of every managed workspace identity.
`PCL_FLEET_VIEWER_ID` can supply the same value as a local default, but
`launch --viewer-id ...` embeds the validated viewer in the spawned cockpit so
it does not depend on the caller's transient environment.

`launch` also embeds the resolved `CMUX_CLI`, `CMUX_SOCKET_PATH`, tagged-build
metadata, and Office path into the cockpit command. That keeps refresh and Enter
bound to the installed fork app and its exact socket after the external launch
process exits.

## Controls

- `↑` / `↓`: choose an agent
- Enter: focus its existing workspace, or create one attached to its tmux session
- `r`: refresh now
- `q`: close the cockpit process

The cockpit refreshes every 10 seconds. Override with `PCL_FLEET_POLL_MS`. Quota is near-wall at 15% remaining by default; override with `PCL_FLEET_NEAR_WALL_HEADROOM`. A failed refresh retains only the last complete snapshot and labels it `STALE` with its age. Before any complete snapshot, failure is labelled `OFFLINE`.

## Commands

```text
pcl-fleet snapshot --viewer-id <principal-id> [--json]
pcl-fleet cockpit --viewer-id <principal-id>
pcl-fleet launch --viewer-id <principal-id>
pcl-fleet jump <agent-id> --viewer-id <principal-id>
pcl-fleet doctor --viewer-id <principal-id>
```

`doctor` checks both the viewer-scoped Studio projection through Office and local
cmux socket reachability. Use `PCL_FLEET_TRANSPORT=local` only for a Studio-side
diagnostic of the legacy multi-source collector.

## Failure posture

- Required source failure fails the refresh loudly; it never turns absence into idle.
- Missing account binding renders quota `unknown`; the global selected seat is not guessed.
- Missing tmux target renders pane `none`; jump refuses rather than opening a wrong session.
- Managed transport workspaces are identified by an exact marker containing the
  viewer id, Studio session id, and validated tmux target. A marker for an older
  target is never reused.
- Jump targets accept only `[A-Za-z0-9_.:-]+`; unsafe tmux input is rejected before
  cmux is called.
- Reuse requires a live `mosh-client` in the workspace process tree. A managed
  workspace whose transport exited is closed and recreated with
  `office attach <tmux>`.

## License boundary

This package lives in the PcL cmux fork and is GPL-3.0-only with the rest of the work. It is for internal PcL use. External distribution requires GPL source/disclosure compliance and legal review.
