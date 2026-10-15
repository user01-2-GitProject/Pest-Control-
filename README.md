# Pest Control

A native mobile, 1v1 insect RTS set on a forest floor. We are building a playable prototype first and adding polish as the game proves itself.

## Current milestone

**Offline Android prototype:** one map, 20 ants, a pan/zoom camera, tap/drag selection, and tap-to-move commands.

This is the milestone target, not a claim that every feature is implemented or tested. Online play and iOS are product goals; this document does not claim either is ready.

## Game direction

- High-angle camera and low-poly 3D art.
- Ants specialize in swarms, ladybugs in flight, and beetles in armor.
- Milk aphids for steady Honeydew, or eat them for fast Biomass at the cost of future income.
- Target match scale: 50 units per player and roughly 10-minute matches.
- Visual anchors: red ants, stag beetles, ladybugs, glowing mushrooms, blue crystals, and log-bridge chokepoints.

## Technical direction

- Specified engine: Godot 4.7. Verify the actual project version and available toolchain before setup or export; do not silently change it.
- Target platforms: Android and iOS, with smooth sustained play on roughly 2020 mid-range phones.
- Multiplayer direction: server-authoritative simulation. Phones send commands and render; the server decides game state, including damage and resources.
- Device performance, collision quality, and online reliability require measured validation. A desktop run or successful build does not establish mobile readiness.
- Engine, netcode model, and project structure changes need Jimmy's agreement.

## How we work

Jimmy steers the game. Claude leads core engineering. Codex leads visuals and PR/code review, and contributes scoped implementation. We work as peers, share ideas, and challenge decisions when evidence supports it.

See [COLLABORATION.md](COLLABORATION.md) for responsibilities, review criteria, and how to avoid overlapping changes. Claude should also read [CLAUDE.md](CLAUDE.md).

Technical review belongs to Codex. Jimmy should receive a plain-English verdict and any game decisions that need his input, rather than being asked to judge unfamiliar code.

## Historical research

The previous README is preserved in [the historical blueprint](docs/historical-blueprint.md). It contains unverified research, corrupted formatting, and proposals that differ from the current scope. It is reference material, not an accepted architecture or implementation report.
