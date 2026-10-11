class_name FollowCamera
extends Camera2D

## Follows the ball on BOTH axes, Prototype D style. Ported from src/systems/CameraController.ts,
## taking the `followCameraX` branch (the shaft levels lock X; this one does not).
##
## Smooth lerp with look-ahead in the direction of travel, clamped to the level bounds so the
## view never shows the outside of the map.

@export var target_path: NodePath
## The ghost line to frame while aiming. Optional: with none, the camera just follows.
@export var preview_path: NodePath

var _target: Ball = null
var _preview: TrajectoryPreview = null
var _bounds: Rect2 = Rect2()
var _look: Vector2 = Vector2.ZERO
## Eased zoom, so pulling back to show a shot is a move rather than a jump.
var _zoom: float = 1.0


func _ready() -> void:
	_target = get_node_or_null(target_path) as Ball
	_preview = get_node_or_null(preview_path) as TrajectoryPreview
	if _preview == null:
		# Fall back to the sibling every level already has. Looking it up rather than requiring the
		# path means existing level scenes get the aim framing without being edited, and a level
		# that genuinely has no preview still works -- the framing is simply skipped.
		var parent: Node = get_parent()
		if parent != null:
			_preview = parent.get_node_or_null(^"TrajectoryPreview") as TrajectoryPreview
	# Godot's own smoothing is off: the Phaser follow is ported here so the feel matches.
	position_smoothing_enabled = false
	_zoom = zoom.x


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

	# Pull back far enough to hold the whole shot, then settle back in once it is away.
	var framing: Rect2 = _aim_framing()
	_apply_zoom(_zoom_for(framing), delta, t)

	var view: Vector2 = _view_size()
	var desired: Vector2 = Vector2(_target.state.x, _target.state.y - t.camera_climb_offset * view.y) + _look

	if framing.size != Vector2.ZERO:
		# Centre between the ball and the far end of the line rather than on the ball. Keeping the
		# ball centred while zoomed out wastes half the view on where the shot is coming FROM.
		var middle: Vector2 = framing.get_center()
		desired = desired.lerp(middle, clampf(t.camera_aim_recentre, 0.0, 1.0))

	global_position = global_position.lerp(_clamp_to_bounds(desired, view), k)


## The box to keep on screen while aiming: the ghost line plus the ball. Empty when not aiming.
func _aim_framing() -> Rect2:
	if _preview == null:
		return Rect2()
	var line: Rect2 = _preview.line_bounds()
	if line.size == Vector2.ZERO:
		return Rect2()
	return line.expand(Vector2(_target.state.x, _target.state.y))


## How far out to pull so `framing` fits, as a zoom factor. 1 is the default view.
func _zoom_for(framing: Rect2) -> float:
	var t: TuningData = TuningData.get_active()
	if framing.size == Vector2.ZERO:
		return 1.0
	var screen: Vector2 = get_viewport_rect().size
	var wanted: Vector2 = framing.size + Vector2.ONE * (t.camera_aim_margin * 2.0)
	# Zoom BELOW 1 shows more. Take whichever axis needs the most room, and never zoom IN past the
	# resting view -- a short drag should not shove the camera into the ball's face.
	var fit: float = minf(screen.x / maxf(1.0, wanted.x), screen.y / maxf(1.0, wanted.y))
	return clampf(fit, maxf(0.05, t.camera_aim_zoom_min), 1.0)


func _apply_zoom(wanted: float, delta: float, t: TuningData) -> void:
	var k: float = _frame_lerp(t.camera_zoom_lerp, delta)
	_zoom += (wanted - _zoom) * k
	zoom = Vector2(_zoom, _zoom)


func snap_to_target() -> void:
	if _target == null:
		return
	_look = Vector2.ZERO
	_zoom = 1.0
	zoom = Vector2.ONE
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
