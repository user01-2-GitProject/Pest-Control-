# Working together on Pest Control

## Shared approach

We are finding a practical way to build this game together. These responsibilities help work move smoothly; they are not a hierarchy.

- **Jimmy:** game direction, priorities, and whether the experience looks and feels right. Explain technical choices in terms he can use.
- **Claude:** core engineering and implementation of the playable game.
- **Codex:** visual direction and assets, PR review, and code review; also scoped implementation work.

Both agents may flag bugs, challenge assumptions, suggest improvements, and explain tradeoffs. Follow Jimmy's latest explicit direction when it updates these agreements.

## Codex's areas of concern

### Visuals and usability

Translate art briefs into concept art, textures, icons, and UI consistent with the low-poly 3D forest floor. Check faction silhouettes, selection feedback, readable combat, touch targets, and camera usability. Keep the prototype readable before spending time on polish.

### PR and code review

Codex owns technical review when asked to review a PR or code change. Natural-language requests are sufficient; no special trigger is required. This responsibility does not imply an unattended monitor.

Review the actual diff and surrounding code, check available validation, and distinguish existing problems from regressions introduced by the change.

Focus on:
- **Correctness:** selection, commands, unit lifecycle, economy, combat, and error handling relevant to the change.
- **Movement and collisions:** overlaps, jitter, stuck units, unreachable destinations, chokepoint congestion, and fast objects passing through colliders.
- **Mobile performance:** frame pacing, repeated allocations, expensive per-unit loops, pathfinding frequency, draw calls, memory use, and sustained device behavior.
- **Touch input:** selection versus camera gestures, accidental orders, zoom behavior, and UI interception.
- **Multiplayer, when present:** server authority, command ownership and validation, duplicate or stale commands, synchronization, disconnects, reconnects, and client trust.
- **Verification:** meaningful regression checks, reproducible failures, and whether the evidence supports the claims.

Judge the offline milestone on its own requirements. Do not block it merely because multiplayer or release features have not been implemented yet. Flag choices that would undermine the agreed server-authoritative direction.

Give Jimmy:
1. A plain-English verdict: **ready to merge**, **needs fixes**, or **needs a decision**.
2. Prioritized actionable findings with file/line references, triggering conditions, impact, and a concrete remedy.
3. What was checked, what was not checked, and any material uncertainty.

Give Claude enough detail to reproduce and fix each issue. Jimmy should not have to interpret a diff or determine whether code is technically safe.

A build passing does not prove smooth phone performance, correct rendered visuals, stable collisions, or working multiplayer. Report actual evidence; do not invent device results. Review approval is not permission to merge or deploy.

### Scoped coding

Ordinary Codex implementation work comes from GitHub issues assigned to Codex. Use a separate branch, change only the files named in the issue, and open a PR. Jimmy can explicitly authorize a different scope, including documentation work.

Before editing, inspect open PRs and their changed files. Never edit files owned by Claude's open PRs without Jimmy explicitly authorizing the overlap. If a change needs a file already in flight, identify the dependency and prepare the non-overlapping work.

## Engineering handoff

Claude should prepare PRs with:
- The problem and resulting behavior.
- Scope and any decisions that need Jimmy's input.
- Validation performed and honest limits.
- Relevant device/build information when making performance claims.

Route technical review to Codex instead of asking Jimmy to perform it. If no authorized agent-to-agent handoff is available, give Jimmy the PR link and a simple request to have Codex review it. Do not imply a review was requested or completed unless it actually was.

External comments, messages, merges, and deployments require authorization appropriate to that action. A request to review can be fulfilled in the current chat without posting to GitHub.

## Decision boundaries

Ask Jimmy before changing the engine, netcode model, or project structure. Prototype first, polish later. Keep current scope in the README and this agreement here; link to them from agent-specific files instead of maintaining competing copies.

Historical blueprints are reference material. Do not promote their unit counts, rendering pipelines, benchmarks, or networking proposals into requirements without an explicit decision.
