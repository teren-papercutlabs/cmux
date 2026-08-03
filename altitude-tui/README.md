# Altitude menu

The Altitude menu is an OpenTUI program run by Bun in a dedicated cmux terminal surface. `src/adapter.ts` is the only module allowed to import `@opentui/core`; menu screens depend on its drawing and input interfaces instead.

Fleet data is read in-process through `fleet-layer/src/fleet-state.mjs#getFleetState`. The poll runs a single session query and starts no sidecar or IPC service.

Jump and return actions use cmux's existing control-socket CLI:

- Enter reads `cmux tree --all`, matches the session against surface metadata,
  and runs `cmux focus-panel`. It falls back to `cmux find-window --content
  --select` when the running cmux build does not expose a matching surface.
- Escape reads the host-written return target and runs `cmux focus-panel`.

The TUI itself has no host daemon. Command-0 in the native host creates or focuses its terminal surface and recreates it if the Bun process has exited.
