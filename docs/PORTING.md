# Porting Project Juice: Phaser → Godot

**Engine:** Godot **4.7.2.stable.official** (`ed1daf0bf`), standard build, typed GDScript only.
**Reference project:** `D:\REPLAY\ProjectJuice` (Phaser 3.90 + TypeScript). Read-only — nothing in
it was modified by this port.

**Phase 1:** project setup, the ball simulation, both ball types, the slingshot, grounded launches,
the trajectory prediction, a camera, a test room and headless tests.

**Phase 2:** glass (all five rocky modes, both bounce modes, the rising assist, breaking and
respawn), spikes, flags and the spawn, the reachability check, and the first building-block
scenes.

**Phase 3:** the three remaining launch-limiter modes (charges, heat, elasticity), fans,
trampolines, cables and the lever. Logic only, by instruction: no HUD, no audio and no juice
layer, and nothing visual that has no logic behind it. Pickups, the juice/audio layers and the
tuning panel remain.

> ### Read this before trusting phase 3
>
> Phases 1 and 2 were **transcribed** from the Phaser source with the source open. Phase 3 could
> not be: `D:\REPLAY\ProjectJuice` is not in this repository and was not reachable from the
> session that wrote it. What stood in for it was the complete tuning contract --
> `tuning/phaser_tuning.json`, all 250 Phaser values with their defaults -- plus the existing
> ported code, which in several places turned out to describe the missing systems precisely.
>
> So phase 3 is graded, and the grades are in the table below:
>
> | | |
> |---|---|
> | **transcribed** | the Phaser code was readable, directly or through code already ported from it |
> | **derived** | the tuning keys and the existing architecture pin the behaviour down; little room to be wrong |
> | **reconstructed** | the keys name the model but not its arithmetic; structurally right, numerically worth checking |
>
> Everything is covered by the headless tests, and the two architectural invariants -- `step_ball`
> is the only mover, and a prediction cannot disturb the level -- are tested directly for every
> new actor. Where a reading was uncertain it is flagged in the code at the point it matters, not
> only here.

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
| `src/systems/LaunchLimiter.ts` | `core/launch_limiter.gd` (+ `since_launchable` in `ball/ball.gd`) | **derived.** All four modes. Grounded came in phase 1; charges, heat and elasticity are phase 3. |
| `src/systems/Actors.ts` (fans) | `core/fan_field.gd` + `blocks/fan_block.gd` | **derived.** Stateless force field; `fans.sustain` is the one reading I am unsure of (see below). |
| `src/systems/Actors.ts` (trampolines) | `core/ball_sim.gd` (`_apply_trampoline_launch`) | **transcribed in effect.** The pad's three keys line up one for one with the glass boost's, which phase 2 ported from source and already called "trampoline-style". |
| `src/systems/Actors.ts` (cables) | `core/cable.gd` + `blocks/cable_block.gd` | **reconstructed.** Verlet chain. Structure and the two-mode throw are well pinned; `clearAbove`/`clearBelow` deliberately unmapped. |
| `src/systems/Actors.ts` (the lever) | `core/lever.gd` + `blocks/lever_block.gd` | **reconstructed.** Torque balance. The parts list is unambiguous, the units are not. |

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

**The limiter.** Phase 1 ported Grounded only, where `canLaunch` collapses to "on a launchable
surface, or inside the coyote window". Phase 3 added the other three; see the phase 3 notes.

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

## Phase 3 notes

**The limiter is not in the step, on purpose.** It never moves a ball: it answers "may this shot
go?" and "how hard?" at the moment of release. Keeping it beside the simulation rather than inside
it means it cannot throw the ghost line off, and the tests can drive a limiter with no ball and no
scene. It is a `RefCounted` rather than an autoload for the same reason `BallSim` is: a `--script`
SceneTree has no autoloads.

**Heat never refuses a shot.** It makes one weaker and its ghost line shorter, and that is all.
This is the behaviour the Phaser project itself flagged as unfinished -- a patient player can
still slow-climb on repeated airborne shots -- so a test pins it deliberately. If it ever becomes
a refusal, that test should be the first thing to fail.

**A trampoline is a material, not an actor list.** A pad is a shape made of springy stuff, so it
goes through `_respond_to_shape` exactly where glass does and gets collision, resting support,
friction, the route check, the editor gizmo and the drawing for free. Two rules differ from glass:
a pad launches on a *landing* (glass gives its boost up when landed on so a glass ledge stays
standable; a pad you could stand on would not be a trampoline), and the rising assist does not run
after a launch (the pad already decided where the ball is going).

**Cables and levers are the first things the ball can move**, which makes them the first things
`StepWorld.ghost()` has to copy rather than share. This is not housekeeping: if a preview swung the
real ropes, drawing one would physically disturb the level, and merely aiming at a shot would
change where it went. Both are tested for it directly. Both are also advanced once per
`step_ball` and never per substep -- inside the substep loop a fast ball would advance them
further than a slow one and the ghost would drift.

**Three things left unmapped on purpose**, so they show up in `docs/unmapped_tuning_keys.txt` as
"not ported" rather than being bent into roles where they do nothing:

- `cables.clearAbove` (128) and `cables.clearBelow` (96). A cable contact only ever happens within
  the ball's radius plus the rope's thickness, about 17 px, so bands of that size would be
  satisfied every single time. Beside `padding.*` and `padding.actorClearance` they read as
  level-generation clearance -- how much room to leave around a rope so it is landable and
  passable. The one-way floor rule is pure geometry instead.
- `trampoline.idleBounce`, `idleSpeed`, `boingInterval`. An idle animation and its sound. No logic
  behind them, so out of scope by instruction.

**What to check against the Phaser source, in priority order.** Everything here passes its tests;
these are the places where a test can only prove the code is self-consistent, not that it matches
the original.

1. **`lever.pivotFriction` and `lever.torqueScale`.** At `torqueScale` 1 the plank slams into its
   stop under either ball in well under a second, which suggests `torqueScale` is carrying a units
   conversion in the original. Is `pivotFriction` a torque (as here) or an angular deceleration?
2. **`fans.sustain` (0.55).** Used here as how much push survives at the very edge of the mouth, so
   a ball slides out of a stream rather than falling off a shelf of air. It could instead be a
   decay on the push once the ball is leaving.
3. **The cable throw.** `cables.softness` is used only for how far the rope gives (`recoil`), not
   to damp the bounce. `cables.impactBonus` is applied only to the *sustained* throw, mirroring
   glass, where `boostImpactGain` applies only in Boost mode -- in the physical case the bounce
   already scales with the impact, so adding a bonus would count it twice.
4. **Where the fan force goes.** The phase-1 comment in `ball_sim.gd` said "fans multiply [the
   gravity scale] in Phaser", but `fans.targetSpeed`, `strength` and `falloff` only make sense as a
   force field converging on a stream speed, which is how it is built. If Phaser really folds it
   into a gravity scale, the hovering behaviour will differ.
5. **`squishy.trampolineBounce` is 0 while `squishy.launchesOffTrampoline` is false.** Read here as
   the two agreeing rather than conflicting: the squishy ball neither launches off a pad nor would
   get anything if it did. A non-launching ball instead bounces at the global
   `trampoline.squishyBounce` (0.12).

**One editor caveat.** A cable's two anchors are its Polygon2D points, which gives a flat bounding
box, so a dead horizontal or vertical cable is hard to click in the empty space around it -- pick
it up by a handle or from the scene tree. `_edit_get_rect` would be the obvious fix and is not
available: it is a `CanvasItem` virtual that GDScript may not override, and this project turns that
warning into an error. Point-editing, which is what the Polygon2D rule is chiefly about, works
normally.

---

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

**171 values map** onto `TuningData` after phase 3. **79 do not** and are listed in
`docs/unmapped_tuning_keys.txt`:

| Group | Count | Why it is not here |
|---|---|---|
| `juice.*`, `fx.*`, `audio.*` | 50 | the juice and audio layers, excluded by instruction |
| `pickups.*` | 10 | the pickups phase |
| `padding.*`, `procedural.*` | 9 | level generation (not planned) |
| `trampoline.*` idle animation | 3 | an idle wobble and its sound: visuals with no logic |
| `cables.clearAbove`, `clearBelow` | 2 | level-generation clearance, not collision (see above) |
| `slingshot.aimSlowMoPitch`, `showContactMarkers` | 2 | an audio pitch and a debug marker |
| `camera.mode` | 1 | only the prototype-D camera is ported |
| `squishy.screenShake`, `rocky.screenShake` | 2 | juice |

Every value the ported systems read is mapped. Nothing excluded here changes how a ball moves.

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
| **Cables:** sag capped at maxSag, anchors stay pinned | 56.0 px of droop, cap 56 |
| **Cables:** squishy thrown (234 px/s), rocky lands dead (0) | the per-ball split holds |
| **Cables:** one-way floor, caught from above and passed from below | both |
| **Cables:** sustained throw ignores the drop height | 502.0 px/s from either height |
| **Cables:** a preview leaves the real rope bit-identical | all 15 knots unmoved |
| **Levers:** rocky tips the plank harder than squishy | 107 steps to the stop against 266 |
| **Levers:** a counterweight holds its side down; the stop holds | both |
| **Levers:** a preview leaves the real plank's angle unchanged | unmoved |
| **Trampolines:** rocky thrown, squishy barely moved | 1780 px/s against 81 |
| **Trampolines:** launch = pad speed + its share of the impact | 1780 = 1150 + 0.45 x 1400 |
| **Fans:** squishy flown, rocky only slowed | -75 px against +53 px in 0.3 s |
| **Fans:** never brakes a ball already faster than the stream | 0 px/s^2 at 900 px/s up |
| **Fans:** a pane shadows the stream for both balls alike | holds |
| **Limiter:** grounded refuses mid-air even with air launches allowed | refused |
| **Limiter:** charges spend, refill, and respect the settle dwell | all correct |
| **Limiter:** glass refills for rocky only | squishy 0, rocky 3 |
| **Limiter:** a fully hot ball still fires, weakly | power x0.40 |
| **Limiter:** elasticity wears by pull, floors, and recovers | all correct |
| Prediction stays exact through a fan, a pad, a cable and a lever | 0.000000 px each |
The prediction check is the important one: the ghost and the ball run the same
`BallSim.step_ball`, so anything other than zero means they have been allowed to drift apart.

The **final** step of a prediction is measured separately and allowed to differ: the ghost stops
mid-step when its bounce budget runs out while the real ball finishes that step. The Phaser
project documents and tests around the same caveat. Every step before it is exact.
