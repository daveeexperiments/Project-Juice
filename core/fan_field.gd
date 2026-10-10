class_name FanField
extends RefCounted

## A column of moving air. Ported from the fan actor in src/systems/Actors.ts.
##
## A fan carries a ball along its direction up to `fans.targetSpeed`, weaker the further down the
## stream it is, and weaker again at the edges. The two balls feel it completely differently: the
## squishy ball is light enough to be flown (`squishy.fanMultiplier` 2.4 against its own gravity of
## 840 px/s^2), the rocky ball barely drifts (0.3 against 1920). That asymmetry is the puzzle --
## a fan is a route for one ball and scenery for the other.
##
## IT HOLDS NO STATE. The push is a pure function of where the ball is, which way the fan blows and
## what the ball is made of. That matters for more than tidiness: a stateless actor needs no copy
## in `StepWorld.ghost()`, so the prediction is exact through a fan for free.
##
## A fan never brakes. Only the shortfall below the target speed is made up, so flying a fast shot
## through a stream costs nothing -- being slowed by scenery you cannot see would read as the game
## cheating.

## How finely the line of sight from mouth to ball is sampled, in pixels. Fixed rather than
## adaptive so the ghost and the ball sample identically.
const SIGHT_STEP: float = 8.0

var id: int = 0
## Centre of the mouth, in world space.
var origin: Vector2 = Vector2.ZERO
## Which way it blows. Always normalised.
var direction: Vector2 = Vector2.UP
## Half the mouth's width, across the stream.
var half_width: float = 48.0
## How far the stream reaches before it dies. -1 takes the global `fans.range`.
var range_override: float = -1.0
## This fan's own strength, multiplying the global one. 1 is a standard fan.
var strength_scale: float = 1.0


func _init(
	fan_id: int,
	at: Vector2,
	blows: Vector2,
	width: float,
	reach: float = -1.0,
	strength: float = 1.0,
) -> void:
	id = fan_id
	origin = at
	direction = blows.normalized() if blows.length() > 0.0 else Vector2.UP
	half_width = maxf(1.0, width * 0.5)
	range_override = reach
	strength_scale = strength


func reach() -> float:
	return range_override if range_override >= 0.0 else maxf(0.0, TuningData.get_active().fans_range)


## The acceleration this fan applies to a ball at `x, y`, in px/s^2. Zero when the ball is outside
## the stream, behind the mouth, or in its shadow.
##
## `world` is needed only for the line-of-sight test; pass the same world the step is running
## against so the ghost sees the same shadows the ball will.
func accel_for(x: float, y: float, vx: float, vy: float, form: BallForm, world: StepWorld) -> Vector2:
	var t: TuningData = TuningData.get_active()
	var multiplier: float = form.fan_multiplier
	if multiplier <= 0.0 or strength_scale <= 0.0:
		return Vector2.ZERO

	var to_ball: Vector2 = Vector2(x - origin.x, y - origin.y)
	# How far down the stream, and how far off its centre line.
	var along: float = to_ball.dot(direction)
	var span: float = reach()
	if along < 0.0 or along > span or span <= 0.0:
		return Vector2.ZERO
	var across: float = absf(to_ball.dot(Vector2(-direction.y, direction.x)))
	if across > half_width:
		return Vector2.ZERO

	# Fades along the stream by `fans.falloff` as an exponent, so 1 is a straight taper and higher
	# values keep the push strong near the mouth and drop it off a cliff further out.
	var distance_fade: float = pow(1.0 - clampf(along / span, 0.0, 1.0), maxf(0.0, t.fans_falloff))
	# ...and softens towards the edges rather than stopping dead at them, so a ball drifting out of
	# a stream slides out of it instead of falling off a shelf of air.
	var edge: float = 1.0 - clampf(across / half_width, 0.0, 1.0)
	var edge_fade: float = lerpf(clampf(t.fans_sustain, 0.0, 1.0), 1.0, edge)

	# Only the shortfall is made up: a fan pushes a slow ball and ignores a fast one.
	var speed_along: float = vx * direction.x + vy * direction.y
	var shortfall: float = maxf(0.0, t.fans_target_speed - speed_along)
	if shortfall <= 0.0:
		return Vector2.ZERO

	if not _in_sight(x, y, world):
		return Vector2.ZERO

	var rate: float = maxf(0.0, t.fans_strength) * strength_scale * multiplier
	return direction * (rate * shortfall * distance_fade * edge_fade)


## Can the air actually get there? Rock always stops it; glass only when `fans.blockedByGlass` is
## on, which is what lets a pane be a window the wind blows through or a lid that holds it back.
##
## Deliberately asks NOTHING about the ball. Where a stream reaches is a property of the air, so
## the per-ball glass rules stay out of it: if the rocky ball's pass-through mode opened a shadow
## the squishy ball still saw, the two would disagree about the shape of the stream, and a broken
## pane would move the stream for one form and not the other.
##
## Sampled along the segment from mouth to ball at a fixed spacing. Fixed on purpose: an adaptive
## step would sample the ghost and the real ball differently and the prediction would drift.
func _in_sight(x: float, y: float, world: StepWorld) -> bool:
	var block_glass: bool = TuningData.get_active().fans_blocked_by_glass
	var from: Vector2 = origin
	var span: Vector2 = Vector2(x, y) - from
	var distance: float = span.length()
	if distance <= SIGHT_STEP:
		return true
	var steps: int = int(ceil(distance / SIGHT_STEP))
	var step: Vector2 = span / float(steps)

	for shape: ShapeBody in world.shapes:
		if not world.is_shape_solid(shape):
			continue
		if shape.material == SurfaceKind.GLASS and not block_glass:
			continue
		for i: int in range(1, steps):
			var p: Vector2 = from + step * float(i)
			if shape.contains(p.x, p.y):
				return false
	return true


## Does this fan blow a ball upward enough to launch from? `grounded.launchFromFan` lets a player
## held up by a stream take a shot, so being carried is not a dead end.
func is_launchable_stream(x: float, y: float, form: BallForm, world: StepWorld) -> bool:
	var t: TuningData = TuningData.get_active()
	if not t.grounded_launch_from_fan:
		return false
	# Measured off straight up, which is -Y on screen.
	var angle: float = rad_to_deg(direction.angle_to(Vector2.UP))
	if absf(angle) > clampf(t.grounded_fan_launch_angle, 0.0, 89.0):
		return false
	# It has to actually be pushing this ball: a stream the rocky ball sinks through is no floor.
	return accel_for(x, y, 0.0, 0.0, form, world).length() > 0.0
