class_name Slingshot
extends Node2D

## Aiming, the cradle and the launch. Ported from src/systems/Slingshot.ts.
##
## Input deliberately comes from `_input`, not from a click target: in Phaser the aim listens on
## the window rather than the canvas so a drag works over the letterbox and outside the browser.
## The Godot equivalent is taking the event stream and converting through the canvas transform,
## which also keeps the aim correct at any window size and under any camera shake.
##
## Aim is always the drag VECTOR (see AimMath). No angle is stored anywhere in this file.

signal shot_fired(power: float)
signal shot_refused()

const INK: Color = Color("141414")
const FAINT: Color = Color("8a867d")
const GHOST_FORK_LENGTH: float = 2.2

@export var ball_path: NodePath
@export var preview_path: NodePath

var aiming: bool = false
## Where the drag started and where the pointer is now, both in world space.
var _start: Vector2 = Vector2.ZERO
var _current: Vector2 = Vector2.ZERO
## Set while the ball is lifted into the fork; null-equivalent when not cradled.
var _cradled: bool = false
var _cradle_normal: Vector2 = Vector2.UP
var _cradle_surface: Vector2 = Vector2.ZERO
## Which edge of the aim range the drag last rested on, so the clamp cannot flicker.
var _last_edge: int = AimMath.EDGE_FROM

var _ball: Ball = null
var _preview: TrajectoryPreview = null
var _world: StepWorld = null


func _ready() -> void:
	z_index = 6
	_ball = get_node_or_null(ball_path) as Ball
	_preview = get_node_or_null(preview_path) as TrajectoryPreview


func setup(world: StepWorld) -> void:
	_world = world


var cradled: bool:
	get:
		return _cradled

## Where the ball is allowed to launch FROM. Grounded mode is the only mode in phase 1.
var can_launch: bool:
	get:
		if _ball == null:
			return false
		return _cradled or _ball.can_launch_now


func _input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_begin(_world_point(button.position))
			else:
				_release()
			return
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			# Right mouse cancels a drag, and switches form otherwise -- as in Phaser.
			if aiming:
				cancel()
			else:
				GameState.switch_form()
			return

	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and aiming:
		_current = _world_point(motion.position)
		# A drag that lost its button outside the window: end it rather than hang.
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_release()
		return

	if event.is_action_pressed("cancel_aim") and aiming:
		cancel()
	elif event.is_action_pressed("switch_form"):
		GameState.switch_form()


func _notification(what: int) -> void:
	# Losing focus mid-drag cancels cleanly rather than leaving the band stretched.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and aiming:
		cancel()


## Screen pixels to world space, through the canvas transform: correct at any window size, and
## unaffected by camera shake because the transform is the one actually used to draw.
func _world_point(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func _begin(at: Vector2) -> void:
	if _ball == null:
		return
	aiming = true
	_start = at
	_current = at
	_try_engage_cradle()


func cancel() -> void:
	if not aiming and not _cradled:
		return
	aiming = false
	_lower_from_cradle()
	if _preview != null:
		_preview.clear_line()
	queue_redraw()


func _release() -> void:
	if not aiming:
		return
	var aim: AimMath.AimVector = _aim()
	aiming = false
	if _preview != null:
		_preview.clear_line()

	var shot: Dictionary = _velocity_for(aim.drag)
	var allowed: bool = _ball != null and can_launch
	if not shot.is_empty() and allowed:
		_cradled = false
		_ball.launch((shot["velocity"] as Vector2).x, (shot["velocity"] as Vector2).y, shot["power"] as float)
		shot_fired.emit(shot["power"] as float)
	else:
		# Released while airborne, or with no real pull: the band goes slack.
		_lower_from_cradle()
		if not shot.is_empty():
			shot_refused.emit()
	queue_redraw()


## Lift the ball into the fork when a drag starts on a surface. Ported from engageCradle: the
## ball's state moves to the cradle point, so the preview and the launch both start from there.
func _try_engage_cradle() -> void:
	if _ball == null or not _ball.on_launchable_ground or _ball.held:
		return
	var normal: Vector2 = Vector2(0.0, -1.0)
	if _ball.state.ground_material != SurfaceKind.NONE:
		normal = Vector2(0.0, _ball.state.ground_ny).normalized()
		if normal == Vector2.ZERO:
			normal = Vector2(0.0, -1.0)
	_cradled = true
	_cradle_normal = normal
	_cradle_surface = Vector2(_ball.state.x, _ball.state.y) - normal * _ball.radius
	_ball.held = true
	_ball.state.vx = 0.0
	_ball.state.vy = 0.0
	var lift: float = _ball.radius * TuningData.get_active().slingshot_cradle_lift
	_ball.state.x += normal.x * lift
	_ball.state.y += normal.y * lift


func _lower_from_cradle() -> void:
	if not _cradled or _ball == null:
		return
	_cradled = false
	_ball.held = false


## The aim for the current drag, as a vector. Never an angle. Public so the debug overlay can
## show exactly what the slingshot is working from.
func current_aim() -> AimMath.AimVector:
	return _aim()


## The aim for the current drag, as a vector. Never an angle.
func _aim() -> AimMath.AimVector:
	var raw: Vector2 = _current - _start
	var snap: float = TuningData.get_active().slingshot_angle_snap_step if Input.is_action_pressed("aim_snap") else 0.0
	var aim: AimMath.AimVector = AimMath.aim_from_drag(raw, snap, _aim_range(), _last_edge)
	_last_edge = aim.edge
	return aim


func _aim_range() -> AimMath.AimRange:
	var arc: Array = AimMath.range_degrees()
	var rotate: float = 0.0
	if TuningData.get_active().slingshot_aim_relative_to_surface and _cradled:
		# Straight up is the zero case, so measure the turn from there and swing the whole arc.
		rotate = AimMath.display_degrees(_cradle_normal) - 90.0
	return AimMath.make_range(arc[0] as float, arc[1] as float, rotate)


## Launch velocity for a drag, or {} when the pull is inside the dead zone.
##
## Power comes from the drag's LENGTH and direction from its vector: the two never interact, so
## no direction is ever weaker or unreachable.
func _velocity_for(drag: Vector2) -> Dictionary:
	if _ball == null:
		return {}
	var t: TuningData = TuningData.get_active()
	var length: float = drag.length()
	if length < t.slingshot_dead_zone:
		return {}
	var power: float = clampf(
		(length - t.slingshot_dead_zone) / maxf(1.0, t.slingshot_drag_for_max_power - t.slingshot_dead_zone),
		0.0,
		1.0,
	)
	var max_speed: float = _ball.form.max_launch_speed
	var min_speed: float = minf(_ball.form.min_launch_speed, max_speed)
	var speed: float = lerpf(min_speed, max_speed, power)
	var u: Vector2 = -drag / length
	return {"velocity": u * speed, "power": power}


## Called every frame by the level: refresh the ghost line and the band.
func update_aim() -> void:
	if not aiming or _ball == null:
		queue_redraw()
		return
	var aim: AimMath.AimVector = _aim()
	var shot: Dictionary = _velocity_for(aim.drag)
	if shot.is_empty() or _preview == null or _world == null:
		if _preview != null:
			_preview.clear_line()
		queue_redraw()
		return

	# The ghost starts where the ball IS, updating every frame as it drifts.
	var from: Vector2 = Vector2(_ball.state.x, _ball.state.y)
	_preview.simulate(_ball.form, from, shot["velocity"] as Vector2, _world)
	# Greyed out when the shot cannot go.
	_preview.show_line(INK if can_launch else FAINT)
	queue_redraw()


func _draw() -> void:
	if not aiming or _ball == null:
		return
	var aim: AimMath.AimVector = _aim()
	if aim.length <= 0.0:
		return
	var t: TuningData = TuningData.get_active()
	var ball_pos: Vector2 = Vector2(_ball.state.x, _ball.state.y)
	var r: float = _ball.radius
	var pull: Vector2 = -aim.direction
	# The band takes the same colour as the ghost line, so "this shot will not go" reads the
	# same way in both places.
	var colour: Color = INK if can_launch else FAINT

	# The max-pull ring, so full power is visible rather than guessed.
	draw_arc(ball_pos, t.slingshot_drag_for_max_power, 0.0, TAU, 48, Color(colour, 0.18), 1.5)

	# The fork: anchored on the surface when cradled, trailing behind the ball in mid-air.
	var base: Vector2 = _cradle_surface if _cradled else ball_pos + pull * r * GHOST_FORK_LENGTH
	var tips: Vector2 = aim.direction.orthogonal() * r * 1.1
	draw_line(base - tips, ball_pos - tips, colour, 3.0)
	draw_line(base + tips, ball_pos + tips, colour, 3.0)
	# The band, stretched by the pull.
	draw_line(base - tips, ball_pos, Color(colour, 0.85), 2.0)
	draw_line(base + tips, ball_pos, Color(colour, 0.85), 2.0)
