class_name AimMath
extends RefCounted

## Aiming maths, pure and testable. Ported from src/systems/AimMath.ts.
##
## THE RULE the whole file exists to enforce: **the aim is the drag vector**. Nothing here ever
## stores an angle and reads it back, because that is where aiming gets stuck -- a value in
## (-180, 180] that is clamped, smoothed or snapped fights itself every time the drag crosses the
## wrap. Degrees are produced only at the very end, for a readout, and never feed back in.

const RANGE_FULL: int = 0
const RANGE_UPWARD: int = 1
const RANGE_CUSTOM: int = 2

const EDGE_FROM: int = 0
const EDGE_TO: int = 1

## How much better the other edge must be before the clamp swaps to it, as a difference of dot
## products. Worth roughly +-3.5 degrees of slack: enough that a hand wobbling opposite the range
## holds one edge instead of snapping between hard left and hard right, small enough that a
## deliberate sweep still crosses over once and stays crossed.
const EDGE_HYSTERESIS: float = 0.12


## Snap a direction to the nearest multiple of `step_degrees` by rotating the vector itself.
##
## Working on the vector is what makes this safe in every direction: there is no angle to wrap,
## so straight down behaves exactly like straight up, and a drag sweeping past 180 degrees snaps
## to the neighbouring step rather than jumping the long way round.
static func snap_direction(u: Vector2, step_degrees: float) -> Vector2:
	if step_degrees <= 0.0:
		return u
	var step: float = deg_to_rad(step_degrees)
	# atan2 is a local measurement, consumed on the next line and never stored.
	var snapped: float = round(atan2(u.y, u.x) / step) * step
	return Vector2(cos(snapped), sin(snapped))


## A direction from degrees, counter-clockwise with 90 = up. Screen y points down, hence -sin.
static func direction_from_degrees(degrees: float) -> Vector2:
	var rad: float = deg_to_rad(degrees)
	return Vector2(cos(rad), -sin(rad))


## Launch direction for a readout: 0-359, counter-clockwise, 90 = straight up. Display only.
static func display_degrees(u: Vector2) -> float:
	if u.x == 0.0 and u.y == 0.0:
		return 0.0
	# Screen y grows downward, so negate it for the usual counter-clockwise convention.
	var deg: float = rad_to_deg(atan2(-u.y, u.x))
	return fposmod(deg, 360.0)


## The arc the panel's mode asks for, as [from_degrees, to_degrees].
static func range_degrees() -> Array:
	var t: TuningData = TuningData.get_active()
	match t.slingshot_aim_range_mode:
		RANGE_FULL:
			return [0.0, 360.0]
		RANGE_CUSTOM:
			return [t.slingshot_aim_range_min, t.slingshot_aim_range_max]
	return [15.0, 165.0]


## Build a range from an arc in degrees, optionally rotated so it sits relative to a surface.
static func make_range(from_degrees: float, to_degrees: float, rotate_by_degrees: float = 0.0) -> AimRange:
	var r: AimRange = AimRange.new()
	var span: float = to_degrees - from_degrees
	# A span of a full turn (or more) is no limit at all.
	if not is_finite(span) or absf(span) >= 359.999:
		r.unlimited = true
		r.centre = direction_from_degrees(0.0)
		r.cos_half = -1.0
		r.from_dir = r.centre
		r.to_dir = r.centre
		return r
	if span < 0.0:
		span += 360.0

	r.unlimited = false
	r.from_dir = direction_from_degrees(from_degrees + rotate_by_degrees)
	r.to_dir = direction_from_degrees(from_degrees + span + rotate_by_degrees)
	r.centre = direction_from_degrees(from_degrees + span * 0.5 + rotate_by_degrees)
	r.cos_half = cos(deg_to_rad(span * 0.5))
	return r


## Clamp a direction into a range, working only on vectors.
##
## Inside the arc is a single dot product against its centre. Outside, the nearer edge wins,
## again by dot product. No angle is ever subtracted from another, so there is no wrap to stick
## at. Dead opposite the middle both edges are equally far, so `last_edge` breaks the tie --
## without it, a drag held straight down in "upward only" flickers between hard left and right.
static func clamp_to_range(u: Vector2, r: AimRange, last_edge: int = EDGE_FROM) -> AimClamp:
	var result: AimClamp = AimClamp.new()
	result.direction = u
	result.clamped = false
	result.edge = last_edge
	if r.unlimited or (u.x == 0.0 and u.y == 0.0):
		return result

	var to_centre: float = u.dot(r.centre)
	if to_centre >= r.cos_half:
		return result

	var to_from: float = u.dot(r.from_dir)
	var to_to: float = u.dot(r.to_dir)
	var nearest: int = EDGE_FROM if to_from > to_to else EDGE_TO

	var held: float = to_from if last_edge == EDGE_FROM else to_to
	var best: float = maxf(to_from, to_to)
	var edge: int = last_edge if best - held <= EDGE_HYSTERESIS else nearest

	result.direction = r.from_dir if edge == EDGE_FROM else r.to_dir
	result.clamped = true
	result.edge = edge
	return result


## Turn a raw drag into an aim.
##
## Order matters, and is the same as Phaser's: the range is applied AFTER snapping, so a snapped
## direction can never land outside the allowed arc; and which edge to rest on is decided from
## the RAW direction, never the snapped one, because snapping quantises the drag into steps that
## land either side of the tie and would flick the aim between edges however wide the band was.
static func aim_from_drag(
	raw_drag: Vector2,
	snap_step_degrees: float = 0.0,
	r: AimRange = null,
	last_edge: int = EDGE_FROM,
) -> AimVector:
	var aim: AimVector = AimVector.new()
	var length: float = raw_drag.length()
	aim.length = length
	aim.edge = last_edge
	if length == 0.0 or not is_finite(length):
		return aim

	# The launch direction is straight back along the drag.
	var raw: Vector2 = -raw_drag / length

	if r == null or r.unlimited:
		var snapped_free: Vector2 = snap_direction(raw, snap_step_degrees)
		aim.direction = snapped_free
		aim.drag = -snapped_free * length
		return aim

	var outside: AimClamp = clamp_to_range(raw, r, last_edge)
	if outside.clamped:
		# Parked on an edge: that IS the limit, so there is nothing to snap it to.
		aim.direction = outside.direction
		aim.drag = -outside.direction * length
		aim.clamped = true
		aim.edge = outside.edge
		return aim

	# Inside the range: snap as usual, then re-clamp in case a step lands just outside it.
	var snapped: Vector2 = snap_direction(raw, snap_step_degrees)
	var limited: AimClamp = clamp_to_range(snapped, r, outside.edge)
	aim.direction = limited.direction
	aim.drag = -limited.direction * length
	aim.clamped = limited.clamped
	aim.edge = limited.edge
	return aim


## A range of allowed aim directions, held as vectors rather than numbers.
class AimRange extends RefCounted:
	var unlimited: bool = true
	var centre: Vector2 = Vector2.RIGHT
	## Cosine of half the arc's width, so "is this allowed" is one dot product.
	var cos_half: float = -1.0
	var from_dir: Vector2 = Vector2.RIGHT
	var to_dir: Vector2 = Vector2.RIGHT


class AimClamp extends RefCounted:
	var direction: Vector2 = Vector2.ZERO
	var clamped: bool = false
	var edge: int = AimMath.EDGE_FROM


class AimVector extends RefCounted:
	## Drag vector after snapping, in world pixels. The ball launches opposite this.
	var drag: Vector2 = Vector2.ZERO
	## Launch direction, a unit vector. Screen axes, so y is negative when aiming upward.
	var direction: Vector2 = Vector2.ZERO
	## Drag length in pixels, unchanged by snapping or clamping.
	var length: float = 0.0
	## True when an aim range pushed the direction onto one of its edges.
	var clamped: bool = false
	## Which edge it rests on, so the clamp cannot flicker.
	var edge: int = AimMath.EDGE_FROM
