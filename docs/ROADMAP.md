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
| Art delivery | **The sheets as delivered. No requests go back to the designer.** PNG pages, transparent, 4096². | Every adaptation happens in Godot. No layer-name convention, no per-piece SVG, no re-exports — so classification and collision are driven by a **manifest we own**, not by metadata in the art. See "The manifest". |
| Build order | **Greybox first, art second.** Each beat is playable in plain blocks before any sprite touches it. | Level building starts immediately with tools that already exist, instead of waiting on the pipeline. See "How we build the level". |
| Ball names | **Squishy and Rocky.** | The code keeps the names it has, including the Phaser-inherited tuning keys (`rocky.cableBounce` and friends). The designer's notes say "Heavy"; that is just a synonym to read through, not something to correct. |
| World scale | **k = 2.5.** Ball 60 px on screen, source art imported at 24%. | A uniform multiply of every length, speed and acceleration; times untouched. See "The world scale is k = 2.5". |
| Many cables | **Sleeping, not approximation.** A rope that is not moving stops being simulated until something touches it. | The field becomes affordable *without* costing prediction exactness, because a sleeping rope genuinely is not moving. See "The cable field". |
| The auto-bounce shaft | **Constructed, not tuned.** Per-pad `horizontal_keep = 0` and `impact_bonus = 0`. | The bounce is deterministic by construction rather than by careful tuning, so it cannot drift. See "The auto-bounce shaft". |
| Level assembly | **One continuous composition built from instanced beat scenes.** | Visually seamless and faithful to the designer's layout, while every beat stays separately openable and testable. See "How we build the level". |

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

**The one exception:** the hollow spiky gears, and the ring the player passes *inside*. That is an
annulus — the ball touches the inner surface — and `ShapeBody` holds a single closed outline with no
hole support. It gets an explicit answer in the manifest rather than falling out of the pipeline:
two radii, two circles, one of them inverted.

### Slicing a sheet: `BitMap.opaque_to_polygons` does it, and more

Godot's built-in sprite sheet slicer is grid-based and cannot express a page of irregularly placed
blobs. `BitMap.opaque_to_polygons()` can: it finds connected regions *and* simplifies their
outlines in one call.

Measured on a real 2000x2000 terrain sheet, which it split into **18 shapes**:

| epsilon | verts/shape | biggest |
|---|---|---|
| 0.5 | 695 | 1570 — raw trace, this is ink noise |
| 2.0 | 85 | 179 |
| **4.0** | **41** | **68** — a good working budget |
| 8.0 | 27 | 38 |

So the vertex-budget question is answered before Phase 0 even starts: **epsilon ≈ 4 gives ~40
vertices per piece**, comfortable for `ShapeBody.contact`, which is O(edges).

Better still, it is not only a slicer. One call gives both halves of a piece:

- the polygon's **bounding box** → the AtlasTexture region for the sprite
- the polygon **itself** → the collision outline, already simplified, ready to be closed by the
  ball radius

**This requires a transparent background, and the delivered sheets have one.** All six came through
with alpha, so it is `BitMap.create_from_image_alpha()` and no guessing. Worth recording why that
mattered: the early test sheet was ink on opaque white, so the mask had to be built by thresholding
on *darkness*, which works for black ink and silently drops anything light-coloured — the pink and
purple worm, the props with pale fills. Those would simply have vanished. The alpha path removes the
whole class of problem, and nothing needs to be asked for.

Also note that **alpha tracing is now the only terrain path**, not a fallback behind SVG paths. That
is fine, and the measurement above is why: at epsilon ≈ 8 a traced 4096 px terrain piece lands at
40–58 vertices, which is the budget we wanted anyway. The thing SVG would have bought is precision
we do not need, because the outline is about to be radius-closed and deliberately made to disagree
with the art.

One thing still unverified, and it cannot be answered by asking: what `opaque_to_polygons` does with
a **hole** — which decides the hollow gears and the ring the ball passes inside. Test it on a real
ring. If it returns only the outer boundary, the manifest answer below handles it without any
geometry work at all.

### What the delivered sheets actually contain

Measured on the real exports in `art/source/`, all six of which came through with **transparent
backgrounds** — so the importer uses alpha and the darkness fallback is never needed.

| Sheet | Size | Shapes |
|---|---|---|
| Blob Sheet 1 / 2 / 3 | 4096² | 11 + 22 + 18 = **51 terrain pieces** |
| Prop Sheet 1 / 2 | 4096² | 58 + 57 = **115 props** |
| character sprite sheet | 5600×800 | **7 morph frames** |

**Epsilon ≈ 8 is right for a 4096 sheet**, giving 40–58 vertices per terrain piece. The earlier
figure of 4 was measured on a 2000 px sheet; the tolerance is in source pixels, so it tracks the
resolution.

**The props measurement settles the primitives argument with numbers.** Median prop outline is
**24 vertices** — but 26 of the 115 run past 60, and the worst reach **532**. Those are the gears
and saw blades: every tooth is real outline detail. Replacing those 26 with circles removes
something like five thousand vertices from the collision world, and removes the wedging that
tracing teeth would have caused. A circle is one number.

**Four shapes on Prop Sheet 1 have a 1 px bounding box** — stray pixels or antialiasing residue.
The importer needs a minimum-area filter, or they become four invisible collision bodies.

### The manifest: how a piece gets its collision, with no help from the art

The earlier plan had the designer name layers (`gear_`, `vent_`, `deco_`) and let the name pick the
collision primitive. That is off the table: the art is final and nothing goes back to them. The
sheets carry no names, no layers and no metadata — 51 terrain pieces and 115 props as anonymous
blobs of alpha.

So the classification has to live on our side, and the right place for it is a **manifest**: one
checked-in resource listing every piece, its atlas region, and the collision it gets.

```
res://art/manifest/props_sheet_1.tres
  piece 00  rect(128, 96, 412, 410)   kind = circle   r = 203
  piece 01  rect(602, 110, 96, 388)   kind = rect
  piece 02  rect(730, 96, 410, 404)   kind = annulus  r_outer = 202  r_inner = 141
  ...
```

Three properties make this the right shape for the problem:

- **The importer guesses, a human confirms.** Shape classification is measurable, so the first pass
  is automatic: compare a piece's area against its bounding circle and count its outline vertices,
  and a gear or a saw blade is obvious — high vertex count, area close to a perfect disc. Aspect
  ratio plus near-full box fill means rectangle. Everything else falls out as a polygon to review.
  That turns 115 props into a handful of corrections rather than 115 decisions.
- **It is idempotent.** Re-running the importer regenerates the atlas regions and outlines but
  *keeps* the manifest's `kind` values. Nothing hand-decided is ever lost to a re-import, which is
  the failure that makes most art pipelines quietly unusable after a month.
- **It is reviewable in a diff.** A collision change on a piece shows up in version control as a
  one-line change in a text resource, which is exactly what Risk 1 — art and collision drifting
  apart — needs in order to be noticeable.

Two things the manifest answers for free:

**The annulus.** A ring the ball travels inside needs no hole support anywhere in the geometry
pipeline. It is `kind = annulus` with two radii, both measured off the sliced piece, and the
collision is two circles — one solid, one inverted. The geometry question was only ever hard
because we were trying to derive it; authored, it is two numbers.

**`deco/`.** Nothing in the sheets marks a piece as decoration, and on reflection nothing *should*:
the same gear is machinery in one beat and background in another. So `kind` in the manifest is the
piece's **default**, overridable per placement. The folder still decides terrain-versus-prop, which
is a property of the piece; whether a given instance reaches the simulation is a property of where
it is put.

### The world scale, from the character sheet

The seven morph frames, left to right:

| Frame | Size | |
|---|---|---|
| 1 | 431 × 187 | stretched |
| 2 | 305 × 194 | stretched |
| **3** | **250 × 246** | **curled — a resting form** |
| 4 | 491 × 139 | stretched, the longest |
| 5 | 454 × 190 | stretched |
| 6 | 361 × 220 | stretched |
| **7** | **255 × 248** | **curled — the other resting form** |

So **the worm at rest is a circle about 250 px across** in source art, and that is the number *k*
is measured from. The sim currently puts it at 24 px, so art used at 1:1 would mean k ≈ 10.4 — far
too large on screen. The art is authored to be scaled down; what remains is choosing the on-screen
size:

| On-screen ball | k | Art scale |
|---|---|---|
| 48 px | 2 | 19% |
| **60 px** | **2.5** | **24%** |
| 64 px | ~2.7 | 26% |
| 96 px | 4 | 38% |
| 128 px | ~5.3 | 51% |

### The world scale is k = 2.5

**Ball 60 px across on screen, source art imported at 24%.** Locked, because every beat built
before the decision would have to be rescaled afterwards, and the transform is cheap now and
expensive after a hundred pieces exist.

Why 2.5 and not larger, which was the earlier instinct:

- **The preview needs room.** A full launch is 1000 px/s under 1200 px/s² gravity — the ghost line
  for a strong shot spans several hundred prototype pixels. The arc must be visible *and* its
  landing point legible at the same time. At k = 4 the same shot needs over three thousand screen
  pixels of arc to read, and the camera is forced so far out that the 96 px ball stops feeling big
  anyway. Scale buys nothing once the thing you are aiming with no longer fits on screen.
- **60 px is not a small protagonist.** It is a sixth of a 1080 p screen's height. The prototype's
  24 px ball felt small because it was a flat circle, not because of its size.
- **2.5 keeps the tuning readable**, which matters because the brief is that these numbers stay
  hand-editable. Gravity 1200 → 3000, full launch 1000 → 2500, radius 12 → 30. Round numbers that
  can still be reasoned about by eye.

It is one constant in one transform script and nothing is built on it yet, so it is still a cheap
number to change — but it stops being cheap the moment the first beat is dressed.

**The morph's extent is now quantified, and it changes the earlier advice.** At its longest the
worm is 491 px against a 250 px resting circle — it reaches roughly a full radius past the
collision at each end, which is not the modest overlap assumed earlier.

The fix is orientation rather than restraint: the morph stretches along its own long axis, so if
that axis is aligned with the **contact tangent when grounded** (and with velocity when airborne),
the stretch runs *along* a floor instead of into it. Only a wall contact during a morph still
overlaps, and that is rare and brief.

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

Once collision is authored rather than traced, the art is **free** — and since the art is final,
that is the property doing the real work here. Every grainy ink edge, every gear tooth, every
pale fill is detail that never reaches the simulation and therefore cannot cost us anything. The
pipeline does not need the art to be shaped a particular way, which is exactly why no requests have
to go back.

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

With k = 2.5 the unified value is **30**: one `radius` for both forms, 60 px across on screen.

Note which radius the terrain closing uses. Today it must use the *larger* of the two (squishy's
12) so one outline is safe for both forms; once they are equal that caveat disappears and the
closing radius is simply the ball's radius.

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
  clipping, so accept it. The frames are what they are and will not be redrawn, so the two levers
  we do have are both ours: the orientation rule above, which turns the stretch along the surface
  instead of into it, and `fx.switchPopMs`, which decides how long any overlap is on screen. A
  shorter morph is a smaller problem.
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

- **The slicer.** `opaque_to_polygons` over each sheet, with the minimum-area filter, producing an
  atlas region and a simplified outline per piece. Pieces must be ordered **deterministically** —
  sorted row-major by bounding box, not by whatever order the call happens to return — because that
  order is what the manifest keys on.
- **The manifest and its classifier**, above. The guess is a measurement; the corrections are a
  short editor pass; the result is checked in.
- **An importer** that turns a manifest entry into a Godot scene: sprite plus the collision its
  `kind` says. Built on the existing `@tool` block pattern so pieces stay editable in the viewport.
  For everything except terrain this is a primitive and needs no geometry work at all.
- **The terrain path only:** alpha trace → simplify at epsilon ≈ 8 → close by the ball radius →
  vertex budget warning. The budget serves feel *and* performance at once, since `ShapeBody.contact`
  is O(edges).
- **The overlay** from Risk 1. With no layer names to cross-check against, this is the *only* thing
  that catches a piece whose collision is wrong, so it moves up in importance rather than being a
  nicety.

---

## Phase 2 — make the sim survive a real level

- **Broadphase.** A uniform spatial hash is the right first choice: the level is mostly static, the
  ball is a point query, and it is a day's work. Bucket by the ball's radius.
- **Cable sleeping**, below — the cable field is the one piece of the composition that is a
  performance problem by itself, independent of level size.
- **The pocket detector** from Risk 2, in the test suite.
- **Shape caching.** Make sure `smooth_closed_polygon` runs once on load, not per frame.
- **A performance test in the suite**, so a regression is a red build rather than a bad feeling six
  weeks later.

### The cable field

The composition has a dense field of hanging cables in the middle of the level. Costed out, that is
a problem on its own: a rope is Verlet-integrated with `RELAX_PASSES = 3` constraint passes per
step, and the trajectory preview re-steps the whole world for every frame of aiming. Tens of ropes
multiplied by the preview's step budget multiplied by three relax passes lands in the high hundreds
of thousands of constraint solves **per aiming frame**. Aiming would be the slowest thing in the
game.

The answer is the one every physics engine reaches for — Box2D, PhysX, Havok, Unity and Unreal all
ship it — and it is **sleeping**, not approximation:

> A rope whose largest knot movement stays below a threshold for N consecutive steps stops being
> integrated. It wakes when something touches it.

Why sleeping rather than a cheaper rope: **it costs the prediction nothing.** Fewer relax passes in
the ghost, or a simplified ghost rope, would make the preview an approximation — and the preview
being exact is the game. A sleeping rope is not an approximation of a moving rope; it is a rope that
genuinely is not moving. Freezing it in the ghost is therefore exactly right, and the hanging
cables the ball never goes near are precisely the ones that are asleep.

**The one subtlety that will break it if missed:** the sleep flag and the sleep counter are
simulation state, so they belong in `snapshot()`, `restore()` and `ghost_copy()` alongside the knot
positions. Leave them out and the ghost wakes a rope the real ball left asleep — the two run the
same code from *different* state, and the preview drifts. That is the invariant-2 failure mode, and
it earns a test beside the existing `a prediction leaves the real rope exactly where it was`.

Three layers, in order of how much they buy:

1. **Most of the field is `deco/`.** Cables the ball can never reach are art. This is the biggest
   win and costs nothing.
2. **Sleeping** for the ones that are real.
3. **Broadphase**, so a distant sleeping rope is not even visited to be found asleep.

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

### The auto-bounce shaft

One section of the composition is a column of facing pads that the ball is meant to ricochet
between, all the way to the top, on its own — the player holds no input and the sequence is pure
spectacle.

**Do not get there by tuning.** "Always works" and "carefully tuned bouncy physics" are opposites:
the ball arrives at the first pad with whatever velocity the player's shot gave it, each bounce
amplifies the difference, and after five or six the sequence either overshoots or stalls. A
tolerance that holds in testing fails on the shot nobody tried.

The mechanism to make it deterministic already exists and needs no new system.
`_apply_trampoline_launch` does not *add* to the incoming velocity — it **replaces** the normal
component outright:

```
wanted = (launch_speed + impact_bonus * impact_speed) * form.trampoline_bounce
v      = tangent * horizontal_keep + normal * wanted
```

Two of those terms are the only places the arrival velocity enters. Set both to zero **for the pads
in this shaft** and the outgoing velocity is `normal * launch_speed` — identical every time,
whatever the ball was doing when it arrived. The bounce becomes a property of the pad's geometry
rather than of the shot, so the sequence is right by construction and cannot drift when something
else is tuned.

What it needs:

- **Per-pad `horizontal_keep` and `impact_bonus` on `ShapeBody`**, defaulting to `-1` meaning "use
  the global" — exactly the pattern `launch_speed` and `bounce_boost` already follow. The global
  values stay as they are, because an ordinary trampoline elsewhere *should* respond to how hard it
  was hit.
- **An input lock while the sequence runs**, so a launch mid-ricochet cannot break out of a
  cinematic. The limiter already owns the "may this shot go?" question, so this is a flag there, not
  a special case in the simulation.
- **A failsafe exit.** If the ball is still in the shaft after N seconds, something is wrong;
  release the lock rather than trap the player. Cheap insurance against the one entry nobody tried.

The good consequence: this section drops down the risk list. It is on rails, so only its entry and
its exit need design attention.

---

## How we build the level

### The unit is a beat, and each beat is a scene

Every sticky note in the composition is a **beat** — one thing the player learns. One beat, one
scene, assembled into the full level later. That gives fast iteration (load one beat, not a level
ten thousand pixels wide), a testable unit, and a clean seam for two people to work either side of.

**This does not mean cutting the level into chunks.** The designer's composition is one continuous
space and it stays one continuous space: the level is a single scene whose children are *instanced*
beat sub-scenes, positioned to match the layout exactly. Godot instancing means there is no seam,
no loading boundary and no visual difference from having drawn it all in one file — and each beat is
still a scene you can open on its own, play on its own, and run a solution replay against.

So the composition is authoritative for *where everything is*, and the beat split is authoritative
for *how the work is organised*. They never have to disagree. The one rule that keeps it true: a
beat scene is positioned by its own root transform and holds nothing that reaches across into
another beat — a cable anchored in one beat and hanging into the next belongs to one of them, by
decision, not by accident.

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

**The world scale is settled: k = 2.5.** That unblocks the first greybox, and the next three
actions are in a strict order, because each one would have to be redone if it came earlier:

1. **Apply the scale, in one commit.** Unify `squishy.radius` and `rocky.radius` to **30**, then
   multiply every length, speed and acceleration in `tuning/tuning_data.gd` by 2.5 and leave every
   duration alone. The existing prediction-exactness tests verify this for free — they are all
   relative, so a correct uniform transform leaves all 81 checks green, and *any* number missed or
   any time value scaled by mistake shows up as a failure. That is the whole reason to do it as its
   own commit with nothing else in it.
2. **The slicer, the manifest, then the importer** — in that order, because each feeds the next.
   Slice the six sheets deterministically with the minimum-area filter that the 1 px specks on Prop
   Sheet 1 proved necessary; generate the manifest with guessed collision kinds; review the guesses;
   build piece scenes from it. Needs the scale from step 1 for the closing radius and for `epsilon`.
3. **Greybox beat 1** — launch, land on the chimney, do not touch the gears — in a new scene file,
   built from existing blocks, for playtesting. Then the loop in "Who does what" takes over.

Those three run in sequence. Alongside them, three tracks run in parallel:

- **Beats.** Greybox → play → lock → dress, one at a time, starting with the opening section.
  Needs no new systems to begin.
- **Pipeline and performance** (Phases 1–2). Independent of the beats until the dressing step.
- **Actors** (Phase 3), pulled in as the beats demand them rather than built speculatively — the
  opening section needs none, so the first gear can wait until a beat actually calls for one.

Phase 0's spike still happens, but it is now about the *art* questions (vertex budget, closing
radius, import workflow) rather than about whether the level can be started.

Phase 5 is continuous rather than a stage.
