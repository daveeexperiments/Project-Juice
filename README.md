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
| **F1** | Debug overlay: collision edges, hitboxes, glass types, respawn point, limiter state |

By default launches are unlimited but only from a surface facing up — no wall jumps, no stacking
shots in mid-air. That is one of four **limiter modes**, set by `limiter_mode` in the tuning:

| Mode | What stops you launching for ever |
|---|---|
| **Grounded** (default) | A shot only goes from a surface you could stand on, plus a coyote window |
| **Charges** | A budget of shots, refilled by touching a surface whose facing *and* material qualify — glass gives nothing back to the squishy ball and a full refill to the rocky one |
| **Heat** | Every shot heats the ball. Rock sheds heat, air barely does. A hot ball still fires, just weakly, and its ghost line is cut short |
| **Elasticity** | The band wears with use — more for a full pull, more again in mid-air — and recovers with time |

Aiming slows the world rather than freezing it, so anything pushing the ball keeps pushing while a
shot is lined up.

Each surface is a route for one ball and an obstacle for the other, which is the whole game:

| | Squishy | Rocky |
|---|---|---|
| Glass | bounces off it, hard | smashes through it |
| Trampoline | nearly dead underfoot | thrown a long way |
| Cable | thrown by it | lands in it dead |
| Fan | flown by the stream | only slowed by it |
| Lever | barely disturbs it | tips it |

## Tests

```bash
godot --headless --path . --script tests/run_tests.gd
```

Exit code 0 on success. They need no display and no scene. The important one is **prediction
exactness**: the ghost line and the real ball run the same `BallSim.step_ball`, so a predicted
shot and the shot itself must match step for step — anything other than zero means the two have
been allowed to drift apart.

If you add a script with a new `class_name`, run `godot --headless --editor --quit --path .` once
so Godot writes it into the class cache — a `--script` run reads that cache and cannot see new
global classes without it.

`.github/workflows/tests.yml` runs the same suite on every push and pull request, pinned to Godot
4.7.2 because the prediction checks assert exact float equality. It does **not** trust the exit
code alone: a script that fails to compile anywhere in the project makes the tests that use it
crash and vanish while the runner still prints "PASSED" and exits 0 — breaking `core/cable.gd` on
purpose dropped the count from 81 to 72 with a zero status. So the workflow also fails on any
compile or runtime script error, and on the check count falling below `MIN_CHECKS`. Raise that
number when you add checks; never lower it to turn a red build green.

## Layout

| Folder | Holds |
|---|---|
| `core/` | The shared simulation: the step function, collision, glass rules, the route check |
| `ball/` | The ball node and its two forms |
| `slingshot/` | Aiming, the cradle, the band — and `aim_math.gd`, kept pure and testable |
| `prediction/` | The dashed ghost line |
| `blocks/` | Building blocks to drag into a level: Terrain, Glass, Trampoline, Spikes, Cable, Fan, Lever, Flag, Spawn |
| `tuning/` | Every gameplay number, as one Resource |
| `levels/`, `camera/`, `debug/`, `tests/`, `docs/` | |

## Three rules worth knowing before changing anything

**One step function.** `BallSim.step_ball` is the only code that moves a ball. The real ball and
the prediction both call it, which is the only reason the ghost line can be exact. Anything that
moves the ball goes in there, never in the ball node or the preview alone.

**No gameplay numbers outside the tuning resource.** `tuning/tuning_data.gd` holds them all, and
systems read `TuningData.get_active()` live, so editing a value in the Inspector — including the
*remote* inspector while the game is running — changes the feel immediately.

**A prediction must not touch the world.** Cables and levers move, so `StepWorld.ghost()` hands
the preview *copies* of them. Anything new that the ball can change has to be copied there too —
otherwise drawing a ghost line would swing the real ropes, and merely aiming at a shot would
change where it went. There are tests for this; add one alongside them.

## Building blocks

Each mechanic is a scene you drag into a level. They are `@tool` scripts, so they draw correctly
in the editor, and they inherit from `Polygon2D` / `Marker2D` so you can click them in the
viewport and drag their points. Collision is rebuilt from the polygon when the level loads.

A **Trampoline** is a Terrain block with its material set to trampoline, the same way Glass is —
a pad is a shape made of springy stuff rather than a separate kind of thing. A **Fan** is aimed by
rotating the node, and its polygon is the mouth, so the mouth's width is the stream's width. A
**Cable**'s two polygon points are its anchors and the rope hangs between them; because that
leaves a flat bounding box, grab a dead horizontal or vertical cable by one of its handles or from
the scene tree. A **Lever** is a Marker2D: it *is* a pivot, with the plank's length and tilt limit
as numbers rather than an outline.
