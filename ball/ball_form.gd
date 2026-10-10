class_name BallForm
extends RefCounted

## One ball type, reading its numbers live from the tuning. Ported from src/forms/BallForm.ts
## and the two form files beside it.
##
## The rule from the Phaser project holds: the simulation reads these fields and NEVER asks which
## form it is. A third ball means another entry here, not a branch in the physics.
##
## Fields are properties rather than copies so that editing the tuning in the Inspector changes
## the feel on the very next step.

const SQUISHY: int = 0
const ROCKY: int = 1

var id: int = SQUISHY
var label: String = "Squishy"


static func make(form_id: int) -> BallForm:
	var f: BallForm = BallForm.new()
	f.id = form_id
	f.label = "Rocky" if form_id == ROCKY else "Squishy"
	return f


static func next_id(form_id: int) -> int:
	return SQUISHY if form_id == ROCKY else ROCKY


var gravity_multiplier: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_gravity_multiplier if id == ROCKY else t.squishy_gravity_multiplier

var radius: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_radius if id == ROCKY else t.squishy_radius

var min_launch_speed: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_min_launch_speed if id == ROCKY else t.squishy_min_launch_speed

var max_launch_speed: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_max_launch_speed if id == ROCKY else t.squishy_max_launch_speed

var restitution_wall: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_restitution_wall if id == ROCKY else t.squishy_restitution_wall

var restitution_glass: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_restitution_glass if id == ROCKY else t.squishy_restitution_glass

var landing_friction: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_landing_friction if id == ROCKY else t.squishy_landing_friction

var air_drag: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_air_drag if id == ROCKY else t.squishy_air_drag

var stop_bounce_threshold: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_stop_bounce_threshold if id == ROCKY else t.squishy_stop_bounce_threshold

var squash_amount: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_squash_amount if id == ROCKY else t.squishy_squash_amount

var settles_on_landing: bool:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_settles_on_landing if id == ROCKY else t.squishy_settles_on_landing

var settle_bounce_height: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_settle_bounce_height if id == ROCKY else t.squishy_settle_bounce_height

var settle_hops: int:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_settle_hops if id == ROCKY else t.squishy_settle_hops

var landing_grip: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_landing_grip if id == ROCKY else t.squishy_landing_grip

## Only the rocky ball breaks glass. The physics asks this, never which form it is.
var breaks_glass: bool:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_breaks_glass if id == ROCKY else t.squishy_breaks_glass

var glass_break_min_impact: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_glass_break_min_impact if id == ROCKY else t.squishy_glass_break_min_impact

var glass_break_speed_keep: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_glass_break_speed_keep if id == ROCKY else t.squishy_glass_break_speed_keep

var rising_assist: bool:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_rising_assist if id == ROCKY else t.squishy_rising_assist

var mass: float:
	get:
		var t: TuningData = TuningData.get_active()
		return t.rocky_mass if id == ROCKY else t.squishy_mass
