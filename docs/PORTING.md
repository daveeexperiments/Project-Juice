# Porting Project Juice: Phaser → Godot

**Engine:** Godot **4.7.2.stable.official** (`ed1daf0bf`), standard build, typed GDScript only.
**Reference project:** `D:\REPLAY\ProjectJuice` (Phaser 3.90 + TypeScript). Read-only — nothing in
it was modified by this port.

**Phase 1:** project setup, the ball simulation, both ball types, the slingshot, grounded launches,
the trajectory prediction, a camera, a test room and headless tests.

**Phase 2:** glass (all five rocky modes, both bounce modes, the rising assist, breaking and
respawn), spikes, flags and the spawn, the reachability check, and the first building-block
scenes. Fans, trampolines, levers, cables, pickups, juice, audio and the tuning panel remain for
later phases.

---

## File map

| Phaser file | Godot script | Notes |
|---|---|---|
| `src/systems/MaterialCollision.ts` (`stepBall` and helpers) | `core/ball_sim.gd` | The shared step. Order of operations kept identical. Tile-grid paths dropped: this port has polygons only. |
| `src/systems/MaterialCollision.ts` (`BodyState`) | `core/ball_state.gd` | `groundMaterial: null` became `SurfaceKind.NONE`, since a typed int cannot be null. |
| `src/systems/MaterialCollision.ts` (`Contact`) | `core/contact.gd` | Fields for unported systems (glass breaking, trampoline launches, rising assist) left out. |
| `src/systems/MaterialCollision.ts` (`CollisionPolicy`) | `core/step_policy.gd` | Only `on_contact` is needed in phase 1. |
| `src/systems/MaterialCollision.ts` (`StepWorld`) | `core/step_world.gd` | Plus `from_group`, which builds the world from scene nodes instead of a Tiled map. |
| `src/systems/ShapeBody.ts` (`ShapeBody`, `contact`, `contains`) | `core/shape_body.gd` | Ported verbatim, including the closest-point-across-all-edges rule. |
| `src/systems/ShapeBody.ts` (`ShapeContact`) | `core/shape_contact.gd` | |
| `src/config/tuning.ts` (`Material`) | `core/surface_kind.gd` | |
| `src/config/tuning.ts` (`DEFAULT_TUNING`, `restitutionFor`) | `tuning/tuning_data.gd` | Values exported to `tuning/phaser_tuning.json` and loaded on startup. |
| `src/config/tuning.ts` (the live `tuning` object) | `tuning/tuning_service.gd` (autoload `Tuning`) | Owns the live resource; the sim reads `TuningData.get_active()`. |
| `src/forms/BallForm.ts`, `SquishyForm.ts`, `RockyForm.ts` | `ball/ball_form.gd` | One class with an id, reading tuning live, rather than three files. |
| `src/entities/Ball.ts` | `ball/ball.gd` | Simulation, form switching, overlap resolution, placeholder visuals. |
| `src/systems/AimMath.ts` | `slingshot/aim_math.gd` | Ported whole, including the edge hysteresis and the snap-then-clamp ordering. |
| `src/systems/Slingshot.ts` | `slingshot/slingshot.gd` | Drag, cradle, aim range, launch gating, band and fork drawing. |
| `src/systems/AimPointer.ts` | `slingshot/slingshot.gd` (`_input`) | See "window-level input" below. |
| `src/systems/TrajectoryPreview.ts` | `prediction/trajectory_preview.gd` | Same shared step; dashes, along-fade and per-bounce fade ported. |
| `src/systems/CameraController.ts` (the `followCameraX` branch) | `camera/follow_camera.gd` | Prototype D follows both axes. |
| `src/scenes/Game.ts` (fixed step, aim slow motion, form switch) | `levels/level.gd` | Only the phase-1 parts. |
| `src/debug/DebugOverlay.ts`, `src/debug/DesignOverlay.ts` | `debug/debug_overlay.gd` | Merged into one F1 overlay. |
| `src/systems/MaterialCollision.ts` (glass helpers) | `core/glass_rules.gd` | `rockyGlassMode`, `rockyWouldBreak`, `glassIsSolidFor`, `effectiveMaterial` and `blocksRoute` in one place. |
| `src/systems/GlassClassify.ts` | `core/glass_rules.gd` (`classify`) | Edges weighed by LENGTH, never filtered by it. |
| `src/systems/Actors.ts` (`Spikes`, `spikeContact`, `spikeSweep`) | `core/spike_strip.gd` | Whole block is deadly, from every side, swept along the path. |
| `src/systems/LevelLoader.ts` (`checkRouteOpen`) | `core/route_check.gd` | Static and tree-free, so the tests can seal a level and prove it catches it. |
| `src/systems/LevelLoader.ts` (object reading) | `blocks/*.gd` + `levels/level.gd` (`_build_world`) | Tiled objects became editor scenes; the level reads the groups they add themselves to. |
| `src/systems/LevelLoader.ts` (`breakShape`, `restoreShapes`) | `levels/level.gd` | Breaking, the respawn timer and the "never on top of the ball" rule. |
| `src/debug/*` (glass/spike/flag marks) | `debug/debug_overlay.gd` | Glass by type, spike boxes, flag reach, respawn point, active mode. |
| `src/juice/InkParticles.ts` (shards only) | `levels/shatter_effect.gd` | Placeholder shards; the juice layer is a later phase. |
| `src/systems/LevelLoader.ts` | *(not ported)* | Tiled loading is replaced by scene nodes in the `terrain` group. |
| `src/systems/LaunchLimiter.ts` | *(partly, in `ball/ball.gd`)* | Only the Grounded mode: `since_launchable` is the port of `sinceGrounded`. Heat, charges and elasticity are not ported. |

New files with no Phaser counterpart: `core/game_state.gd` (autoload), `levels/test_room.tscn`,
`levels/test_room_backdrop.gd`, `tuning/save_default.gd`, `tests/run_tests.gd`, and the building
blocks `blocks/Terrain.tscn`, `Glass.tscn`, `Spikes.tscn`, `Flag.tscn`, `Spawn.tscn` with their
`@tool` scripts.

---

## Not ported 1:1, and why

**Tiles.** Phaser's `stepBall` collides against a tile grid *and* polygons, and clamps the substep
to `min(radius, tileSize)`. This port has no tile grid — level geometry is `Polygon2D` nodes — so
the tile branch is gone and the substep clamps to `radius * 0.5` alone. For the cave-style levels
this phase targets, the two are equivalent: the Phaser cave levels have no tile layers either.

**`null` ground material.** GDScript cannot hold a typed null, so `SurfaceKind.NONE` (-1) stands
in. Every `state.groundMaterial !== null` test became `!= SurfaceKind.NONE`.

**Window-level input.** Phaser's `AimPointer` listens on `window` rather than the canvas, so a
drag keeps tracking over the letterbox and outside the browser. Godot's `_input` already receives
events regardless of what is under the pointer, and screen→world goes through
`get_canvas_transform().affine_inverse()`, which is the transform actually used to draw — so the
aim is correct at any window size and would stay correct under camera shake. Losing focus
mid-drag cancels via `NOTIFICATION_APPLICATION_FOCUS_OUT`; a mouse-up anywhere releases. Phaser's
`setPointerCapture` has no equivalent and is not needed.

**The cradle lift is instant.** In Phaser the ball's *state* moves to the cradle point immediately
and only the *visual* is tweened up over ~120 ms (`liftAnim`), with a pull-back offset as power
builds. This port moves the state the same way but does not animate the visual, so the lift pops.
Cosmetic only — the simulation and the prediction see the same positions either way.

**Tuning panel.** Not ported (later phase). The Inspector stands in: select the **Tuning** autoload
in the *remote* scene tree during play and edit `data`.

**The limiter.** Only Grounded is ported, because it is the only mode phase 1 uses. `canLaunch`
collapses to "on a launchable surface, or inside the coyote window".

---

## Phase 2 notes

**The blocks inherit from editable node types, and they have to.** Terrain, Glass and Spikes
extend `Polygon2D`; Flag and Spawn extend `Marker2D`. A `Node2D` that draws only in `_draw()`
has an empty editor rect, so clicking its shape in the viewport selects nothing, and Godot
offers the point-dragging gizmo only to the Polygon2D family. Inheriting gives both for free.
The inherited `color` is set fully transparent so Polygon2D supplies the handles and the bounds
while `_draw()` supplies the ink look.

**`material` had to be renamed.** The brief asks for a `material` export on the terrain block, but
`CanvasItem.material` already exists (the shader one) and Godot refuses to let a script redefine
it. The export is **`surface_material`**; everything else about it is as specified.

**The prediction takes a ghost copy of the world.** `StepWorld.ghost()` shares the geometry but
keeps its own `predicted_broken` set, so a predicted break opens the route for the rest of the
line and leaves the real world untouched. Same idea as `GhostTiles` in Phaser.

**Spike slabs are ordinary wall shapes.** A strip registers both a `SpikeStrip` (deadly, swept)
and a wall `ShapeBody` flagged `spike_base`. That gets collision, the prediction and the drawing
for free, and the route check steps over anything flagged — spikes are flown around, not barriers.
The Phaser project learned this the hard way: a slab that covered the teeth fenced the ball off
from the very zone that kills it, and every strip went quietly inert.

**Glass respawn waits for the ball.** A pane whose timer is up but which would reappear around
the ball waits another 0.25 s, as `restoreShapes` does in Phaser.

## Where the Phaser code and the brief disagreed

Three places; the Phaser code won each time, as instructed.

1. **Camera look-ahead.** The brief says "look-ahead in the direction of travel". Phaser looks
   ahead on X in whichever direction the ball is moving, but on Y only when **falling**
   (`Math.max(0, vy)`) — there is no upward look-ahead, deliberately, so a climb keeps the ball
   low on screen. Ported as Phaser has it.

2. **"Releasing while airborne fizzles".** True, but in Phaser the fizzle is gated on the
   *limiter*, which includes the coyote window — so a release a few hundredths of a second after
   leaving a ledge still fires. Ported with the coyote window (`grounded.coyoteTime`, 0.1 s), not
   as a hard "must be touching right now".

3. **"Glass is solid for both balls" in phase 1.** Matches Phaser only because the current tuning
   has rocky breaking glass on contact; the Phaser code path for that exists and is simply not
   ported. When phase 2 adds it, `_respond_to_shape` is where it goes — the hook is commented.

Also worth flagging: the brief lists the current defaults as *Physical* bounce style and *Reflect*
glass. That matches the Phaser project as of `TUNING_VERSION = 15`, so nothing special was needed —
but both values come from the exported JSON, so if the Phaser defaults change, re-export and this
port follows.

---

## Tuning

`tuning/phaser_tuning.json` is generated from the Phaser `DEFAULT_TUNING` (250 values, tuning
version 15). It did not exist before this port; the extractor parses `src/config/tuning.ts`
without modifying it.

**69 values map** onto `TuningData`. **181 do not** and are listed in
`docs/unmapped_tuning_keys.txt`. They are, in full, the systems this phase excludes:

| Group | Count | Arrives in |
|---|---|---|
| `juice.*`, `fx.*`, `audio.*` | 50 | the juice/audio phase |
| `cables.*` | 16 | the cables phase |
| `risingAssist.*` | 10 | the bounce-styles phase |
| `pickups.*`, `heat.*`, `charges.*`, `elasticity.*` | 33 | the limiter phase |
| `trampoline.*`, `fans.*`, `lever.*`, `spikes.*`, `flags.*` | 33 | the actors phases |
| `padding.*`, `procedural.*` | 9 | level generation (not planned) |
| per-ball `breaksGlass`, `cableBounce`, `fanMultiplier`, `trampolineBounce`, … | 18 | with their systems |
| `surfaces.glass.*` boost/break values | 10 | glass phase 2 |
| `limiter.mode`, `slingshot.allowAirLaunch`, `camera.mode`, … | 12 | later |

Nothing in that list affects phase-1 behaviour: every value the ported systems read is mapped.

To regenerate after changing the Phaser defaults:

```bash
node <scratch>/extract-tuning.mjs          # writes tuning/phaser_tuning.json
godot --headless --path . --script tuning/save_default.gd   # rewrites tuning/default.tres
```

---

## Running it

**The test room:** open the project in Godot and press **F5**, or click ▶. `levels/test_room.tscn`
is the main scene, so there is nothing to pick. To run it from the command line:

```bash
godot --path C:\Users\Davee\Documents\project-juice
```

**Controls:** hold **left mouse** anywhere and drag back to aim, release to launch. **Q**, **Space**
or **right mouse** switches ball. **Shift** snaps the angle. **Esc** or right mouse cancels a drag.
**R** respawns. **F1** toggles the debug overlay.

**The tests:**

```bash
godot --headless --path C:\Users\Davee\Documents\project-juice --script tests/run_tests.gd
```

Exit code 0 on success, 1 on any failure. They need no display and no scene.

---

## What the tests check

| Check | Result |
|---|---|
| Prediction, squishy: reflect / boost / rising / boost+rising | 0.000000 px each, 6 shots |
| Prediction, rocky: each of the five glass modes | 0.000000 px each, 6 shots |
| Aim: never sticks, never jumps, covers the circle (snap 0 and 5) | 0 stuck, 0.500 deg / 5.000 deg largest step |
| Aim range edge does not flicker | 3 swaps in a full sweep |
| Glass: always / never / hard (both sides) / pass / obstructions-only | all as specified |
| Glass: pass-through is still solid for squishy | holds |
| Classification: bridge is an obstruction, wall pane is cladding | both correct |
| Spikes: bite from all six faces, not from 3 radii clear | correct |
| Spikes: swept check catches a 120px step across a 10px strip | caught |
| Respawn: starts at spawn, follows the most recent flag | correct |
| Route check: passes open, catches rock-sealed, ignores glass-sealed | correct |
| Squishy settles rather than bouncing forever | comes to rest |
The prediction check is the important one: the ghost and the ball run the same
`BallSim.step_ball`, so anything other than zero means they have been allowed to drift apart.

The **final** step of a prediction is measured separately and allowed to differ: the ghost stops
mid-step when its bounce budget runs out while the real ball finishes that step. The Phaser
project documents and tests around the same caveat. Every step before it is exact.
