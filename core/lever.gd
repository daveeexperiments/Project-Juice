class_name Lever
extends RefCounted

## A plank balanced on a pivot. Ported from the lever actor in src/systems/Actors.ts.
##
## The puzzle is the mass difference: `lever.massRocky` 6 against `lever.massSquishy` 1 means the
## rocky ball tips a plank the squishy ball barely disturbs, so the same seesaw is a switch for one
## ball and a floor for the other. (Those two numbers match `squishy.mass` and `rocky.mass`
## exactly in the shipped tuning, but they are separate keys in Phaser and are kept separate here:
## a lever that needed its own balance should not have to change what a ball weighs everywhere
## else.)
##
## LIKE A CABLE, IT HOLDS STATE THE BALL CAN CHANGE -- an angle and an angular velocity -- so
## `StepWorld.ghost()` copies it rather than sharing it, or drawing a preview would tip the real
## plank and aiming would rearrange the level.
##
## HOW MUCH OF THIS IS A TRANSCRIPTION: the structure is, the arithmetic is a reconstruction. The
## eight `lever.*` keys name a torque-balance model unambiguously -- masses, a plank mass, angular
## damping, pivot friction, a counterweight, a torque scale and an impact strength are the parts
## list of exactly one kind of simulation -- but they do not pin down the units, and the Phaser
## source was not reachable when this was written. What is certainly right: a heavier ball tips it
## further, a counterweight opposes that, damping and friction settle it, and an impact kicks it.
## What wants checking against the original: whether `pivotFriction` is a torque (as here) or an
## angular deceleration, and whether `torqueScale` is doing the work of a units bridge.

## The smallest moment of inertia we will divide by, so a silly plank mass cannot explode.
const MIN_INERTIA: float = 0.001

var id: int = 0
## The hinge, in world space.
var pivot: Vector2 = Vector2.ZERO
## Half the plank's length, so the ends sit at +/- this along it.
var half_length: float = 90.0
## Collision radius of the plank itself.
var thickness: float = 6.0
## How far it may tilt either way, in radians. A seesaw, not a windmill: without a stop a plank
## with a ball on one end would simply spin, which is not what any of the tuning describes.
var max_tilt: float = deg_to_rad(35.0)

## Where it is now: 0 is level, positive tips the B end (the +X side at rest) downwards.
var angle: float = 0.0
## ...and how fast it is turning, in radians per second.
var angular_velocity: float = 0.0

## Torque accumulated this step by the ball resting on or striking the plank. Cleared every step,
## so a ball that leaves stops loading it.
var _applied_torque: float = 0.0


func _init(
	lever_id: int,
	at: Vector2,
	plank_half_length: float = 90.0,
	plank_thickness: float = 6.0,
	tilt_limit_degrees: float = 35.0,
) -> void:
	id = lever_id
	pivot = at
	half_length = maxf(1.0, plank_half_length)
	thickness = maxf(1.0, plank_thickness)
	max_tilt = deg_to_rad(clampf(tilt_limit_degrees, 0.0, 89.0))


## The plank's direction at its current angle, from the pivot towards the B end.
func along() -> Vector2:
	return Vector2(cos(angle), sin(angle))


## The two ends, in world space.
func end_a() -> Vector2:
	return pivot - along() * half_length


func end_b() -> Vector2:
	return pivot + along() * half_length


## Resistance to being turned: a uniform rod about its centre, I = m(2L)^2/12 = mL^2/3.
func inertia() -> float:
	var mass: float = maxf(0.0, TuningData.get_active().lever_plank_mass)
	return maxf(MIN_INERTIA, mass * half_length * half_length / 3.0)


## How fast the plank's surface is moving at a point on it, which is what lets a tipping plank
## carry a ball rather than slide out from under it.
func surface_velocity_at(point: Vector2) -> Vector2:
	var arm: Vector2 = point - pivot
	# v = omega x r, which in 2D is omega * perpendicular(r).
	return Vector2(-arm.y, arm.x) * angular_velocity


# ---------------------------------------------------------------- the plank itself

## Advance the plank by one step. Called once per `step_ball`, never per substep.
func step(dt: float) -> void:
	var t: TuningData = TuningData.get_active()
	var torque: float = _applied_torque
	_applied_torque = 0.0

	# A counterweight hung on the A end, pulling that side down for ever.
	if absf(t.lever_counterweight) > 0.0:
		torque -= t.lever_counterweight * t.world_gravity * half_length * t.lever_torque_scale

	angular_velocity += (torque / inertia()) * dt

	# Damping is proportional and settles the swing; pivot friction is a constant drag that brings
	# it to a dead stop instead of letting it creep for ever.
	var keep: float = maxf(0.0, 1.0 - maxf(0.0, t.lever_angular_damping) * dt)
	angular_velocity *= keep
	var drag: float = maxf(0.0, t.lever_pivot_friction) / inertia() * dt
	if absf(angular_velocity) <= drag:
		angular_velocity = 0.0
	else:
		angular_velocity -= signf(angular_velocity) * drag

	angle += angular_velocity * dt
	# Hitting a stop ends the motion rather than bouncing off it: a seesaw thumps down.
	if angle > max_tilt:
		angle = max_tilt
		angular_velocity = minf(angular_velocity, 0.0)
	elif angle < -max_tilt:
		angle = -max_tilt
		angular_velocity = maxf(angular_velocity, 0.0)


## Load the plank with a ball sitting on it at `point`, which is what makes a lever a scale.
## Torque is mass x gravity x the arm, so standing further out does more.
func load_from(point: Vector2, form: BallForm) -> void:
	var t: TuningData = TuningData.get_active()
	var arm: float = (point - pivot).dot(along())
	_applied_torque += mass_of(form) * t.world_gravity * arm * t.lever_torque_scale


## Kick the plank with an impact, on top of the standing load.
func strike(point: Vector2, form: BallForm, impact_speed: float) -> void:
	var t: TuningData = TuningData.get_active()
	var arm: float = (point - pivot).dot(along())
	_applied_torque += mass_of(form) * impact_speed * arm * t.lever_impact_strength * t.lever_torque_scale


## What this ball weighs AS FAR AS A LEVER IS CONCERNED. Deliberately the lever's own keys rather
## than `form.mass`, which is what the rest of the game uses.
static func mass_of(form: BallForm) -> float:
	var t: TuningData = TuningData.get_active()
	return t.lever_mass_rocky if form.id == BallForm.ROCKY else t.lever_mass_squishy


# ---------------------------------------------------------------- the ball against the plank

## The closest point on the plank to a ball, as {point, normal, depth, arm}, or {} when clear.
func contact_for(cx: float, cy: float, r: float) -> Dictionary:
	var reach: float = r + thickness
	var direction: Vector2 = along()
	var to_ball: Vector2 = Vector2(cx - pivot.x, cy - pivot.y)
	# Project onto the plank and clamp to its ends, exactly as a segment test does.
	var arm: float = clampf(to_ball.dot(direction), -half_length, half_length)
	var point: Vector2 = pivot + direction * arm
	var offset: Vector2 = Vector2(cx - point.x, cy - point.y)
	var distance: float = offset.length()
	if distance >= reach:
		return {}

	var normal: Vector2 = Vector2.UP if distance < 0.00001 else offset / distance
	return {"point": point, "normal": normal, "depth": reach - distance, "arm": arm}


## Everything the prediction could change.
func snapshot() -> Dictionary:
	return {"angle": angle, "angular_velocity": angular_velocity, "torque": _applied_torque}


func restore(saved: Dictionary) -> void:
	angle = saved["angle"] as float
	angular_velocity = saved["angular_velocity"] as float
	_applied_torque = saved["torque"] as float


## A copy the prediction can tip about without touching the real plank.
func ghost_copy() -> Lever:
	var copy: Lever = Lever.new(id, pivot, half_length, thickness, rad_to_deg(max_tilt))
	copy.angle = angle
	copy.angular_velocity = angular_velocity
	copy._applied_torque = _applied_torque
	return copy
