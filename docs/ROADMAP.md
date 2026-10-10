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
| Collision source | **Derived from the art, then simplified.** | One authoring step, not two. The risk is collision noise; §Risk 1 is about containing it. |
| Art delivery | **SVG per piece with named layers, plus PNG at a fixed scale.** | We can read outlines from the SVG path rather than tracing pixels, and fall back to the PNG when a path is unusable. |

---

## The three risks, in the order they will bite

### Risk 1 — the art/collision seam

Today one polygon is *both* the drawing and the collision, so they cannot disagree. A sprite breaks
that, and a physics game lives or dies on the seam.

It is sharper here than in most games because of the preview. If collision geometry has millimetre
bumps the ball catches on, the ghost line will be *correct* and still look broken — which is worse
than being wrong, because it is unfalsifiable by eye.

**Containment:** a vertex budget per piece, a simplification pass with a measured tolerance, and a
debug overlay that draws the collision outline over the sprite so a mismatch is visible rather than
felt. Nothing ships without passing the overlay.

### Risk 2 — organic terrain traps the ball

Every surface in the prototype is a clean rectangle or a gentle slope. The new terrain is
hand-drawn blobs with concave pockets and wobbling edges. A rolling ball finds concave pockets,
and a slingshot game with no walking has no way to climb out of one.

This is a **design** risk disguised as a technical one, and it will not show up in a unit test.
It needs play, early, on real art — which is why §Phase 0 exists.

The existing `smoothing` on `TerrainBlock` (Catmull-Rom) was built for exactly this and is the
first lever to reach for.

### Risk 3 — the sim is O(every shape)

`find_shape_contact` loops every shape in the world, every substep, up to four resolve passes.
At 11 shapes that is free. At a few hundred it is the frame budget. A broadphase is not an
optimisation to do later; it is a prerequisite for the level existing at all.

---

## Phase 0 — the spike. Do this before building any tooling.

Take **one** real terrain blob and **one** gear from the delivered assets and push them end to end:
Figma → import → collision → play. Nothing reusable, no abstractions, throwaway code welcome.

It answers five questions at once, cheaply, and all five are expensive to get wrong later:

1. Are the SVG paths clean, or are the ink edges thousands of nodes?
2. What vertex count does a terrain piece simplify to before it stops looking like itself?
3. Does a ball roll across it, or snag?
4. Does a ball get trapped in the concave parts?
5. **What is the world scale?** — see below.

**The world-scale question is the one to settle first**, because the designer is making art right
now against an assumption nobody has written down.

The sim's numbers are in prototype pixels: the ball is **22–24 px across** (squishy radius 12,
rocky 11), gravity is 1200 px/s², a full launch is 1000 px/s. The whole tuning sits in that scale.
Two ways to reconcile it with the art, and it must be one or the other:

- **Scale the art to the sim.** The designer is told "the player is 24 px across" and sizes
  everything to that. Free, but a 24 px protagonist is small for a polished 2D game and gives the
  art nowhere to breathe.
- **Scale the sim to the art.** Multiply every length, speed and acceleration by *k* and leave
  times alone. This is a clean, uniform transform — the prediction tests are relative and should
  still pass, which is exactly how we verify it was done correctly. At k=4 the ball is ~96 px,
  which suits detailed sprite work much better.

Scaling the sim is the better answer if the art wants it, and it is cheap *now* and expensive
after a hundred pieces exist. **Pick k in Phase 0 and tell the designer the number.**

---

## Phase 1 — the art pipeline

Build the thing the spike proved out.

- **A naming convention, agreed with the designer, before the next batch of art.** Layer names are
  the only structure that survives the export, so they have to carry the piece's kind
  (`terrain_`, `prop_`, `gear_`, `hazard_`), and — where it matters — its collision intent.
- **An importer** that turns a delivered piece into a Godot scene: sprite plus a simplified
  collision polygon, built on the existing `@tool` block pattern so pieces stay editable in the
  viewport.
- **Simplification** (Ramer–Douglas–Peucker or similar) with the tolerance from the spike, and a
  hard vertex budget that warns when a piece exceeds it. The budget serves feel *and* performance
  at once: `ShapeBody.contact` is O(edges), so a 500-vertex blob is both snaggy and slow.
- **The overlay** from Risk 1, as a toggle beside the existing F1 debug view.

Decorative art that nothing collides with should be plain sprites that never reach the sim at all.
Keeping that distinction sharp is most of what keeps the level fast.

---

## Phase 2 — make the sim survive a real level

- **Broadphase.** A uniform spatial hash is the right first choice: the level is mostly static, the
  ball is a point query, and it is a day's work. Bucket by the ball's radius. The gain is from
  O(shapes) to O(nearby shapes) and it is the difference between the level running and not.
- **Shape caching.** `smooth_closed_polygon` runs per piece; make sure it runs once on load.
- **A performance test in the suite**, so a regression shows up as a red build rather than as a bad
  feeling six weeks later.

---

## Phase 3 — the actors the art implies

The props are mostly circular and most of them clearly turn. In sim terms:

- **Rotating bodies (gears, saw blades).** The lever already solved the hard part — surface
  velocity at the contact point, and a ghost-safe copy in `StepWorld.ghost()`. A gear is that,
  continuously driven instead of torque-balanced. A ball landing on a turning gear should be
  *carried*, which falls out of the same relative-velocity bounce the lever uses.
- **Saw blades** are rotating hazards: `SpikeStrip` semantics on a rotating body. The swept check
  already exists and matters more here, because a fast blade and a fast ball can pass through each
  other in one step.
- **Moving platforms** (the pulley-on-post pieces). Simplest useful version: a shape on a path with
  a surface velocity. Same contact maths again.
- **Chains over pulleys** are a variant of the cable that already exists.

Each one must be ghost-copied in `StepWorld.ghost()` and must come with a prediction-exactness
test, same as cables and levers. That is non-negotiable: a prediction that is wrong near a gear is
worse than having no gears.

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
- Extend `.claude/skills/ball/SKILL.md` with the art pipeline rules, so the conventions live beside
  the code rather than in anyone's head.
- A short **"how to add a piece"** and **"how to add an actor"** cookbook — the two things you will
  do most often.
- The invariants stay what they are: **one step function**, **a prediction must not touch the
  world**, **no gameplay numbers outside the tuning resource**. Everything above is built to keep
  those true, not to work around them.

---

## Suggested order

Phase 0 first, in full, before anything else is built. It is a day or two and it de-risks the
expensive parts. Then Phase 1 and Phase 2 can run together — the pipeline and the broadphase do not
touch each other. Phase 3 is incremental: one actor at a time, each with its tests, each playable
on arrival. Phase 4 needs 1–3 done. Phase 5 is continuous rather than a stage.
