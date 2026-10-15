# Pest Control: Godot project

Milestone 2: first online play. Two phones each control 20 ants on one flat
map, against a server that owns the game state. Offline practice still works.
LAN or localhost only: no matchmaking, accounts or internet hosting yet.

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
godot --headless -s res://tests/smoke_main.gd
godot --headless -s res://tests/test_net.gd
```

CI also runs a dedicated server and two `tests/net_bot.gd` clients as three
separate processes over UDP; see `.github/workflows/godot-tests.yml`.

## Networking model

- **Server-authoritative.** Clients send only move intent (`MOVE`: unit ids + target).
  The server runs SimWorld and its `issue_move` validation (ownership, list size,
  finite target). Each client gets 8 commands per tick (extras dropped) and is
  kicked above 100 packets/s.
- **Snapshots, 20 Hz.** After every tick each client gets the full unit state
  (8 bytes per unit, ~330 bytes per tick for 40 ants, ~6.6 KB/s down). Sent
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
- Online: the install token is not authentication; anyone who copies it can take
  the slot. LAN only; don't expose the port to the internet.
- Hosting on a phone: the server ticks in the render loop, so a host hitch over
  250 ms drops sim time (logged as "dropped N ticks") and backgrounding the host
  stops the match. A dedicated server avoids both; a server thread is planned
  before the 2 x 50 stress milestone. The host also plays at ~0 ms ping while
  the other player pays Wi-Fi latency, so competitive play needs a dedicated server.
- iOS: LAN play will need `NSLocalNetworkUsageDescription` in the iOS export
  (no export presets are in the repo yet).
- Online: full snapshots every tick. Fine for 2 x 20; delta-compress before 2 x 50
  with combat.
- Not yet tested on real phones or a real Wi-Fi network; CI covers localhost UDP only.
- Movement is straight-line plus overlap push. No pathfinding or obstacles yet (Milestone 2).
- Overlap check is O(n²); fine for 20 units, needs a spatial hash before 2 x 50.
- Ants are 7 meshes each; batch or merge before scaling.
- Not yet measured on a phone.
