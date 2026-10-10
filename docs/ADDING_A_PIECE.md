# Working with the sliced art

How to get from a delivered sheet to a piece standing in a level. Written to be followed without
asking anyone, including me.

## The two commands

```bash
godot --headless --path . --script tools/slice_sheets.gd    # find the pieces
godot --headless --path . --script tools/import_pieces.gd   # give them collision
```

Both are safe to re-run at any time, and the second is the one you run after changing a `kind`.
Neither touches the source art.

| Where | What | Who owns it |
|---|---|---|
| `art/manifest/<sheet>.tres` | every piece, and the collision each one gets | **you** — the `kind` field |
| `art/scenes/<family>/<id>.tscn` | **the placeable piece** — art plus collision | generated, don't hand-edit |
| `art/atlas/<family>/<id>.tres` | one AtlasTexture per piece, used *by* the scenes above | generated, never placed directly |
| `docs/SHEET_REPORT.md` | the same list as a table, for reading away from the editor | generated |

> **Drag from `art/scenes/`. Never from `art/atlas/`.**
>
> An `art/atlas/` file is a *texture*, not a scene. The Scene dock will refuse to accept it, and
> dropping it in the viewport gives you a bare `Sprite2D` — the art with no collision at all. The
> two symptoms together ("it won't drop into the tree" and "it isn't solid") always mean the atlas
> folder. It was called `art/pieces/` once, which made that mistake very easy to make.

Each placeable scene is:

```
<id>          TerrainBlock   the collision, scaled to world size, placeholder ink off
  Art         Sprite2D       the piece's art
```

It stays a `TerrainBlock` rather than a sprite with a shape bolted on, because that is what the
rest of the game already understands — the level collects the `terrain` group on load, so
collision, the route check, the editor gizmo and the debug overlay all come along unchanged.

**Levels instance these scenes, so a re-import updates every placement you have already made.**
Change a gear's `kind` from `POLYGON` to `CIRCLE`, re-run the importer, and every copy of it in
every level becomes a disc. That is the payoff for the manifest being separate from the art.

A piece with `kind = NONE` gets a plain `Node2D` and a sprite — no block, so it never joins the
group and never reaches the simulation.

The piece textures are the useful part day to day. Each is an `AtlasTexture` pointing at a region
of its sheet, so they show up individually with thumbnails in Godot's FileSystem dock and can be
dragged straight into a scene — and because they point at the sheet rather than copying pixels,
all 162 of them cost under a megabyte and there is only ever one copy of the art.

Current contents: **51 terrain pieces** across three blob sheets, **111 props** across two prop
sheets.

## Reviewing a piece's collision

The sheets carry no names, layers or metadata — the art is final and nothing goes back to the
designer — so the slicer *measures* each shape and guesses. The guess is right most of the time and
is never the last word.

1. Open `art/manifest/prop_sheet_1.tres` in the Inspector.
2. Expand `pieces`, pick one, and look at its thumbnail in `art/scenes/props/`.
3. Set `kind` to what it should collide as.
4. Tick `reviewed`.

**Re-running the slicer keeps `kind`, `radius`, `inner_radius` and `reviewed`.** Only the measured
geometry is refreshed. You cannot lose a decision by re-importing, which is the whole reason the
manifest exists instead of the importer recomputing collision from the art each time.

| `kind` | collides as | use for |
|---|---|---|
| `POLYGON` | the traced outline, closed by the ball's radius | terrain you land on |
| `CIRCLE` | one radius | gears, pulleys, wheels, saw blades |
| `RECT` | the region's box | beams, straight pipes, platforms |
| `ANNULUS` | two radii, inner surface solid | a ring the ball travels **inside** |
| `NONE` | nothing at all | decoration, in every placement |

### Why a gear is a circle and not its outline

Because the teeth are visual. Trace them and the ball wedges between two teeth and stops, which
reads as the game being broken. The worst outline on the prop sheets is **532 vertices**; as a
circle it is one number. The median prop is 24 vertices, so it is a small number of pieces — the
gears and blades — carrying nearly all the cost.

This is the general rule, and it is deliberate: **collision is authored, and it is allowed to
disagree with the art on purpose.** See `docs/ROADMAP.md`.

### The measurements, if you want to argue with a guess

Each piece carries the three numbers the guess was made from:

- **`solidity`** — opaque pixels over the area the outline encloses. Near 1 is solid; **below 0.62
  means hollow**, which is how the three ring gears were found (0.38, 0.43, 0.52).
- **`box_fill`** — opaque pixels over the bounding box. **Above 0.88 is a rectangle.**
- **`circularity`** — the outline's area over that of the largest circle fitting the box.
  **Above 0.82 on a square-ish box is a disc.**

`circularity` is only meaningful on a roughly square box — an elongated piece reports values well
above 1 because the inscribed circle is small. That is why the disc test checks squareness first.

## The world scale is derived, not set

`PieceImporter.art_scale()` works it out rather than storing it:

```
art_scale = ball diameter in world units / 250 source pixels
```

250 is the resting worm's diameter on the character sheet, measured — a fact about the art. The
ball on screen *is* the worm, so once the ball's radius is fixed in the tuning, the scale for every
other piece follows. At a radius of 36 that is **0.288**, and the ball works out to
125 source pixels, which is what terrain closing uses.

The useful consequence: if the tuning is ever rescaled, re-run the importer and every piece
rescales with it, still matching the ball exactly. Nothing to keep in step by hand.

## What the four kinds actually produce

- **`CIRCLE`** becomes a regular polygon, because `ShapeBody` holds outlines and nothing else. The
  number of sides is **computed from the radius**, not fixed: enough that no facet bulges more
  than 0.4 world pixels from the true curve. A fixed count is wrong in both directions — 24 sides
  wastes edges on a small bolt and is visibly faceted on a 1200-pixel flywheel.
- **`RECT`** is the region's four corners.
- **`POLYGON`** is the traced outline, **closed by the ball's radius** — offset outward by 125
  source pixels and back in, which fills every pocket the ball physically cannot enter. Then
  re-simplified, which matters: offsetting with round joins lays a fan of points around every
  convex corner and inflates a 40-vertex piece to 290. That would quietly undo the vertex budget.
- **`ANNULUS`** produces **no collision yet.** A ring the ball travels *inside* needs the ball
  contained, and a `ShapeBody` outline pushes a ball *out*. It needs either an inverted body or the
  ring built from overlapping rim segments. Three pieces are affected and no beat uses one yet.
  Falling back to a solid disc would be worse than nothing — it fills the hole the ball is meant to
  pass through, and the route closes for a reason nobody can see.

## Two constants that matter more than they look

**`SheetSlicer.ALPHA_THRESHOLD`** decides what counts as part of a piece. Raise it and the faint,
semi-transparent parts of a prop stop counting, so one prop comes apart into several regions — and
since ids are positional, every id after it shifts and every decision in the manifest attaches to
the wrong piece. It is set from a measurement, not a guess:

```bash
godot --headless --path . --script tools/probe_threshold.gd
```

Look for a **plateau** — a span of thresholds where the piece count does not move. Prop Sheet 2
climbs steadily above 0.2 (57 → 66 → 77 → 85 → 99) because its pieces carry soft shading; Prop
Sheet 1 and the terrain sheets are hard-edged and do not care. 0.1 sits in the range where all of
them are stable.

**`SheetSlicer.DEFAULT_EPSILON`** is the outline simplification, in source pixels. At 8 a terrain
piece lands at 38–54 vertices median, which is a comfortable budget for `ShapeBody.contact` — it
is O(edges). Lower it and outlines get expensive; raise it and silhouettes stop looking like
themselves.

## Making a piece deadly, and making it turn

Two different fields, in two different places, because they answer two different questions.

**Deadly is a property of the piece.** Open its manifest entry and set `role` to `HAZARD`, then
re-run the importer. Every copy of that piece, in every level, gains a `Hazard` child and kills on
contact. It is added as a **child** of the existing root, never a change of root — Godot cannot
propagate a root-type change to scenes that already instance this one, so doing it that way would
mean rebuilding every level.

The deadly disc is deliberately **larger** than the piece's collision: collision is the biggest
circle that fits the art, the hazard reaches the tooth tips, so the ball meets the teeth before the
solid hub. Get that ordering backwards and the solid fences the ball away from the region that
kills it, and the hazard goes silently inert — `core/spike_strip.gd` opens by warning about exactly
that. A near-square gear has almost no gap between the two half-extents, so there is a 5% clearance
floor and a test that holds it.

You get the ghost line's behaviour for free: it already stops dead at a hazard, so the preview ends
at the blade. That warning is honest, because the real ball dies there too.

**Turning is a property of the placement.** Select a placed piece and set
`spin_degrees_per_second`. Two copies of the same gear can turn at different speeds, or opposite
ways.

It is **visual only** — it rotates the `Art` child and never the collision, which stays the circle
the manifest chose. That is not a shortcut: a gear that only kills has no reason to turn in the
simulation, and a static hazard is *shared* by the trajectory preview rather than copied, so it
costs the prediction nothing. Only a gear the ball is meant to **ride** needs real rotation, and
that is a different system.

## Two different questions about collision

They get answered in two different places, and keeping them apart is what lets placement and
collision be worked on by two people at once.

**What does this piece collide AS?** A property of the *piece*. It lives in `art/manifest/`, and
changing it there and re-importing updates every copy in every level. A gear is a disc everywhere
or nowhere.

**Does THIS copy collide at all?** A property of the *placement*. It is the `collides` checkbox on
the placed node. Untick it and that instance keeps its art and never reaches the simulation —
which is how the same gear is machinery in one beat and background in another.

The practical consequence: **almost every collision fix happens without anyone touching the level
file.** Place things, and corrections to how they collide arrive underneath you.

## Adding a sheet later

Drop it in the folder that matches what it *is* — `terrain/`, `props/`, `character/` or `deco/` —
because the folder decides the collision family, and re-run the slicer. `art/source/README.md` has
the folder table.

The folder decides terrain-versus-prop, which is a property of the piece. It does **not** decide
whether a particular instance is scenery: the same gear is machinery in one beat and background in
another, so that is set per placement.
