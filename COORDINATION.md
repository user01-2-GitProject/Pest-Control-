# Pest Control — shared work and handoffs

This is the living coordination board for Claude, Codex, and Jimmy. Update it through Git so neither agent needs Jimmy to relay routine technical context. Read it together with [COLLABORATION.md](COLLABORATION.md) before starting work.

Git stores the handoff; it does not automatically wake or notify either agent. Check this document, open PRs, and their latest commits when resuming. A PR review remains authoritative for the code revision it actually reviewed.

## Working baseline

- PC-first Godot RTS; mobile is deferred.
- Main includes the integrated Ants match prototype from PR #7: Honeydew gathering, training, combat, victory, offline bot, and LAN server-authoritative play.
- Main is unfinished. Standard PC input merged in PR #8 (54ac87f); Jimmy playtested it on desktop (2026-10-15, "controls all work").
- Low art target: clean graphic/vector treatment. High: tactile clay/sculpted treatment. Neither setting is implemented.
- Factions retain independent identities and recognizable insect anatomy. Share gameplay visibility and collision rules across graphics settings.
- Jimmy tested the earlier #3 movement prototype. Local and GitHub headless tests passed for #7; that is not visual or full playtest acceptance.

## Active work

| ID | Owner | Work / status | Files or area | Next step / evidence |
|---|---|---|---|---|
| NAV-01 | Claude | Milestone 2 navigation: logs and rocks on the map, A* paths, crowd steering, chokepoint queueing, blocked destinations; protocol v6. Branch claude/crowd-navigation-3x53jf | game/src/sim/sim_world.gd, game/src/view/world_view.gd, game/src/net/protocol.gd, game/tests/test_nav.gd, game/tests/test_match.gd, game/README.md, .github/workflows/godot-tests.yml, COORDINATION.md | Codex review of the PR; Jimmy playtest. Codex: log/rock meshes in world_view.gd are placeholders and yours to restyle. |
| VISUAL-01 | Codex | Art direction agreed; next production batch not yet started | Planned new concept/asset files; no runtime files claimed yet | Prepare desktop HUD, selection/command feedback, and resource-icon studies consistent with Low/High targets. Record exact paths before implementation. |
| COORD-01 | Codex | Establishing this board and agent entry-point links | COORDINATION.md, AGENTS.md, CLAUDE.md, COLLABORATION.md | Publish through a documentation PR; both agents may maintain their entries afterward. |

Claims are coordination aids, not permanent locks. Verify the live PR file list. Do not overwrite another agent's in-flight files; request a handoff or work elsewhere. Do not infer that an idle-looking branch has been abandoned.

## Handoffs

### HANDOFF-001 — Codex → Claude: PR #8 focus-loss recovery

- **Status:** resolved. Fix e92fae7, viewport-input regression d52ba74, CI green; Codex re-review at d52ba74: ready to merge. Merged in PR #8 (54ac87f).
- **Reviewed revision:** 96588e51856722fd03227dea80a832170bd603b1.
- **PR:** [#8 — Standard PC RTS controls](https://github.com/user01-2-GitProject/Pest-Control-/pull/8).
- **Finding:** game/src/input/pc_controls.gd:45–47 clears held keys on focus loss but leaves the selection drag active.
- **Reproduce:** begin left-drag box selection, lose window focus, release left outside the game, return and move the mouse without holding a button. The box can keep tracking and right-click commands are suppressed.
- **Evidence:** Godot 4.7.2 headless viewport-event reproduction: after press, drag, focus-out notification, and a button_mask=0 motion, both _left_down and _boxing remain true. Existing smoke_main and GitHub tests pass because they do not exercise this sequence.
- **Suggested fix:** one pointer-cancel helper that clears the overlay and both drag flags, used on focus loss and disable. Defensively cancel when motion shows left is no longer held. Cancel without emitting a selection or move command.
- **Acceptance:** regression verifies focus interruption clears the gesture, no phantom selection is emitted, and the next right-click produces an order. Retest through actual viewport event dispatch, not only direct callbacks.
- **Boundary:** Codex has not modified Claude's PR files.

## Update protocol

1. Fetch current main and inspect open PRs before claiming work. Read the latest board and reviews.
2. Add or update your work row with owner, status, exact files, branch/PR, and next action. Proposed work is not implementation evidence.
3. Keep routine work independent within agreed scope. Put dependencies and requests in numbered handoffs; acknowledge a handoff explicitly when you take it.
4. On handoff completion, record the fixing commit, test evidence, and reviewer outcome. Preserve the original finding and append its resolution.
5. If this file conflicts, retain both agents' updates and reconcile statuses against current GitHub state. Do not replace it with an old branch's copy.
6. Move completed work rows to the dated journal. Keep unresolved handoffs visible.
7. Give Jimmy a short batch walkthrough for visual changes and meaningful decisions. Routine technical review goes between agents through PRs and this board.
8. Only mark work merged, tested, or approved when the corresponding evidence exists. A proposed task does not grant merge, deployment, or architecture-change permission.

## Change journal

### 2026-10-15 — Codex

- Integrated PRs #1–#6 through #7; duplicate #4 closed with its commits preserved. Main commit d106cbe7f0ce9e527e1c96019ded9feb6703fbd9.
- Resolved gameplay/networking conflicts and separated TRAIN/NOTICE message IDs under protocol v3.
- Verified simulation, match rules, scene smoke, network, and separate-process UDP tests locally and in GitHub CI. External Kilo review remained queued and was not counted as completed.
- Reviewed #8 at 96588e5; one reproduced focus-loss bug sent to Claude in a GitHub review. No gameplay files changed by Codex during this review.
- Created this shared board. Visual direction remains the agreed Low graphic/vector and High clay/sculpted targets; implementation is still pending.

### 2026-10-16 — Claude

- RTS-ORDERS merged (#13, #14 with Codex follow-ups). Jimmy playtested: "works like a charm".
- Started NAV-01 (milestone 2: reliable navigation and collision in a small battle).

### 2026-10-15 — Claude

- PR #8 (standard PC controls) merged after HANDOFF-001; Jimmy's desktop playtest passed. Jimmy asked for rally points, hotkeys and similar next.
- Started PC-INPUT-2 (client-side only: groups, hotkeys, double-click). RTS-ORDERS follows and will bump the protocol version.
