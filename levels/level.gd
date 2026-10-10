class_name Level
extends Node2D

## Runs a level. Ported from the parts of src/scenes/Game.ts and src/systems/LevelLoader.ts that
## phases 1 and 2 cover: building the world from the blocks in the scene, driving the fixed step,
## the aim slow-motion, glass breaking and respawn, spikes, flags, and the reachability check.
##
## The simulation advances in `_physics_process`, which Godot calls at the rate set in the
## project (120/s, matching the Phaser fixed step). Visuals and aiming happen in `_process`.

signal glass_broke(shape: ShapeBody)
signal ball_spiked()

@onready var ball: Ball = $Ball
@onready var slingshot: Slingshot = $Slingshot
@onready var preview: TrajectoryPreview = $TrajectoryPreview
@onready var camera: FollowCamera = $FollowCamera
@onready var overlay: DebugOverlay = $DebugOverlay
@onready var shatter: ShatterEffect = $ShatterEffect

var world: StepWorld = null
## The eased slow-motion factor: 1 normally, easing towards the aim time scale while aiming.
var _aim_scale: float = 1.0
## Which block each shape came from, so breaking one can hide its node.
var _block_of: Dictionary = {}
## Shapes waiting to come back: id -> seconds left.
var _broken: Dictionary = {}
## Counts down after a spike hit; spikes cannot trigger again until it reaches zero.
var _spike_grace: float = 0.0
var _frozen: bool = false
var _route_error: String = ""
var _error_label: Label = null


func _ready() -> void:
	_build_world()
	GlassRules.classify(world.shapes)

	GameState.reset_for_level(_spawn_point())
	ball.setup(world, GameState.respawn_point - Vector2(0.0, ball.radius))
	slingshot.setup(world)
	camera.setup(world.bounds(), ball)
	overlay.setup(world, self)
	ball.spiked.connect(_on_spiked)
	ball.glass_broken.connect(break_glass)

	_check_route_open()


# ---------------------------------------------------------------- building

## Build the collision world from the block scenes in the tree.
##
## Geometry comes from the scene, not from code: a TerrainBlock (or a Glass block, which is the
## same script with `material` preset) becomes a solid; a SpikesBlock becomes a hazard strip plus
## a solid slab, because a strip is a piece of wall with a toothed face.
func _build_world() -> void:
	world = StepWorld.new()
	var next_id: int = 1

	for node: Node in get_tree().get_nodes_in_group(&"terrain"):
		var block: TerrainBlock = node as TerrainBlock
		if block == null or block.polygon.size() < 3:
			continue
		var shape: ShapeBody = block.build_shape(next_id)
		world.shapes.append(shape)
		_block_of[next_id] = block
		next_id += 1

	for node: Node in get_tree().get_nodes_in_group(&"spikes"):
		var block: SpikesBlock = node as SpikesBlock
		if block == null:
			continue
		var strip: SpikeStrip = block.build_strip(next_id)
		world.spikes.append(strip)
		# ...and its solid body, so the airflow, the prediction and the route check see a wall.
		var slab: ShapeBody = ShapeBody.new(next_id + 100000, strip.corners(), SurfaceKind.WALL, 0.0)
		slab.spike_base = true
		world.shapes.append(slab)
		next_id += 1


func _spawn_point() -> Vector2:
	for node: Node in get_tree().get_nodes_in_group(&"spawn"):
		var block: SpawnBlock = node as SpawnBlock
		if block != null:
			return block.respawn_point()
	return Vector2(270.0, 200.0)


# ---------------------------------------------------------------- the loop

func _physics_process(delta: float) -> void:
	if _frozen:
		return
	var dt: float = delta * TuningData.get_active().world_time_scale * _aim_scale
	if _spike_grace > 0.0:
		_spike_grace -= dt
	ball.step(dt)
	world.time += dt
	_check_flags()
	_tick_glass_respawn(dt)


func _process(delta: float) -> void:
	_update_aim_scale(delta)
	if Input.is_action_just_pressed("toggle_debug"):
		GameState.toggle_debug()
	if Input.is_action_just_pressed("restart_level"):
		return_to_flag()
	slingshot.update_aim()
	ball.sync_visuals(delta)


## Aiming SLOWS the world; it never freezes it, so anything that pushes the ball keeps pushing
## while the shot is lined up. Eased rather than snapped. Ported from Game.applyLiveWorldTuning.
func _update_aim_scale(delta: float) -> void:
	var t: TuningData = TuningData.get_active()
	var target: float = clampf(t.slingshot_aim_time_scale, 0.05, 1.0) if slingshot.aiming else 1.0
	var ramp: float = maxf(0.001, t.slingshot_aim_ramp_seconds)
	var step: float = delta / ramp
	_aim_scale += clampf(target - _aim_scale, -step, step)


# ---------------------------------------------------------------- glass

## Shatter a pane: it stops colliding at once, and comes back later if it is set to.
func break_glass(shape: ShapeBody) -> void:
	if shape.broken:
		return
	shape.broken = true
	var block: TerrainBlock = _block_of.get(shape.id, null) as TerrainBlock
	if block != null:
		block.visible = false
	if shatter != null:
		shatter.burst(shape.bounds.get_center(), shape.bounds.size)
	var seconds: float = _respawn_seconds_for(shape)
	if seconds > 0.0:
		_broken[shape.id] = seconds
	glass_broke.emit(shape)


func _respawn_seconds_for(shape: ShapeBody) -> float:
	var override: float = TuningData.get_active().glass_respawn_seconds_override
	return override if override >= 0.0 else shape.respawn_seconds


## Tick the shattered panes back in. Nothing reappears on top of the ball.
func _tick_glass_respawn(dt: float) -> void:
	if _broken.is_empty():
		return
	for id: int in _broken.keys():
		var left: float = (_broken[id] as float) - dt
		if left > 0.0:
			_broken[id] = left
			continue
		var shape: ShapeBody = _shape_by_id(id)
		if shape == null:
			_broken.erase(id)
			continue
		# Wait until the ball is clear, or a pane would reappear around it.
		shape.broken = false
		var overlapping: bool = shape.contact(ball.state.x, ball.state.y, ball.radius) != null
		shape.broken = true
		if overlapping:
			_broken[id] = 0.25
			continue
		shape.broken = false
		var block: TerrainBlock = _block_of.get(id, null) as TerrainBlock
		if block != null:
			block.visible = true
		_broken.erase(id)


func _shape_by_id(id: int) -> ShapeBody:
	for shape: ShapeBody in world.shapes:
		if shape.id == id:
			return shape
	return null


# ---------------------------------------------------------------- spikes and flags

func _on_spiked(_strip: SpikeStrip) -> void:
	if _spike_grace > 0.0 or _frozen:
		return
	var t: TuningData = TuningData.get_active()
	_spike_grace = t.spikes_grace_seconds + t.spikes_respawn_delay
	slingshot.cancel()
	ball.visible = false
	_frozen = true
	ball_spiked.emit()
	if shatter != null:
		shatter.burst(Vector2(ball.state.x, ball.state.y), Vector2(16.0, 16.0))
	await get_tree().create_timer(t.spikes_respawn_delay).timeout
	_frozen = false
	ball.visible = true
	return_to_flag()


## Raise any flag the ball has reached. The most recent one is where it comes back to.
func _check_flags() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"flags"):
		var flag: FlagBlock = node as FlagBlock
		if flag == null or flag.activated:
			continue
		var reach: float = flag.reach() + ball.radius
		if Vector2(ball.state.x, ball.state.y).distance_to(flag.global_position) <= reach:
			flag.activated = true
			GameState.respawn_point = flag.respawn_point()


## Back to the last raised flag (or the spawn), with everything reset. `R` does this too.
func return_to_flag() -> void:
	slingshot.cancel()
	ball.setup(world, GameState.respawn_point - Vector2(0.0, ball.radius))
	_restore_all_glass()
	camera.snap_to_target()


func _restore_all_glass() -> void:
	for shape: ShapeBody in world.shapes:
		if shape.broken:
			shape.broken = false
			var block: TerrainBlock = _block_of.get(shape.id, null) as TerrainBlock
			if block != null:
				block.visible = true
	_broken.clear()


# ---------------------------------------------------------------- reachability

## Rock must never close the route. Ported from Level.checkRouteOpen.
##
## Every pane the rocky ball could get through is treated as open, then the level is flooded from
## the spawn: if the last flag cannot be reached even then, rock is at fault and the level is
## broken. Glass set to "never" counts as solid; spikes do not block, because they are flown
## around rather than sealing anything.
func _check_route_open() -> void:
	if not OS.is_debug_build():
		return
	# A flag is "reached" when the ball could get close enough to RAISE it, not when the flood
	# reaches the foot of the pole -- the foot sits inside whatever the flag stands on, and is
	# solid by construction.
	var targets: Array[Dictionary] = []
	var names: PackedStringArray = PackedStringArray()
	for node: Node in get_tree().get_nodes_in_group(&"flags"):
		var flag: FlagBlock = node as FlagBlock
		if flag == null:
			continue
		targets.append({
			"at": flag.global_position - Vector2(0.0, ball.radius),
			"reach": flag.reach() + ball.radius,
		})
		names.append(flag.name)
	if targets.is_empty():
		return

	var start: Vector2 = GameState.respawn_point - Vector2(0.0, ball.radius)
	var missed: PackedInt32Array = RouteCheck.unreachable(world.shapes, start, targets, world.bounds().grow(32.0))
	if missed.is_empty():
		return

	var blocked_names: PackedStringArray = PackedStringArray()
	for index: int in missed:
		blocked_names.append(names[index])
	_show_route_error(
		"BLOCKED BY ROCK: %s cannot be reached from the spawn,
" % ", ".join(blocked_names)
		+ "even with every breakable pane removed. Only glass may block a path."
	)


func _show_route_error(message: String) -> void:
	_route_error = message
	push_error("Level: " + message)
	if _error_label != null:
		return
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_error_label = Label.new()
	_error_label.text = "LEVEL BLOCKED\n\n" + message
	_error_label.position = Vector2(16.0, 60.0)
	_error_label.add_theme_color_override("font_color", Color.WHITE)
	_error_label.add_theme_color_override("font_outline_color", Color("b3231a"))
	_error_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_error_label)


var route_error: String:
	get:
		return _route_error
