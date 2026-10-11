class_name FollowCamera
extends Camera2D

## Follows the ball on BOTH axes, Prototype D style. Ported from src/systems/CameraController.ts,
## taking the `followCameraX` branch (the shaft levels lock X; this one does not).
##
## Smooth lerp with look-ahead in the direction of travel, clamped to the level bounds so the
## view never shows the outside of the map.

@export var target_path: NodePath
## The slingshot to read the aim from. Optional: with none, the camera just follows the ball.
@export var slingshot_path: NodePath

var _target: Ball = null
var _slingshot: Slingshot = null
var _bounds: Rect2 = Rect2()
var _look: Vector2 = Vector2.ZERO
## Eased zoom, so pulling back to show a shot is a move rather than a jump.
var _zoom: float = 1.0
## Eased pull strength, 0 to 1. Everything the aiming camera does is a function of this one
## number, which is why it cannot argue with itself: one smooth input, one smooth response.
var _aim_power: float = 0.0


func _ready() -> void:
	_target = get_node_or_null(target_path) as Ball
	_slingshot = get_node_or_null(slingshot_path) as Slingshot
	if _slingshot == null:
		# Fall back to the sibling every level already has. Looking it up rather than requiring the
		# path means existing level scenes get the aim framing without being edited, and a level
		# with no slingshot still works -- the framing is simply skipped.
		var parent: Node = get_parent()
		if parent != null:
			_slingshot = parent.get_node_or_null(^"Slingshot") as Slingshot
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

	var pulling: bool = _slingshot != null and _slingshot.aiming
	_aim_power += (_wanted_power() - _aim_power) * _frame_lerp(t.camera_aim_lerp, delta)
	# The aim lead eases slowly so the mouse cannot whip the view about; the flight look-ahead
	# keeps the follow's own rate, because during a shot the camera should keep up with the ball.
	var lead_rate: float = t.camera_aim_lerp if pulling or _aim_power > 0.01 else t.camera_follow_lerp
	_look += (_wanted_lead(t) - _look) * _frame_lerp(lead_rate, delta)
	_zoom_towards(lerpf(1.0, maxf(0.05, t.camera_aim_zoom_min), _aim_power), t, delta)

	var desired: Vector2 = Vector2(_target.state.x, _target.state.y) + _look
	# The climb offset uses the RESTING view, not the live one. Taken from the zoomed view it grows
	# with the pull-back, so simply opening the view would drag the framing upward at the same
	# time -- two movements for one input, which is most of what read as the camera fighting back.
	desired.y -= t.camera_climb_offset * get_viewport_rect().size.y

	var k: float = _frame_lerp(t.camera_follow_lerp, delta)
	global_position = global_position.lerp(_clamp_to_bounds(desired, _view_size()), k)


## How hard the shot is being pulled, 0 to 1. The same curve the launch itself uses.
##
## Driven by the DRAG rather than by the ghost line, and that is the whole fix. The line is
## re-simulated every frame and its extent jumps whenever the ghost clips a wall or spends its
## bounce budget; a camera framing it chases a signal that moves on its own. The drag is the
## player's hand. It only changes when they move, it changes smoothly, and leading it reads as the
## camera anticipating rather than arguing.
func _wanted_power() -> float:
	if _slingshot == null or not _slingshot.aiming or _slingshot.last_aim == null:
		return 0.0
	var t: TuningData = TuningData.get_active()
	var length: float = _slingshot.last_aim.length
	var span: float = maxf(1.0, t.slingshot_drag_for_max_power - t.slingshot_dead_zone)
	return clampf((length - t.slingshot_dead_zone) / span, 0.0, 1.0)


## Where to look: along the shot while aiming, along the travel while flying.
func _wanted_lead(t: TuningData) -> Vector2:
	if _slingshot != null and _slingshot.aiming and _slingshot.last_aim != null:
		# Out along the launch direction, as far as the pull deserves. Both terms are smooth in the
		# mouse position, so the target never jitters on its own.
		return _slingshot.last_aim.direction * (_aim_power * t.camera_aim_lead)

	var velocity: Vector2 = Vector2(_target.state.vx, _target.state.vy)
	return Vector2(
		clampf(velocity.x * t.camera_look_ahead, -t.camera_look_ahead_max, t.camera_look_ahead_max),
		clampf(maxf(0.0, velocity.y) * t.camera_look_ahead, 0.0, t.camera_look_ahead_max),
	)


func _zoom_towards(wanted: float, t: TuningData, delta: float) -> void:
	# Never open the view wider than the level itself. Past that point `_clamp_to_bounds` stops
	# following the ball and parks on the middle of the map, which lands as a jump to somewhere the
	# player is not -- and on a level with one stray piece far out, somewhere very far away.
	_zoom = maxf(_zoom_floor(), _zoom + (wanted - _zoom) * _frame_lerp(t.camera_zoom_lerp, delta))
	zoom = Vector2(_zoom, _zoom)


## The most zoomed-OUT the view may get and still fit inside the level.
func _zoom_floor() -> float:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return 0.05
	var screen: Vector2 = get_viewport_rect().size
	return minf(1.0, maxf(screen.x / _bounds.size.x, screen.y / _bounds.size.y))


func snap_to_target() -> void:
	if _target == null:
		return
	_look = Vector2.ZERO
	_aim_power = 0.0
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
