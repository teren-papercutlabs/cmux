# PcL fleet cockpit: solution shape

Status: locked before implementation, 2026-07-13.  
WB: `c02ff745-aa1c-46e3-a246-227a3161a805`.  
North star: increase the percentage of active PcL agents running autonomously, while routing Teren only to agents that need him.

## Decision

PcL owns a GitHub fork at `teren-papercutlabs/cmux`, with `manaflow-ai/cmux` retained as `upstream`. The native app stays as close to upstream as possible. PcL-specific behavior lives in `fleet-layer/`, a dependency-free Node sidecar that reads existing PcL control-plane state and drives cmux exclusively through its supported CLI/socket contract. No new runtime, database, daemon, or Swift state model is introduced.

The cockpit is a terminal UI hosted in a cmux workspace. It polls the current PcL state, renders the autonomous/needs-you split as the first and largest read, and lets the operator focus an agent with the keyboard. Agent workspaces attach to the agent's existing tmux session; cmux remains a host for the existing Claude Code/Codex CLIs rather than replacing either runtime.

This is a view over live state, not a second source of truth.

## Gate 0: live premise and implicated surface

Live evidence inspected before this document was written:

- `dev.session_lifecycle` contains current worker lifecycle state and lineage (`session_id`, `parent_session_id`, `originated_by`, `root_persistent_id`, `state`).
- `public.sessions` contains the matching entity/session labels and jump handles (`agent_name`, `session_tag`, `tmux_session`, `ended_at`).
- `dev.session_signals` contains the latest Pharos `needs_reply` signal used for the `needs-you` override.
- `pcl agents list` returns the active fleet roster.
- `pcl loop list --status active` returns the registered autonomous loops. At shape time it returned an empty live set.
- `pcl burn quota` and `pcl auth claude status` return current account quota fill and auth health.
- cmux documents a supported CLI/socket surface for `list-workspaces`, `new-workspace`, `select-workspace`, `focus-pane`, `send`, and raw RPC.

The missing surface is one operator view joining those sources around the agent entity. No missing transport or fleet-state plumbing was found.

## Gate 1: root mechanism and class

- **Symptom:** fleet state is visible only by checking separate session, loop, and quota commands, so attention is routed by manual scanning rather than by exception.
- **Immediate cause:** no entity-level projection joins lifecycle, autonomy, quota, and jump handles.
- **Root mechanism:** existing telemetry is session-shaped while Teren operates agent entities. The lineage join exists but no control surface projects it.
- **Recurrence stance:** category. Every added agent or worker increases manual scan cost unless the view resolves session lineage to its owning entity.
- **Audit WB:** not worth a separate sweep. This is a new bounded view over named existing primitives, and the implementation includes contract fixtures for every source.
- **Class:** design-bearing, reversible, internally scoped. It creates a new operator surface but no canonical state, credential path, destructive mutation, or external egress.

## Gate 2: load-bearing mechanism and layer

The load-bearing mechanism is deterministic TypeScript/Node code in the fork:

1. A collector invokes existing read-only CLIs with argv arrays, bounded timeouts, and independent stdout/stderr capture.
2. A projector resolves each session to an owner entity using `root_persistent_id`, then `parent_session_id` / `originated_by`, then the session's own registered agent only as a final fallback.
3. A terminal renderer shows the north-star split and one row per active agent.
4. A cmux adapter creates/selects workspaces through the CLI, which reaches the unix socket.

The sidecar runs as the foreground process in the cockpit workspace. It polls every 10 seconds by default. Polling is correct for v1 because the upstream sources do not expose one shared event stream, the fleet is small, and freshness is operational rather than transactional. The interval is configurable with `PCL_FLEET_POLL_MS`. Failures are isolated per source: the last complete snapshot stays visible with a red stale-source line; partial output never silently becomes healthy state.

Non-loading test: the cockpit continues to operate without an agent remembering any policy. State is collected and classified in code at render time.

## Gate 3: primitive contract — extend, do not rebuild

Existing primitives fit:

- Read PcL state with `marshal db query`, `pcl agents list`, `pcl loop list --status active`, `pcl burn quota`, and `pcl auth claude status`.
- Control cmux with its bundled `cmux` CLI and `CMUX_SOCKET_PATH` contract.
- Attach existing agent sessions with `tmux attach-session -t <exact name>` inside a cmux workspace.

The fleet layer does not query Supabase directly, parse credentials, write lifecycle rows, create its own socket, or patch cmux's native state model. Swift is untouched in v1. If a later interaction cannot be expressed through the supported socket API, that single capability is the only justified native extension.

## Entity, status, autonomy, and quota contracts

### Entity resolution

The roster is active agent entities, not sessions. Each open session is assigned to an entity by resolving its root/parent/origin session and reading the registered `public.sessions.agent_name`. A child session never becomes a second fleet row. The preferred jump target is the active channel-bound main (`session_tag LIKE 'telegram:dm:%'`) with a tmux name, then another persistent agent session, then the freshest pane-backed owned session.

### Status

`needs-you` has precedence when the latest Pharos signal for any owned open session has `needs_reply=true`. Otherwise an entity with an owned lifecycle row in `working` is `running`; entities with only `briefed`/`spawned` rows or no open lifecycle row are `idle`. The cockpit shows counts and source staleness so absence is never disguised as healthy idleness.

### Autonomous badge

An entity is autonomous only when an active registered loop targets one of its owned sessions. The loop registry is authoritative; a prose claim, terminal title, or historical goal is not enough.

### Quota headroom

The latest token event for an owned session supplies its account binding. The matching `pcl burn quota` row supplies 5-hour and 7-day fill. Headroom is `100 - max(5h fill, 7d fill)`. A configurable near-wall threshold defaults to 15% remaining. Missing binding is rendered `unknown`, not guessed from the globally selected seat.

## cmux mapping and jump contract

Every managed workspace carries a description marker `pcl-agent:<agent-id>` and a visible title. On jump:

1. list workspaces through the socket-backed CLI;
2. select the existing matching workspace when present;
3. otherwise create a workspace running `tmux attach-session -t <exact tmux name>`, mark it, then select it;
4. refuse with an explicit cockpit error when no live tmux target exists.

The cockpit itself is a managed workspace with marker `pcl-fleet-cockpit`. Arrow keys move the selection, Enter jumps, `r` refreshes, and `q` exits. The snapshot command emits JSON for deterministic tests and other future consumers.

## Gate 4: result proof, persistence proof, rollback, and blast

- **Result standard:** the tagged cmux build displays the real active fleet, makes autonomous percentage and needs-you count primary, updates from live sources, and focuses an existing agent pane on Enter.
- **Event proof:** run the collector against live Studio state; launch the tagged app; create the cockpit through the tagged CLI/socket; inspect its screen; jump to a known tmux-backed agent; verify cmux reports that workspace selected.
- **State proof:** `fleet-layer/bin/pcl-fleet snapshot --json` is the deterministic standing smoke. It must return a non-empty active fleet, source timestamps, and internally consistent counts. `fleet-layer/bin/pcl-fleet doctor` checks required CLIs and cmux socket reachability.
- **Thing attachment:** the fork's `fleet-layer` package and its runbook.
- **Activation:** operator launch and every poll; CI/local tests exercise parsers and projection fixtures.
- **Red owner:** Rasim.
- **State mutation and consumer:** only cmux workspace metadata/selection mutates; Teren consumes the rendered cockpit. PcL canonical state remains read-only.
- **Rollback and blast:** quit the cockpit workspace and remove/ignore `fleet-layer/`. Revert PcL commits or reset the fork to upstream. Blast is limited to cmux workspaces created with `pcl-agent:` markers.
- **Check obligation:** true. This leaves an ongoing operator behavior. The standing check is the live `snapshot --json` plus `doctor` consumer smoke, documented in the runbook and executable after every pull.

Operational debt created: managed cmux workspaces can outlive sessions. Payment is source-fired reconciliation during each jump/launch: stale managed markers are detected and shown, never reused for a different tmux target. V1 does not destroy stale workspaces automatically; destructive cleanup requires an explicit future command.

## Gate 5: target-surface conflict report

- **Surfaces read:** fork `CLAUDE.md`, `README.md`, `docs/cli-contract.md`, `docs/custom-sidebars.md`, and the socket/CLI references named there.
- **Findings:** upstream requires tagged builds for isolation; cmux already treats the CLI/socket as the automation boundary; user-facing native strings require full localization; terminal hot paths have strict performance rules.
- **Why it matters:** a Swift sidebar would add localization, render-loop, and upstream-merge cost without adding v1 capability. A terminal sidecar avoids all three while still rendering inside cmux.
- **Recommended plan action:** keep v1 entirely in `fleet-layer/`, use tagged builds, and add Swift only for a proven missing socket capability.
- **Plan changed by Gate 5:** no. It confirmed the minimal-Swift sidecar decision.

## Review passes

- **Ruth:** run inline. The shape directly increases autonomous operation and exception-only principal attention. It is reversible, bounded, and adds no human recall step.
- **Cowboy:** run inline. The larger move is not another dashboard; it is a keyboard-operated cockpit inside the terminal host. The v1 deliberately makes the north-star split actionable while refusing premature arm/rotation controls.
- **Codex technical:** run inline from repository and live source inspection. Key risks are output-shape drift, lineage mistakes, shell injection, stale sockets, and false quota attribution. The implementation contracts above contain each risk.
- **Schema lens:** n/a; no schema change.
- **Security lens:** shell execution is constrained to fixed binaries with argv arrays. Tmux names and cmux handles are validated before use; no command is constructed by string concatenation without POSIX quoting at the single `new-workspace --command` boundary. No secret values are read or logged.

## Build and run story

Studio verification:

1. clone `teren-papercutlabs/cmux` with submodules;
2. run `./scripts/setup.sh` if GhosttyKit is absent;
3. build with `./scripts/reload.sh --tag pcl-fleet --launch`;
4. run the tagged socket helper or set `CMUX_CLI`/`CMUX_SOCKET_PATH` from the emitted tagged build;
5. run `fleet-layer/bin/pcl-fleet doctor`, `snapshot --json`, then `launch`.

Teren's Mac uses the same clone/setup/tagged-build sequence. PcL CLI access, the Studio database route, and local tmux sessions are prerequisites; the runbook makes them explicit. The sidecar needs no npm install.

## GPL boundary

The fork and `fleet-layer/` are one GPL-3.0 work for internal PcL use. No external distribution is planned. If the cockpit becomes an external product, distribution must include corresponding source and preserve GPL notices, or the fleet layer must be separated behind a process boundary after legal review. Internal use does not trigger source-distribution obligations.

## Growth path, not v1 blockers

After the spine proves useful:

- one-action arm-to-autonomous using the existing autopilot primitives;
- OSC notification rings projected into needs-you state;
- quota rotation through the existing session restart primitive;
- event-driven refresh when a shared fleet event feed exists;
- native Swift cockpit only if terminal-hosted interaction proves insufficient.

Those controls mutate fleet state and require separate solution shapes, permission boundaries, and live rollback tests.

## Design passport

- passport: `SS-PASSPORT-2026-06-22-F3A9D1`
- classification: `design-bearing`
- rollback: quit managed workspaces; revert PcL-only commits; upstream fork remains intact
- blast boundary: local cmux workspaces marked `pcl-agent:` and read-only PcL CLI calls
- obligation: true; live snapshot and doctor checks keep the view honest
- fundamental review: already principal-ratified fork/sidecar direction; this document resolves implementation mechanics without changing that decision

