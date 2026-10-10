---
name: ball
description: The rules of Project Juice's ball simulation. Load before changing anything that affects how the ball moves, bounces, or is launched - new surfaces or actors (fans, pads, ropes, levers, hazards), launch and limiter behaviour, the trajectory preview, the tuning resource, or the headless tests. Also load when a prediction and the real shot disagree, when a ball gets stuck or tunnels, or when adding gameplay numbers.
---

# The ball simulation

A vertical-shaft precision platformer. The player never walks or jumps: they drag a slingshot and
fire, switching between a light **squishy** ball and a heavy **rocky** ball. This is a Godot 4.7
port of a Phaser 3 prototype; `docs/PORTING.md` maps every file to its original and grades how
faithful each part is.

Typed GDScript only. Static types everywhere, no C#, no Godot 3 syntax. This project turns some
GDScript warnings into errors — notably overriding a native virtual, which is how an attempt to
override `CanvasItem._edit_get_rect` was caught.

## Three invariants. Breaking any of them breaks the game quietly.

### 1. `BallSim.step_ball` is the only code that moves a ball

The real ball (`ball/ball.gd`) and the trajectory preview (`prediction/trajectory_preview.gd`)
both call it, with the same fixed `dt`. That shared call is the *only* reason the ghost line can be
exact. A force applied in the ball node, or in the preview alone, makes the preview a lie.

So: anything that moves the ball goes in `core/ball_sim.gd`. No exceptions. If something feels like
it belongs on the node, it belongs in the step.

The step's order of operations is load-bearing and matches the Phaser original:

```
moving actors -> fans -> gravity -> air drag -> rolling friction -> speed cap
  -> substepped movement (spike sweep + contact resolution)
  -> pending lift -> pass-through drag -> support probe -> roll-off
  -> cable centring -> settle re-arm -> spin
```

**Moving actors advance once per step, at the top — never inside the substep loop.** Stepped per
substep they would advance further for a fast ball than a slow one, and the ghost would drift from
the ball even though both run the same function.

### 2. A prediction must not touch the world

`StepWorld.ghost()` decides what the preview shares and what it copies, and that single choice is
the whole correctness question:

- **Immutable → share.** Shapes, spike strips, fans. Copying would only cost time.
- **The ball can change it → copy.** Cables, levers, and the predicted-broken glass set.

Get this wrong and drawing a ghost line physically disturbs the level: *aiming at a shot changes
where it goes.* If you add anything the ball can change, copy it in `ghost()` and add a test
beside the existing ones (`a prediction leaves the real rope exactly where it was`).

Note the matching requirement: the ghost must leave the world alone **and** still match the ball
step for step. Both only hold because both run the same code from the same state.

### 3. No gameplay numbers outside `tuning/tuning_data.gd`

Every number lives there, and systems read `TuningData.get_active()` live every step — so editing
a value in the Inspector, including the *remote* inspector during play, changes the feel
immediately.

Two consequences people get wrong:

- **Don't invent a key.** If you need a reference value, reuse an existing one and say why in a
  comment. `Cable.absorb` scales recoil against `world.maxBallSpeed` rather than inventing a
  "typical impact" constant.
- **The sim must not depend on an autoload.** `TuningData.active` is a static, not the `Tuning`
  autoload, because a `--script` SceneTree has no autoloads. That is what lets the tests exercise
  the real simulation with no scene at all. `LaunchLimiter` is a plain `RefCounted` for the same
  reason.

Per-object variation is *not* a tuning number — it is a property of the placed object, like a
pad's `launch_speed`, a cable's `slack`, or a lever's tilt limit. Default those to `-1` meaning
"use the global".

## The actual game: the per-ball split

The physics never asks which form it is. It asks what the form *does* — `form.breaks_glass`,
`form.launches_off_trampoline`, `form.cable_bounce`. A third ball should be another entry in
`ball/ball_form.gd`, not a branch in the physics.

| Surface | Squishy | Rocky |
|---|---|---|
| Glass | bounces off it hard (0.65) | smashes through it |
| Trampoline | nearly dead underfoot (0.12) | thrown a long way (1150+) |
| Cable | thrown by it (0.31) | lands in it dead (0.04, under its bounce threshold) |
| Fan | flown by the stream (2.4) | only slowed by it (0.3, less than its gravity) |
| Lever | barely disturbs it (mass 1) | tips it (mass 6) |

Every row is "a route for one ball, an obstacle for the other". When you add a surface, decide its
row first — a surface that treats both balls alike is usually a design mistake, and the tests
include per-ball checks precisely to catch the two forms being accidentally made alike.

## Adding a surface vs adding an actor

Decide with one question: **does it hold state the ball can change?**

**No → make it a material.** Add to `core/surface_kind.gd`, give it a branch in
`BallSim._respond_to_shape`, and handle it in `restitution_for` / `friction_for`. It then gets
collision, resting support, friction, the route check, the editor gizmo and the drawing for free.
This is how trampolines work: a pad is a shape made of springy stuff. Per-pad variation goes on
`ShapeBody` beside `bounce_boost` and `launch_speed`. In the editor it is another
`surface_material` on `TerrainBlock`.

**Yes → it needs its own list on `StepWorld`**, a `step(dt)` called from the top of `step_ball`, a
`find_*_contact` / `_respond_to_*` pair in `_resolve_contacts`, `snapshot`/`restore`/`ghost_copy`,
and a line in `ghost()`. Follow `core/cable.gd`. Also probe it in `BallSim.ground_under`, or a ball
resting on it gets no friction, never counts as launchable ground, and is stuck there with no shot.

Either way: resolve it **before** the static world in `_resolve_contacts`. Where a rope crosses a
ledge, the thing the ball touched first is the rope, and resolving the ledge first pushes the ball
through it.

## Launching

`LaunchLimiter` (`core/launch_limiter.gd`) deliberately lives *beside* the simulation, not inside
it: it never moves the ball, it answers "may this shot go?" and "how hard?" at release. Four modes
— Grounded, Charges, Heat, Elasticity — set by `limiter_mode`.

- **Scale launch power in `Slingshot._velocity_for`**, where the preview reads it too. That is why
  the ghost line always shows the shot that will actually happen rather than one at full power.
- **Read `was_grounded` before mutating state.** `Ball.launch` burns the coyote grace and the
  ground material, and every mode charges differently for an airborne shot.
- **The cradle is not a special case.** A ball in the fork reports itself grounded, so it flows
  through the same answer. An earlier version short-circuited on `_cradled` and let a player with
  no charges fire anyway by starting the drag on the floor.
- **Heat never refuses a shot** — it only weakens it and shortens the ghost line. This is the
  behaviour the Phaser project flagged as an open design question (a patient player can still
  slow-climb), so a test pins it. If it becomes a refusal, that test should fail first.

One definition of "flat enough to stand on": `BallSim.is_horizontal_surface`. The settle, grounded
launches and the landing-vs-wall-bounce rule all use it. If they disagreed, a ball could settle
somewhere it cannot launch from, which reads as the game being broken.

## Running the tests

```bash
godot --headless --path . --script tests/run_tests.gd    # exit 0 on success
```

No display, no scene. **If you added a script with a new `class_name`, the run will fail with
`Could not find base class` until Godot writes it into the class cache** — a `--script` run reads
`.godot/global_script_class_cache.cfg`, which only the editor produces:

```bash
godot --headless --editor --quit --path .                 # then run the tests
```

That import pass is also the fastest way to find parse errors across the whole project.

A few GDScript format gotchas the tests hit: `%g` and the `+` flag (`%+.0f`) are not supported by
GDScript's `%` operator.

### What the tests are actually for

The prediction-exactness checks are the point of the architecture, and they must read
`0.000000 px`. Anything else means the ghost and the ball have been allowed to drift apart. Only
the *final* step of a prediction may differ — the ghost stops mid-step when its bounce budget
runs out while the real ball finishes that step. The Phaser project documents the same caveat.

When you write a behavioural test, measure the thing you mean. Two mistakes already made here:

- Measuring the *peak over time* instead of the first event. A ball left bouncing on a pad settles
  into a rhythm off the ceiling, so every drop height converges on the same impact and the impact
  bonus becomes invisible. Measure the first launch.
- Comparing against *another world's* actor. A rope that has been landed on hangs lower than one
  only flown through, so measure each world against its own.

Use a tolerance for resting contacts (within half a pixel), not float equality: the push-out pass
holds a resting ball just shy of the exact figure.

## Where the numbers came from, and where they are soft

**The port is finished and the Phaser project is no longer being developed. This is the game
now.** There is no original to defer to: `tuning/phaser_tuning.json` is a frozen set of starting
values, not a source to re-import from, and a question about how something should behave is a
design question, not an archaeology one. Answer it by what plays well.

That said, some numbers are better founded than others, and it is worth knowing which. Phases 1–2
were transcribed with the Phaser source open; phase 3 (the limiter modes, fans, trampolines,
cables, the lever) was reconstructed from the tuning keys alone. `docs/PORTING.md` grades each
system **transcribed / derived / reconstructed** and lists the places where a reading was inferred
rather than read. **If something feels wrong in cables or the lever, start there** — those are the
inferences, so they are the likeliest to need tuning.

One is a known defect rather than a doubt: at `lever.torqueScale` 1 the plank hits its stop under
either ball, so the mass difference is invisible and the lever is not yet a puzzle element.

The provenance comments throughout the code (`Ported from src/systems/X.ts`) are history worth
keeping — they explain why a function is shaped the way it is — but they are not instructions to
go and look anything up.

## Standing instructions

- **Don't touch level files** after the user has edited them. They build levels themselves and
  have had work overwritten. A new level in a new file is fine; editing theirs is not.
- No exports or builds unless asked.
