# Pest Control

A PC-first, 1v1 insect RTS set on a forest floor. We are building a playable prototype first and adding polish as the game proves itself.

## Current build

An unfinished Godot prototype with an Ants-only match loop: gather Honeydew, train workers and soldiers, fight, and win by destroying a colony or the ten-minute health tiebreak. Play offline against a bot or connect two clients over LAN.

See [game/README.md](game/README.md) for running the build, current controls, tests, and limitations. Jimmy tested the earlier movement prototype (PR #3). The integrated match loop has headless validation; that does not establish visual polish or complete gameplay.

The direction is PC with standard RTS mouse-and-keyboard controls. The current build still has touch-first mouse equivalents; the control conversion remains unfinished. Mobile is deferred.

## Game direction

- High-angle camera. Recognizable insects with independently distinctive faction identities.
- Agreed visual targets: clean graphic/vector Low and tactile clay/sculpted High, sharing gameplay visibility and silhouettes. These are concept targets, not implemented graphics settings.
- Ants specialize in swarms, ladybugs in flight, and beetles in armor.
- Milk aphids for steady Honeydew, or eat them for fast Biomass at the cost of future income.
- Target match scale: 50 units per player and roughly 10-minute matches.
- Visual anchors: red ants, stag beetles, ladybugs, glowing mushrooms, blue crystals, and log-bridge chokepoints.

## Technical direction

- Specified engine: Godot 4.7. Verify the actual project version and available toolchain before setup or export; do not silently change it.
- Current platform scope: PC (Linux and Windows); minimum hardware remains to be established. Mobile is deferred.
- Multiplayer direction: server-authoritative simulation. Clients send commands and render; the server decides game state, including damage and resources.
- Device performance, collision quality, and online reliability require measured validation. A desktop run or successful build does not establish release readiness.
- Engine, netcode model, and project structure changes need Jimmy's agreement.

## How we work

Jimmy steers the game. Claude leads core engineering. Codex leads visuals and PR/code review, and contributes scoped implementation. We work as peers, share ideas, and challenge decisions when evidence supports it.

See [COLLABORATION.md](COLLABORATION.md) for responsibilities, review criteria, and how to avoid overlapping changes. Claude should also read [CLAUDE.md](CLAUDE.md).

Technical review belongs to Codex. Jimmy should receive a plain-English verdict and any game decisions that need his input, rather than being asked to judge unfamiliar code.

## Historical research

The previous README is preserved in [the historical blueprint](docs/historical-blueprint.md). It contains unverified research, corrupted formatting, and proposals that differ from the current scope. It is reference material, not an accepted architecture or implementation report.
