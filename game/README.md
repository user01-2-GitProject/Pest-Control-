# Pest Control: Godot project

Milestone 1: offline prototype. One flat forest-floor map, 20 placeholder ants,
high-angle camera, select and move. No online play yet.

Platform: **PC first** (Linux and Windows). Mobile is deferred, not dropped: the
project keeps the Mobile renderer so it can export to phones later.

## Open and run

1. Godot 4.7, **Import** `game/project.godot`.
2. Press **F5**.

## Controls

Current controls are touch-first with mouse equivalents. Standard PC RTS controls
(left-drag box select, right-click move, WASD/edge scroll) are the next change.

| Action | Touch | Mouse |
|---|---|---|
| Select one ant | Tap it | Left click |
| Move selection | Tap ground | Left click ground |
| Box select | Hold ~0.35 s (ring appears), then drag | Hold left, then drag |
| Pan | One-finger drag, or two-finger drag | Right or middle drag |
| Zoom | Pinch | Wheel |
| Select all / clear | **All** / **Clear** buttons | same |

## PC build

1. Editor > Manage Export Templates > **Download and Install**.
2. Project > Export > Add **Linux** (and/or **Windows Desktop**), then **Export Project**.

## Layout

```
src/sim/      SimWorld: rules and state, fixed 20 Hz tick, no nodes. Server can run it later.
src/view/     Ant, map and marker visuals. Read sim state, interpolate between ticks.
src/input/    Touch gestures and camera rig.
src/ui/       HUD: stats, buttons, drag box.
src/main.gd   Wires the layers; selection is client-side only.
tests/        Headless tests (run in CI on every PR).
```

## Tests

```
cd game
godot --headless --import
godot --headless -s res://tests/test_sim.gd
godot --headless -s res://tests/smoke_main.gd
```

## Known limits

- Movement is straight-line plus overlap push. No pathfinding or obstacles yet (Milestone 2).
- Overlap check is O(n²); fine for 20 units, needs a spatial hash before 2 x 50.
- Ants are one merged mesh each; switch to MultiMesh if draw calls become a problem.
- Not yet profiled on a minimum-spec PC.
