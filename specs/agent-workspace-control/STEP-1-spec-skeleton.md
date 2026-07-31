# Agent Workspace Control — Step 1

## Intent

- Make the principal's cmux workspace directly observable, configurable, and diagnosable by authorized agents.
- Ensure agent-visible state is the same state rendered by Cmd-K and used by its shortcuts.

## User + Context

- Primary user: Teren, working across ephemeral Claude and Codex sessions on an MBA.
- Agent actors: Altitude and delegated agents preparing and maintaining the MBA workspace from Studio.
- The workspace protects macro-level priority while allowing two active conversations and opportunistic overflow.

## Problem Boundaries (In/Out)

- In: persistent Lead and Understudy assignment, session associations, resolved Cmd-K rows, workspace/pane/session identity, health, and safe remote configuration.
- In: machine-readable inspection that does not depend on screenshots, Screen Recording, or Accessibility permission.
- Out: arbitrary remote desktop control, hidden changes to Studio sessions, and automatic reprioritization without Teren's instruction.

## Assumptions + Known Unknowns

- Session identity must survive cmux relaunches; transient pane and Bonsplit tab identifiers do not qualify.
- The existing DEBUG control socket can expose the rendered command-palette snapshot and drive test interactions.
- Known unknown: which CNS session, if any, Teren intended by the conceptual label `cns-lead`; no inference is permitted.

## Constraints + Non-Negotiables

- Official cmux remains an untouched fallback.
- Workspace repair must not restart, rename, or mutate underlying Studio sessions.
- Lead and Understudy remain manually anointed at session level.
- One shared model must feed UI rendering, shortcuts, configuration, and diagnostic output.
- Repairs must be reversible and independently verifiable.

## Success Signals (Measurable)

- An agent can query JSON containing configured roles, resolved live targets, groups, and exact empty-query Cmd-K rows.
- Lead and Understudy still resolve after a cmux relaunch.
- Programmatic palette toggle plus results query returns Lead first and Understudy second.
- Enter focuses Lead and Command-Enter focuses Understudy in an automated live check.
- Missing or stale targets are reported explicitly rather than rendered as an unexplained empty list.

## Failure Signals + Safe Fallback

- Failure: configured role IDs do not resolve, UI and diagnostic rows differ, or assignments disappear after relaunch.
- Failure: an agent needs a principal-provided screenshot to determine workspace state.
- Safe fallback: retain official cmux and preserve the last known-good custom app/config backup; never mutate Studio sessions to repair presentation state.

## Exceptions + Escalation Triggers

- `UNRESOLVED_SESSION_ALIAS`: a conceptual label has multiple or zero live session matches; ask Teren before attaching one.
- `CONTROL_SURFACE_GAP`: a rendered state cannot be obtained through the control socket; add a bounded read-only diagnostic before relying on human observation.
- `PRINCIPAL_AUTHORITY`: changing Lead, Understudy, or group meaning without an explicit instruction requires Teren's decision.

## Collaboration Contract (Owners, Reviewers, Handoff)

- Responsible owner: Rasim/Altitude infrastructure agent.
- Reviewer: Teren for attention semantics and live dogfood; cmux reviewer for implementation safety.
- Dependencies: cmux control socket, Office attach CLI, MBA custom tagged app.
- Handoff condition: machine-readable live verification passes and Teren only needs to judge whether the interaction feels right, not diagnose configuration.

## Current Status

READY_WITH_RISKS — the DEBUG socket already exposes palette snapshots, but priority persistence currently uses a transient Bonsplit tab identifier and must be corrected before the control contract is reliable.
