# Pest Control: Godot project

Milestone 3: first playable match loop (Ants only). Milk aphids for honeydew,
train workers and soldiers at your colony (cap 50 ants), fight in melee, and win
by destroying the enemy colony. Play offline against a simple local bot, or
online against another PC through a server that owns every rule.
LAN or localhost only: no matchmaking, accounts or internet hosting yet.

## Match rules (placeholder balance, tune from playtests)

| | Cost | Train | HP | Damage / s | Speed |
|---|---|---|---|---|---|
| Worker | 50 | 5 s | 40 | 4 | 4.0 m/s |
| Soldier | 100 | 8 s | 100 | 12 | 3.5 m/s |
| Colony | | | 1500 | | |

- Start: colony, 6 workers (already milking), 4 soldiers, 100 honeydew.
- Workers milk an aphid cluster for 2 s, carry 10 honeydew home, repeat.
- Cost is paid when queued; queue holds 5; queued ants count toward the 50 cap.
- Idle soldiers attack enemy ants within 6 m (and give up chasing past 9 m).
  Workers fight only when ordered. A move order holds fire until arrival, so
  retreating works. An attack on a colony fights ants met on the way.
- All hits in a tick land together, so two ants can kill each other.
- Win: destroy the enemy colony. At 10:00 the colony with more health left wins;
  equal health is a draw.
- Online, the match clock starts when both players have joined.

Platform: **PC first** (Linux and Windows). Mobile is deferred, not dropped: the
project keeps the Mobile renderer so it can export to phones later.

## Open and run

1. Godot 4.7, **Import** `game/project.godot`.
2. Press **F5**. Controls are listed below.
3. Pick **Play offline**, **Host game**, or type an address and **Join**.

## Play online (two PCs, same LAN)

1. PC A: **Host game**. Its HUD shows "join at 192.168.x.x".
2. PC B: type that address, **Join**.
Each player controls only their own ants (red = player 1, slate = player 2).

Or run a dedicated server on a PC and have both clients join the PC's address:

```
cd game
godot --headless -s res://src/net/server_main.gd -- --port 7777
```

Uses UDP port 7777. A firewall on the host must allow it.

## Controls

Standard PC RTS controls. Touch still works on touchscreens (tap, drag to pan,
hold then drag to box select, pinch to zoom) for a later mobile build.

| Action | Mouse / keyboard |
|---|---|
| Select one ant | Left click it (Shift+click adds or removes) |
| Select all of a type on screen | Double click an ant |
| Box select | Left drag (Shift adds to the selection) |
| Clear selection | Left click empty ground, or Esc |
| Select all | Ctrl+A, or the **All** button |
| Move | Right click ground |
| Attack | Right click an enemy ant or colony (red ring) |
| Milk aphids | With workers selected, right click an aphid leaf |
| Train | **Q** worker, **E** soldier, or the **Worker 50** / **Soldier 100** buttons |
| Control groups | Ctrl+1–9 sets, Shift+1–9 adds, 1–9 selects; tap twice to jump the camera there |
| Jump to your colony | Space |
| Rally point (new ants go there) | Click your mound, then right-click ground, an aphid or an enemy. Right-click the mound to clear |
| Pan | Arrow keys, mouse at the screen edge, or middle drag |
| Zoom | Mouse wheel or trackpad pinch |

## PC build

1. Editor > Manage Export Templates > **Download and Install**.
2. Project > Export > Add **Linux** (and/or **Windows Desktop**), then **Export Project**.

## Layout

```
src/sim/      SimWorld: rules and state, fixed 20 Hz tick, no nodes. The server runs it.
src/ai/       BotAI: offline opponent; issues commands through the same queue as players.
src/net/      Protocol (wire format), GameServer, NetClient, SnapshotBuffer (jitter buffer),
              server_main.gd (headless entry point).
src/view/     Ant, map and marker visuals. Read sim state, interpolate between ticks.
src/input/    PC mouse/keyboard controls, touch gestures, camera rig.
src/ui/       HUD: stats, buttons, drag box. Start menu.
src/main.gd   Wires the layers; selection is client-side only.
tests/        Headless tests (run in CI on every PR).
```

## Tests

```
cd game
godot --headless --import
godot --headless -s res://tests/test_sim.gd
godot --headless -s res://tests/test_match.gd
godot --headless -s res://tests/smoke_main.gd
godot --headless -s res://tests/test_net.gd
```

CI also runs a dedicated server and two `tests/net_bot.gd` clients as three
separate processes over UDP; see `.github/workflows/godot-tests.yml`.

## Networking model

Protocol v3 combines match commands with token-based rejoin, rate limits, and host notices. Older clients must update.

- **Server-authoritative.** Clients send only intent: `ORDER` (unit ids, target
  point, optional target id) and `TRAIN` (kind). The server runs SimWorld, whose
  `issue_order` / `issue_train` check ownership, honeydew, queue, unit cap and
  match state, and caps each client at 8 commands per tick. Damage, honeydew,
  cooldowns and victory are computed only on the server.
- **Snapshots, 20 Hz.** After every tick each client gets the full state: every
  ant, colony and aphid (11 bytes each with kind, hp and flags) plus both
  players' economy and the winner. ~0.4 KB per tick at the start, ~1.2 KB at
  2 x 50 ants (~24 KB/s down). Sent
  unreliable-ordered, so a late snapshot is dropped instead of stalling newer ones.
  Commands, results, join and reject are reliable.
- **Interpolation.** Clients draw the world 2 ticks (100 ms) behind the newest
  snapshot and blend between snapshots. That hides jitter up to ~50 ms and one
  lost packet. No extrapolation: if snapshots stop, ants hold still.
- **Join.** `HELLO` carries a protocol version and a random install token.
  Mismatched versions and strangers (when both slots are taken) are rejected with
  a reason. A slot belongs to the first token that took it; the same client token can
  rejoin it at once, even before its old connection times out.
- **Dead links.** ENet peer timeout is 5 s (default 30). Clients show
  "Connection unstable" after 1.5 s without snapshots, and "Host paused" when
  the hosting phone goes to the background.

## Known limits

- This is an unfinished Ants-only prototype, not the complete RTS.
- No attack-move, stop/hold, or minimap yet. W A S D panning is off so those can use letter keys (`PAN_WITH_WASD` in `pc_controls.gd` turns it back on).
- No Biomass/culling, player-built structures, other factions, terrain pathfinding, fog of war, or finished art yet.
- Movement is straight-line plus overlap push and colony collision; there is no obstacle navigation.
- No prediction: online commands are visible after roughly 100 ms interpolation plus network latency.
- Tokens protect reserved slots but are not account authentication. Desktop tokens currently live for one client instance; restarting the app cannot recover its old slot. LAN only; do not expose this server publicly.
- The match continues after a disconnect. No surrender or reconnect UI yet.
- Hosting shares the render loop; long stalls drop simulation time (logged). A dedicated server avoids rendering contention.
- Full snapshots expose both players' economy. No hidden-information security is claimed.
- Balance and bot behavior are placeholders. Visuals, real-LAN reliability, Windows exports, and minimum-PC performance still need hands-on testing.
- Headless tests cover simulation, match rules, scene wiring, and loopback UDP. Simulation timings are not rendered frame-rate measurements.
