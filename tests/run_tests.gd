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
##  6. THE GHOST DOES NOT TOUCH THE LEVEL. Cables and levers are the first actors the ball can
##     move, so a prediction could move them by accident. If drawing a preview swung the real
##     ropes or tipped the real planks, merely aiming would rearrange the level and change where
##     the shot went. Checked knot by knot and angle by angle, and together with (1) for every
##     new actor: the ghost must leave the world alone AND still match the ball exactly.
##  7. THE PER-BALL SPLIT. Each surface is a route for one ball and an obstacle for the other --
##     glass and cables for the squishy ball, trampolines for the rocky one, fans for the squishy
##     one. These are the checks that would catch the two forms being accidentally made alike.
##  8. THE LIMITER. All four modes gate and scale launches as specified, and heat in particular
##     never refuses a shot -- it only weakens it.

const TOLERANCE: float = 0.0001

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	print("Project Juice -- phase 3 tests\n")
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

	print("\n cables")
	_test_cables()

	print("\n levers")
	_test_levers()

	print("\n trampolines")
	_test_trampolines()

	print("\n fans")
	_test_fans()

	print("\n launch limiter")
	_test_limiter_grounded()
	_test_limiter_charges()
	_test_limiter_heat()
	_test_limiter_elasticity()

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
# ---------------------------------------------------------------- levers

func _test_levers() -> void:
	var t: TuningData = TuningData.get_active()
	var squishy: BallForm = BallForm.make(BallForm.SQUISHY)
	var rocky: BallForm = BallForm.make(BallForm.ROCKY)

	# A lever is a COUNTERWEIGHT SWITCH. The weight parks the plank against one stop and holds it
	# there until something heavy enough lands on the raised end. These two checks run against the
	# SHIPPED tuning rather than overriding it, because the switch is a designed threshold: the
	# counterweight (1.5) sits deliberately between the squishy ball's mass (1) and the rocky
	# ball's (6). Retune it outside that band and these should fail -- that is the point of them.
	var world: StepWorld = _lever_world()
	var lever: Lever = world.levers[0]
	_settle_lever(lever, 3.0)
	var rest: float = lever.angle
	_check(
		"a counterweight parks the plank against a stop",
		is_equal_approx(absf(rest), lever.max_tilt),
		"rests at %.1f deg, limit %.1f" % [rad_to_deg(rest), rad_to_deg(lever.max_tilt)],
	)

	var after_squishy: float = _drop_on_raised_end(world, squishy, rest)
	var after_rocky: float = _drop_on_raised_end(world, rocky, rest)
	_check(
		"the counterweight holds against squishy and yields to rocky",
		is_equal_approx(after_squishy, rest) and absf(after_rocky - rest) > lever.max_tilt,
		"squishy leaves it at %.1f deg, rocky throws it to %.1f (from %.1f)" % [
			rad_to_deg(after_squishy), rad_to_deg(after_rocky), rad_to_deg(rest)],
	)

	# The stop is a stop, whatever is piled on it.
	var slammed: StepWorld = _lever_world()
	_run_from(slammed, rocky, Vector2(560.0, 200.0), Vector2(0.0, 400.0), 2.0)
	_check(
		"a plank never tips past its limit",
		absf(slammed.levers[0].angle) <= slammed.levers[0].max_tilt + TOLERANCE,
		"%.2f deg, limit %.2f" % [rad_to_deg(slammed.levers[0].angle), rad_to_deg(slammed.levers[0].max_tilt)],
	)

	# Left alone it comes to a dead stop rather than creeping for ever.
	var swinging: StepWorld = _lever_world()
	swinging.levers[0].angular_velocity = 3.0
	var dt: float = t.fixed_delta()
	for _i: int in 600:
		swinging.levers[0].step(dt)
	_check(
		"a plank left alone settles",
		is_zero_approx(swinging.levers[0].angular_velocity),
		"%.6f rad/s after 5 s" % swinging.levers[0].angular_velocity,
	)

	# Same architectural property cables have, and for the same reason.
	var live: StepWorld = _lever_world()
	var angle_before: float = live.levers[0].angle
	var preview: TrajectoryPreview = TrajectoryPreview.new()
	preview._ready()
	preview.simulate(rocky, Vector2(560.0, 300.0), Vector2(0.0, 200.0), live)
	preview.free()
	_check(
		"a prediction leaves the real plank exactly where it was",
		is_equal_approx(live.levers[0].angle, angle_before),
		"still at %.6f rad after a preview that lands on it" % live.levers[0].angle,
	)

	_test_prediction_through_actors("a lever", _lever_world(), rocky, Vector2(560.0, 300.0), Vector2(0.0, 200.0))


## A room with one plank pivoted in the middle of it, at the block's own default tilt limit.
func _lever_world() -> StepWorld:
	var world: StepWorld = _plain_room()
	world.levers.append(Lever.new(1, Vector2(500.0, 700.0), 90.0, 6.0, 25.0))
	return world


## Let the plank find its resting position under the counterweight alone.
func _settle_lever(lever: Lever, seconds: float) -> void:
	var dt: float = TuningData.get_active().fixed_delta()
	for _i: int in int(seconds / dt):
		lever.step(dt)


## Drop a ball straight onto whichever end the counterweight has left raised, from `rest`.
## Returns the angle the plank ends at.
func _drop_on_raised_end(world: StepWorld, form: BallForm, rest: float) -> float:
	var lever: Lever = world.levers[0]
	lever.angle = rest
	lever.angular_velocity = 0.0
	var a: Vector2 = lever.end_a()
	var b: Vector2 = lever.end_b()
	var raised: Vector2 = a if a.y < b.y else b
	_run_from(world, form, Vector2(raised.x, raised.y - 60.0), Vector2.ZERO, 3.0)
	return lever.angle


## How many steps it takes the ball to drive the plank to its stop. Returns the cap if it never
## gets there.
func _steps_to_tilt_limit(world: StepWorld, form: BallForm, from: Vector2) -> int:
	var state: BallState = BallState.new()
	state.x = from.x
	state.y = from.y
	state.ground_material = SurfaceKind.NONE
	var lever: Lever = world.levers[0]
	var dt: float = TuningData.get_active().fixed_delta()
	var cap: int = 900
	for i: int in cap:
		if not BallSim.step_ball(state, form, world, dt, null):
			return cap
		if absf(lever.angle) >= lever.max_tilt - 0.0001:
			return i
	return cap


# ---------------------------------------------------------------- cables

func _test_cables() -> void:
	var t: TuningData = TuningData.get_active()
	var squishy: BallForm = BallForm.make(BallForm.SQUISHY)
	var rocky: BallForm = BallForm.make(BallForm.ROCKY)

	# The rope settles into its droop, and the cap holds it there.
	var world: StepWorld = _cable_world()
	var rope: Cable = world.cables[0]
	var dt: float = t.fixed_delta()
	for _i: int in 600:
		rope.step(dt)
	var middle: Vector2 = rope.points[rope.points.size() / 2]
	var flat: float = rope.anchor_a.lerp(rope.anchor_b, 0.5).y
	_check(
		"a rope sags, and never further than maxSag",
		middle.y > flat and middle.y - flat <= t.cables_max_sag + TOLERANCE,
		"%.1f px of droop, cap %.0f" % [middle.y - flat, t.cables_max_sag],
	)
	_check(
		"a rope stays pinned at both ends",
		rope.points[0].is_equal_approx(rope.anchor_a) and rope.points[rope.points.size() - 1].is_equal_approx(rope.anchor_b),
		"anchors held after 600 steps",
	)

	# The per-ball split, as with glass and pads: a rope throws the squishy ball and the rocky ball
	# lands in it dead (0.31 against 0.04, under a 60 px/s threshold).
	var squishy_hit: Dictionary = _first_contact_with(_cable_world(), squishy, Vector2(500.0, 300.0), Vector2.ZERO, SurfaceKind.CABLE)
	var rocky_hit: Dictionary = _first_contact_with(_cable_world(), rocky, Vector2(500.0, 300.0), Vector2.ZERO, SurfaceKind.CABLE)
	_check(
		"a rope throws the squishy ball and the rocky ball lands in it dead",
		(squishy_hit["out"] as float) > 100.0 and is_zero_approx(rocky_hit["out"] as float),
		"squishy out %.0f px/s, rocky out %.0f" % [squishy_hit["out"], rocky_hit["out"]],
	)

	# A ONE-WAY FLOOR: caught from above, passed straight through from below. Each world is
	# measured against its OWN rope -- a rope that has been landed on sits lower than one that has
	# only been flown through, so comparing across the two would be comparing different ropes.
	var dropped: StepWorld = _cable_world()
	var landed: BallState = _run_from(dropped, squishy, Vector2(500.0, 300.0), Vector2.ZERO, 2.0)
	var caught: bool = landed.y < _rope_middle_y(dropped) and landed.ground_material == SurfaceKind.CABLE

	var risen: StepWorld = _cable_world()
	var rising: BallState = _run_from(risen, squishy, Vector2(500.0, 720.0), Vector2(0.0, -900.0), 0.25)
	var passed: bool = rising.y < _rope_middle_y(risen)

	_check(
		"a cable is a one-way floor: caught from above, passed through from below",
		caught and passed,
		"came to rest on it at y %.0f (rope %.0f), rose through it to y %.0f (rope %.0f)" % [
			landed.y, _rope_middle_y(dropped), rising.y, _rope_middle_y(risen),
		],
	)
	# Within half a pixel rather than to float equality: a resting contact is held out by the
	# push-out pass every step, which settles just shy of the exact figure.
	var clearance: float = _rope_middle_y(dropped) - landed.y
	var wanted_clearance: float = squishy.radius + dropped.cables[0].thickness()
	_check(
		"a ball resting in a rope sits on top of it, by its radius and the rope's thickness",
		absf(clearance - wanted_clearance) < 0.5,
		"%.3f px of clearance, expected %.3f" % [clearance, wanted_clearance],
	)

	# Sustained mode throws to the ball's own height whatever the drop. Measured with the impact
	# bonus switched off, since that is the part that is deliberately allowed to vary.
	var saved: Dictionary = _apply({"cables_sustain_bounce": true, "cables_impact_bonus": 0.0})
	var low: Dictionary = _first_contact_with(_cable_world(), squishy, Vector2(500.0, 400.0), Vector2.ZERO, SurfaceKind.CABLE)
	var high: Dictionary = _first_contact_with(_cable_world(), squishy, Vector2(500.0, 100.0), Vector2.ZERO, SurfaceKind.CABLE)
	var wanted: float = sqrt(2.0 * t.world_gravity * squishy.gravity_multiplier * squishy.sustained_cable_height)
	_check(
		"a sustained rope throws to the same height whatever the drop",
		is_equal_approx(low["out"] as float, wanted) and is_equal_approx(high["out"] as float, wanted),
		"%.1f and %.1f px/s out, both wanting %.1f" % [low["out"], high["out"], wanted],
	)
	_restore(saved)

	# A rope puts a spent budget back, for both balls.
	saved = _apply({
		"limiter_mode": LaunchLimiter.MODE_CHARGES,
		"charges_max": 3,
		"charges_settle_time": 0.0,
		"cables_refills_charges": true,
	})
	var limiter: LaunchLimiter = LaunchLimiter.new()
	_drain(limiter)
	limiter.note_contact(_contact_facing(-1.0, SurfaceKind.CABLE), rocky)
	var refilled: int = limiter.charges
	_restore(saved)
	_check("a rope refills the budget", refilled == 3, "%d charges" % refilled)

	# THE ONE THAT MATTERS MOST. A rope is the first thing in this port the ball can move, so it is
	# the first thing a prediction could move by accident. If drawing a preview swung the real
	# ropes, merely aiming would disturb the level and change where the shot went.
	var live: StepWorld = _cable_world()
	for _i: int in 120:
		live.cables[0].step(dt)
	var before: PackedVector2Array = live.cables[0].points.duplicate()
	var preview: TrajectoryPreview = TrajectoryPreview.new()
	preview._ready()
	preview.simulate(squishy, Vector2(500.0, 300.0), Vector2(60.0, 200.0), live)
	preview.free()
	var untouched: bool = true
	for i: int in before.size():
		if not before[i].is_equal_approx(live.cables[0].points[i]):
			untouched = false
			break
	_check(
		"a prediction leaves the real rope exactly where it was",
		untouched,
		"all %d knots unmoved by a preview that lands on the rope" % before.size(),
	)

	_test_prediction_through_actors("a cable", _cable_world(), squishy, Vector2(500.0, 300.0), Vector2(60.0, 200.0))


## A room with one slack rope strung across the middle. Built fresh each time, because a rope
## remembers how it has been swung and a test that reused one would depend on the order.
func _cable_world() -> StepWorld:
	var world: StepWorld = _plain_room()
	world.cables.append(Cable.new(1, Vector2(200.0, 600.0), Vector2(800.0, 600.0), 0.25, -1.0))
	return world


## The first contact with `material`: {out, impact}, or out -1 if it never happened.
func _first_contact_with(
	world: StepWorld,
	form: BallForm,
	from: Vector2,
	velocity: Vector2,
	material: int,
) -> Dictionary:
	var state: BallState = BallState.new()
	state.x = from.x
	state.y = from.y
	state.vx = velocity.x
	state.vy = velocity.y
	state.ground_material = SurfaceKind.NONE
	var watch: MaterialWatch = MaterialWatch.new()
	watch.want = material
	var dt: float = TuningData.get_active().fixed_delta()
	for _i: int in 900:
		if not BallSim.step_ball(state, form, world, dt, watch):
			break
		if watch.out_speed >= 0.0:
			break
	return {"out": watch.out_speed, "impact": watch.impact_speed}


## Records the first contact with one material and counts them all.
class MaterialWatch extends StepPolicy:
	var want: int = SurfaceKind.CABLE
	var out_speed: float = -1.0
	var impact_speed: float = 0.0
	var hits: int = 0

	func on_contact(contact: Contact) -> bool:
		if contact.material == want:
			hits += 1
			if out_speed < 0.0:
				out_speed = contact.out_speed
				impact_speed = contact.impact_speed
		return true


## Run the ball for `seconds` and hand back everything about where it ended up.
func _run_from(
	world: StepWorld,
	form: BallForm,
	from: Vector2,
	velocity: Vector2,
	seconds: float,
) -> BallState:
	var state: BallState = BallState.new()
	state.x = from.x
	state.y = from.y
	state.vx = velocity.x
	state.vy = velocity.y
	state.ground_material = SurfaceKind.NONE
	var dt: float = TuningData.get_active().fixed_delta()
	for _i: int in int(seconds / dt):
		if not BallSim.step_ball(state, form, world, dt, null):
			break
	return state


## How low the middle of the first rope is hanging, in this world.
func _rope_middle_y(world: StepWorld) -> float:
	var rope: Cable = world.cables[0]
	return rope.points[rope.points.size() / 2].y


# ---------------------------------------------------------------- trampolines

func _test_trampolines() -> void:
	var t: TuningData = TuningData.get_active()
	var squishy: BallForm = BallForm.make(BallForm.SQUISHY)
	var rocky: BallForm = BallForm.make(BallForm.ROCKY)
	var world: StepWorld = _plain_room()
	var pad: ShapeBody = ShapeBody.new(500, PackedVector2Array([
		Vector2(400.0, 980.0), Vector2(600.0, 980.0), Vector2(600.0, 1000.0), Vector2(400.0, 1000.0),
	]), SurfaceKind.TRAMPOLINE, 0.0)
	world.shapes.append(pad)
	var above: Vector2 = Vector2(500.0, 700.0)

	# The mirror of glass: a pad throws the rocky ball and is nearly dead under the squishy one.
	# Note the ball comes straight DOWN onto it -- a pad has to launch on a landing, where glass
	# deliberately gives up its boost so a glass ledge stays standable.
	var rocky_up: float = _fastest_rise(world, rocky, above)
	var squishy_up: float = _fastest_rise(world, squishy, above)
	_check(
		"a pad throws the rocky ball and barely moves the squishy one",
		rocky_up > squishy_up * 5.0 and rocky_up > t.trampoline_launch_speed * 0.8,
		"rocky %.0f px/s up, squishy %.0f" % [rocky_up, squishy_up],
	)

	# Arriving faster is rewarded, which is what `impactBonus` buys. Measured on the FIRST launch
	# only: left to bounce, the ball settles into a rhythm off the ceiling and every drop height
	# converges on the same impact, so a peak-over-time reading cannot see the bonus at all.
	var from_low: Dictionary = _first_launch_off(world, rocky, Vector2(500.0, 900.0))
	var from_high: Dictionary = _first_launch_off(world, rocky, Vector2(500.0, 200.0))
	_check(
		"a harder landing launches harder",
		(from_high["out"] as float) > (from_low["out"] as float),
		"%.0f px/s out from a %.0f impact, %.0f out from a %.0f impact" % [
			from_low["out"], from_low["impact"], from_high["out"], from_high["impact"],
		],
	)
	_check(
		"the launch is the pad's speed plus its share of the impact",
		is_equal_approx(
			from_high["out"] as float,
			(t.trampoline_launch_speed + t.trampoline_impact_bonus * (from_high["impact"] as float))
				* rocky.trampoline_bounce,
		),
		"%.1f px/s out for a %.1f impact" % [from_high["out"], from_high["impact"]],
	)

	# One soft pad in a level should not mean retuning every pad in the game.
	var soft: StepWorld = _plain_room()
	var soft_pad: ShapeBody = ShapeBody.new(501, PackedVector2Array([
		Vector2(400.0, 980.0), Vector2(600.0, 980.0), Vector2(600.0, 1000.0), Vector2(400.0, 1000.0),
	]), SurfaceKind.TRAMPOLINE, 0.0)
	soft_pad.launch_speed = 200.0
	soft.shapes.append(soft_pad)
	var off_soft: float = _first_launch_off(soft, rocky, above)["out"] as float
	var off_normal: float = _first_launch_off(world, rocky, above)["out"] as float
	_check(
		"a pad can override the global launch speed",
		off_soft < off_normal * 0.6,
		"%.0f px/s off a 200 px/s pad vs %.0f off a %.0f one" % [off_soft, off_normal, t.trampoline_launch_speed],
	)

	# A pad refills a spent budget for both balls, whichever way it was hit.
	var saved: Dictionary = _apply({
		"limiter_mode": LaunchLimiter.MODE_CHARGES,
		"charges_max": 3,
		"charges_settle_time": 0.0,
		"trampoline_refills_squishy": true,
		"trampoline_refills_rocky": true,
	})
	var limiter: LaunchLimiter = LaunchLimiter.new()
	_drain(limiter)
	limiter.note_contact(_contact_facing(0.0, SurfaceKind.TRAMPOLINE), squishy)
	var squishy_refill: int = limiter.charges
	_drain(limiter)
	limiter.note_contact(_contact_facing(0.0, SurfaceKind.TRAMPOLINE), rocky)
	var rocky_refill: int = limiter.charges
	_restore(saved)
	_check(
		"a pad refills the budget for both balls, even hit side-on",
		squishy_refill == 3 and rocky_refill == 3,
		"squishy %d, rocky %d from a sideways hit a wall rule would have refused" % [squishy_refill, rocky_refill],
	)

	_test_prediction_through_actors("a trampoline", world, rocky, Vector2(450.0, 700.0), Vector2(80.0, 200.0))


## The first launch a pad gives the ball: {out, impact}, both in px/s. Returns out -1 if the ball
## never got launched at all, which is the right answer for a ball that cannot launch off a pad.
func _first_launch_off(world: StepWorld, form: BallForm, from: Vector2) -> Dictionary:
	var state: BallState = BallState.new()
	state.x = from.x
	state.y = from.y
	state.ground_material = SurfaceKind.NONE
	var watch: LaunchWatch = LaunchWatch.new()
	var dt: float = TuningData.get_active().fixed_delta()
	for _i: int in 600:
		if not BallSim.step_ball(state, form, world, dt, watch):
			break
		if watch.out_speed >= 0.0:
			break
	return {"out": watch.out_speed, "impact": watch.impact_speed}


## Records the first launch off a pad and nothing else.
class LaunchWatch extends StepPolicy:
	var out_speed: float = -1.0
	var impact_speed: float = 0.0

	func on_contact(contact: Contact) -> bool:
		if contact.launched_off and out_speed < 0.0:
			out_speed = contact.out_speed
			impact_speed = contact.impact_speed
		return true


## The fastest upward speed the ball reaches, over a few seconds. Negative Y is up, so this is the
## biggest -vy seen.
func _fastest_rise(world: StepWorld, form: BallForm, from: Vector2) -> float:
	var state: BallState = BallState.new()
	state.x = from.x
	state.y = from.y
	state.ground_material = SurfaceKind.NONE
	var dt: float = TuningData.get_active().fixed_delta()
	var best: float = 0.0
	for _i: int in 400:
		if not BallSim.step_ball(state, form, world, dt, null):
			break
		best = maxf(best, -state.vy)
	return best


# ---------------------------------------------------------------- fans

func _test_fans() -> void:
	var world: StepWorld = _plain_room()
	var fan: FanField = FanField.new(1, Vector2(500.0, 1000.0), Vector2.UP, 200.0, 640.0, 1.0)
	world.fans.append(fan)

	var squishy: BallForm = BallForm.make(BallForm.SQUISHY)
	var rocky: BallForm = BallForm.make(BallForm.ROCKY)
	var start: Vector2 = Vector2(500.0, 700.0)

	# The whole fan puzzle in one check: the same stream is a route for one ball and scenery for
	# the other, because 0.3 of the push cannot beat the rocky ball's 1920 px/s^2 of gravity.
	var squishy_dy: float = _drift_in_world(world, squishy, start, Vector2.ZERO, 0.3)
	var rocky_dy: float = _drift_in_world(world, rocky, start, Vector2.ZERO, 0.3)
	_check(
		"a fan flies the squishy ball and only slows the rocky one",
		squishy_dy < 0.0 and rocky_dy > 0.0,
		"squishy %.0f px, rocky %.0f px over 0.3 s" % [squishy_dy, rocky_dy],
	)

	# A fan makes up the shortfall and nothing more, so flying a fast shot through one is free.
	var slow: Vector2 = fan.accel_for(start.x, start.y, 0.0, 0.0, squishy, world)
	var already_fast: Vector2 = fan.accel_for(start.x, start.y, 0.0, -900.0, squishy, world)
	_check(
		"a fan pushes a slow ball and never brakes a fast one",
		slow.length() > 0.0 and already_fast == Vector2.ZERO,
		"%.0f px/s^2 at rest, %.0f at 900 px/s up" % [slow.length(), already_fast.length()],
	)

	# Outside the mouth and behind it there is no stream at all.
	var off_to_the_side: Vector2 = fan.accel_for(start.x + 180.0, start.y, 0.0, 0.0, squishy, world)
	var behind_the_mouth: Vector2 = fan.accel_for(start.x, 1040.0, 0.0, 0.0, squishy, world)
	var past_the_reach: Vector2 = fan.accel_for(start.x, 1000.0 - 700.0, 0.0, 0.0, squishy, world)
	_check(
		"the stream has edges, a back and an end",
		off_to_the_side == Vector2.ZERO and behind_the_mouth == Vector2.ZERO and past_the_reach == Vector2.ZERO,
		"nothing outside the mouth, behind it, or beyond its reach",
	)

	# A pane across the stream: a lid when `blockedByGlass` is on, a window when it is off.
	var lidded: StepWorld = _plain_room()
	lidded.fans.append(fan)
	lidded.shapes.append(ShapeBody.new(900, PackedVector2Array([
		Vector2(400.0, 850.0), Vector2(600.0, 850.0), Vector2(600.0, 870.0), Vector2(400.0, 870.0),
	]), SurfaceKind.GLASS, 0.0))
	GlassRules.classify(lidded.shapes)

	var saved: Dictionary = _apply({"fans_blocked_by_glass": true})
	var blocked: Vector2 = fan.accel_for(start.x, start.y, 0.0, 0.0, squishy, lidded)
	_restore(saved)
	saved = _apply({"fans_blocked_by_glass": false})
	var through: Vector2 = fan.accel_for(start.x, start.y, 0.0, 0.0, squishy, lidded)
	_restore(saved)
	_check(
		"glass is a lid on the stream, or a window, as the tuning says",
		blocked == Vector2.ZERO and through.length() > 0.0,
		"blocked %.0f px/s^2, window %.0f" % [blocked.length(), through.length()],
	)

	# Where the stream reaches must not depend on which ball is asking, or the two forms would
	# disagree about the shape of the level.
	saved = _apply({"fans_blocked_by_glass": true})
	var rocky_blocked: bool = fan.accel_for(start.x, start.y, 0.0, 0.0, rocky, lidded) == Vector2.ZERO
	_restore(saved)
	_check(
		"a pane shadows the stream for both balls alike",
		rocky_blocked,
		"the rocky ball's pass-through rules do not move the air",
	)

	# `grounded.launchFromFan`: being carried is not a dead end.
	saved = _apply({"grounded_launch_from_fan": true, "grounded_fan_launch_angle": 45.0})
	var up_is_launchable: bool = fan.is_launchable_stream(start.x, start.y, squishy, world)
	var sideways: FanField = FanField.new(2, Vector2(500.0, 1000.0), Vector2.RIGHT, 200.0, 640.0, 1.0)
	var sideways_is_not: bool = not sideways.is_launchable_stream(start.x, start.y, squishy, world)
	_restore(saved)
	_check(
		"an upward stream can be launched from, a sideways one cannot",
		up_is_launchable and sideways_is_not,
		"within %.0f deg of up" % 45.0,
	)

	_test_prediction_through_actors("a fan", world, squishy, start, Vector2(120.0, -300.0))


## The regression that matters for every actor: the ghost and the ball must still agree step for
## step once something other than terrain is pushing them about.
##
## Ropes are snapshotted around both runs. The preview should not move them at all -- that is
## checked separately -- but the real ball certainly does, so the state is put back afterwards and
## a later test is not handed a rope this one has already swung.
func _test_prediction_through_actors(
	label: String,
	world: StepWorld,
	form: BallForm,
	from: Vector2,
	velocity: Vector2,
) -> void:
	var ropes: Dictionary = world.snapshot_actors()
	var preview: TrajectoryPreview = TrajectoryPreview.new()
	preview._ready()
	var predicted: PackedVector2Array = preview.simulate(form, from, velocity, world)
	preview.free()
	world.restore_actors(ropes)

	var state: BallState = BallState.new()
	state.x = from.x
	state.y = from.y
	state.vx = velocity.x
	state.vy = velocity.y
	state.ground_material = SurfaceKind.NONE
	var policy: RealPolicy = RealPolicy.new()
	policy.world = world
	var dt: float = TuningData.get_active().fixed_delta()
	var worst: float = 0.0
	var last: int = predicted.size() - 1
	for i: int in range(1, predicted.size()):
		BallSim.step_ball(state, form, world, dt, policy)
		if i < last:
			worst = maxf(worst, Vector2(state.x, state.y).distance_to(predicted[i]))

	world.restore_actors(ropes)
	_check(
		"prediction stays exact through %s" % label,
		worst <= TOLERANCE,
		"worst %.6f px over %d steps" % [worst, predicted.size()],
	)


## A bare room: floor, ceiling, nothing to get in the way. The big test world is too cluttered for
## actor tests -- its ramp and ledges sit in the way of any stream long enough to matter.
func _plain_room() -> StepWorld:
	var world: StepWorld = StepWorld.new()
	world.shapes.append(ShapeBody.new(1, PackedVector2Array([
		Vector2(0.0, 1000.0), Vector2(1000.0, 1000.0), Vector2(1000.0, 1060.0), Vector2(0.0, 1060.0),
	]), SurfaceKind.WALL, 0.0))
	world.shapes.append(ShapeBody.new(2, PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1000.0, 0.0), Vector2(1000.0, 40.0), Vector2(0.0, 40.0),
	]), SurfaceKind.WALL, 0.0))
	return world


## How far the ball moved on Y over `seconds`. Negative is upward.
func _drift_in_world(
	world: StepWorld,
	form: BallForm,
	from: Vector2,
	velocity: Vector2,
	seconds: float,
) -> float:
	var state: BallState = BallState.new()
	state.x = from.x
	state.y = from.y
	state.vx = velocity.x
	state.vy = velocity.y
	state.ground_material = SurfaceKind.NONE
	var dt: float = TuningData.get_active().fixed_delta()
	for _i: int in int(seconds / dt):
		if not BallSim.step_ball(state, form, world, dt, null):
			break
	return state.y - from.y


# ---------------------------------------------------------------- the launch limiter
#
# All four modes are pure bookkeeping: they gate and scale launches and never move a ball. That is
# why these need no world, no scene and no ball -- which is also the argument for keeping the
# limiter out of `BallSim.step_ball`.

func _test_limiter_grounded() -> void:
	# allowAirLaunch is TRUE in the shipped tuning, so this also pins down that Grounded mode
	# ignores it. Grounded mode IS the refusal; if it consulted the switch it would never refuse.
	var saved: Dictionary = _apply({
		"limiter_mode": LaunchLimiter.MODE_GROUNDED,
		"slingshot_allow_air_launch": true,
	})
	var limiter: LaunchLimiter = LaunchLimiter.new()
	limiter.reset()
	_check("grounded mode fires from the ground", limiter.can_launch(true), "allowed")
	_check(
		"grounded mode refuses in mid-air even with air launches allowed",
		not limiter.can_launch(false),
		"refused",
	)
	_check("grounded mode never weakens a shot", is_equal_approx(limiter.launch_scale(), 1.0), "power x1.00")
	_restore(saved)


func _test_limiter_charges() -> void:
	var saved: Dictionary = _apply({
		"limiter_mode": LaunchLimiter.MODE_CHARGES,
		"charges_max": 3,
		"charges_settle_time": 0.0,
		"slingshot_allow_air_launch": true,
		"charges_refill_on_floor": true,
		"charges_refill_on_ceiling": false,
		"charges_refill_on_wall_material": true,
		"charges_refill_on_glass_material": false,
		"charges_refill_on_glass_for_rocky": true,
	})
	var squishy: BallForm = BallForm.make(BallForm.SQUISHY)
	var rocky: BallForm = BallForm.make(BallForm.ROCKY)
	var limiter: LaunchLimiter = LaunchLimiter.new()

	limiter.reset()
	var fired: int = 0
	while limiter.can_launch(false) and fired < 10:
		limiter.note_launch(1.0, false)
		fired += 1
	_check(
		"charges mode spends the budget and then refuses",
		fired == 3 and not limiter.can_launch(false),
		"fired %d, %d left" % [fired, limiter.charges],
	)

	# A rock floor puts the whole budget back.
	limiter.note_contact(_contact_facing(-1.0, SurfaceKind.WALL), squishy)
	_check("a rock floor refills the budget", limiter.charges == 3, "%d charges" % limiter.charges)

	# A ceiling is switched off, so hitting one gives nothing back.
	_drain(limiter)
	limiter.note_contact(_contact_facing(1.0, SurfaceKind.WALL), squishy)
	_check("a ceiling refills nothing when switched off", limiter.charges == 0, "%d charges" % limiter.charges)

	# The glass exception: a dead end for the squishy ball, a refill for the rocky one.
	_drain(limiter)
	limiter.note_contact(_contact_facing(-1.0, SurfaceKind.GLASS), squishy)
	var squishy_charges: int = limiter.charges
	limiter.note_contact(_contact_facing(-1.0, SurfaceKind.GLASS), rocky)
	var rocky_charges: int = limiter.charges
	_check(
		"glass refills for the rocky ball only",
		squishy_charges == 0 and rocky_charges == 3,
		"squishy %d, rocky %d" % [squishy_charges, rocky_charges],
	)

	# With a settle time set, a touch arms the refill but only staying put collects it.
	_restore(saved)
	saved = _apply({
		"limiter_mode": LaunchLimiter.MODE_CHARGES,
		"charges_max": 3,
		"charges_settle_time": 0.5,
	})
	_drain(limiter)
	limiter.note_contact(_contact_facing(-1.0, SurfaceKind.WALL), squishy)
	var on_touch: int = limiter.charges
	limiter.tick(0.2, SurfaceKind.WALL, squishy)
	var part_way: int = limiter.charges
	limiter.tick(0.4, SurfaceKind.WALL, squishy)
	var settled: int = limiter.charges
	_check(
		"a settle time makes the refill wait for the ball to stay",
		on_touch == 0 and part_way == 0 and settled == 3,
		"touch %d, 0.2s %d, 0.6s %d" % [on_touch, part_way, settled],
	)

	# Bouncing away before the dwell is served forfeits it.
	_drain(limiter)
	limiter.note_contact(_contact_facing(-1.0, SurfaceKind.WALL), squishy)
	limiter.tick(0.2, SurfaceKind.WALL, squishy)
	limiter.tick(0.2, SurfaceKind.NONE, squishy)
	limiter.tick(0.4, SurfaceKind.WALL, squishy)
	_check(
		"leaving early forfeits the refill",
		limiter.charges == 0,
		"%d charges after bouncing off mid-dwell" % limiter.charges,
	)
	_restore(saved)


func _test_limiter_heat() -> void:
	var saved: Dictionary = _apply({"limiter_mode": LaunchLimiter.MODE_HEAT})
	var t: TuningData = TuningData.get_active()
	var squishy: BallForm = BallForm.make(BallForm.SQUISHY)
	var rocky: BallForm = BallForm.make(BallForm.ROCKY)
	var limiter: LaunchLimiter = LaunchLimiter.new()

	limiter.reset()
	limiter.note_launch(1.0, true)
	var ground_heat: float = limiter.heat
	limiter.reset()
	limiter.note_launch(1.0, false)
	var air_heat: float = limiter.heat
	_check(
		"an airborne shot costs more heat than a grounded one",
		air_heat > ground_heat,
		"air %.2f vs ground %.2f" % [air_heat, ground_heat],
	)

	# The documented design: heat never refuses a shot, it only weakens it. This is the behaviour
	# the Phaser project flagged as an open question (a patient player can still slow-climb), so
	# it is pinned here deliberately -- if it ever becomes a refusal, this check should fail first.
	limiter.heat = 1.0
	_check(
		"a fully hot ball still fires, weakly",
		limiter.can_launch(true) and limiter.launch_scale() < 1.0,
		"power x%.2f" % limiter.launch_scale(),
	)
	_check(
		"power at full heat matches the tuning",
		is_equal_approx(limiter.launch_scale(), 1.0 - t.heat_power_loss_at_max_heat),
		"x%.2f, expected x%.2f" % [limiter.launch_scale(), 1.0 - t.heat_power_loss_at_max_heat],
	)
	_check(
		"the ghost line shrinks at full heat",
		is_equal_approx(limiter.preview_scale(), 1.0 - t.heat_preview_shrink_at_max_heat),
		"x%.2f" % limiter.preview_scale(),
	)

	# Cooling rates: rock sheds heat, air barely does. That gap is what makes a chain of airborne
	# shots cost something, and it is the whole reason the mode works.
	var on_rock: float = _cooled_over(limiter, 1.0, SurfaceKind.WALL, squishy)
	var in_air: float = _cooled_over(limiter, 1.0, SurfaceKind.NONE, squishy)
	_check(
		"rock sheds heat far faster than air",
		on_rock > in_air * 10.0,
		"%.2f per second on rock vs %.2f in air" % [on_rock, in_air]
	)

	var rocky_on_glass: float = _cooled_over(limiter, 1.0, SurfaceKind.GLASS, rocky)
	var squishy_on_glass: float = _cooled_over(limiter, 1.0, SurfaceKind.GLASS, squishy)
	_check(
		"the rocky ball cools on glass faster than the squishy one",
		rocky_on_glass > squishy_on_glass,
		"rocky %.2f vs squishy %.2f" % [rocky_on_glass, squishy_on_glass],
	)
	_restore(saved)


func _test_limiter_elasticity() -> void:
	var saved: Dictionary = _apply({
		"limiter_mode": LaunchLimiter.MODE_ELASTICITY,
		"elasticity_scale_loss_by_power": true,
	})
	var t: TuningData = TuningData.get_active()
	var squishy: BallForm = BallForm.make(BallForm.SQUISHY)
	var limiter: LaunchLimiter = LaunchLimiter.new()

	limiter.reset()
	limiter.note_launch(1.0, true)
	var after_full: float = limiter.elasticity
	limiter.reset()
	limiter.note_launch(0.25, true)
	var after_gentle: float = limiter.elasticity
	_check(
		"a gentle shot wears the band less than a full pull",
		after_gentle > after_full,
		"gentle %.3f vs full %.3f" % [after_gentle, after_full],
	)

	limiter.reset()
	for _i: int in 40:
		limiter.note_launch(1.0, false)
	_check(
		"wear stops at the floor",
		is_equal_approx(limiter.elasticity, clampf(t.elasticity_min, 0.0, 1.0)),
		"%.3f, floor %.3f" % [limiter.elasticity, t.elasticity_min],
	)
	_check(
		"a worn band still fires, weakly",
		limiter.can_launch(true) and limiter.launch_scale() < 1.0,
		"power x%.2f" % limiter.launch_scale(),
	)

	var worn: float = limiter.elasticity
	limiter.tick(1.0, SurfaceKind.NONE, squishy)
	_check(
		"the band recovers with time",
		limiter.elasticity > worn,
		"%.3f -> %.3f over a second" % [worn, limiter.elasticity],
	)
	_restore(saved)


## Spend every charge, so the next thing tested starts from empty.
func _drain(limiter: LaunchLimiter) -> void:
	limiter.reset()
	for _i: int in maxi(1, TuningData.get_active().charges_max) + 2:
		limiter.note_launch(1.0, false)


## Heat shed over `seconds` resting on `material`, starting from fully hot.
func _cooled_over(limiter: LaunchLimiter, seconds: float, material: int, form: BallForm) -> float:
	limiter.heat = 1.0
	limiter.tick(seconds, material, form)
	return 1.0 - limiter.heat


## A contact whose surface faces `ny` (-1 is a floor, +1 a ceiling, 0 a wall).
func _contact_facing(ny: float, material: int) -> Contact:
	var at: BallState = BallState.new()
	return Contact.make(at, 0.0, ny, material, 300.0, 100.0, true, BallSim.is_horizontal_surface(ny))


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


## Write the list of Phaser values this port never found a home for.
##
## This asks a THROWAWAY TuningData to read the frozen export, rather than reading
## `get_active().unmapped_keys`. That used to work only as a side effect: `get_active()` loaded the
## JSON over the live values on first use, and the list fell out of it. Now that nothing loads the
## JSON on its own -- the authored defaults are the only source -- reading the live instance would
## report zero unmapped keys and overwrite this document with an empty file, which reads as "all
## ported" when it means "never asked".
##
## The throwaway instance also keeps the report honest in the other direction: it cannot disturb
## the values the tests above just ran against.
func _report_unmapped() -> void:
	var probe: TuningData = TuningData.new()
	var keys: PackedStringArray = probe.load_phaser_json(TuningData.PHASER_JSON_PATH).duplicate()
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
