# Project Juice — Godot port

A vertical-shaft precision platformer: **two balls, one slingshot**. You never walk or jump — you
drag back a slingshot and fire, switching between a light **squishy** ball that bounces and a
heavy **rocky** ball that smashes glass.

This is the Godot 4 port of a Phaser 3 + TypeScript prototype. The Phaser project remains the
reference for behaviour; [`docs/PORTING.md`](docs/PORTING.md) maps every ported file and records
what could not be ported one-to-one.

## Running it

Open the project in **Godot 4.7** and press **F5** — `levels/test_room.tscn` is the main scene.

| Input | Does |
|---|---|
| Hold **LMB** and drag back, release | Aim and launch. Power comes from the drag's length, direction from its vector |
| **Q**, **Space**, **RMB** | Switch ball |
| **Shift** | Snap the aim angle |
| **Esc**, **RMB** while dragging | Cancel the shot |
| **R** | Back to the last raised flag |
| **F1** | Debug overlay: collision edges, hitboxes, glass types, respawn point |

Launches are unlimited, but only from a surface facing up — no wall jumps, no stacking shots in
mid-air. Aiming slows the world rather than freezing it, so anything pushing the ball keeps
pushing while a shot is lined up.

## Tests

```bash
godot --headless --path . --script tests/run_tests.gd
```

Exit code 0 on success. They need no display and no scene. The important one is **prediction
exactness**: the ghost line and the real ball run the same `BallSim.step_ball`, so a predicted
shot and the shot itself must match step for step — anything other than zero means the two have
been allowed to drift apart.

If you add a script with a new `class_name`, run `godot --headless --path . --import` once so
Godot registers it before the tests can see it.

## Layout

| Folder | Holds |
|---|---|
| `core/` | The shared simulation: the step function, collision, glass rules, the route check |
| `ball/` | The ball node and its two forms |
| `slingshot/` | Aiming, the cradle, the band — and `aim_math.gd`, kept pure and testable |
| `prediction/` | The dashed ghost line |
| `blocks/` | Building blocks to drag into a level: Terrain, Glass, Spikes, Flag, Spawn |
| `tuning/` | Every gameplay number, as one Resource |
| `levels/`, `camera/`, `debug/`, `tests/`, `docs/` | |

## Two rules worth knowing before changing anything

**One step function.** `BallSim.step_ball` is the only code that moves a ball. The real ball and
the prediction both call it, which is the only reason the ghost line can be exact. Anything that
moves the ball goes in there, never in the ball node or the preview alone.

**No gameplay numbers outside the tuning resource.** `tuning/tuning_data.gd` holds them all, and
systems read `TuningData.get_active()` live, so editing a value in the Inspector — including the
*remote* inspector while the game is running — changes the feel immediately.

## Building blocks

Each mechanic is a scene you drag into a level. They are `@tool` scripts, so they draw correctly
in the editor, and they inherit from `Polygon2D` / `Marker2D` so you can click them in the
viewport and drag their points. Collision is rebuilt from the polygon when the level loads.
