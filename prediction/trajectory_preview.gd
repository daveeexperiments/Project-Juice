class_name TrajectoryPreview
extends Node2D

## The dashed ghost line. Ported from src/systems/TrajectoryPreview.ts.
##
## It runs the SAME `BallSim.step_ball` the real ball runs, with the same fixed dt, which is the
## only reason the prediction can be exact. The one difference is the policy: this one counts
## bounces and stops after its budget, where the ball's squashes and reports.
##
## Phase 1 predicts against static terrain, so no copy of the world is needed. When glass can
## break (phase 2) this takes a throwaway copy with its own broken set, as GhostTiles does in
## Phaser.

const MAX_STEPS: int = 600

var _points: PackedVector2Array = PackedVector2Array()
## Running path length at each point, so dashes can be spaced along the curve.
var _distances: PackedFloat32Array = PackedFloat32Array()
## Which bounce each point belongs to, for the per-bounce fade.
var _segments: PackedInt32Array = PackedInt32Array()
var _total_length: float = 0.0
var _colour: Color = Color("141414")
var _visible_line: bool = false

var _sim: BallState = BallState.new()
var _policy: PreviewPolicy = null


func _ready() -> void:
	_policy = PreviewPolicy.new()
	z_index = 5


## Predict a shot. Returns the path, so the tests can compare it with the real ball step by step.
func simulate(form: BallForm, from: Vector2, velocity: Vector2, world: StepWorld) -> PackedVector2Array:
	# A throwaway copy of the world: same geometry, its own set of predicted breaks. The ghost
	# can smash a pane and carry on through the gap without touching what the real ball sees.
	var ghost: StepWorld = world.ghost()
	_policy.ghost_world = ghost
	_points = PackedVector2Array()
	_distances = PackedFloat32Array()
	_segments = PackedInt32Array()
	_total_length = 0.0

	var t: TuningData = TuningData.get_active()
	_policy.segment = 0
	# The first collision, plus N further bounces.
	_policy.contacts_left = 1 + clampi(t.preview_bounces, 0, 5)

	_sim.x = from.x
	_sim.y = from.y
	_sim.vx = velocity.x
	_sim.vy = velocity.y
	# Launching always leaves the ground, exactly as Ball.launch does.
	_sim.ground_material = SurfaceKind.NONE
	_sim.ground_ny = 0.0
	_sim.spin = 0.0
	_sim.settle_hops = 0
	# Every prediction starts owing nothing, exactly as a fresh launch does.
	_sim.pending_lift = 0.0

	var dt: float = t.fixed_delta()
	var max_length: float = t.preview_length

	_points.append(from)
	_distances.append(0.0)
	_segments.append(0)

	for _i: int in MAX_STEPS:
		if _total_length >= max_length:
			break
		var px: float = _sim.x
		var py: float = _sim.y
		var segment: int = _policy.segment
		var keep_going: bool = BallSim.step_ball(_sim, form, ghost, dt, _policy)
		_total_length += Vector2(_sim.x - px, _sim.y - py).length()
		_points.append(Vector2(_sim.x, _sim.y))
		_distances.append(_total_length)
		_segments.append(segment)
		if not keep_going:
			break

	queue_redraw()
	return _points


func show_line(colour: Color) -> void:
	_colour = colour
	_visible_line = true
	queue_redraw()


func clear_line() -> void:
	_visible_line = false
	_points = PackedVector2Array()
	queue_redraw()


func _draw() -> void:
	if not _visible_line or _points.size() < 2 or _total_length <= 0.0:
		return
	var t: TuningData = TuningData.get_active()
	var spacing: float = maxf(2.0, t.preview_dash_spacing)
	var dash_len: float = clampf(t.preview_dash_length, 1.0, spacing)

	var start: float = 0.0
	while start < _total_length:
		var a: Dictionary = _point_at(start)
		var b: Dictionary = _point_at(minf(start + dash_len, _total_length))
		var along_fade: float = 1.0 - t.preview_fade * (start / _total_length)
		var bounce_fade: float = pow(1.0 - clampf(t.preview_bounce_fade, 0.0, 1.0), float(a["segment"]))
		var alpha: float = maxf(0.06, along_fade * bounce_fade)
		draw_line(a["point"] as Vector2, b["point"] as Vector2, Color(_colour, alpha), 3.0)
		start += spacing


## Walk the path to the point at distance `d` along it.
func _point_at(d: float) -> Dictionary:
	var seg: int = 0
	while seg < _points.size() - 2 and _distances[seg + 1] < d:
		seg += 1
	var a: Vector2 = _points[seg]
	var b: Vector2 = _points[mini(seg + 1, _points.size() - 1)]
	var da: float = _distances[seg]
	var db: float = _distances[mini(seg + 1, _distances.size() - 1)]
	var t: float = (d - da) / (db - da) if db > da else 0.0
	return {
		"point": a + (b - a) * t,
		"segment": _segments[mini(seg + 1, _segments.size() - 1)],
	}


## Counts bounces and stops when the budget runs out. The ghost's only difference from the ball.
class PreviewPolicy extends StepPolicy:
	var contacts_left: int = 1
	var segment: int = 0
	## The throwaway world this prediction is running against.
	var ghost_world: StepWorld = null

	func on_contact(contact: Contact) -> bool:
		if contact.broke_glass:
			# The pane is gone and the ball carries straight on: not a bounce, so the budget is
			# untouched and the line keeps its colour.
			return true
		if not contact.is_impact:
			# A gentle contact: settling onto something ends the line, brushing a wall does not.
			return not contact.landing
		segment += 1
		contacts_left -= 1
		return contacts_left > 0

	## Predicted breaks are marked in the ghost world only, so the line shows the route it opens.
	func on_glass(shape: ShapeBody, _state: BallState, _impact_speed: float) -> int:
		if ghost_world != null:
			ghost_world.predicted_broken[shape.id] = true
		return StepPolicy.GLASS_BREAK

	## The ghost stops dead on spikes. Seeing the line end there is the warning, and it is true:
	## the real ball would be sent back to its flag at that point.
	func on_spikes(_strip: SpikeStrip, _state: BallState) -> void:
		contacts_left = 0
