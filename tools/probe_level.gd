extends SceneTree

## Load a level's geometry, drop the ball on it, and report where it ends up.
##
##   godot --headless --path . --script tools/probe_level.gd -- res://levels/beat_01.tscn
##
## "It opened without errors" is not the same as "it is playable". A level can load perfectly and
## still drop the ball through the seam between two terrain pieces, spawn it inside a prop, or
## leave it rolling for ever down a slope nobody meant to be a slope. Those are invisible in the
## editor and obvious here.
##
## It builds the world from the scene's blocks and steps `BallSim` directly, rather than running
## the `Level` node. That is not a shortcut -- a `--script` SceneTree has no autoloads, so
## `Level._ready()` cannot run at all. Driving the simulation is what the headless tests already
## do, and it means this probe exercises the real step function with no scene tree, in about a
## second.
##
## This is the small version of the per-beat solution replay the roadmap wants in CI. The replay
## adds the intended shots; this only asks whether the level holds the ball up.

const DEFAULT_LEVEL: String = "res://levels/beat_01.tscn"
const SETTLE_STEPS: int = 900


func _initialize() -> void:
	var path: String = DEFAULT_LEVEL
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		printerr("could not load %s" % path)
		quit(1)
		return

	# Never added to the tree: `_ready` would need autoloads that do not exist here. Global
	# transforms still resolve, because they are computed from the parent chain rather than from
	# being in a tree.
	var scene: Node = packed.instantiate()

	var world: StepWorld = StepWorld.new()
	var blocks: Array[Node] = []
	_collect(scene, blocks)
	var next_id: int = 1
	for node: Node in blocks:
		var block: TerrainBlock = node as TerrainBlock
		if block == null or block.polygon.size() < 3:
			continue
		# Matches Level._build_world: a placement switched off is scenery. The probe has to agree
		# with the game about what collides, or it checks a level nobody will ever play.
		if not block.collides:
			continue
		world.shapes.append(block.build_shape(next_id))
		next_id += 1

	# Hazards, so "is this gear actually deadly?" has an answer that is not "play it and find out".
	var strips: int = 0
	var discs: int = 0
	for node: Node in blocks:
		var hazard: SpikesBlock = node as SpikesBlock
		if hazard == null:
			continue
		var built: SpikeStrip = hazard.build_strip(0)
		world.spikes.append(built)
		if built.is_disc():
			discs += 1
		else:
			strips += 1

	print("%s" % path.get_file())
	print("  %d solid pieces, bounds %s" % [world.shapes.size(), world.bounds()])
	print("  %d hazards (%d disc, %d strip)" % [world.spikes.size(), discs, strips])
	if world.shapes.is_empty():
		printerr("  NO COLLISION AT ALL -- every piece in this level is decoration")
		quit(1)
		return

	var spawn: Vector2 = _spawn_point(scene)
	var form: BallForm = BallForm.make(BallForm.SQUISHY)
	var state: BallState = BallState.new()
	state.x = spawn.x
	state.y = spawn.y - form.radius
	var start: Vector2 = Vector2(state.x, state.y)

	var step: float = TuningData.get_active().fixed_delta()
	var started: int = Time.get_ticks_msec()
	for _i: int in SETTLE_STEPS:
		BallSim.step_ball(state, form, world, step, null)
	print("  stepped %d frames in %.1fs" % [SETTLE_STEPS, float(Time.get_ticks_msec() - started) / 1000.0])

	var at: Vector2 = Vector2(state.x, state.y)
	var speed: float = Vector2(state.vx, state.vy).length()
	# There is no `grounded` flag on BallState: resting on something IS having a ground material,
	# which the step sets from the support probe and clears the moment the ball leaves a surface.
	var supported: bool = state.ground_material != SurfaceKind.NONE
	var seconds: float = float(SETTLE_STEPS) * step

	print("  ball %s -> %s after %.1fs" % [start, at, seconds])
	print("  resting: %s   speed %.1f px/s" % ["yes" if supported else "NO", speed])

	var bounds: Rect2 = world.bounds()
	if at.y > bounds.position.y + bounds.size.y + 200.0:
		printerr("  FELL THROUGH -- the ball ended below everything in the level")
		quit(1)
		return
	if not supported:
		printerr("  NEVER SETTLED -- still unsupported after %.0f seconds" % seconds)
		quit(1)
		return
	print("  ok -- the level holds the ball up")
	quit(0)


## Every TerrainBlock in the scene, including inside instanced piece scenes.
##
## Walks the tree rather than reading the `terrain` group, because group membership is added in
## `_ready` and nothing here is in a tree to have had one.
func _collect(node: Node, into: Array[Node]) -> void:
	if node is TerrainBlock or node is SpikesBlock:
		into.append(node)
	for child: Node in node.get_children():
		_collect(child, into)


func _spawn_point(scene: Node) -> Vector2:
	var found: Node = scene.find_child("Spawn", true, false)
	if found is Node2D:
		return (found as Node2D).global_position
	# No spawn marker: start above the middle of the level and let it fall.
	return Vector2.ZERO
