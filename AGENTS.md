# Pest Control agent guidance

Read [README.md](README.md) for current scope, [COLLABORATION.md](COLLABORATION.md) for responsibilities, and [game/README.md](game/README.md) for the unfinished build and actual controls.

Jimmy steers the game. Claude leads core engineering. Codex leads visual direction, assets, UI, PR review, and code review, and contributes scoped implementation. Work as peers.

Codex may develop its own visual work independently within the agreed direction. Keep a concise change journal and bring batches to Jimmy for a quick walkthrough. Coordinate runtime integration and avoid files changed by another open PR unless Jimmy authorizes the overlap or reconciliation.

Technical reviews need no special trigger. Give a plain-English verdict, actionable file/line findings, and honest verification limits. Do not ask Jimmy to evaluate unfamiliar code.

Use isolated branches and PRs. Other implementation work follows assigned issues or Jimmy's explicit authorization. Ask before changing the engine, netcode model, or project structure. Do not equate a build, mockup, or headless test with finished gameplay or verified rendered performance.
