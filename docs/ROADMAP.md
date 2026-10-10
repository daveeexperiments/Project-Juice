# Plan of action: from prototype to the machine level

The prototype proved the feel. This is the plan for turning it into a polished, sprite-based level
without losing the thing that makes it worth playing.

**The goal that constrains everything else:** the trajectory preview must stay exact. It is the
mechanic, not a feature. Every decision below is downstream of keeping the ghost line honest.

---

## Decisions already taken

| Decision | Choice | Consequence |
|---|---|---|
| Movement | **Slingshot only.** No walking, no jumping. | No character controller. The sim's movement model is unchanged. Level design stays a precision-aiming puzzle. |
| Physics | **Keep the custom sim.** Not Godot physics. | Prediction stays exact. The cost is that broadphase and rotating bodies are ours to build — Godot would have given those away free. |
| Collision | **Authored, not derived.** Primitives for props; simplified, radius-closed polygons for terrain. | See below. This is the decision everything else hangs off. |
| Art delivery | **SVG per piece with named layers, plus PNG at a fixed scale.** | Layer names drive which collision primitive a piece gets. Where a polygon is needed, the SVG path beats tracing pixels. |
| Build order | **Greybox first, art second.** Each beat is playable in plain blocks before any sprite touches it. | Level building starts immediately with tools that already exist, instead of waiting on the pipeline. See "How we build the level". |
| Ball names | **Squishy and Rocky.** | The code keeps the names it has, including the Phaser-inherited tuning keys (`rocky.cableBounce` and friends). The designer's notes say "Heavy" — that needs passing on, so layer names and future notes line up. |

---

## The collision model

> **Collision is not derived from the art. It is authored, and it is allowed to disagree with the
> art on purpose.**

Deriving collision from the drawing is backwards for a physics game. The art is detail; the
collision is a purpose-built proxy, often a different shape deliberately.

### Most props are primitives, not polygons

The machinery is nearly all circular, and the detail that makes it read as machinery is exactly the
detail that would wreck the physics.

| Asset | Collision | Why |
|---|---|---|
| Gears, pulleys, wheels, flywheels | **Circle** | The teeth are visual. Trace them and the ball wedges between teeth. A gear is a disc that spins. |
| Saw blades | **Circle** + hazard radius | Same. The teeth sell the danger; the circle does the physics. |
| Straight pipes, beams, platforms | **Rectangle / capsule** | |
| Pipe elbows | **Two rectangles** | |
| Springs, rubber | **Trampoline surface** | Already built. |
| Vents | **Fan** | Already built. The designer's "vfx for the air currents" is pure VFX, no collision. |
| Chains | **Cable** | Already built. |
| Piston | **Moving rectangle** | |
| Pipe fragments for the explosion | **None** | Pure VFX. Never reaches the sim. |

Only the **terrain blobs** genuinely need polygons. That shrinks the hard part of the pipeline to
one category, and most of the designer's moving parts map onto systems that already exist.

**The exception to settle deliberately:** the hollow spiky gears, and the ring the player passes
*inside*. That is an annulus — the ball touches the inner surface — and `ShapeBody` holds a single
closed outline with no hole support. It needs an explicit answer rather than falling out of the
pipeline.

### Terrain: simplify, then close by the ball's radius

A ball of radius *r* physically cannot touch the inside of any pocket narrower than *r*. So do not
model that pocket.

Offset the outline outward by *r*, then inward by *r* — a morphological **closing**, which is
`Geometry2D.offset_polygon` twice. Every concavity too small for the ball is filled; everything the
ball can actually reach survives untouched. It is the formal version of what level designers do by
hand when they fillet an inside corner so a ball rolls through instead of wedging.

Use the **larger** of the two radii (squishy's 12, not rocky's 11), so one collision shape is safe
for both forms.

### The quiet benefit

Once collision is authored rather than traced, the art is **free**. The ink edges can be as grainy
and detailed as the designer likes, because none of it reaches the sim. Worth telling them: it
removes a constraint they may be working under.

---

## The character

The player is no longer a drawn circle. It is an animated sprite — a one-eyed worm that curls into
a circle, with one eye.

**It is a circle in both forms.** The only art that is not circular is the *morph between them*: a
short sprite sheet where the worm uncurls, flips and curls back up. Those elongated frames are a
transition, not a shape the worm holds, so **the collision is one circle and never changes.** No
capsule, no multi-circle body, no orientation state in the simulation.

**Pink-dominant is Squishy, green-dominant is Rocky, and both are the same size.** The form switch
is the fur: soft and out versus dense and in. That is a strong piece of design, because the player
reads the current form instantly with no UI at all.

### Same radius in both — unify the tuning

The tuning currently has `squishy.radius` 12 and `rocky.radius` 11. The art says they are the same
circle, so these should become one number.

This is worth doing for its own sake, not just to match the art. **An 8% size difference is
invisible to the eye and decisive in a tight gap** — a gap Rocky fits through and Squishy does not,
with nothing on screen to explain why. That is an unfair rule, and unfair rules in a precision game
read as bugs.

It also removes a whole class of edge case: `Ball._resolve_overlap` exists because switching to a
*larger* form mid-air can leave the ball inside a wall, and it pushes outward in rings until it
finds space. With equal radii that can no longer happen. The code stays as a guard; the situation
stops arising.

The final value waits on the world-scale decision, since *k* scales it with everything else.

### The sprite never drives the collision

> **The collision shape is a circle of `form.radius`. Always.** The sprite squashes, stretches and
> elongates; the sim does not notice.

Same principle as the terrain, applied to the player. Three consequences that are easy to get
wrong:

- **Never transform-rotate the character.** One eye means free rotation spends half its arc upside
  down. Airborne, orient the sprite along the velocity vector so the eye leads. Grounded, play a
  roll cycle — and `state.spin` already drives it for free, because it accumulates as
  `vx / radius * dt`, which *is* the rolled angle. `spin` stays in the sim untouched and feeds a
  frame index instead of a rotation.
- **Stretch backwards from the leading edge, not symmetrically about the centre.** Scale about the
  centre and both ends grow, so the nose juts past the collision circle by `(stretch − 1) × r` and
  visibly buries itself in a wall a frame before the physics stops it. Anchor the leading edge at
  the collision boundary and let the tail stretch behind; the trailing stretch is what reads as
  speed anyway.
- **Let the fur overlap surfaces.** Collision is the body, not the halo. Fur squashing *into* a
  surface reads as soft; fur holding the character off a surface reads as floating.

### Two state machines, flowing one way

The sim has form, grounded, held, settle hops and contacts. The visuals have idle, aiming, launch,
flying, impact, rolling, switch, break, death, respawn. **The visual machine is driven by the sim
and never the reverse.**

It lives in its own node (`BallVisuals`), not in `ball.gd`, so the simulation file stays about
simulation and the art is swappable. The state *selection* should be a pure function — given
`BallState`, form and the last contact, return a visual state — so it is unit-testable like
everything else here, even though the animation is not.

`Contact` is already the animation trigger payload: it carries `impact_speed`, `material`,
`landing`, `boosted`, `launched_off` and `broke_glass`. That is enough to pick an impact animation
*and* scale its intensity, with no new event system.

### Animation must never gate gameplay

No "play the wind-up, then launch". The moment a shot waits on an animation frame the prediction
becomes a lie and the input feels laggy — and the prediction being honest is the whole game.
Anticipation is cosmetic: the sim acts immediately and the art catches up.

**The form switch is the case where this is load-bearing, not merely tidy.** In the sim it is
instant: gravity changes on the frame the button goes down. The morph animation runs behind it and
the simulation never waits.

The designer's own beat depends on it. "Switching from Squishy to Heavy just before landing greatly
reduces the impact" is a precision mid-air action — the player presses switch perhaps 100 ms before
contact. Gate the switch on the morph finishing and the window becomes unreliable, the preview lies
about the landing, and the beat that *teaches* the mechanic is the first thing to break.

Two consequences for the visual layer, neither of which touches the sim:

- The morph frames stick out past the collision circle, so switching while resting against a
  surface will overlap it. Over a couple of hundred milliseconds that reads as squash rather than
  clipping — accept it, and ask the designer to keep the morph's extent modest.
- The morph must survive interruption. Switch twice quickly and the sim is already in the new form
  while the animation is half-way through; the visual layer plays on from where it is, or reverses.

`fx.switchPopMs` and `fx.switchPopScale` are sitting unused in the tuning keys and are where the
morph's duration belongs.

### The ball sprite is the scale reference

It is on screen 100% of the time, and *k* falls out of its width. That makes it the **first** art
to lock, not the last.

---

## The three risks, in the order they will bite

### Risk 1 — art and collision drift apart

Authoring collision separately fixes the snagging problem and introduces a bookkeeping one: the two
can now disagree *by accident* as well as by design, and nothing will complain.

It is sharper here than in most games because of the preview. If collision does not match what the
player sees, the ghost line will be *correct* and still look broken — which is worse than being
wrong, because it is unfalsifiable by eye.

**Containment:** a debug overlay that draws the collision shape over the sprite, as a toggle beside
the existing F1 view. Nothing ships without passing it.

### Risk 2 — organic terrain traps the ball

Every surface in the prototype is a clean rectangle or a gentle slope. The new terrain is
hand-drawn blobs with concave pockets, and a game with no walking has no way out of one.

This is a **design** risk disguised as a technical one, and it will not show up by itself. Three
layers, strongest first:

1. **Radius closing**, above. Removes the problem at the source for anything narrower than the ball.
2. **A pocket detector in the test suite.** Walk a level, flag any concave region that could trap a
   ball. Exactly the spirit of the existing `route_check`, which already answers "is this level
   still completable". A level that creates a trap should fail CI, not get found by a player.
3. **A runtime net, last resort only.** If the ball sits below rest speed for N steps and cannot
   launch, nudge or respawn. `world_roll_off_strength` is already the same family of idea. Useful
   as a safety net, dangerous as a crutch — it is an admission the geometry is wrong.

**Also watch the seams between adjacent terrain pieces.** `ShapeBody.contact` already avoids
snagging *within* one outline, by taking the closest point across every edge — that is exactly what
the warning comment in that file is about. But two abutting pieces can still catch a ball on the
join. Box2D hits this hard enough to have a dedicated feature for it (chain shapes with ghost
vertices). Either overlap pieces generously or merge adjacent terrain into single outlines.

### Risk 3 — the sim is O(every shape)

`find_shape_contact` loops every shape in the world, every substep, up to four resolve passes.
At 11 shapes that is free. At a few hundred it is the frame budget. A broadphase is not an
optimisation to do later; it is a prerequisite for the level existing at all.

---

## Phase 0 — the spike. Do this before building any tooling.

Take **one** real terrain blob — the nastiest one, with the deepest concave pocket, not the easiest
— and **one** gear, and push them end to end: Figma → import → collision → play. Nothing reusable,
no abstractions, throwaway code welcome.

1. Are the SVG paths clean, or are the ink edges thousands of nodes?
2. What vertex count does a terrain piece simplify to before it stops looking like itself?
3. Does radius-closing fill the pockets without destroying the silhouette's character?
4. Does a ball roll across it, or snag?
5. **What is the world scale?** — below.

**The world-scale question is the one to settle first**, because the designer is making art right
now against an assumption nobody has written down.

The sim's numbers are in prototype pixels: the ball is **22–24 px across** (squishy radius 12,
rocky 11), gravity is 1200 px/s², a full launch is 1000 px/s. The whole tuning sits in that scale.
Two ways to reconcile it with the art, and it must be one or the other:

- **Scale the art to the sim.** The designer is told "the player is 24 px across" and sizes
  everything to that. Free, but a 24 px protagonist is small for a polished 2D game and gives the
  art nowhere to breathe.
- **Scale the sim to the art.** Multiply every length, speed and acceleration by *k* and leave times
  alone. A clean uniform transform — the prediction tests are relative and should still pass, which
  is exactly how we verify it was done correctly. At k=4 the ball is ~96 px, which suits detailed
  sprite work much better.

Scaling the sim is the better answer if the art wants it, and it is cheap *now* and expensive after
a hundred pieces exist. **Pick k in Phase 0 and tell the designer the number.**

---

## Phase 1 — the art pipeline

- **A naming convention, agreed with the designer, before the next batch of art.** Layer names are
  the only structure that survives the export, so they carry the piece's kind — and the kind picks
  the collision primitive. `gear_`, `pipe_`, `vent_`, `spring_`, `chain_`, `terrain_`, `deco_`.
  `deco_` is the important one: it means "never reaches the sim".
- **An importer** that turns a delivered piece into a Godot scene: sprite plus the right collision
  for its kind. Built on the existing `@tool` block pattern so pieces stay editable in the viewport.
  For everything except terrain this is a primitive and needs no geometry work at all.
- **The terrain path only:** SVG path (preferred) or alpha trace (fallback) → simplify → close by
  ball radius → vertex budget warning. The budget serves feel *and* performance at once, since
  `ShapeBody.contact` is O(edges).
- **The overlay** from Risk 1.

---

## Phase 2 — make the sim survive a real level

- **Broadphase.** A uniform spatial hash is the right first choice: the level is mostly static, the
  ball is a point query, and it is a day's work. Bucket by the ball's radius.
- **The pocket detector** from Risk 2, in the test suite.
- **Shape caching.** Make sure `smooth_closed_polygon` runs once on load, not per frame.
- **A performance test in the suite**, so a regression is a red build rather than a bad feeling six
  weeks later.

---

## Phase 3 — the actors the art implies

- **Rotating bodies (gears, saw blades).** The lever already solved the hard part: surface velocity
  at the contact point, and a ghost-safe copy in `StepWorld.ghost()`. A gear is that, continuously
  driven instead of torque-balanced. A ball landing on a turning gear should be *carried*, which
  falls out of the same relative-velocity bounce the lever uses.
- **Saw blades** are rotating hazards: `SpikeStrip` semantics on a rotating body. The swept check
  matters more here, because a fast blade and a fast ball can pass through each other in one step.
- **Moving platforms** (the pulley-on-post pieces, the piston). A shape on a path with a surface
  velocity. Same contact maths again.
- **Chains over pulleys** are a variant of the cable that already exists.
- **The annulus** named above, for rings the ball travels inside.

Each one must be ghost-copied in `StepWorld.ghost()` and must come with a prediction-exactness
test, same as cables and levers. Non-negotiable: a prediction that is wrong near a gear is worse
than having no gears.

---

## How we build the level

### The unit is a beat, and each beat is a scene

Every sticky note in the composition is a **beat** — one thing the player learns. One beat, one
scene, assembled into the full level later. That gives fast iteration (load one beat, not a level
ten thousand pixels wide), a testable unit, and a clean seam for two people to work either side of.

The opening section is the proof that this starts cheaply. Its four beats need **no new systems**:

| The designer's note | What it already is |
|---|---|
| "can't launch again while it's in the air" | Grounded limiter mode, already the default |
| "if it falls onto the obstacles, he dies" | `SpikeStrip` |
| "switching to Heavy just before landing reduces the impact, bounces less" | Rocky's wall restitution is `0` — it lands dead. Mid-air switching is already on Q / Space / RMB |
| "he can break objects when he is Heavy" | The glass system: `rocky_breaks_glass`, breaking, respawn |

### Greybox, play, lock, dress

1. **Greybox** the beat out of existing blocks, matching the composition. No sprites.
2. **Play it.** Does it teach what the note says it teaches? This is the step that cannot be
   automated and is the whole reason greybox comes first.
3. **Lock** the collision once it plays well.
4. **Dress** it with art, which by then changes nothing about how it plays — because collision is
   authored, not derived.

### Every beat gets a solution replay

Record the intended sequence of shots and assert in CI that it still completes. Cheap to build, and
it is what stops a tuning change silently breaking beat 3 while you are polishing beat 7. It is the
same idea as the existing `route_check`, one level more specific.

The ambitious version — proving a beat is *unsolvable* without its intended mechanic, so a teaching
beat cannot be accidentally bypassed — is real and much harder. Worth doing later, for the beats
that carry the most teaching weight.

### Who does what

| Mine | Yours | Shared |
|---|---|---|
| Importer and piece scenes | Composition and route | What each beat teaches |
| New actors (gears, breakables, moving platforms) | Placement and spacing | When a beat is "done" |
| Broadphase, pocket detector, overlay | Feel and tuning | The beat list and its order |
| The world-scale transform | Which art goes where | |
| Greybox skeletons from the composition | Playtesting — the part only you can do | |
| Per-beat solution replays | | |

The loop: you send a section and say which note is the beat, I hand back a playable greybox scene,
you play it and say what is wrong, I fix systems while you adjust placement. Short turns, and
neither of us is ever blocked on the other.

### Then the level

- Assemble the beat scenes into the full composition.
- Extend the **route check** across the whole level, so "is this still completable" is a test and
  not a memory.
- Checkpoints from the existing flag system.
- Camera work: the level is wide, and the current camera was tuned for a shaft.

---

## Phase 5 — keeping it yours

The brief is that you can work on this without help, so this is a deliverable, not an afterthought.

- Keep the one-file-one-idea structure and the comment density that is already in `core/`.
- Extend `.claude/skills/ball/SKILL.md` with the collision model, so the conventions live beside the
  code rather than in anyone's head.
- A short **"how to add a piece"** and **"how to add an actor"** cookbook — the two things you will
  do most often.
- The invariants stay what they are: **one step function**, **a prediction must not touch the
  world**, **no gameplay numbers outside the tuning resource**. Everything above is built to keep
  those true, not to work around them.

---

## Suggested order

Greybox-first reorders this. **Level building does not wait for the pipeline** — it starts now,
with blocks that already exist and are already tested, and runs alongside everything else.

**Blocking everything: pick the world scale.** It is one number, and the way to get it is to
measure the ball sprite's width in Figma at the designer's native scale:

```
k = designer_ball_width_px / 24
```

Then either the art is drawn to a 24 px ball, or every length, speed and acceleration in the tuning
is multiplied by *k* with times left alone. The second is a uniform transform the existing
prediction tests verify for free, because they are relative. **Do this before the first greybox**,
or every beat built before the decision has to be rescaled afterwards.

After that, three tracks run in parallel:

- **Beats.** Greybox → play → lock → dress, one at a time, starting with the opening section.
  Needs no new systems to begin.
- **Pipeline and performance** (Phases 1–2). Independent of the beats until the dressing step.
- **Actors** (Phase 3), pulled in as the beats demand them rather than built speculatively — the
  opening section needs none, so the first gear can wait until a beat actually calls for one.

Phase 0's spike still happens, but it is now about the *art* questions (vertex budget, closing
radius, import workflow) rather than about whether the level can be started.

Phase 5 is continuous rather than a stage.
