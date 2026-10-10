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
##   gravity -> air drag -> rolling friction -> speed cap -> substepped movement with spike sweep
##   and contact resolution -> pending lift -> pass-through drag -> support probe -> roll-off ->
##   settle re-arm -> spin.
##
## Phase 2 scope: polygon terrain, glass (all five rocky modes, both bounce modes, the rising
## assist) and spikes. Fans, trampolines, cables, levers and pickups are later phases; where the
## Phaser step calls into them, the call site is marked.

## How many push-out passes per substep. Enough for a ball wedged into a corner.
const RESOLVE_PASSES: int = 4


## Advance one ball by one fixed step. Returns false when the run ended (spikes, or a policy that
## has seen enough).
static func step_ball(state: BallState, form: BallForm, world: StepWorld, dt: float, policy: StepPolicy) -> bool:
	var t: TuningData = TuningData.get_active()

	# Phase 1-2 have no fans, so the gravity scale is always 1. Fans multiply it in Phaser.
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

		# Later phases resolve levers, trampolines and cables before the static world here.
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
	if material == SurfaceKind.GLASS and not landing:
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

	var is_impact: bool = impact_speed > form.stop_bounce_threshold or boosted
	# A boost replaces the sideways speed itself, so landing friction must not scrub it again.
	if is_impact and not boosted and c.ny < -0.5:
		_apply_tangential_friction(state, c.nx, c.ny, form.landing_friction)
	# Steer a climbing bounce upward, after the physical result and the friction, so it has the
	# last word. Never on a landing: that is what the settle is for.
	if not landing:
		_apply_rising_assist(state, form, c.nx, c.ny, material, vy_before)

	if policy != null:
		var contact: Contact = Contact.make(state, c.nx, c.ny, material, impact_speed, out_speed, is_impact, landing)
		contact.boosted = boosted
		return policy.on_contact(contact)
	return true


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
static func ground_under(state: BallState, form: BallForm, world: StepWorld) -> Array:
	var probe_y: float = state.y + TuningData.get_active().world_edge_support_margin + 1.0
	for shape: ShapeBody in world.shapes:
		if not world.is_shape_solid(shape) or not GlassRules.is_solid_for(shape, form):
			continue
		var c: ShapeContact = shape.contact(state.x, probe_y, form.radius)
		if c != null and c.ny < -0.4:
			# Cladding the rock ignores reports as wall, so resting on it counts as rock.
			return [GlassRules.effective_material(shape, form), c.ny]
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
	return maxf(0.0, form.restitution_wall * t.surface_wall_restitution_multiplier)


## Rolling friction per material, in px/s^2.
static func friction_for(material: int) -> float:
	var t: TuningData = TuningData.get_active()
	return t.surface_glass_friction if material == SurfaceKind.GLASS else t.surface_wall_friction


static func _approach(current: float, target: float, max_delta: float) -> float:
	if current < target:
		return minf(current + max_delta, target)
	return maxf(current - max_delta, target)
