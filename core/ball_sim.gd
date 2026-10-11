class_name BallSim
extends RefCounted

## The shared ball simulation. Ported from `stepBall` and friends in
## src/systems/MaterialCollision.ts.
##
## THE RULE, carried over from the Phaser project: this is the only code that moves a ball. The
## real ball and the trajectory prediction both call `step_ball`, so they cannot drift apart. Any
## new force, bounce rule or surface goes in here, never in the ball node or the preview alone.
##
## The order of operations matters and is kept identical to the Phaser version:
##   moving actors -> fans -> gravity -> air drag -> rolling friction -> speed cap -> substepped
##   movement with spike sweep and contact resolution -> pending lift -> pass-through drag ->
##   support probe -> roll-off -> cable centring -> settle re-arm -> spin.
##
## Scope after phase 3: polygon terrain, glass (all five rocky modes, both bounce modes, the
## rising assist), spikes, trampolines, fans, cables and levers. Pickups and the juice layer are
## still to come.
##
## THE OTHER RULE, which phase 3 made load-bearing: the moving actors (cables and levers) are
## advanced ONCE per step, at the top, never inside the substep loop. Stepped per substep they
## would advance further for a fast ball than a slow one, and the ghost would drift from the ball
## even though both run this same function.

## How many push-out passes per substep. Enough for a ball wedged into a corner.
const RESOLVE_PASSES: int = 4


## Advance one ball by one fixed step. Returns false when the run ended (spikes, or a policy that
## has seen enough).
static func step_ball(state: BallState, form: BallForm, world: StepWorld, dt: float, policy: StepPolicy) -> bool:
	var t: TuningData = TuningData.get_active()

	# The moving actors advance first, ONCE per step and never per substep, so the ball and the
	# ghost always meet them in the same place at the same time. Stepping them inside the substep
	# loop would advance them further for a fast ball than a slow one.
	_step_cables(world, dt)
	_step_levers(world, dt)

	# A ball in a pipe is on a rail: no gravity, no drag, no contacts. The branch sits AFTER the
	# moving actors so the rest of the world keeps running while the ball is inside -- ropes still
	# swing, planks still settle -- and the ghost sees the same thing, because it runs this same
	# code from the same state.
	if state.pipe_id >= 0:
		_advance_in_pipe(state, world, dt)
		return true

	var entered: Pipe = _pipe_taking(state, world)
	if entered != null:
		_enter_pipe(state, entered)
		return true

	# Moving air next, so it is part of the same forces phase as gravity and the two can cancel:
	# a squishy ball in an upward stream hovers because the push and the weight land in the same
	# step, not because anything special-cases hovering.
	_apply_fans(state, form, world, dt)
	state.vy += t.world_gravity * form.gravity_multiplier * dt

	if form.air_drag > 0.0:
		var keep: float = maxf(0.0, 1.0 - form.air_drag * dt)
		state.vx *= keep
		state.vy *= keep

	if state.ground_material != SurfaceKind.NONE:
		var friction: float = friction_for(state.ground_material) * t.world_rolling_friction
		state.vx = _approach(state.vx, 0.0, friction * dt)

	var max_speed: float = t.world_max_ball_speed
	var speed_sq: float = state.vx * state.vx + state.vy * state.vy
	if speed_sq > max_speed * max_speed:
		var k: float = max_speed / sqrt(speed_sq)
		state.vx *= k
		state.vy *= k

	# Substep so the ball never moves more than half its radius at a time: a fast ball must not
	# clip a corner or tunnel through a thin ledge.
	var max_move: float = maxf(1.0, form.radius * 0.5)
	var travel: float = sqrt(state.vx * state.vx + state.vy * state.vy) * dt
	var substeps: int = maxi(1, int(ceil(travel / max_move)))
	var sdt: float = dt / float(substeps)

	for _i: int in substeps:
		var from_x: float = state.x
		var from_y: float = state.y
		state.x += state.vx * sdt
		state.y += state.vy * sdt
		# Spikes are checked along the path travelled, not just where the ball landed, so a fast
		# ball cannot be in front of a strip on one step and past it on the next.
		var hit: SpikeStrip = find_spikes(from_x, from_y, state, form, world)
		if hit != null:
			if policy != null:
				policy.on_spikes(hit, state)
			return false
		if not _resolve_contacts(state, form, world, policy):
			return false

	# A lift owed from under a ceiling is handed over as soon as the ball is clear of it.
	_release_pending_lift(state, form, world)
	_apply_pass_through_drag(state, form, world, dt)

	var support: Array = ground_under(state, form, world)
	state.ground_material = support[0] as int
	state.ground_ny = (support[1] as float) if state.ground_material != SurfaceKind.NONE else 0.0
	_apply_roll_off(state, form, world, dt)
	_apply_cable_centring(state, form, world, dt)
	_reset_settle_when_airborne(state, form)
	state.spin += (state.vx / maxf(1.0, form.radius)) * dt
	return true


## Push the ball out of everything it overlaps and bounce it, deepest contact first.
static func _resolve_contacts(state: BallState, form: BallForm, world: StepWorld, policy: StepPolicy) -> bool:
	for _pass: int in RESOLVE_PASSES:
		# Spikes come first and end everything: there is no bounce to resolve, the run is over.
		# This catches a ball already touching one -- resting against it, or pushed into it.
		var spikes: SpikeStrip = find_spikes(state.x, state.y, state, form, world)
		if spikes != null:
			if policy != null:
				policy.on_spikes(spikes, state)
			return false

		# Ropes before the static world: where a cable crosses a ledge, the thing the ball actually
		# touched first is the rope, and resolving the ledge first would push the ball through it.
		var rope: Array = find_cable_contact(state, form, world)
		if not rope.is_empty():
			if not _respond_to_cable(state, form, rope[0] as Cable, rope[1] as Dictionary, policy):
				return false
			continue

		var plank: Array = find_lever_contact(state, form, world)
		if not plank.is_empty():
			if not _respond_to_lever(state, form, plank[0] as Lever, plank[1] as Dictionary, policy):
				return false
			continue

		var found: Array = find_shape_contact(state, form, world)
		if found.is_empty():
			return true
		var shape: ShapeBody = found[0] as ShapeBody
		var contact: ShapeContact = found[1] as ShapeContact
		if not _respond_to_shape(state, form, shape, contact, world, policy):
			return false
	return true


## The deepest contact across every solid shape, or [] when the ball is clear.
static func find_shape_contact(state: BallState, form: BallForm, world: StepWorld) -> Array:
	var best_shape: ShapeBody = null
	var best_contact: ShapeContact = null
	for shape: ShapeBody in world.shapes:
		# Gone in this world (really broken, or broken earlier in this prediction).
		if not world.is_shape_solid(shape):
			continue
		# Pass-through glass is simply not there for the rocky ball.
		if not GlassRules.is_solid_for(shape, form):
			continue
		var c: ShapeContact = shape.contact(state.x, state.y, form.radius)
		if c == null:
			continue
		if best_contact == null or c.depth > best_contact.depth:
			best_shape = shape
			best_contact = c
	if best_contact == null:
		return []
	return [best_shape, best_contact]


## Bounce off a polygon. The normal comes from the closest point on the outline, so slopes, dips
## and angled glass all work with no special cases.
static func _respond_to_shape(
	state: BallState,
	form: BallForm,
	shape: ShapeBody,
	c: ShapeContact,
	world: StepWorld,
	policy: StepPolicy,
) -> bool:
	var approach: float = -(state.vx * c.nx + state.vy * c.ny)

	# Does the rock shatter this pane, or settle on it? "pass" never gets here: the glass was
	# skipped as non-solid before any contact was found.
	if shape.material == SurfaceKind.GLASS and GlassRules.would_break(shape, form, approach):
		var decision: int = StepPolicy.GLASS_BREAK
		if policy != null:
			decision = policy.on_glass(shape, state, approach)
		if decision == StepPolicy.GLASS_STOP:
			return false
		if decision == StepPolicy.GLASS_BREAK:
			state.vx *= form.glass_break_speed_keep
			state.vy *= form.glass_break_speed_keep
			var broke: Contact = Contact.make(state, c.nx, c.ny, SurfaceKind.GLASS, approach, 0.0, true, false)
			broke.broke_glass = true
			if policy != null:
				return policy.on_contact(broke)
			return true

	state.x += c.nx * c.depth
	state.y += c.ny * c.depth

	var vn: float = state.vx * c.nx + state.vy * c.ny
	if vn >= 0.0:
		return true

	var impact_speed: float = -vn
	var vy_before: float = state.vy
	# Cladding the rock is ignoring answers "wall" here, so it lands on it like rock.
	var material: int = GlassRules.effective_material(shape, form)
	# Coming down onto something that faces up is a LANDING, not a bounce off a wall: no glass
	# boost, no rising assist, just the settle. Without this the thing that makes glass ramps fun
	# also makes every glass ledge impossible to stand on.
	var landing: bool = is_horizontal_surface(c.ny)

	var out_speed: float = 0.0
	var boosted: bool = false
	var launched_off: bool = false
	# A trampoline launches whichever way it is hit, landing or not. This is deliberately NOT the
	# glass rule: glass gives up its boost on a landing so a glass ledge can be stood on, whereas
	# a pad that let you stand on it would not be a trampoline. The ball that cannot launch off one
	# falls through to the ordinary path below and settles on it normally.
	if material == SurfaceKind.TRAMPOLINE and form.launches_off_trampoline:
		out_speed = _apply_trampoline_launch(state, form, c.nx, c.ny, vn, impact_speed, shape.launch_speed)
		launched_off = out_speed > 0.0
	elif material == SurfaceKind.GLASS and not landing:
		out_speed = _apply_glass_bounce(state, form, c.nx, c.ny, vn, impact_speed, shape.bounce_boost)
		boosted = not form.breaks_glass and TuningData.get_active().glass_bounce_mode == 1
	else:
		var restitution: float = restitution_for(form, material)
		out_speed = impact_speed * restitution
		if out_speed < form.stop_bounce_threshold:
			out_speed = 0.0
		# Settle FIRST: it decides how much bounce a landing is allowed before the impulse is
		# applied. (Applying it afterwards was a real bug in the Phaser version: the number was
		# computed, reported, and then ignored, so the ball kept its full bounce.)
		if landing:
			out_speed = _settle_onto(state, form, c.nx, c.ny, out_speed)
		state.vx += c.nx * (out_speed - vn)
		state.vy += c.ny * (out_speed - vn)

	var is_impact: bool = impact_speed > form.stop_bounce_threshold or boosted or launched_off
	# A boost or a launch replaces the sideways speed itself, so landing friction must not scrub it
	# a second time.
	if is_impact and not boosted and not launched_off and c.ny < -0.5:
		_apply_tangential_friction(state, c.nx, c.ny, form.landing_friction)
	# Steer a climbing bounce upward, after the physical result and the friction, so it has the
	# last word. Never on a landing: that is what the settle is for. Never off a trampoline
	# either -- the pad already decided where the ball is going, and nudging it afterwards would
	# make a launch off a tilted pad land somewhere other than the ghost line promised.
	if not landing and not launched_off:
		_apply_rising_assist(state, form, c.nx, c.ny, material, vy_before)

	if policy != null:
		var contact: Contact = Contact.make(state, c.nx, c.ny, material, impact_speed, out_speed, is_impact, landing)
		contact.boosted = boosted
		contact.launched_off = launched_off
		return policy.on_contact(contact)
	return true


# ---------------------------------------------------------------- fans

## Add up every stream the ball is standing in. Fans hold no state, so this needs no copy for the
## prediction: the ghost calls the same function against the same fans and gets the same answer.
static func _apply_fans(state: BallState, form: BallForm, world: StepWorld, dt: float) -> void:
	if world.fans.is_empty():
		return
	var push: Vector2 = Vector2.ZERO
	for fan: FanField in world.fans:
		push += fan.accel_for(state.x, state.y, state.vx, state.vy, form, world)
	if push == Vector2.ZERO:
		return
	state.vx += push.x * dt
	state.vy += push.y * dt


## Is the ball being held up by a stream it could launch from? Used by the ball for
## `grounded.launchFromFan`, so a player carried by a fan is not stranded with no shot.
static func fan_support(state: BallState, form: BallForm, world: StepWorld) -> bool:
	for fan: FanField in world.fans:
		if fan.is_launchable_stream(state.x, state.y, form, world):
			return true
	return false


## Is the ball sitting still, just above something it could stand on?
##
## The support probe reaches `world.edgeSupportMargin` -- a few pixels -- because that is the right
## reach for deciding what the ball is *resting on*. It is the wrong reach for deciding whether a
## player is stranded. A ball can come to a dead stop a little clear of a surface: wedged in a dip
## whose normal is too steep to count, settled on a curve where the probe passes beside the
## contact, or held just off a ledge. None of those is airborne in any sense the player would
## recognise, and in a game with no walking a shot that will not fire there is the end of the run.
##
## So: near-stationary AND something flat within reach below. Both halves matter. Speed alone would
## hand a free shot to the apex of every vertical launch, where velocity passes through zero;
## requiring a surface within a ball's reach below means the only place it triggers is one the
## player would call standing.
##
## The speed test reuses `world.restMaxSpeed`, which is already this project's definition of "slow
## enough to count as resting", rather than inventing a second number that would drift from it.
static func hovering_support(state: BallState, form: BallForm, world: StepWorld) -> bool:
	var t: TuningData = TuningData.get_active()
	var reach: float = maxf(0.0, t.grounded_hover_reach)
	if reach <= 0.0:
		return false
	if state.vx * state.vx + state.vy * state.vy > t.world_rest_max_speed * t.world_rest_max_speed:
		return false
	var found: Array = ground_under(state, form, world, reach)
	return not found.is_empty() and is_horizontal_surface(found[1] as float)


# ---------------------------------------------------------------- levers

## Tip every plank by one step. Called once per `step_ball`, never per substep.
static func _step_levers(world: StepWorld, dt: float) -> void:
	for lever: Lever in world.levers:
		lever.step(dt)


## The deepest plank contact, or [] when the ball is clear of them all.
static func find_lever_contact(state: BallState, form: BallForm, world: StepWorld) -> Array:
	var best_lever: Lever = null
	var best_hit: Dictionary = {}
	for lever: Lever in world.levers:
		var hit: Dictionary = lever.contact_for(state.x, state.y, form.radius)
		if hit.is_empty():
			continue
		if best_hit.is_empty() or (hit["depth"] as float) > (best_hit["depth"] as float):
			best_lever = lever
			best_hit = hit
	if best_hit.is_empty():
		return []
	return [best_lever, best_hit]


## Land on a plank. The ball bounces off it and loads it at the same time, which is the two-way
## coupling that makes a lever a lever rather than a moving floor.
##
## The bounce is measured against the plank's own surface speed, not against the world, so a
## plank tipping away from the ball does not hit it as hard as a plank tipping into it. Without
## that a lever on the way down would still bounce a ball as if it were static.
static func _respond_to_lever(
	state: BallState,
	form: BallForm,
	lever: Lever,
	hit: Dictionary,
	policy: StepPolicy,
) -> bool:
	var n: Vector2 = hit["normal"] as Vector2
	var point: Vector2 = hit["point"] as Vector2
	state.x += n.x * (hit["depth"] as float)
	state.y += n.y * (hit["depth"] as float)

	# The ball's weight bears on the plank for as long as it is touching, bounce or no bounce.
	lever.load_from(point, form)

	var surface: Vector2 = lever.surface_velocity_at(point)
	var relative_x: float = state.vx - surface.x
	var relative_y: float = state.vy - surface.y
	var vn: float = relative_x * n.x + relative_y * n.y
	if vn >= 0.0:
		return true
	var impact_speed: float = -vn

	# A landing kicks it as well as loading it.
	lever.strike(point, form, impact_speed)

	var restitution: float = restitution_for(form, SurfaceKind.WALL)
	var out_speed: float = impact_speed * restitution
	if out_speed < form.stop_bounce_threshold:
		out_speed = 0.0
	# Applied to the RELATIVE velocity, then handed back to the world, so the plank carries the
	# ball with it instead of sliding out from under it.
	relative_x += n.x * (out_speed - vn)
	relative_y += n.y * (out_speed - vn)
	state.vx = relative_x + surface.x
	state.vy = relative_y + surface.y

	var landing: bool = is_horizontal_surface(n.y)
	if landing:
		_apply_tangential_friction(state, n.x, n.y, form.landing_friction)

	if policy != null:
		var contact: Contact = Contact.make(
			state, n.x, n.y, SurfaceKind.WALL, impact_speed, out_speed,
			impact_speed > form.stop_bounce_threshold, landing,
		)
		return policy.on_contact(contact)
	return true


# ---------------------------------------------------------------- cables

## Swing every rope by one step. Called once per `step_ball`, never per substep.
static func _step_cables(world: StepWorld, dt: float) -> void:
	for cable: Cable in world.cables:
		cable.step(dt)


## The deepest rope contact the ball is actually stopped by, or [] when it is clear of them all.
## A rope the ball is passing up through reports nothing: that is the one-way floor.
static func find_cable_contact(state: BallState, form: BallForm, world: StepWorld) -> Array:
	var best_cable: Cable = null
	var best_hit: Dictionary = {}
	for cable: Cable in world.cables:
		var hit: Dictionary = cable.contact_for(state.x, state.y, form.radius)
		if hit.is_empty() or not cable.is_solid_from(state.y, hit):
			continue
		if best_hit.is_empty() or (hit["depth"] as float) > (best_hit["depth"] as float):
			best_cable = cable
			best_hit = hit
	if best_hit.is_empty():
		return []
	return [best_cable, best_hit]


## Land on a rope. The rope gives, then throws.
##
## Two throws, chosen by `cables.sustainBounce`, and they are the same pair of choices glass has:
## OFF is a plain physical bounce at the ball's own `cableBounce`, ON always throws to the ball's
## `sustainedCableHeight` whatever the drop. `cables.impactBonus` applies only to the sustained
## throw, exactly as glass's `boostImpactGain` applies only in Boost mode -- in the physical case
## the bounce already scales with the impact, so adding a bonus would count it twice.
static func _respond_to_cable(
	state: BallState,
	form: BallForm,
	cable: Cable,
	hit: Dictionary,
	policy: StepPolicy,
) -> bool:
	var t: TuningData = TuningData.get_active()
	var n: Vector2 = hit["normal"] as Vector2
	state.x += n.x * (hit["depth"] as float)
	state.y += n.y * (hit["depth"] as float)

	var vn: float = state.vx * n.x + state.vy * n.y
	if vn >= 0.0:
		return true
	var impact_speed: float = -vn

	# The rope takes the hit before it returns it, and then stops ringing.
	cable.absorb(hit["index"] as int, n, impact_speed)
	cable.settle_after_impact()

	var out_speed: float = 0.0
	var sustained: bool = t.cables_sustain_bounce
	if sustained:
		# The speed that reaches exactly that height under this ball's own gravity.
		var height: float = maxf(0.0, form.sustained_cable_height)
		var rise: float = sqrt(2.0 * t.world_gravity * form.gravity_multiplier * height)
		out_speed = rise + maxf(0.0, t.cables_impact_bonus) * impact_speed
		# A sustained throw REPLACES the speed along the normal and only scales the tangent, the
		# same split the trampoline and the glass boost use.
		var tx: float = state.vx - n.x * vn
		var ty: float = state.vy - n.y * vn
		state.vx = tx + n.x * out_speed
		state.vy = ty + n.y * out_speed
	else:
		out_speed = impact_speed * maxf(0.0, form.cable_bounce)
		if out_speed < form.stop_bounce_threshold:
			out_speed = 0.0
		state.vx += n.x * (out_speed - vn)
		state.vy += n.y * (out_speed - vn)

	if policy != null:
		var contact: Contact = Contact.make(
			state, n.x, n.y, SurfaceKind.CABLE, impact_speed, out_speed,
			impact_speed > form.stop_bounce_threshold or sustained, is_horizontal_surface(n.y),
		)
		return policy.on_contact(contact)
	return true


## Roll a ball resting on a rope towards the middle of it, so it finds the low point instead of
## balancing near an anchor. Gravity along the rope already does some of this; the bias makes it
## prompt, the way `world.rollOffStrength` does for a ledge edge.
static func _apply_cable_centring(state: BallState, form: BallForm, world: StepWorld, dt: float) -> void:
	var bias: float = TuningData.get_active().cables_centring_bias
	if bias <= 0.0 or world.cables.is_empty():
		return
	var rope: Array = find_cable_contact(state, form, world)
	if rope.is_empty():
		return
	var cable: Cable = rope[0] as Cable
	var hit: Dictionary = rope[1] as Dictionary
	var along: float = hit["along"] as float
	# Dead centre already: nothing to do, and no direction to pick either.
	if is_equal_approx(along, 0.5):
		return
	var tangent: Vector2 = cable.tangent_at(hit["index"] as int)
	var towards_middle: float = signf(0.5 - along)
	state.vx += tangent.x * towards_middle * bias * dt
	state.vy += tangent.y * towards_middle * bias * dt


# ---------------------------------------------------------------- trampolines

## A launch off a pad, along its normal. Returns the speed leaving along that normal.
##
## The same split as the glass boost, and for the same reason: the normal component is REPLACED by
## the pad's own speed while the tangent is only scaled, so the pad decides how hard the ball
## leaves and the approach decides where it goes. `trampoline.launchSpeed`, `impactBonus` and
## `horizontalKeep` line up one for one with glass's `boostStrength`, `boostImpactGain` and
## `boostSidewaysKeep`, which is why phase 2 could already describe the glass boost as
## "trampoline-style": this is that same move with the pad's numbers.
##
## Unlike the glass boost there is no cap of its own -- `world.maxBallSpeed` catches it on the next
## step, and the shipped `launchSpeed` of 1150 sits under that 1400 anyway.
static func _apply_trampoline_launch(
	state: BallState,
	form: BallForm,
	nx: float,
	ny: float,
	vn: float,
	impact_speed: float,
	override: float,
) -> float:
	var t: TuningData = TuningData.get_active()
	var base: float = override if override >= 0.0 else t.trampoline_launch_speed
	# A harder landing throws the ball further, so a pad rewards arriving fast.
	var wanted: float = (base + maxf(0.0, t.trampoline_impact_bonus) * impact_speed) * form.trampoline_bounce
	if wanted <= 0.0:
		return 0.0

	var tx: float = state.vx - nx * vn
	var ty: float = state.vy - ny * vn
	var keep: float = maxf(0.0, t.trampoline_horizontal_keep)
	state.vx = tx * keep + nx * wanted
	state.vy = ty * keep + ny * wanted
	return wanted


# ---------------------------------------------------------------- glass

## A bounce off glass: a plain reflection, or a trampoline-style launch along the normal.
## Ported from applyGlassBounce. Returns the speed leaving along the normal.
static func _apply_glass_bounce(
	state: BallState,
	form: BallForm,
	nx: float,
	ny: float,
	vn: float,
	impact_speed: float,
	override: float,
) -> float:
	var t: TuningData = TuningData.get_active()
	var restitution: float = restitution_for(form, SurfaceKind.GLASS)

	# A ball that breaks glass never gets boosted off it, and Reflect is a plain bounce.
	if form.breaks_glass or t.glass_bounce_mode != 1:
		var out_speed: float = impact_speed * restitution
		if out_speed < form.stop_bounce_threshold:
			out_speed = 0.0
		state.vx += nx * (out_speed - vn)
		state.vy += ny * (out_speed - vn)
		return out_speed

	var strength: float = override if override >= 0.0 else t.glass_boost_strength
	var wanted: float = maxf(strength, strength + impact_speed * maxf(0.0, t.glass_boost_impact_gain))

	# Split the velocity into the part along the normal and the part across it, so each can be
	# treated separately: the normal is replaced by the boost, the tangent is only scaled.
	var tx: float = state.vx - nx * vn
	var ty: float = state.vy - ny * vn
	var keep: float = maxf(0.0, t.glass_boost_sideways_keep)
	var speed_out: float = wanted
	var next_x: float = tx * keep + nx * speed_out
	var next_y: float = ty * keep + ny * speed_out

	# Cap the whole result, not just the normal part, or a fast glancing hit still escalates.
	var cap: float = maxf(0.0, t.glass_boost_max_speed)
	var speed: float = sqrt(next_x * next_x + next_y * next_y)
	if cap > 0.0 and speed > cap:
		var scale: float = cap / speed
		next_x *= scale
		next_y *= scale
		speed_out *= scale

	state.vx = next_x
	state.vy = next_y
	return speed_out


## Inside a pane the rock is passing through: shed a little speed. Ported from
## applyPassThroughDrag.
static func _apply_pass_through_drag(state: BallState, form: BallForm, world: StepWorld, dt: float) -> void:
	var drag: float = TuningData.get_active().glass_pass_through_drag
	if not form.breaks_glass or drag <= 0.0:
		return

	var inside: bool = false
	for shape: ShapeBody in world.shapes:
		if shape.material != SurfaceKind.GLASS or not world.is_shape_solid(shape):
			continue
		if GlassRules.is_solid_for(shape, form):
			continue
		if shape.contact(state.x, state.y, form.radius) != null:
			inside = true
			break
	if not inside:
		return

	var keep: float = maxf(0.0, 1.0 - drag * dt)
	state.vx *= keep
	state.vy *= keep


# ---------------------------------------------------------------- rising assist

## Steer a climbing bounce upward, so a rising shot is never cut short by an unlucky angle.
## Ported from applyRisingAssist, including the skim lift under downward-facing surfaces.
static func _apply_rising_assist(
	state: BallState,
	form: BallForm,
	nx: float,
	ny: float,
	material: int,
	vy_before: float,
) -> void:
	var t: TuningData = TuningData.get_active()
	if not form.rising_assist or t.bounce_style != 1:
		return
	# Screen y points down, so rising is negative.
	if -vy_before <= maxf(0.0, t.rising_threshold):
		return

	var glass: bool = material == SurfaceKind.GLASS
	if not (t.rising_glass_enabled if glass else t.rising_wall_enabled):
		return
	var strength: float = clampf(t.rising_glass_strength if glass else t.rising_wall_strength, 0.0, 1.0)
	if strength <= 0.0:
		return
	var min_angle: float = clampf(t.rising_glass_min_angle if glass else t.rising_wall_min_angle, 0.0, 89.0)
	var min_up: float = maxf(0.0, t.rising_glass_min_up_speed if glass else t.rising_wall_min_up_speed)

	# A surface whose normal points downward cannot throw anything upward. Remember the lift and
	# let the ball skim out from under it.
	if ny > 0.02:
		if t.rising_skim_lift:
			state.pending_lift = maxf(state.pending_lift, min_up * strength)
		return

	var speed: float = sqrt(state.vx * state.vx + state.vy * state.vy)
	if speed < 0.0001:
		return

	# 1. Lift the direction into the cone, keeping its left/right sense.
	var want_sin: float = sin(deg_to_rad(min_angle))
	var dir_x: float = state.vx / speed
	var dir_y: float = state.vy / speed
	if -dir_y < want_sin:
		var side: float = (1.0 if nx >= 0.0 else -1.0) if dir_x == 0.0 else signf(dir_x)
		var lifted_x: float = side * cos(deg_to_rad(min_angle))
		var lifted_y: float = -want_sin
		# Blend towards the lifted direction by the assist's strength, then renormalise.
		dir_x += (lifted_x - dir_x) * strength
		dir_y += (lifted_y - dir_y) * strength
		var length: float = sqrt(dir_x * dir_x + dir_y * dir_y)
		if length == 0.0:
			length = 1.0
		dir_x /= length
		dir_y /= length

	# 2. Never aim into the surface. If the lift turned the direction inward, slide it along the
	# surface on the open side instead of forcing it through.
	if dir_x * nx + dir_y * ny < 0.0:
		var along_x: float = -ny
		var along_y: float = nx
		var sign_along: float = 1.0 if dir_x * along_x + dir_y * along_y >= 0.0 else -1.0
		dir_x = along_x * sign_along
		dir_y = along_y * sign_along
		# Sliding along a surface that still points downward gains nothing, so bank the lift.
		if dir_y > 0.0 and t.rising_skim_lift:
			state.pending_lift = maxf(state.pending_lift, min_up * strength)

	state.vx = dir_x * speed
	state.vy = dir_y * speed

	# 3. Floor on the upward speed, raising it only as far as the floor, never beyond.
	var want_up: float = min_up * strength
	if -state.vy < want_up:
		state.vy = -want_up


## Hand over a lift owed from under a ceiling, once the ball is clear of it.
static func _release_pending_lift(state: BallState, form: BallForm, world: StepWorld) -> void:
	var owed: float = state.pending_lift
	if owed <= 0.0:
		return
	var t: TuningData = TuningData.get_active()
	if not form.rising_assist or t.bounce_style != 1 or not t.rising_skim_lift:
		state.pending_lift = 0.0
		return

	# Still under something? Keep holding it. The probe reaches a good two radii up on purpose: a
	# shallower one clears the instant the ball is pushed out of the surface, fires the lift, and
	# sends it straight back into the same ceiling -- an endless rattle rather than a skim.
	var probe_y: float = state.y - form.radius * 2.0
	var probe_r: float = form.radius * 0.9
	for shape: ShapeBody in world.shapes:
		if not world.is_shape_solid(shape):
			continue
		if shape.contact(state.x, probe_y, probe_r) != null:
			return

	state.pending_lift = 0.0
	if -state.vy < owed:
		state.vy = -owed


# ---------------------------------------------------------------- spikes

## The first spike strip the ball touched on its way from (from_x, from_y) to where it is now.
static func find_spikes(
	from_x: float,
	from_y: float,
	state: BallState,
	form: BallForm,
	world: StepWorld,
) -> SpikeStrip:
	for strip: SpikeStrip in world.spikes:
		if strip.sweep(from_x, from_y, state.x, state.y, form.radius):
			return strip
	return null


# ---------------------------------------------------------------- surfaces and settling

## Is this surface flat enough to count as a floor?
##
## One definition, used by three things that must agree: the settle, grounded launches, and the
## rule that a landing is not a wall bounce. If they disagreed the ball could settle somewhere it
## is not allowed to launch from, which reads as the game being broken.
static func is_horizontal_surface(ny: float) -> bool:
	var tolerance: float = clampf(TuningData.get_active().grounded_surface_tolerance, 0.0, 89.0)
	return ny <= -cos(deg_to_rad(tolerance))


## Landing on a floor: a couple of quickly shrinking hops, strong grip, then it stays put.
static func _settle_onto(state: BallState, form: BallForm, nx: float, ny: float, out_speed: float) -> float:
	if not form.settles_on_landing or not is_horizontal_surface(ny):
		return out_speed

	var hops_done: int = state.settle_hops
	var left: int = maxi(0, form.settle_hops - hops_done)
	state.settle_hops = hops_done + 1

	# Each hop is a fraction of the last, so two or three land in well under a second.
	var height: float = form.settle_bounce_height * pow(0.45, float(hops_done))
	var hop_speed: float = 0.0
	if left > 0:
		hop_speed = sqrt(2.0 * TuningData.get_active().world_gravity * form.gravity_multiplier * maxf(0.0, height))

	# Grip: a landing scrubs the sideways speed hard, so the ball stays where it came down.
	var tx: float = -ny
	var ty: float = nx
	var vt: float = state.vx * tx + state.vy * ty
	var keep: float = maxf(0.0, 1.0 - form.landing_grip)
	state.vx += tx * (vt * keep - vt)
	state.vy += ty * (vt * keep - vt)

	return minf(out_speed, hop_speed)


## Re-arm the settle once the ball is genuinely flying again.
##
## The test has to be stricter than "off the ground and moving up", because a settle hop is
## itself off the ground and moving up: that reset the count every hop and bounced the ball at
## the same height forever. A real departure is faster than the first hop could ever be.
static func _reset_settle_when_airborne(state: BallState, form: BallForm) -> void:
	if state.ground_material != SurfaceKind.NONE:
		return
	var first_hop: float = sqrt(
		2.0 * TuningData.get_active().world_gravity * form.gravity_multiplier * maxf(0.0, form.settle_bounce_height)
	)
	if -state.vy > first_hop * 1.3 + 40.0:
		state.settle_hops = 0


## What is under the ball, and how flat it is. Returns [material, ny].
static func ground_under(state: BallState, form: BallForm, world: StepWorld, extra_reach: float = 0.0) -> Array:
	var probe_y: float = state.y + TuningData.get_active().world_edge_support_margin + 1.0 + maxf(0.0, extra_reach)
	for shape: ShapeBody in world.shapes:
		if not world.is_shape_solid(shape) or not GlassRules.is_solid_for(shape, form):
			continue
		var c: ShapeContact = shape.contact(state.x, probe_y, form.radius)
		if c != null and c.ny < -0.4:
			# Cladding the rock ignores reports as wall, so resting on it counts as rock.
			return [GlassRules.effective_material(shape, form), c.ny]

	# A rope holds a ball up too, and a ball lying in one has to know it: otherwise it never gets
	# the rope's rolling friction, never counts as launchable ground, and a squishy ball that came
	# to rest in a cable would be stuck there with no shot available.
	for cable: Cable in world.cables:
		var hit: Dictionary = cable.contact_for(state.x, probe_y, form.radius)
		if hit.is_empty() or not cable.is_solid_from(probe_y, hit):
			continue
		var n: Vector2 = hit["normal"] as Vector2
		if n.y < -0.4:
			return [SurfaceKind.CABLE, n.y]

	# A plank is a floor too, and a tilting one is a floor that can be launched from, which is how
	# a lever becomes a route rather than just a thing that moves.
	for lever: Lever in world.levers:
		var plank: Dictionary = lever.contact_for(state.x, probe_y, form.radius)
		if plank.is_empty():
			continue
		var pn: Vector2 = plank["normal"] as Vector2
		if pn.y < -0.4:
			return [SurfaceKind.WALL, pn.y]
	return [SurfaceKind.NONE, 0.0]


## Touching something but not supported means the centre is past the edge: the ball is balanced
## on a corner. Gravity already pulls it along the angled surface; this exaggerates that so it
## tips off promptly instead of creeping.
static func _apply_roll_off(state: BallState, form: BallForm, world: StepWorld, dt: float) -> void:
	if state.ground_material != SurfaceKind.NONE:
		return
	var extra: float = TuningData.get_active().world_roll_off_strength - 1.0
	if extra <= 0.0:
		return

	var found: Array = find_shape_contact(state, form, world)
	if found.is_empty():
		return
	var c: ShapeContact = found[1] as ShapeContact
	# Only a slope tips: a flat face has nowhere to roll.
	if absf(c.nx) < 0.05 or absf(c.ny) < 0.05:
		return

	var tangent_x: float = -c.ny
	var tangent_y: float = c.nx
	# Gravity is (0, g); its component along the tangent is g * tangent_y.
	var gravity: float = TuningData.get_active().world_gravity * form.gravity_multiplier
	var along: float = gravity * tangent_y * extra * dt
	state.vx += tangent_x * along
	state.vy += tangent_y * along


static func _apply_tangential_friction(state: BallState, nx: float, ny: float, keep: float) -> void:
	var tangent_x: float = -ny
	var tangent_y: float = nx
	var vt: float = state.vx * tangent_x + state.vy * tangent_y
	var delta: float = vt * keep - vt
	state.vx += tangent_x * delta
	state.vy += tangent_y * delta


## Final bounce a form gets off a material: ball bounce x surface multiplier.
static func restitution_for(form: BallForm, material: int) -> float:
	var t: TuningData = TuningData.get_active()
	if material == SurfaceKind.GLASS:
		return maxf(0.0, form.restitution_glass * t.surface_glass_restitution_multiplier)
	# Only ever reached by a ball that cannot launch off a pad, since the launcher is handled
	# before the restitution path is taken at all. The shipped 0.12 makes a trampoline nearly dead
	# underfoot for the squishy ball, which is what makes it the rocky ball's route.
	if material == SurfaceKind.TRAMPOLINE:
		return maxf(0.0, t.trampoline_squishy_bounce)
	return maxf(0.0, form.restitution_wall * t.surface_wall_restitution_multiplier)


## Rolling friction per material, in px/s^2. Trampolines have no friction of their own in the
## Phaser tuning, so they grip like rock; a rope has its own, and it is slippery by comparison.
static func friction_for(material: int) -> float:
	var t: TuningData = TuningData.get_active()
	match material:
		SurfaceKind.GLASS:
			return t.surface_glass_friction
		SurfaceKind.CABLE:
			return t.cables_rolling_friction
	return t.surface_wall_friction


static func _approach(current: float, target: float, max_delta: float) -> float:
	if current < target:
		return minf(current + max_delta, target)
	return maxf(current - max_delta, target)


# ---------------------------------------------------------------- pipes

## The pipe this ball is being drawn into, or null.
static func _pipe_taking(state: BallState, world: StepWorld) -> Pipe:
	for pipe: Pipe in world.pipes:
		if pipe.entry_for(state.x, state.y, state.vx, state.vy) >= 0.0:
			return pipe
	return null


## Take the ball onto the rail.
##
## The speed carried in is the speed it arrived with, so a hard shot comes out hard and the
## preview stays honest about it -- but never below `pipes.minSpeed`, because a ball that crawls
## to a halt inside a pipe cannot launch and cannot walk out.
static func _enter_pipe(state: BallState, pipe: Pipe) -> void:
	var t: TuningData = TuningData.get_active()
	var at: float = pipe.entry_for(state.x, state.y, state.vx, state.vy)
	var speed: float = Vector2(state.vx, state.vy).length() * maxf(0.0, t.pipes_speed_keep)

	state.pipe_id = pipe.id
	state.pipe_distance = at
	state.pipe_heading = 1.0 if at <= 0.0 else -1.0
	state.pipe_speed = maxf(speed, t.pipes_min_speed)

	var where: Vector2 = pipe.point_at(at)
	state.x = where.x
	state.y = where.y
	# Nothing is supporting it, and a stale ground material would give it friction and a launch it
	# should not have while it is inside.
	state.ground_material = SurfaceKind.NONE
	state.settle_hops = 0
	state.pending_lift = 0.0


## Carry the ball along, and put it out of whichever end it reaches.
static func _advance_in_pipe(state: BallState, world: StepWorld, dt: float) -> void:
	var pipe: Pipe = _pipe_by_id(world, state.pipe_id)
	if pipe == null or not pipe.is_usable():
		# The pipe is gone from under it -- let it fall rather than freeze in mid-air.
		_leave_pipe(state, Vector2.DOWN, 0.0)
		return

	state.pipe_distance += state.pipe_speed * state.pipe_heading * dt

	if state.pipe_distance <= 0.0 or state.pipe_distance >= pipe.length():
		var end: float = 0.0 if state.pipe_distance <= 0.0 else pipe.length()
		var out: Vector2 = pipe.point_at(end)
		state.x = out.x
		state.y = out.y
		# Leaving along the pipe, in the direction of travel. `direction_at` always points towards
		# the far end, so a ball going backwards leaves against it.
		_leave_pipe(state, pipe.direction_at(end) * state.pipe_heading, state.pipe_speed)
		return

	var here: Vector2 = pipe.point_at(state.pipe_distance)
	state.x = here.x
	state.y = here.y
	# Kept in step with the rail so anything reading velocity -- the camera, the visuals, the
	# aim -- sees the ball moving the way it looks like it is moving.
	var heading: Vector2 = pipe.direction_at(state.pipe_distance) * state.pipe_heading
	state.vx = heading.x * state.pipe_speed
	state.vy = heading.y * state.pipe_speed
	state.spin += state.pipe_speed / maxf(1.0, _radius_of(state)) * dt


static func _leave_pipe(state: BallState, heading: Vector2, speed: float) -> void:
	var out: Vector2 = heading.normalized() if heading.length_squared() > 0.0 else Vector2.DOWN
	state.vx = out.x * speed
	state.vy = out.y * speed
	state.pipe_id = -1
	state.pipe_distance = 0.0
	state.pipe_heading = 1.0
	state.pipe_speed = 0.0


static func _pipe_by_id(world: StepWorld, pipe_id: int) -> Pipe:
	for pipe: Pipe in world.pipes:
		if pipe.id == pipe_id:
			return pipe
	return null


## The rolling radius for spin while in transit. The form is not passed this far down, and the two
## forms are the same circle, so either serves.
static func _radius_of(_state: BallState) -> float:
	return maxf(1.0, TuningData.get_active().squishy_radius)
