class_name ShapeBody
extends RefCounted

## A solid drawn as a polygon, in world space. Ported from src/systems/ShapeBody.ts.
##
## One outline is used for drawing AND for collision, so what you see is what you hit.
##
## The important detail, carried over exactly: `contact` finds the closest point across EVERY
## edge before deciding anything. Testing edge by edge and taking the first hit makes a ball
## rolling along a curve snag where two edges meet; taking the nearest point over the whole
## outline means a joint reports the shared vertex with a normal running straight out of it.

## How finely each span between drawn points is sampled when smoothing.
const SAMPLES_PER_SPAN: int = 8

## Rocky-vs-glass overrides, per piece. DEFAULT follows the global mode.
const ROCKY_DEFAULT: int = -1
const ROCKY_OBSTRUCTION: int = 0
const ROCKY_ALWAYS: int = 1
const ROCKY_HARD: int = 2
const ROCKY_NEVER: int = 3
const ROCKY_PASS: int = 4

## What a piece of glass IS, for "break obstructions only".
const GLASS_AUTO: int = -1
const GLASS_OBSTRUCTION: int = 0
const GLASS_WALL: int = 1

var id: int = 0
## The smoothed outline, closed (last point joins the first). This is what collides.
var points: PackedVector2Array = PackedVector2Array()
## The points it was drawn from, kept so the editor can still show handles.
var drawn_from: PackedVector2Array = PackedVector2Array()
var smoothing: float = 0.0
var material: int = SurfaceKind.WALL
var bounds: Rect2 = Rect2()

## Glass pieces shatter whole, so a broken one stops colliding entirely.
var broken: bool = false
## Seconds until this piece returns once broken. 0 means never; -1 means use the global setting.
var respawn_seconds: float = -1.0
## Per-object override of what the rocky ball does to this pane.
var rocky_breaks: int = ROCKY_DEFAULT
## Cladding or obstruction. AUTO is worked out once on load by GlassClassify.
var glass_type_override: int = GLASS_AUTO
## The answer the detection settled on. Only meaningful for glass.
var glass_type: int = GLASS_OBSTRUCTION
## This pane throws the ball back at its own speed rather than the global boost. -1 = global.
var bounce_boost: float = -1.0
## True for the solid body of a spike strip: collides like wall, but the route check steps over
## it, because spikes are flown around rather than sealing a level.
var spike_base: bool = false


func _init(shape_id: int, outline: PackedVector2Array, shape_material: int, shape_smoothing: float = 0.0) -> void:
	id = shape_id
	material = shape_material
	drawn_from = outline.duplicate()
	smoothing = shape_smoothing
	points = smooth_closed_polygon(outline, shape_smoothing)
	bounds = _bounds_of(points)


## Circle against the whole outline. Returns null when clear.
func contact(cx: float, cy: float, r: float) -> ShapeContact:
	if broken:
		return null
	if cx + r < bounds.position.x or cx - r > bounds.end.x:
		return null
	if cy + r < bounds.position.y or cy - r > bounds.end.y:
		return null

	var best_x: float = 0.0
	var best_y: float = 0.0
	var best_dist_sq: float = INF
	var count: int = points.size()
	for i: int in count:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % count]
		var abx: float = b.x - a.x
		var aby: float = b.y - a.y
		var len_sq: float = abx * abx + aby * aby
		var t: float = 0.0 if len_sq == 0.0 else clampf(((cx - a.x) * abx + (cy - a.y) * aby) / len_sq, 0.0, 1.0)
		var px: float = a.x + abx * t
		var py: float = a.y + aby * t
		var dist_sq: float = (cx - px) * (cx - px) + (cy - py) * (cy - py)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_x = px
			best_y = py

	var dist: float = sqrt(best_dist_sq)
	var inside: bool = contains(cx, cy)
	if not inside and dist >= r:
		return null

	if dist < 0.000001:
		# Dead on the outline: push straight up rather than dividing by zero.
		return ShapeContact.make(0.0, -1.0, r)

	# Outside, the normal runs from the surface to the ball; inside, the other way, so a ball that
	# has ended up in the rock is pushed back out of it.
	var sign_out: float = -1.0 if inside else 1.0
	return ShapeContact.make(
		((cx - best_x) / dist) * sign_out,
		((cy - best_y) / dist) * sign_out,
		(r + dist) if inside else (r - dist),
	)


## Even-odd ray cast: is this point inside the outline?
func contains(x: float, y: float) -> bool:
	var inside: bool = false
	var count: int = points.size()
	var j: int = count - 1
	for i: int in count:
		var a: Vector2 = points[i]
		var b: Vector2 = points[j]
		if (a.y > y) != (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside


## Round a drawn polygon into a flowing curve with Catmull-Rom, so a level can be laid out as a
## few points and still come out organic. `smoothing` 0 keeps the drawn corners exactly.
## Ported from smoothClosedPolygon in src/systems/ShapeBody.ts.
static func smooth_closed_polygon(raw: PackedVector2Array, smoothing_amount: float) -> PackedVector2Array:
	var n: int = raw.size()
	if n < 3 or smoothing_amount <= 0.0:
		return raw.duplicate()

	var strength: float = minf(1.0, smoothing_amount)
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		var p0: Vector2 = raw[(i - 1 + n) % n]
		var p1: Vector2 = raw[i]
		var p2: Vector2 = raw[(i + 1) % n]
		var p3: Vector2 = raw[(i + 2) % n]
		for s: int in SAMPLES_PER_SPAN:
			var t: float = float(s) / float(SAMPLES_PER_SPAN)
			# Blend the straight edge with the spline, so `smoothing` reads as "how round".
			out.append(Vector2(
				lerpf(p1.x + (p2.x - p1.x) * t, _catmull_rom(p0.x, p1.x, p2.x, p3.x, t), strength),
				lerpf(p1.y + (p2.y - p1.y) * t, _catmull_rom(p0.y, p1.y, p2.y, p3.y, t), strength),
			))
	return out


static func _catmull_rom(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


func _bounds_of(outline: PackedVector2Array) -> Rect2:
	if outline.is_empty():
		return Rect2()
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for p: Vector2 in outline:
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
