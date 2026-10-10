extends SceneTree

## Headless test runner.
##
##   godot --headless --path . --script tests/run_tests.gd
##
## What it checks, and why:
##
##  1. PREDICTION EXACTNESS. The ghost line and the real ball run the same `BallSim.step_ball`,
##     so a shot predicted and then taken must match step for step -- in every glass mode, both
##     bounce modes and with the rising assist on and off. Anything other than 0.0 divergence
##     means the two have been allowed to drift apart, which is the one bug this architecture
##     exists to prevent.
##  2. AIM SWEEP. A drag taken right around the circle, both ways, must move the aim smoothly:
##     no sample where the pointer moved and the direction did not, and no jump bigger than the
##     pointer's own step. The regression test for the sticking bug.
##  3. GLASS MODES. Each rocky-vs-glass mode does what it says: break, land dead, pass through.
##  4. SPIKES. Triggered from every side and at maximum speed, including a sweep that would skip
##     a thin strip with a point-in-time check.
##  5. RESPAWN. Always the most recently raised flag.

const TOLERANCE: float = 0.0001

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	print("Project Juice -- phase 2 tests\n")
	var world: StepWorld = _build_test_world()

	print(" prediction")
	_test_prediction(world, BallForm.SQUISHY, "reflect, physical", {})
	_test_prediction(world, BallForm.SQUISHY, "boost", {"glass_bounce_mode": 1})
	_test_prediction(world, BallForm.SQUISHY, "rising assist", {"bounce_style": 1})
	_test_prediction(world, BallForm.SQUISHY, "boost + rising", {"glass_bounce_mode": 1, "bounce_style": 1})
	for mode: int in 5:
		_test_prediction(world, BallForm.ROCKY, "rocky %s" % _mode_name(mode), {"glass_rocky_mode": mode})

	print("\n aim")
	_test_aim_sweep(0.0)
	_test_aim_sweep(5.0)
	_test_aim_sweep_within_range()

	print("\n glass modes")
	_test_glass_modes(world)

	print("\n spikes and respawn")
	_test_spikes_every_side()
	_test_spike_sweep_at_speed()
	_test_respawn_uses_latest_flag()

	print("\n reachability")
	_test_route_check()

	print("\n settling")
	_test_settle_comes_to_rest(world)

	_report_unmapped()

	print("")
	if _failures == 0:
		print("PASSED  %d checks" % _checks)
	else:
		printerr("FAILED  %d of %d checks" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


# ---------------------------------------------------------------- prediction

func _test_prediction(world: StepWorld, form_id: int, label: String, settings: Dictionary) -> void:
	var saved: Dictionary = _apply(settings)
	var form: BallForm = BallForm.make(form_id)
	var shots: Array[Dictionary] = [
		{"from": Vector2(250.0, 1150.0), "v": Vector2(320.0, -900.0)},
		{"from": Vector2(300.0, 1000.0), "v": Vector2(-260.0, -820.0)},
		{"from": Vector2(600.0, 800.0), "v": Vector2(480.0, -420.0)},
		{"from": Vector2(300.0, 420.0), "v": Vector2(520.0, 240.0)},
		{"from": Vector2(560.0, 300.0), "v": Vector2(60.0, 800.0)},
		{"from": Vector2(900.0, 640.0), "v": Vector2(-640.0, 120.0)},
	]

	var worst: float = 0.0
	var worst_final: float = 0.0
	for shot: Dictionary in shots:
		var from: Vector2 = shot["from"] as Vector2
		var velocity: Vector2 = shot["v"] as Vector2

		_reset_glass(world)
		var preview: TrajectoryPreview = TrajectoryPreview.new()
		preview._ready()
		var predicted: PackedVector2Array = preview.simulate(form, from, velocity, world)
		preview.free()

		# The real ball, launched identically into a world where nothing is broken yet.
		_reset_glass(world)
		var state: BallState = BallState.new()
		state.x = from.x
		state.y = from.y
		state.vx = velocity.x
		state.vy = velocity.y
		state.ground_material = SurfaceKind.NONE
		var policy: RealPolicy = RealPolicy.new()
		policy.world = world
		var dt: float = TuningData.get_active().fixed_delta()
		var last: int = predicted.size() - 1
		for i: int in range(1, predicted.size()):
			BallSim.step_ball(state, form, world, dt, policy)
			var gap: float = Vector2(state.x, state.y).distance_to(predicted[i])
			# The FINAL step is excluded, exactly as the Phaser project's own test does: the
			# prediction stops mid-step when its bounce budget runs out, while the real ball
			# finishes that step. Every step before it must match to the last decimal.
			if i == last:
				worst_final = maxf(worst_final, gap)
			else:
				worst = maxf(worst, gap)

	_reset_glass(world)
	_restore(saved)
	_check(
		"prediction matches the real path (%s, %s)" % [BallForm.make(form_id).label, label],
		worst <= TOLERANCE,
		"worst %.6f px over %d shots, final step %.3f" % [worst, shots.size(), worst_final],
	)


# ---------------------------------------------------------------- glass behaviour

func _test_glass_modes(world: StepWorld) -> void:
	var form: BallForm = BallForm.make(BallForm.ROCKY)
	var pane: ShapeBody = _glass_named(world, 900)  # the free-standing bridge

	# Always break: the pane is gone and the ball carries on down.
	var r: Dictionary = _drop_rocky(world, form, pane, GlassRules.MODE_ALWAYS, 700.0)
	_check("always break shatters the pane", r["broke"] as bool, "ball ended at y %.0f" % (r["y"] as float))

	# Never break: lands on it and stays.
	r = _drop_rocky(world, form, pane, GlassRules.MODE_NEVER, 700.0)
	_check("never break lands dead on the pane",
		not (r["broke"] as bool) and (r["grounded"] as bool),
		"ground %s" % SurfaceKind.to_name(r["ground"] as int))

	# Hard hits only: a gentle drop does not break it, a fast one does.
	r = _drop_rocky(world, form, pane, GlassRules.MODE_HARD, 120.0)
	var gentle_held: bool = not (r["broke"] as bool)
	r = _drop_rocky(world, form, pane, GlassRules.MODE_HARD, 1200.0)
	_check("hard hits only: gentle holds, fast breaks",
		gentle_held and (r["broke"] as bool), "break speed %.0f" % TuningData.get_active().glass_hard_break_speed)

	# Pass through: never breaks, and never stops the ball either.
	r = _drop_rocky(world, form, pane, GlassRules.MODE_PASS, 700.0)
	_check("pass through goes straight by",
		not (r["broke"] as bool) and (r["y"] as float) > pane.bounds.end.y,
		"ended at y %.0f, pane bottom %.0f" % [r["y"] as float, pane.bounds.end.y])

	# Squishy must still bounce off a pane the rock passes through.
	var saved: Dictionary = _apply({"glass_rocky_mode": GlassRules.MODE_PASS})
	_reset_glass(world)
	var squishy: BallForm = BallForm.make(BallForm.SQUISHY)
	var state: BallState = BallState.new()
	state.x = pane.bounds.get_center().x
	state.y = pane.bounds.position.y - 120.0
	state.ground_material = SurfaceKind.NONE
	var dt: float = TuningData.get_active().fixed_delta()
	for _i: int in 260:
		BallSim.step_ball(state, squishy, world, dt, null)
	_check("pass-through glass is still solid for squishy",
		state.y < pane.bounds.end.y, "squishy ended at y %.0f" % state.y)
	_restore(saved)

	# Break obstructions only: the bridge breaks, the pane clad to a wall does not.
	var clad: ShapeBody = _glass_named(world, 901)
	GlassRules.classify(world.shapes)
	_check("classification: free-standing pane is an obstruction",
		pane.glass_type == ShapeBody.GLASS_OBSTRUCTION, "bridge")
	_check("classification: pane flat on a wall is cladding",
		clad.glass_type == ShapeBody.GLASS_WALL, "wall pane")
	r = _drop_rocky(world, form, pane, GlassRules.MODE_OBSTRUCTION, 700.0)
	_check("obstructions only: the bridge breaks", r["broke"] as bool, "")
	_reset_glass(world)


## Drop the rocky ball onto a pane in a given mode. Returns what happened.
func _drop_rocky(world: StepWorld, form: BallForm, pane: ShapeBody, mode: int, speed: float) -> Dictionary:
	var saved: Dictionary = _apply({"glass_rocky_mode": mode})
	_reset_glass(world)
	var state: BallState = BallState.new()
	state.x = pane.bounds.get_center().x
	state.y = pane.bounds.position.y - 60.0
	state.vy = speed
	state.ground_material = SurfaceKind.NONE
	var policy: RealPolicy = RealPolicy.new()
	policy.world = world
	var dt: float = TuningData.get_active().fixed_delta()
	for _i: int in 240:
		BallSim.step_ball(state, form, world, dt, policy)
	var result: Dictionary = {
		"broke": pane.broken,
		"y": state.y,
		"grounded": state.ground_material != SurfaceKind.NONE,
		"ground": state.ground_material,
	}
	_restore(saved)
	return result


# ---------------------------------------------------------------- spikes

func _test_spikes_every_side() -> void:
	var strip: SpikeStrip = SpikeStrip.make(1, Vector2(500.0, 500.0), Vector2.UP, 70.0, 18.0)
	var r: float = 11.0
	var cases: Array[Dictionary] = [
		{"name": "on the teeth", "at": Vector2(500.0, 500.0 - 14.0)},
		{"name": "just off the points", "at": Vector2(500.0, 500.0 - 10.0 - r * 0.9)},
		{"name": "behind the slab", "at": Vector2(500.0, 500.0 + 7.0 + r * 0.9)},
		{"name": "past the left end", "at": Vector2(500.0 - 70.0 - r * 0.9, 500.0)},
		{"name": "past the right end", "at": Vector2(500.0 + 70.0 + r * 0.9, 500.0)},
		{"name": "a front corner", "at": Vector2(500.0 - 70.0 - r * 0.4, 500.0 - 10.0 - r * 0.4)},
	]
	var missed: PackedStringArray = PackedStringArray()
	for case: Dictionary in cases:
		if not strip.touches((case["at"] as Vector2).x, (case["at"] as Vector2).y, r):
			missed.append(case["name"] as String)
	_check("spikes bite from every side", missed.is_empty(),
		"missed: %s" % (", ".join(missed) if not missed.is_empty() else "nothing"))

	var clear: bool = not strip.touches(500.0, 500.0 - 10.0 - r * 3.0, r)
	_check("spikes do not bite from well clear", clear, "3 radii in front is safe")


func _test_spike_sweep_at_speed() -> void:
	# A thin strip and a ball crossing it in one step: a point-in-time check would miss this.
	var strip: SpikeStrip = SpikeStrip.make(1, Vector2(500.0, 500.0), Vector2.UP, 70.0, 10.0)
	var r: float = 11.0
	var before: Vector2 = Vector2(500.0, 440.0)
	var after: Vector2 = Vector2(500.0, 560.0)
	_check("a point check would miss the crossing",
		not strip.touches(before.x, before.y, r) and not strip.touches(after.x, after.y, r),
		"endpoints are both clear")
	_check("the swept check catches it", strip.sweep(before.x, before.y, after.x, after.y, r),
		"120px step across a 10px strip")


func _test_respawn_uses_latest_flag() -> void:
	# The autoload singleton does not exist in a --script SceneTree, so the real script is
	# instantiated directly. Same code, no tree.
	var state: Node = (load("res://core/game_state.gd") as GDScript).new() as Node
	state.call("reset_for_level", Vector2(100.0, 900.0))
	var at_spawn: bool = (state.get("respawn_point") as Vector2) == Vector2(100.0, 900.0) and not (state.get("has_flag") as bool)
	state.set("respawn_point", Vector2(400.0, 700.0))
	var first: bool = (state.get("respawn_point") as Vector2) == Vector2(400.0, 700.0) and (state.get("has_flag") as bool)
	state.set("respawn_point", Vector2(800.0, 500.0))
	var latest: bool = (state.get("respawn_point") as Vector2) == Vector2(800.0, 500.0)
	state.free()
	_check("respawn starts at the spawn", at_spawn, "no flag raised yet")
	_check("respawn follows the most recent flag", first and latest, "two flags raised in order")


# ---------------------------------------------------------------- aim

func _test_aim_sweep(snap_degrees: float) -> void:
	var samples: int = 720
	var pointer_step: float = 360.0 / float(samples)
	var allowed: float = (snap_degrees + 0.001) if snap_degrees > 0.0 else (pointer_step + 0.001)
	var worst_step: float = 0.0
	var stuck: int = 0
	var buckets: Dictionary = {}

	for direction: int in [1, -1]:
		var previous: float = NAN
		for i: int in samples:
			var degrees: float = float(direction * i) * pointer_step
			var drag: Vector2 = Vector2(cos(deg_to_rad(degrees)), sin(deg_to_rad(degrees))) * 90.0
			var aim: AimMath.AimVector = AimMath.aim_from_drag(drag, snap_degrees, null, AimMath.EDGE_FROM)
			var now: float = AimMath.display_degrees(aim.direction)
			buckets[int(round(now)) % 360] = true
			if not is_nan(previous):
				var delta: float = absf(fposmod(now - previous + 540.0, 360.0) - 180.0)
				worst_step = maxf(worst_step, delta)
				if delta < 0.0001 and snap_degrees <= 0.0:
					stuck += 1
			previous = now

	_check("aim never sticks (snap %.0f)" % snap_degrees, stuck == 0, "%d samples did not move" % stuck)
	_check("aim never jumps (snap %.0f)" % snap_degrees, worst_step <= allowed,
		"largest step %.3f deg, allowed %.3f" % [worst_step, allowed])
	_check("aim covers the circle (snap %.0f)" % snap_degrees,
		buckets.size() >= (72 if snap_degrees > 0.0 else 300), "%d distinct directions" % buckets.size())


func _test_aim_sweep_within_range() -> void:
	var r: AimMath.AimRange = AimMath.make_range(15.0, 165.0)
	var samples: int = 720
	var swaps: int = 0
	var last_edge: int = AimMath.EDGE_FROM
	var previous_edge: int = AimMath.EDGE_FROM
	for i: int in samples:
		var degrees: float = float(i) * 360.0 / float(samples)
		var drag: Vector2 = Vector2(cos(deg_to_rad(degrees)), sin(deg_to_rad(degrees))) * 90.0
		var aim: AimMath.AimVector = AimMath.aim_from_drag(drag, 0.0, r, last_edge)
		last_edge = aim.edge
		if aim.clamped and aim.edge != previous_edge:
			swaps += 1
		previous_edge = aim.edge
	_check("aim range edge does not flicker", swaps <= 4, "%d edge swaps in a full sweep" % swaps)


## The check has to catch a level rock has sealed, and pass one it has not.
func _test_route_check() -> void:
	var start: Vector2 = Vector2(250.0, 1150.0)
	var target: Array[Dictionary] = [{"at": Vector2(300.0, 980.0), "reach": 40.0}]

	var open_world: StepWorld = _build_test_world()
	var missed: PackedInt32Array = RouteCheck.unreachable(
		open_world.shapes, start, target, open_world.bounds().grow(32.0))
	_check("route check passes an open level", missed.is_empty(), "%d unreachable" % missed.size())

	# Seal the flag inside a box of ROCK. Nothing can get in, so the check must say so.
	var box: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(240, 900), Vector2(360, 900), Vector2(360, 920), Vector2(240, 920)]),
		PackedVector2Array([Vector2(240, 1000), Vector2(360, 1000), Vector2(360, 1020), Vector2(240, 1020)]),
		PackedVector2Array([Vector2(240, 900), Vector2(260, 900), Vector2(260, 1020), Vector2(240, 1020)]),
		PackedVector2Array([Vector2(340, 900), Vector2(360, 900), Vector2(360, 1020), Vector2(340, 1020)]),
	]
	var sealed_world: StepWorld = _build_test_world()
	var next: int = 500
	for outline: PackedVector2Array in box:
		sealed_world.shapes.append(ShapeBody.new(next, outline, SurfaceKind.WALL, 0.0))
		next += 1
	missed = RouteCheck.unreachable(sealed_world.shapes, start, target, sealed_world.bounds().grow(32.0))
	_check("route check catches a level sealed by rock", missed.size() == 1, "%d unreachable" % missed.size())

	# The same box made of breakable GLASS must not be reported: the rock smashes its way in.
	var glassed: StepWorld = _build_test_world()
	next = 600
	for outline: PackedVector2Array in box:
		glassed.shapes.append(ShapeBody.new(next, outline, SurfaceKind.GLASS, 0.0))
		next += 1
	GlassRules.classify(glassed.shapes)
	missed = RouteCheck.unreachable(glassed.shapes, start, target, glassed.bounds().grow(32.0))
	_check("route check lets breakable glass through", missed.is_empty(), "%d unreachable" % missed.size())


# ---------------------------------------------------------------- settling

func _test_settle_comes_to_rest(world: StepWorld) -> void:
	_reset_glass(world)
	var form: BallForm = BallForm.make(BallForm.SQUISHY)
	var state: BallState = BallState.new()
	state.x = 300.0
	state.y = 900.0
	state.ground_material = SurfaceKind.NONE
	var dt: float = TuningData.get_active().fixed_delta()
	for _i: int in 900:
		BallSim.step_ball(state, form, world, dt, null)
	_check("squishy settles instead of bouncing forever",
		absf(state.vy) < 20.0 and state.ground_material != SurfaceKind.NONE,
		"vy %.1f, ground %s" % [state.vy, SurfaceKind.to_name(state.ground_material)])


# ---------------------------------------------------------------- helpers

## The real ball's side of a step: break a pane for good, and note spikes.
class RealPolicy extends StepPolicy:
	var world: StepWorld = null
	var spiked: bool = false

	func on_glass(shape: ShapeBody, _state: BallState, _impact_speed: float) -> int:
		shape.broken = true
		return StepPolicy.GLASS_BREAK

	func on_spikes(_strip: SpikeStrip, _state: BallState) -> void:
		spiked = true


func _mode_name(mode: int) -> String:
	return ["obstruction", "always", "hard", "never", "pass"][mode] as String


func _apply(settings: Dictionary) -> Dictionary:
	var t: TuningData = TuningData.get_active()
	var saved: Dictionary = {}
	for key: String in settings.keys():
		saved[key] = t.get(key)
		t.set(key, settings[key])
	return saved


func _restore(saved: Dictionary) -> void:
	var t: TuningData = TuningData.get_active()
	for key: String in saved.keys():
		t.set(key, saved[key])


func _reset_glass(world: StepWorld) -> void:
	for shape: ShapeBody in world.shapes:
		shape.broken = false


func _glass_named(world: StepWorld, id: int) -> ShapeBody:
	for shape: ShapeBody in world.shapes:
		if shape.id == id:
			return shape
	return null


## The test geometry, built in code so the tests need no scene. A floor, walls, ledges, a slope,
## a free-standing glass bridge (id 900) and a pane clad flat to a wall (id 901).
func _build_test_world() -> StepWorld:
	var world: StepWorld = StepWorld.new()
	var next: int = 1
	var walls: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(40, 1180), Vector2(1160, 1180), Vector2(1160, 1260), Vector2(40, 1260)]),
		PackedVector2Array([Vector2(40, 120), Vector2(110, 120), Vector2(110, 1260), Vector2(40, 1260)]),
		PackedVector2Array([Vector2(1090, 120), Vector2(1160, 120), Vector2(1160, 1260), Vector2(1090, 1260)]),
		PackedVector2Array([Vector2(40, 120), Vector2(1160, 120), Vector2(1160, 180), Vector2(40, 180)]),
		PackedVector2Array([Vector2(170, 1000), Vector2(420, 1000), Vector2(420, 1028), Vector2(170, 1028)]),
		PackedVector2Array([Vector2(620, 870), Vector2(880, 870), Vector2(880, 898), Vector2(620, 898)]),
		PackedVector2Array([Vector2(230, 690), Vector2(470, 690), Vector2(470, 718), Vector2(230, 718)]),
		PackedVector2Array([Vector2(560, 1180), Vector2(900, 1070), Vector2(900, 1115), Vector2(560, 1225)]),
	]
	for outline: PackedVector2Array in walls:
		world.shapes.append(ShapeBody.new(next, outline, SurfaceKind.WALL, 0.0))
		next += 1

	# A bridge over open air: nothing behind it, so it classifies as an obstruction.
	world.shapes.append(ShapeBody.new(900,
		PackedVector2Array([Vector2(480, 600), Vector2(700, 600), Vector2(700, 618), Vector2(480, 618)]),
		SurfaceKind.GLASS, 0.0))
	# A pane laid flat along the left wall: cladding.
	world.shapes.append(ShapeBody.new(901,
		PackedVector2Array([Vector2(110, 400), Vector2(126, 400), Vector2(126, 620), Vector2(110, 620)]),
		SurfaceKind.GLASS, 0.0))

	GlassRules.classify(world.shapes)
	return world


func _report_unmapped() -> void:
	var t: TuningData = TuningData.get_active()
	var keys: PackedStringArray = t.unmapped_keys.duplicate()
	keys.sort()
	var file: FileAccess = FileAccess.open("res://docs/unmapped_tuning_keys.txt", FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(keys) + "\n")
		file.close()
	print("")
	print("  %d Phaser tuning values are still unused (docs/unmapped_tuning_keys.txt)" % keys.size())


func _check(name: String, passed: bool, detail: String) -> void:
	_checks += 1
	if passed:
		print("  ok    %s  (%s)" % [name, detail])
	else:
		_failures += 1
		printerr("  FAIL  %s  (%s)" % [name, detail])
