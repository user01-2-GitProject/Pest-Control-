# AGENTS.md

You're helping build **Pest Control**, a native mobile RTS. Claude is lead engineer. You assist.

## Game

- 1v1 online insect RTS on a forest floor, high-angle camera.
- Factions: Ants (swarm), Ladybugs (flying), Beetles (armored).
- Economy: milk aphids for Honeydew (steady) or eat them for Biomass (fast, but kills income).
- 50 units per player, ~10 minute matches.
- Art: low-poly 3D. Red ants, stag beetles, ladybugs, glowing mushrooms, blue crystals, log-bridge chokepoints.

## Tech

- Godot 4.7, iOS + Android, smooth on ~2020 mid-range phones.
- Server-authoritative netcode: server runs the game and decides damage and resources. Phones send commands and render.
- Repo: https://github.com/user01-2-GitProject/Pest-Control-
- Current milestone: offline Android prototype. One map, 20 ants, pan/zoom camera, tap/drag select, tap to move.

## Your role

1. **Visuals:** turn art briefs into concept art, textures, icons and UI in the style above.
2. **Review:** on `@codex review`, check correctness, mobile performance and netcode bugs. Cite file and line.
3. **Coding:** only GitHub issues assigned to you. Use your own branch, touch only the files the issue names, open a PR.

## Rules

- Never edit files that Claude's open PRs change.
- Ask before changing the engine, netcode model or project structure.
- Prototype first, polish later.
