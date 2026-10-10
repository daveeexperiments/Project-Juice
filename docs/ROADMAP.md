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

## Phase 4 — the level itself

- Lay out the designer's route from the Figma composition.
- Extend the existing **route check** to the real level, so "is this still completable" is a test
  and not a memory.
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

Phase 0 first, in full, before anything else is built. Then Phase 1 and Phase 2 can run together —
the pipeline and the broadphase do not touch each other. Phase 3 is incremental: one actor at a
time, each with its tests, each playable on arrival. Phase 4 needs 1–3 done. Phase 5 is continuous
rather than a stage.
