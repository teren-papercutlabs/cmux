# Build the PcL fleet cockpit on your Mac

Five-minute path for Teren. This builds the PcL-owned cmux fork, runs the native app, then starts the live fleet cockpit inside it.

## Prerequisites

- full Xcode.app installed and opened once to accept its license;
- Node 22+;
- working `pcl`, `marshal`, and `tmux` commands with Studio/PcL access;
- SSH access to `teren-papercutlabs/cmux`.

Confirm the real Xcode toolchain:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

`xcodebuild -version` must print an Xcode version. If it says “requires Xcode,” the active path is still the Command Line Tools stub.

## 1. Clone and prepare

```bash
git clone --recurse-submodules git@github.com:teren-papercutlabs/cmux.git ~/pcl/cmux
cd ~/pcl/cmux
./scripts/setup.sh
```

`setup.sh` initializes the cmux submodules, fetches/builds GhosttyKit, and installs the repository hooks.

## 2. Build and run the native fork

Fast reproducible path:

```bash
cd ~/pcl/cmux
./scripts/reload.sh --tag pcl-fleet --launch
```

This builds an isolated Debug app named `cmux DEV pcl-fleet.app`, launches it, and keeps its bundle ID/socket separate from any other cmux installation.

Xcode UI equivalent:

1. Open `~/pcl/cmux/cmux.xcodeproj` in Xcode.
2. Select the `cmux` scheme and **My Mac** destination.
3. Press **Run**.

Use the tagged script for repeatable cockpit verification; the Xcode UI path is useful for native debugging.

## 3. Start the live fleet cockpit

The safe default requires no socket setting change:

1. In the running cmux app, open a terminal workspace.
2. Run:

```bash
cd ~/pcl/cmux
fleet-layer/bin/pcl-fleet snapshot --json
fleet-layer/bin/pcl-fleet cockpit
```

The first command must report a non-empty real fleet. The second replaces that terminal with the updating cockpit. Use ↑/↓ to select an agent and Enter to jump to its pane.

To launch the cockpit from Apple Terminal instead, set **cmux Settings → Automation → Socket Control Mode → Automation mode**, then run:

```bash
cd ~/pcl/cmux
CMUX_TAG=pcl-fleet CMUX_CLI="$PWD/scripts/cmux-debug-cli.sh" \
  fleet-layer/bin/pcl-fleet doctor
CMUX_TAG=pcl-fleet CMUX_CLI="$PWD/scripts/cmux-debug-cli.sh" \
  fleet-layer/bin/pcl-fleet launch
```

Automation mode accepts only clients from the same macOS user. Do not use Full open access.

## 4. Verify the spine

In the cockpit, confirm:

1. the first read is `AUTONOMOUS N/TOTAL · PERCENT` and `NEEDS YOU N`;
2. each agent row has state, ARMED/—, quota headroom/unknown, and pane ready/none;
3. the timestamp updates after roughly ten seconds;
4. selecting a pane-ready agent and pressing Enter focuses its existing tmux session.

Source-only regression check:

```bash
cd ~/pcl/cmux
npm test --prefix fleet-layer
fleet-layer/bin/pcl-fleet snapshot --json
```

## Later pulls

```bash
cd ~/pcl/cmux
git pull --ff-only origin main
git submodule update --init --recursive
./scripts/reload.sh --tag pcl-fleet --launch
```

No npm install is required. The fleet layer has no third-party Node dependencies.
