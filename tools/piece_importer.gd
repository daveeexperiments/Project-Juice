@tool
class_name PieceImporter
extends RefCounted

## Turns a manifest entry into the collision outline its `kind` calls for.
##
## This is the half of the pipeline where "collision is authored, not derived" actually happens.
## The slicer traced what the art looks like; this decides what the ball hits, and the two are
## allowed to disagree on purpose. A gear's 532-vertex outline becomes a disc of about twenty,
## because the teeth are there to be looked at and tracing them wedges the ball between them.
##
## Everything in and out of here is in SOURCE PIXELS. Scale is applied once, on the root node of
## the generated scene, so a piece's polygon in the editor reads in the same units as the art it
## sits under.

# ---------------------------------------------------------------- the world scale

## The resting worm's diameter in source pixels, measured off the character sheet: frames 3 and 7
## are the curled forms at 250x246 and 255x248.
##
## This is a fact about the art rather than a setting, which is what lets `art_scale()` below be
## derived instead of configured.
const WORM_SOURCE_DIAMETER: float = 250.0

## How many world pixels one source pixel becomes.
##
## **Derived, not chosen.** The ball on screen IS the worm, so the scale is fixed the moment the
## ball's radius is: art_scale = ball diameter in world / worm diameter in source. Reading it from
## the tuning means the zoom-versus-transform decision never has to be settled here -- if the
## tuning is ever scaled, every piece rescales with it and stays consistent with the ball by
## construction. Re-run the importer after such a change and nothing else needs touching.
static func art_scale() -> float:
	var t: TuningData = TuningData.get_active()
	var radius: float = maxf(t.squishy_radius, t.rocky_radius)
	return (radius * 2.0) / WORM_SOURCE_DIAMETER


## The ball's radius expressed in source pixels, which is the unit terrain closing works in.
##
## Uses the LARGER of the two forms so one outline is safe for both. Once the radii are unified
## -- the art says the two forms are the same circle -- this is simply the ball's radius.
static func ball_radius_source() -> float:
	var t: TuningData = TuningData.get_active()
	return maxf(t.squishy_radius, t.rocky_radius) / maxf(0.0001, art_scale())


# ---------------------------------------------------------------- tolerances

## How far a straight facet may bulge away from the true curve it replaces, in WORLD pixels.
##
## A circle has to become a polygon because `ShapeBody` holds outlines and nothing else. The
## question is how many sides, and answering it with a fixed number is wrong in both directions:
## 24 sides on a small bolt is waste, and on a 1200-pixel flywheel it is a visibly faceted edge
## that a rolling ball can feel. Tying the count to the error instead means a piece gets exactly
## the detail its size needs.
##
## 0.4 px is comfortably under what is visible against a ball of radius 12.
const MAX_FACET_ERROR_WORLD: float = 0.4

const MIN_CIRCLE_SEGMENTS: int = 8
const MAX_CIRCLE_SEGMENTS: int = 64

## Join style for the radius closing. ROUND matches what a ball actually sweeps: a square or
## mitred join would carve corners the ball cannot physically reach into.
const CLOSING_JOIN: int = Geometry2D.JOIN_ROUND

## How far the simplified outline may stray from the closed one, in source pixels.
##
## The closing pass has to be followed by a re-simplify, and the reason is easy to miss: offsetting
## with round joins lays a fan of points around every convex corner, so a terrain piece traced at
## 40 vertices comes back at 120-290. That silently throws away the vertex budget epsilon 8 was
## chosen to hit, and `ShapeBody.contact` is O(edges) over every shape in the level -- which is
## Risk 3 in the roadmap, arriving through the back door.
##
## 8 matches the slicer's tolerance, so the outline ends up at the fidelity it was traced at. In
## world units that is about 0.77 px of error against a ball of radius 12.
const SIMPLIFY_EPSILON: float = 8.0


## The collision outline for one piece, in SOURCE PIXELS relative to its region's top-left.
##
## Empty means this piece has no collision at all, which is a real answer -- `NONE` is how
## decoration stays out of the simulation entirely.
static func collision_for(entry: PieceEntry) -> PackedVector2Array:
	match entry.kind:
		PieceEntry.Kind.NONE:
			return PackedVector2Array()
		PieceEntry.Kind.RECT:
			return _rectangle(entry)
		PieceEntry.Kind.CIRCLE:
			return _circle(Vector2(entry.region.size) * 0.5, entry.effective_radius())
		PieceEntry.Kind.ANNULUS:
			# Not emitted yet -- see `annulus_note()`. Falling back to the outer disc would be
			# worse than nothing: it fills the hole the ball is meant to travel through, so the
			# route simply closes and the reason is invisible.
			return PackedVector2Array()
		_:
			return _closed_outline(entry)


## Why `ANNULUS` produces nothing yet, in one place so the importer and its report agree.
static func annulus_note() -> String:
	return (
		"a ring the ball travels INSIDE needs the ball contained, and ShapeBody holds one closed "
		+ "outline that pushes a ball OUT. Needs either an inverted body or the ring built from "
		+ "overlapping rim segments; no beat uses one yet."
	)


# ---------------------------------------------------------------- the four shapes

## The region's box. Beams, straight pipes, platforms.
static func _rectangle(entry: PieceEntry) -> PackedVector2Array:
	var size: Vector2 = Vector2(entry.region.size)
	return PackedVector2Array([
		Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y),
	])


## A regular polygon standing in for a circle, with just enough sides to hide the facets.
static func _circle(centre: Vector2, radius: float) -> PackedVector2Array:
	var sides: int = _segments_for(radius)
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in sides:
		var angle: float = TAU * float(i) / float(sides)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


## How many sides a circle of this radius needs to stay under `MAX_FACET_ERROR_WORLD`.
##
## The bulge between a chord and its arc is the sagitta, r(1 - cos(pi/n)). Solving for n gives
## n = pi / acos(1 - error/r).
static func _segments_for(radius_source: float) -> int:
	var error_source: float = MAX_FACET_ERROR_WORLD / maxf(0.0001, art_scale())
	if radius_source <= error_source:
		return MIN_CIRCLE_SEGMENTS
	var ratio: float = clampf(1.0 - error_source / radius_source, -1.0, 1.0)
	var sides: int = ceili(PI / maxf(0.0001, acos(ratio)))
	return clampi(sides, MIN_CIRCLE_SEGMENTS, MAX_CIRCLE_SEGMENTS)


## Terrain: the traced outline with every pocket the ball cannot fit into filled in.
##
## A morphological CLOSING -- offset outward by the ball's radius, then back inward by the same.
## Every concavity narrower than the ball disappears; everything the ball can actually reach comes
## back untouched. It is the formal version of what a level designer does by hand when they fillet
## an inside corner so a ball rolls through instead of wedging, and it is the main defence against
## Risk 2: organic terrain with no walking has no way out of a pocket.
static func _closed_outline(entry: PieceEntry) -> PackedVector2Array:
	var outline: PackedVector2Array = entry.outline
	if outline.size() < 3:
		return outline

	var radius: float = ball_radius_source()
	if radius <= 0.0:
		return outline

	var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(outline, radius, CLOSING_JOIN)
	if grown.is_empty():
		return outline
	var shrunk: Array[PackedVector2Array] = Geometry2D.offset_polygon(_largest(grown), -radius, CLOSING_JOIN)
	if shrunk.is_empty():
		# Shrinking can erase a piece thinner than the ball entirely. Keeping the traced outline
		# is the safe answer: a thin ledge that collides is better than one that silently vanishes.
		return outline
	return _simplify(_largest(shrunk), SIMPLIFY_EPSILON)


## Ramer-Douglas-Peucker: drop every point that lies within `epsilon` of the line its neighbours
## already describe.
##
## Closed outlines need an anchor pair to split on, and the two points furthest apart are the
## natural choice -- they are certain to survive, so neither half can collapse to nothing.
static func _simplify(outline: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var count: int = outline.size()
	if count < 4:
		return outline

	var first: int = 0
	var second: int = 0
	var furthest: float = -1.0
	for i: int in count:
		var span: float = outline[0].distance_squared_to(outline[i])
		if span > furthest:
			furthest = span
			second = i
	furthest = -1.0
	for i: int in count:
		var span: float = outline[second].distance_squared_to(outline[i])
		if span > furthest:
			furthest = span
			first = i

	var low: int = mini(first, second)
	var high: int = maxi(first, second)
	var front: PackedVector2Array = outline.slice(low, high + 1)
	var back: PackedVector2Array = outline.slice(high) + outline.slice(0, low + 1)

	var kept: PackedVector2Array = _reduce(front, epsilon)
	var tail: PackedVector2Array = _reduce(back, epsilon)
	# Both halves carry the two anchors, so drop the duplicates where they meet.
	for i: int in range(1, tail.size() - 1):
		kept.append(tail[i])
	return kept


## One open run, reduced. Returns its endpoints plus whatever had to stay between them.
static func _reduce(run: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if run.size() < 3:
		return run

	var worst: float = 0.0
	var at: int = 0
	for i: int in range(1, run.size() - 1):
		var distance: float = _distance_to_segment(run[i], run[0], run[-1])
		if distance > worst:
			worst = distance
			at = i

	if worst <= epsilon:
		return PackedVector2Array([run[0], run[-1]])

	var left: PackedVector2Array = _reduce(run.slice(0, at + 1), epsilon)
	var right: PackedVector2Array = _reduce(run.slice(at), epsilon)
	for i: int in range(1, right.size()):
		left.append(right[i])
	return left


static func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var span: Vector2 = to - from
	var length_squared: float = span.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(from)
	var t: float = clampf((point - from).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(from + span * t)


## The polygon enclosing the most area. Offsetting can split a shape into several or spit out the
## hole alongside the body, and the body is always the biggest of them.
static func _largest(polygons: Array[PackedVector2Array]) -> PackedVector2Array:
	var best: PackedVector2Array = polygons[0]
	var best_area: float = absf(_area(best))
	for candidate: PackedVector2Array in polygons:
		var area: float = absf(_area(candidate))
		if area > best_area:
			best = candidate
			best_area = area
	return best


static func _area(polygon: PackedVector2Array) -> float:
	var total: float = 0.0
	var count: int = polygon.size()
	for i: int in count:
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % count]
		total += a.x * b.y - b.x * a.y
	return total * 0.5
