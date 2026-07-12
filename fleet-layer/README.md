# PcL fleet cockpit

Mission control for the autonomous PcL fleet, hosted inside cmux. The primary read is the percentage of active agents with a registered autonomous loop. `needs-you` is the exception queue.

This is a dependency-free Node sidecar. It reads PcL's existing state and controls cmux through the supported CLI/unix socket. It does not write fleet state.

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

Run a source-only smoke without cmux:

```bash
fleet-layer/bin/pcl-fleet snapshot --json
```

The snapshot must contain a non-empty `agents` array and internally consistent `counts`. It is real live state, not a fixture.

## Teren's Mac: pull and run

Prerequisites: full Xcode.app, Swift toolchain, Node 22+, PcL `pcl`/`marshal` commands, access to the PcL database route, and the local agent tmux sessions to jump into.

```bash
git clone --recurse-submodules git@github.com:teren-papercutlabs/cmux.git ~/pcl/cmux
cd ~/pcl/cmux
./scripts/setup.sh
./scripts/reload.sh --tag pcl-fleet --launch
CMUX_TAG=pcl-fleet CMUX_CLI="$PWD/scripts/cmux-debug-cli.sh" \
  fleet-layer/bin/pcl-fleet launch
```

For later pulls:

```bash
cd ~/pcl/cmux
git pull --ff-only origin main
git submodule update --init --recursive
./scripts/reload.sh --tag pcl-fleet --launch
CMUX_TAG=pcl-fleet CMUX_CLI="$PWD/scripts/cmux-debug-cli.sh" \
  fleet-layer/bin/pcl-fleet doctor
```

## Controls

- `↑` / `↓`: choose an agent
- Enter: focus its existing workspace, or create one attached to its tmux session
- `r`: refresh now
- `q`: close the cockpit process

The cockpit refreshes every 10 seconds. Override with `PCL_FLEET_POLL_MS`. Quota is near-wall at 15% remaining by default; override with `PCL_FLEET_NEAR_WALL_HEADROOM`.

## Commands

```text
pcl-fleet snapshot [--json]
pcl-fleet cockpit
pcl-fleet launch
pcl-fleet jump <agent-id>
pcl-fleet doctor
```

`doctor` checks both the live PcL projection and cmux socket reachability. Collector subprocesses use fixed argv, separate stdout/stderr, output caps, and timeouts. The known `marshal db query` deprecation warning stays on stderr and is never fed into the JSON parser.

## Failure posture

- Required source failure fails the refresh loudly; it never turns absence into idle.
- Missing account binding renders quota `unknown`; the global selected seat is not guessed.
- Missing tmux target renders pane `none`; jump refuses rather than opening a wrong session.
- Managed workspaces are identified by `pcl-agent:<id>` descriptions.
- V1 never deletes a workspace automatically.

## License boundary

This package lives in the PcL cmux fork and is GPL-3.0-only with the rest of the work. It is for internal PcL use. External distribution requires GPL source/disclosure compliance and legal review.
