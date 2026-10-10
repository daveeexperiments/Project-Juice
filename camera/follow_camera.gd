class_name FollowCamera
extends Camera2D

## Follows the ball on BOTH axes, Prototype D style. Ported from src/systems/CameraController.ts,
## taking the `followCameraX` branch (the shaft levels lock X; this one does not).
##
## Smooth lerp with look-ahead in the direction of travel, clamped to the level bounds so the
## view never shows the outside of the map.

@export var target_path: NodePath

var _target: Ball = null
var _bounds: Rect2 = Rect2()
var _look: Vector2 = Vector2.ZERO


func _ready() -> void:
	_target = get_node_or_null(target_path) as Ball
	# Godot's own smoothing is off: the Phaser follow is ported here so the feel matches.
	position_smoothing_enabled = false


func setup(level_bounds: Rect2, target: Ball) -> void:
	_bounds = level_bounds
	_target = target
	snap_to_target()


func _process(delta: float) -> void:
	if _target == null:
		return
	var t: TuningData = TuningData.get_active()
	var k: float = _frame_lerp(t.camera_follow_lerp, delta)

	var velocity: Vector2 = Vector2(_target.state.vx, _target.state.vy)
	var wanted: Vector2 = Vector2(
		clampf(velocity.x * t.camera_look_ahead, -t.camera_look_ahead_max, t.camera_look_ahead_max),
		clampf(maxf(0.0, velocity.y) * t.camera_look_ahead, 0.0, t.camera_look_ahead_max),
	)
	_look += (wanted - _look) * k

	var view: Vector2 = _view_size()
	var desired: Vector2 = Vector2(_target.state.x, _target.state.y - t.camera_climb_offset * view.y) + _look
	global_position = global_position.lerp(_clamp_to_bounds(desired, view), k)


func snap_to_target() -> void:
	if _target == null:
		return
	_look = Vector2.ZERO
	var view: Vector2 = _view_size()
	var t: TuningData = TuningData.get_active()
	var desired: Vector2 = Vector2(_target.state.x, _target.state.y - t.camera_climb_offset * view.y)
	global_position = _clamp_to_bounds(desired, view)


func _view_size() -> Vector2:
	return get_viewport_rect().size / maxf(0.01, zoom.x)


func _clamp_to_bounds(desired: Vector2, view: Vector2) -> Vector2:
	if _bounds.size == Vector2.ZERO:
		return desired
	var half: Vector2 = view * 0.5
	var out: Vector2 = desired
	if _bounds.size.x <= view.x:
		out.x = _bounds.position.x + _bounds.size.x * 0.5
	else:
		out.x = clampf(desired.x, _bounds.position.x + half.x, _bounds.end.x - half.x)
	if _bounds.size.y <= view.y:
		out.y = _bounds.position.y + _bounds.size.y * 0.5
	else:
		out.y = clampf(desired.y, _bounds.position.y + half.y, _bounds.end.y - half.y)
	return out


## Convert a per-frame (60fps) lerp factor into a frame-rate independent one. Ported verbatim.
func _frame_lerp(per_frame: float, delta: float) -> float:
	return 1.0 - pow(1.0 - clampf(per_frame, 0.0, 1.0), delta * 60.0)
