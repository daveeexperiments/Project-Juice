class_name GlassRules
extends RefCounted

## What the rocky ball does to a pane, and whether a pane is solid at all.
##
## Ported from the glass helpers in src/systems/MaterialCollision.ts (`rockyGlassMode`,
## `rockyWouldBreak`, `glassIsSolidFor`, `effectiveMaterial`) and from
## src/systems/GlassClassify.ts.
##
## Kept apart from BallSim because three different callers need the same answers: the step, the
## support probe, and the reachability check. One place to ask means they cannot disagree.

const MODE_OBSTRUCTION: int = 0
const MODE_ALWAYS: int = 1
const MODE_HARD: int = 2
const MODE_NEVER: int = 3
const MODE_PASS: int = 4

## Fraction of a pane's outline that must lie flat on terrain before it counts as cladding.
const BACKED_FRACTION: float = 0.3


## The mode in force for one pane: its own setting unless the global one is set to win.
static func mode_for(shape: ShapeBody) -> int:
	var t: TuningData = TuningData.get_active()
	var global_mode: int = clampi(t.glass_rocky_mode, MODE_OBSTRUCTION, MODE_PASS)
	if t.glass_panel_overrides_level:
		return global_mode
	if shape != null and shape.rocky_breaks != ShapeBody.ROCKY_DEFAULT:
		return clampi(shape.rocky_breaks, MODE_OBSTRUCTION, MODE_PASS)
	return global_mode


## Does the rocky ball shatter this pane on this hit?
##
## "always" is the old unconditional break. "hard" wants a real impact, measured along the
## contact normal so skimming along a pane never breaks it. "never" and "pass" never break; a
## pane the rock cannot break behaves like a wall, which is what makes it something to land on.
static func would_break(shape: ShapeBody, form: BallForm, approach: float) -> bool:
	if not form.breaks_glass:
		return false
	var mode: int = mode_for(shape)
	if mode == MODE_NEVER or mode == MODE_PASS:
		return false
	# "Break obstructions only": cladding is ignored, anything in the way breaks on contact.
	if mode == MODE_OBSTRUCTION and shape != null and shape.glass_type == ShapeBody.GLASS_WALL:
		return false
	if mode == MODE_HARD:
		return approach >= maxf(0.0, TuningData.get_active().glass_hard_break_speed)
	return approach >= form.glass_break_min_impact


## Is this pane solid for this ball at all? Only "pass through" makes it not.
static func is_solid_for(shape: ShapeBody, form: BallForm) -> bool:
	if shape == null or shape.material != SurfaceKind.GLASS:
		return true
	if not form.breaks_glass:
		return true
	return mode_for(shape) != MODE_PASS


## What this surface IS as far as the bouncing ball is concerned.
##
## Glass the rocky ball is ignoring (cladding, in "break obstructions only") answers "wall": it
## bounces off it with wall physics and no glass boost, so the rock lands dead as if it had hit
## the rock behind the pane, and every downstream reader -- the support check, the sounds, the
## grounded test -- treats it as wall without knowing anything about glass types.
static func effective_material(shape: ShapeBody, form: BallForm) -> int:
	if shape.material != SurfaceKind.GLASS or not form.breaks_glass:
		return shape.material
	if mode_for(shape) == MODE_OBSTRUCTION and shape.glass_type == ShapeBody.GLASS_WALL:
		return SurfaceKind.WALL
	return SurfaceKind.GLASS


## Does this pane block the route? Used by the reachability check.
##
## Glass the rocky ball can never break is as good as rock. Everything else is passable one way
## or another, and in "break obstructions only" so is anything in the way -- only cladding counts.
static func blocks_route(shape: ShapeBody) -> bool:
	if shape.spike_base:
		return false
	if shape.material != SurfaceKind.GLASS:
		return true
	var mode: int = mode_for(shape)
	if mode == MODE_NEVER:
		return true
	return mode == MODE_OBSTRUCTION and shape.glass_type == ShapeBody.GLASS_WALL


## Decide, once, which glass is cladding and which is in the way.
##
## The question a designer is really asking is "would smashing this open a route, or just strip a
## wall bare?", and that turns out to be answerable from the geometry: a pane laid along a wall
## has one of its LONG sides lying flat against the terrain behind it, while a bridge, a blocker
## or a floating platform touches terrain only at its ends, if at all.
##
## Every edge is probed outward along its own normal and counts as backed when something solid is
## there. Edges are weighed by LENGTH rather than filtered by it: a smoothed outline is hundreds
## of short steps, and a minimum edge length throws the whole pane away.
static func classify(shapes: Array[ShapeBody]) -> void:
	var t: TuningData = TuningData.get_active()
	var gap: float = maxf(0.0, t.glass_wall_gap)
	var tolerance: float = cos(deg_to_rad(maxf(0.0, t.glass_wall_angle)))

	for shape: ShapeBody in shapes:
		if shape.material != SurfaceKind.GLASS:
			continue
		if shape.glass_type_override != ShapeBody.GLASS_AUTO:
			shape.glass_type = shape.glass_type_override
			continue
		shape.glass_type = _classify_one(shape, shapes, gap, tolerance)


static func _classify_one(shape: ShapeBody, shapes: Array[ShapeBody], gap: float, tolerance: float) -> int:
	var total: float = 0.0
	var backed: float = 0.0
	var count: int = shape.points.size()
	for i: int in count:
		var a: Vector2 = shape.points[i]
		var b: Vector2 = shape.points[(i + 1) % count]
		var edge: Vector2 = b - a
		var length: float = edge.length()
		if length == 0.0:
			continue
		total += length

		# Outward normal: flipped if it points back into the pane.
		var n: Vector2 = Vector2(-edge.y, edge.x) / length
		var mid: Vector2 = (a + b) * 0.5
		if shape.contains(mid.x + n.x * 2.0, mid.y + n.y * 2.0):
			n = -n

		var probe: Vector2 = mid + n * (gap + 1.0)
		if _backed_by(shape, probe, n, tolerance, shapes):
			backed += length

	return ShapeBody.GLASS_WALL if total > 0.0 and backed / total >= BACKED_FRACTION else ShapeBody.GLASS_OBSTRUCTION


## Is there terrain just outside this edge, lying the same way the edge does?
static func _backed_by(shape: ShapeBody, probe: Vector2, n: Vector2, tolerance: float, shapes: Array[ShapeBody]) -> bool:
	for other: ShapeBody in shapes:
		if other == shape or other.material == SurfaceKind.GLASS:
			continue
		# Bedded straight into the rock, which is as flat against a wall as a pane can get, so
		# there is no angle left to measure.
		if other.contains(probe.x, probe.y):
			return true
		var c: ShapeContact = other.contact(probe.x, probe.y, 1.0)
		if c == null:
			continue
		# Its normal points out of the terrain, i.e. the opposite way to the pane's.
		if -(c.nx * n.x + c.ny * n.y) >= tolerance:
			return true
	return false
