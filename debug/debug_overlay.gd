class_name DebugOverlay
extends Node2D

## F1 overlay. Ported in spirit from src/debug/DebugOverlay.ts and DesignOverlay.ts.
##
## Draws what the simulation actually believes, not what the art suggests: the collision edges
## the ball is tested against, which way each surface faces, and the live aim numbers. If the
## ball ever behaves oddly, this is the first thing to turn on.

const WALL_COLOUR: Color = Color("2f6fd8")
const GLASS_COLOUR: Color = Color("3fb0c8")
const UP_COLOUR: Color = Color("2fae4e")
const SIDE_COLOUR: Color = Color("d8a21a")
const DOWN_COLOUR: Color = Color("d9432b")
const VELOCITY_COLOUR: Color = Color("c2410c")
const DRAG_COLOUR: Color = Color("7c3aed")
## Glass lying flat on a wall: the rocky ball ignores it.
const WALL_GLASS_COLOUR: Color = Color("2f6fd8")
## Glass in the way -- a bridge, blocker or platform: the rocky ball smashes it.
const OBSTRUCTION_COLOUR: Color = Color("e07b1f")
const SPIKE_COLOUR: Color = Color("d01d3c")
const RESPAWN_COLOUR: Color = Color("2f8f4e")
const ROCKY_MODE_NAMES: Array = [
	"break obstructions only", "always break", "hard hits only", "never break", "pass through",
]

@export var ball_path: NodePath
@export var slingshot_path: NodePath

var _ball: Ball = null
var _slingshot: Slingshot = null
var _world: StepWorld = null
var _level: Level = null
var _label: Label = null


func _ready() -> void:
	z_index = 50
	_ball = get_node_or_null(ball_path) as Ball
	_slingshot = get_node_or_null(slingshot_path) as Slingshot
	_label = Label.new()
	_label.position = Vector2(8.0, 8.0)
	_label.add_theme_color_override("font_color", Color("141414"))
	_label.add_theme_font_size_override("font_size", 11)
	add_child(_label)
	visible = GameState.debug_visible
	GameState.debug_toggled.connect(_on_toggled)


func setup(world: StepWorld, level: Level = null) -> void:
	_world = world
	_level = level


func _on_toggled(on: bool) -> void:
	visible = on
	queue_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return
	queue_redraw()
	_label.text = _status_text()
	# The label is a child of a world-space node, so keep it pinned to the camera.
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		var view: Vector2 = get_viewport_rect().size / maxf(0.01, camera.zoom.x)
		_label.position = camera.global_position - view * 0.5 + Vector2(8.0, 8.0)


func _status_text() -> String:
	if _ball == null:
		return ""
	var s: BallState = _ball.state
	var lines: PackedStringArray = PackedStringArray()
	lines.append("form      %s" % _ball.form.label)
	lines.append("position  %.1f, %.1f" % [s.x, s.y])
	lines.append("velocity  %.0f, %.0f  (%.0f px/s)" % [s.vx, s.vy, s.speed()])
	lines.append("ground    %s  ny %.2f" % [SurfaceKind.to_name(s.ground_material), s.ground_ny])
	lines.append("grounded  %s   launchable %s" % [str(_ball.grounded), str(_ball.on_launchable_ground)])
	lines.append("settle    %d hops used" % s.settle_hops)
	var t: TuningData = TuningData.get_active()
	lines.append("rocky vs glass  %s" % ROCKY_MODE_NAMES[clampi(t.glass_rocky_mode, 0, 4)])
	lines.append("glass bounce    %s" % ("boost" if t.glass_bounce_mode == 1 else "reflect"))
	lines.append("bounce style    %s" % ("rising assist" if t.bounce_style == 1 else "physical"))
	lines.append("respawn   %s" % ("last flag" if GameState.has_flag else "spawn"))
	if _level != null and not _level.route_error.is_empty():
		lines.append("ROUTE     BLOCKED")
	if _slingshot != null and _slingshot.aiming:
		var aim: AimMath.AimVector = _slingshot.current_aim()
		lines.append("drag      %.0f, %.0f  (%.0f px)" % [aim.drag.x, aim.drag.y, aim.length])
		lines.append("aim       %.1f deg%s" % [AimMath.display_degrees(aim.direction), "  CLAMPED" if aim.clamped else ""])
	return "\n".join(lines)


func _draw() -> void:
	if _world == null:
		return

	# Collision edges, coloured by material, with a tick showing which way each one faces.
	for shape: ShapeBody in _world.shapes:
		# Glass is coloured by what it IS: cladding the rock ignores, or something in the way.
		var base: Color = WALL_COLOUR
		if shape.material == SurfaceKind.GLASS:
			base = WALL_GLASS_COLOUR if shape.glass_type == ShapeBody.GLASS_WALL else OBSTRUCTION_COLOUR
		if shape.broken:
			base = Color(base, 0.25)
		var count: int = shape.points.size()
		for i: int in count:
			var a: Vector2 = shape.points[i]
			var b: Vector2 = shape.points[(i + 1) % count]
			draw_line(a, b, base, 1.5)
			var edge: Vector2 = b - a
			if edge.length() < 12.0:
				continue
			var mid: Vector2 = (a + b) * 0.5
			var n: Vector2 = Vector2(-edge.y, edge.x).normalized()
			if shape.contains(mid.x + n.x * 2.0, mid.y + n.y * 2.0):
				n = -n
			draw_line(mid, mid + n * 8.0, _normal_colour(n.y), 1.5)

	if _ball == null:
		return
	var p: Vector2 = Vector2(_ball.state.x, _ball.state.y)
	# The true hitbox, which the art may not match.
	draw_arc(p, _ball.radius, 0.0, TAU, 24, Color(DOWN_COLOUR, 0.7), 1.0)
	# Velocity.
	draw_line(p, p + Vector2(_ball.state.vx, _ball.state.vy) * 0.08, VELOCITY_COLOUR, 2.0)
	# The contact normal of whatever is holding it up.
	if _ball.state.ground_material != SurfaceKind.NONE:
		draw_line(p, p + Vector2(0.0, _ball.state.ground_ny) * 22.0, UP_COLOUR, 2.0)
	# Spike hitboxes: the exact box each strip kills inside, which is the whole block.
	for strip: SpikeStrip in _world.spikes:
		var corners: PackedVector2Array = strip.corners()
		var closed: PackedVector2Array = corners.duplicate()
		closed.append(corners[0])
		draw_polyline(closed, SPIKE_COLOUR, 1.5)

	# Flag reach, and where the ball would come back to.
	for node: Node in get_tree().get_nodes_in_group(&"flags"):
		var flag: FlagBlock = node as FlagBlock
		if flag == null:
			continue
		var reach: float = flag.reach() + _ball.radius
		draw_arc(flag.global_position, reach, 0.0, TAU, 32, Color(RESPAWN_COLOUR, 0.5), 1.0)
	draw_arc(GameState.respawn_point, 10.0, 0.0, TAU, 20, RESPAWN_COLOUR, 2.0)
	draw_line(GameState.respawn_point + Vector2(-14.0, 0.0), GameState.respawn_point + Vector2(14.0, 0.0), RESPAWN_COLOUR, 2.0)

	# The raw drag, straight from the pointer.
	if _slingshot != null and _slingshot.aiming:
		var aim: AimMath.AimVector = _slingshot.current_aim()
		draw_line(p, p + aim.drag, DRAG_COLOUR, 1.5)


func _normal_colour(ny: float) -> Color:
	if ny <= -0.45:
		return UP_COLOUR
	if ny >= 0.12:
		return DOWN_COLOUR
	return SIDE_COLOUR
