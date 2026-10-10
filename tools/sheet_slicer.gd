@tool
class_name SheetSlicer
extends RefCounted

## Finds the individual pieces on a sprite sheet and guesses what each one should collide as.
##
## The sheets arrive as 4096-pixel pages of unrelated shapes with transparent backgrounds, no
## names, no layers and no grid, so Godot's built-in grid slicer cannot express them.
## `BitMap.opaque_to_polygons()` can: it finds each connected run of opaque pixels AND simplifies
## its outline, in one call. The bounding box becomes the sprite's atlas region; the outline is the
## starting point for terrain collision.
##
## Everything here works in SOURCE PIXELS. The world scale is applied later, by the importer.
##
## ## Why it guesses
##
## 115 props is too many to classify by hand, and shape classification is measurable, so the
## slicer measures. A gear is a disc with a spiky edge: its outline encloses nearly the area of a
## circle filling its box, and its box is square. A beam fills its box. A ring encloses far more
## area than it has opaque pixels. Those three measurements separate most of the sheet, and what
## is left is reported for review rather than guessed at.
##
## The guess is never the last word -- `PieceEntry.kind` is yours to change and the slicer will not
## overwrite it.

# ---------------------------------------------------------------- thresholds
#
# These are the classifier's whole behaviour, so they are named and gathered here rather than
# buried in the comparisons. Changing one and re-running is cheap: the decisions already made are
# kept, so only the unreviewed guesses move.

## How opaque a pixel must be to count as part of a piece.
##
## **Measured, not picked** -- run `tools/probe_threshold.gd` to see the curve. It matters far more
## than it looks: raise it and the faint, semi-transparent parts of a piece stop counting, so one
## prop breaks into several regions and every id after it shifts.
##
## Regions found per sheet, against the threshold:
##
## | Sheet | 0.05 | 0.10 | 0.20 | 0.35 | 0.50 | 0.75 |
## |---|---|---|---|---|---|---|
## | Prop Sheet 1 | 54 | 54 | 54 | 55 | 55 | 55 |
## | Prop Sheet 2 | 56 | 57 | 66 | 77 | 85 | 99 |
## | Blob Sheet 1 | 11 | 11 | 11 | 11 | 11 | 11 |
##
## Prop Sheet 2 is the one that gives the game away: its pieces carry soft shading, and the count
## climbs without a plateau above 0.2 as they come apart. Prop Sheet 1 and the terrain sheets are
## hard-edged and do not care. So the usable range is the low end, where every sheet is stable, and
## 0.1 -- Godot's own default -- sits in it.
const ALPHA_THRESHOLD: float = 0.1

## Below this many opaque pixels a region is not a piece.
##
## Prop Sheet 1 has four regions with a 1-pixel bounding box -- stray pixels or antialiasing
## residue. Without this filter they become four invisible collision bodies, which is the kind of
## bug that takes a day to find because there is nothing to see.
const MIN_OPAQUE_PIXELS: int = 64

## ...and below this in either direction it is not a piece either, which catches a long thin smear
## that happens to have enough pixels.
const MIN_SIDE_PIXELS: int = 8

## Outline simplification, in source pixels. At 8 a 4096-pixel terrain piece lands at 40-58
## vertices, which is a comfortable budget for `ShapeBody.contact`. Measured; see the roadmap.
const DEFAULT_EPSILON: float = 8.0

## How square a box must be to be a disc candidate.
const CIRCLE_ASPECT_TOLERANCE: float = 0.12

## ...and how much of a circle filling that box the outline must enclose.
const CIRCLE_MIN_CIRCULARITY: float = 0.82

## How much of its box a piece must fill to be called a rectangle.
const RECT_MIN_BOX_FILL: float = 0.88

## Below this solidity the outline encloses space that has no pixels in it, which means a hole:
## a ring, or a gear drawn as a rim and spokes.
const ANNULUS_MAX_SOLIDITY: float = 0.62

## Pieces are ordered row-major so their ids are stable. A "row" is a band this fraction of the
## median piece height tall -- pieces on a hand-laid page do not line up exactly, and sorting on
## raw y would interleave two neighbouring rows and shuffle every id after them.
const ROW_BAND_FRACTION: float = 0.6


## Everything found on one sheet, ready to be written into a manifest.
##
## `existing` carries the previous manifest, if there is one, so hand-made decisions survive. Pass
## null on a first run.
func slice(sheet_path: String, family: String, existing: SheetManifest, epsilon: float = DEFAULT_EPSILON) -> SheetManifest:
	var image: Image = Image.load_from_file(sheet_path)
	if image == null:
		push_error("SheetSlicer: could not read %s" % sheet_path)
		return null

	var bitmap: BitMap = BitMap.new()
	bitmap.create_from_image_alpha(image, ALPHA_THRESHOLD)
	var whole: Rect2i = Rect2i(Vector2i.ZERO, image.get_size())
	var outlines: Array = bitmap.opaque_to_polygons(whole, epsilon)

	var found: Array[Dictionary] = []
	for traced: Variant in outlines:
		var measured: Dictionary = _measure(traced as PackedVector2Array, image)
		if not measured.is_empty():
			found.append(measured)

	_sort_row_major(found)

	var manifest: SheetManifest = SheetManifest.new()
	manifest.sheet = sheet_path
	manifest.epsilon = epsilon
	manifest.family = family

	# The sheets are named with spaces ("Blob Sheet 1.png"), and these stems become file names and
	# node names, so they are flattened explicitly rather than trusted to `to_snake_case()`.
	var stem: String = sheet_path.get_file().get_basename().to_lower().replace(" ", "_")
	var index: int = 0
	for measured: Dictionary in found:
		manifest.pieces.append(_entry_for(measured, "%s_%02d" % [stem, index], sheet_path, family, existing))
		index += 1

	return manifest


# ---------------------------------------------------------------- measuring one region

## Measure one traced region, or `{}` if it is too small to be a piece.
func _measure(outline: PackedVector2Array, image: Image) -> Dictionary:
	if outline.size() < 3:
		return {}

	var box: Rect2i = _bounds(outline)
	if box.size.x < MIN_SIDE_PIXELS or box.size.y < MIN_SIDE_PIXELS:
		return {}

	var opaque: int = _count_opaque(image, outline, box)
	if opaque < MIN_OPAQUE_PIXELS:
		return {}

	var area: float = absf(_signed_area(outline))
	var box_area: float = float(box.size.x) * float(box.size.y)
	# A circle that fills the box, using the smaller half-extent -- the largest circle that fits.
	var fit_radius: float = minf(float(box.size.x), float(box.size.y)) * 0.5
	var circle_area: float = PI * fit_radius * fit_radius

	return {
		"box": box,
		"outline": outline,
		"solidity": float(opaque) / maxf(1.0, area),
		"box_fill": float(opaque) / maxf(1.0, box_area),
		"circularity": area / maxf(1.0, circle_area),
	}


## The bounding box of a traced outline, in whole pixels.
func _bounds(outline: PackedVector2Array) -> Rect2i:
	var low: Vector2 = outline[0]
	var high: Vector2 = outline[0]
	for point: Vector2 in outline:
		low = low.min(point)
		high = high.max(point)
	var origin: Vector2i = Vector2i(floori(low.x), floori(low.y))
	var corner: Vector2i = Vector2i(ceili(high.x), ceili(high.y))
	return Rect2i(origin, corner - origin)


## Twice the enclosed area, signed -- the shoelace formula. Sign depends on winding, which is why
## callers take the absolute value.
func _signed_area(outline: PackedVector2Array) -> float:
	var total: float = 0.0
	var count: int = outline.size()
	for i: int in count:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % count]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## Opaque pixels inside the OUTLINE, by scanline fill.
##
## It has to be the outline rather than the bounding box. Counting the box was the first attempt
## and it was wrong in a way that was easy to miss: on a tightly packed sheet one piece's box
## overlaps its neighbours, so their pixels were counted too. The symptom was `solidity` coming out
## above 1.0 -- more opaque pixels than the outline could possibly enclose -- which is how the bug
## announced itself. Both `solidity` and `box_fill` were quietly meaningless on Prop Sheet 2, and
## with them the hollow and rectangle tests that read them.
##
## Scanline keeps it affordable. Testing every pixel against the polygon would be O(pixels x
## edges); walking each row's crossings is O(pixels + edges) and runs over all five sheets in
## seconds. Even-odd fill, which is also what makes a ring's hole count as empty -- exactly the
## case `ANNULUS` needs to detect.
func _count_opaque(image: Image, outline: PackedVector2Array, box: Rect2i) -> int:
	var count: int = 0
	var vertices: int = outline.size()
	var last_x: int = box.position.x + box.size.x - 1
	var crossings: Array[float] = []

	for y: int in range(box.position.y, box.position.y + box.size.y):
		# Sample through the middle of the row, so an edge landing exactly on an integer y does
		# not count twice or not at all.
		var scan: float = float(y) + 0.5
		crossings.clear()
		for i: int in vertices:
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i + 1) % vertices]
			# Half-open test: one end below, the other at or above. This is what stops a shared
			# vertex between two edges registering as two crossings.
			if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan):
				crossings.append(a.x + (scan - a.y) / (b.y - a.y) * (b.x - a.x))

		if crossings.size() < 2:
			continue
		crossings.sort()

		var pair: int = 0
		while pair + 1 < crossings.size():
			var from_x: int = maxi(box.position.x, ceili(crossings[pair] - 0.5))
			var to_x: int = mini(last_x, floori(crossings[pair + 1] - 0.5))
			for x: int in range(from_x, to_x + 1):
				if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
					count += 1
			pair += 2

	return count


# ---------------------------------------------------------------- ordering and classification

## Sort pieces into a stable reading order: top row left-to-right, then the next row.
##
## Stability is what makes the manifest work. Ids are positional, so if this order changed between
## runs every decision in the manifest would silently attach to a different piece.
func _sort_row_major(found: Array[Dictionary]) -> void:
	if found.is_empty():
		return

	var heights: Array[float] = []
	for measured: Dictionary in found:
		heights.append(float((measured["box"] as Rect2i).size.y))
	heights.sort()
	var median: float = heights[heights.size() / 2]
	var band: float = maxf(1.0, median * ROW_BAND_FRACTION)

	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var box_a: Rect2i = a["box"] as Rect2i
		var box_b: Rect2i = b["box"] as Rect2i
		var row_a: int = floori(float(box_a.position.y) / band)
		var row_b: int = floori(float(box_b.position.y) / band)
		if row_a != row_b:
			return row_a < row_b
		return box_a.position.x < box_b.position.x
	)


## Build the entry for one measured piece, carrying over any decision already made about it.
func _entry_for(
	measured: Dictionary,
	piece_id: String,
	sheet_path: String,
	family: String,
	existing: SheetManifest,
) -> PieceEntry:
	var box: Rect2i = measured["box"] as Rect2i
	var outline: PackedVector2Array = measured["outline"] as PackedVector2Array

	var entry: PieceEntry = PieceEntry.new()
	entry.id = piece_id
	entry.sheet = sheet_path
	entry.region = box
	# Relative to the region, so a piece that moves on the sheet changes `region` and not this.
	entry.outline = _shift(outline, -Vector2(box.position))
	entry.solidity = measured["solidity"] as float
	entry.box_fill = measured["box_fill"] as float
	entry.circularity = measured["circularity"] as float
	entry.vertex_count = outline.size()
	entry.guessed = _guess(entry, family)

	# The decision half. A previous manifest wins; otherwise the guess is the starting point.
	var previous: PieceEntry = existing.by_id(piece_id) if existing != null else null
	if previous != null:
		entry.kind = previous.kind
		entry.radius = previous.radius
		entry.inner_radius = previous.inner_radius
		entry.reviewed = previous.reviewed
	else:
		entry.kind = entry.guessed

	return entry


## What this piece probably collides as.
##
## Terrain is not guessed at: a blob you stand on needs its outline, and that is the one category
## where tracing is the right answer. Props are measured.
func _guess(entry: PieceEntry, family: String) -> PieceEntry.Kind:
	if family == "terrain":
		return PieceEntry.Kind.POLYGON

	var wide: float = maxf(float(entry.region.size.x), float(entry.region.size.y))
	var narrow: float = minf(float(entry.region.size.x), float(entry.region.size.y))
	var squareness: float = 1.0 - (wide - narrow) / maxf(1.0, wide)

	# A hole first: a ring is square and disc-like too, so asking "is it hollow?" has to come
	# before "is it a disc?" or every ring would be called a solid circle and the ball would be
	# unable to get inside it.
	if entry.solidity < ANNULUS_MAX_SOLIDITY and squareness >= 1.0 - CIRCLE_ASPECT_TOLERANCE:
		return PieceEntry.Kind.ANNULUS

	if squareness >= 1.0 - CIRCLE_ASPECT_TOLERANCE and entry.circularity >= CIRCLE_MIN_CIRCULARITY:
		return PieceEntry.Kind.CIRCLE

	if entry.box_fill >= RECT_MIN_BOX_FILL:
		return PieceEntry.Kind.RECT

	return PieceEntry.Kind.POLYGON


func _shift(outline: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var moved: PackedVector2Array = PackedVector2Array()
	moved.resize(outline.size())
	for i: int in outline.size():
		moved[i] = outline[i] + by
	return moved
