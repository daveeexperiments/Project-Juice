# Working with the sliced art

How to get from a delivered sheet to a piece standing in a level. Written to be followed without
asking anyone, including me.

## What exists after slicing

```bash
godot --headless --path . --script tools/slice_sheets.gd
```

Safe to re-run at any time. It writes three things and never touches the source art:

| Where | What | Who owns it |
|---|---|---|
| `art/manifest/<sheet>.tres` | every piece, and the collision each one gets | **you** — the `kind` field |
| `art/pieces/<family>/<id>.tres` | one AtlasTexture per piece | generated, don't hand-edit |
| `docs/SHEET_REPORT.md` | the same list as a table, for reading away from the editor | generated |

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
2. Expand `pieces`, pick one, and look at its thumbnail in `art/pieces/props/`.
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

## Adding a sheet later

Drop it in the folder that matches what it *is* — `terrain/`, `props/`, `character/` or `deco/` —
because the folder decides the collision family, and re-run the slicer. `art/source/README.md` has
the folder table.

The folder decides terrain-versus-prop, which is a property of the piece. It does **not** decide
whether a particular instance is scenery: the same gear is machinery in one beat and background in
another, so that is set per placement.
