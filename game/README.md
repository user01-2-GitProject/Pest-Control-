# Pest Control: Godot project

Milestone 3: first playable match loop (Ants only). Milk aphids for honeydew,
train workers and soldiers at your colony (cap 50 ants), fight in melee, and win
by destroying the enemy colony. Play offline against a simple local bot, or
online against another phone through a server that owns every rule.
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

## Open and run

1. Godot 4.7, **Import** `game/project.godot`.
2. Press **F5**. Mouse stands in for touch in the editor.
3. Pick **Play offline**, **Host game**, or type an address and **Join**.

## Play online (two phones, same Wi-Fi)

1. Phone A: **Host game**. Its HUD shows "join at 192.168.x.x".
2. Phone B: type that address, **Join**.
Each player controls only their own ants (red = player 1, slate = player 2).

Or run a dedicated server on a PC and have both phones join the PC's address:

```
cd game
godot --headless -s res://src/net/server_main.gd -- --port 7777
```

Uses UDP port 7777. A firewall on the host must allow it.

## Controls

| Action | Touch | Mouse (editor) |
|---|---|---|
| Select one ant | Tap it | Left click |
| Move selection | Tap ground | Left click ground |
| Attack | With ants selected, tap an enemy ant or colony (red ring) | same |
| Milk aphids | With workers selected, tap an aphid leaf | same |
| Train | **Worker 50** / **Soldier 100** buttons (bottom left) | same |
| Box select | Hold ~0.35 s (ring appears), then drag | Hold left, then drag |
| Pan | One-finger drag, or two-finger drag | Right or middle drag |
| Zoom | Pinch | Wheel |
| Select all / clear | **All** / **Clear** buttons | same |

## Android build

1. Editor Settings > Export > Android: set the Android SDK path and a debug keystore.
2. Project > Install Android Build Template.
3. Project > Export > Add **Android**, tick arm64-v8a, tick **Permissions > Internet**
   (needed for online play), then **Export Project** or use the
   one-click deploy button with a phone plugged in (USB debugging on).

## Layout

```
src/sim/      SimWorld: rules and state, fixed 20 Hz tick, no nodes. The server runs it.
src/ai/       BotAI: offline opponent; issues commands through the same queue as players.
src/net/      Protocol (wire format), GameServer, NetClient, SnapshotBuffer (jitter buffer),
              server_main.gd (headless entry point).
src/view/     Ant, map and marker visuals. Read sim state, interpolate between ticks.
src/input/    Touch gestures and camera rig.
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
  a reason. A slot belongs to the first token that took it; the same phone can
  rejoin it at once, even before its old connection times out.
- **Dead links.** ENet peer timeout is 5 s (default 30). Clients show
  "Connection unstable" after 1.5 s without snapshots, and "Host paused" when
  the hosting phone goes to the background.

## Known limits

- Online: tap-to-move shows the marker at once, but ants start moving about
  100 ms + one-way latency later (no client-side prediction yet). Measure on phones
  before deciding whether prediction is needed.
- Online: no player identity, so anyone on the network can take a free slot.
  LAN only; don't expose the port to the internet.
- Online: full snapshots every tick, ~24 KB/s per client at the cap. Delta-compress
  if phones on mobile data struggle. Both players' honeydew is visible to both clients.
- Match loop balance is placeholder. The bot is simple (fixed build, waves of 6).
- No surrender button or reconnect-by-identity yet.
- Not yet tested on real phones or a real Wi-Fi network; CI covers localhost UDP only.
- Movement is straight-line plus overlap push. No pathfinding or obstacles yet (Milestone 2).
- Overlap and target search use a 2 m grid. CI (desktop) measured ~1 ms per tick
  for a bot match and ~3 ms average, ~19 ms worst for a 50 v 50 soldier battle.
  Phones will be slower and are not yet measured.
- Not yet measured on a phone.
