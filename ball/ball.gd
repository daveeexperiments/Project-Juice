class_name Ball
extends Node2D

## The playable ball. Ported from src/entities/Ball.ts.
##
## It owns a BallState and hands it to the shared simulation every physics tick; it never moves
## itself. Visuals are drawn from the state afterwards, so nothing about the look can feed back
## into where the ball goes.
##
## Placeholder art, as specified: squishy is a hollow ink circle, rocky a solid one, with a
## simple squash on impact.

signal contacted(contact: Contact)
signal launched(power: float)
signal form_switched(form_id: int)
## A pane the rocky ball just shattered. The level removes it and plays the shatter.
signal glass_broken(shape: ShapeBody)
## Touched spikes. The level wipes the ball out and sends it back to the last flag.
signal spiked(strip: SpikeStrip)

const INK: Color = Color("141414")
const PAPER: Color = Color("f6f3ec")

var state: BallState = BallState.new()
var form: BallForm = BallForm.make(BallForm.SQUISHY)
## Held in the slingshot cradle: the simulation is paused but the ball still counts as grounded.
var held: bool = false
## Seconds since the ball was last supported, for coyote time.
var air_time: float = 0.0
## Seconds since the ball was last standing on something it could launch from. Ported from
## LaunchLimiter.sinceGrounded, which is what gives Grounded mode its coyote window.
var since_launchable: float = INF
## What stops the player launching for ever: charges, heat or a tiring band, depending on the
## mode. It never moves the ball, so it lives beside the simulation rather than inside it.
var limiter: LaunchLimiter = LaunchLimiter.new()

var _world: StepWorld = null
var _policy: StepPolicy = null
var _squash: Vector2 = Vector2.ONE
var _squash_recover: float = 0.0


func _ready() -> void:
	_policy = BallContactPolicy.new(self)
	GameState.form_changed.connect(_on_form_changed)
	form = BallForm.make(GameState.form_id)


func setup(world: StepWorld, start: Vector2) -> void:
	_world = world
	state.x = start.x
	state.y = start.y
	state.vx = 0.0
	state.vy = 0.0
	state.ground_material = SurfaceKind.NONE
	state.settle_hops = 0
	since_launchable = INF
	air_time = 0.0
	# A death must never leave the player stranded with an empty budget.
	limiter.reset()
	position = start


## One fixed step. The scene calls this; the ball never steps itself from _process.
func step(dt: float) -> void:
	if held:
		air_time = 0.0
		# Cooling and regeneration carry on in the cradle: waiting is how a hot ball recovers.
		limiter.tick(dt, state.ground_material, form)
		return
	if _world == null:
		return
	BallSim.step_ball(state, form, _world, dt, _policy)
	air_time = 0.0 if grounded else air_time + dt
	since_launchable = 0.0 if on_launchable_ground else since_launchable + dt
	limiter.tick(dt, state.ground_material, form)


func sync_visuals(delta: float) -> void:
	position = Vector2(state.x, state.y)
	if _squash_recover > 0.0:
		_squash_recover = maxf(0.0, _squash_recover - delta * 6.0)
		_squash = _squash.lerp(Vector2.ONE, 1.0 - _squash_recover)
	queue_redraw()


var grounded: bool:
	get:
		return state.ground_material != SurfaceKind.NONE

## Grounded, or left a surface within the coyote window.
var counts_as_grounded: bool:
	get:
		return grounded or air_time <= TuningData.get_active().slingshot_coyote_time

var radius: float:
	get:
		return form.radius


## Is the ball standing on something flat enough to launch from? The whole of Grounded mode.
var on_launchable_ground: bool:
	get:
		if held:
			return true
		if state.ground_material != SurfaceKind.NONE:
			return BallSim.is_horizontal_surface(state.ground_ny)
		if _world == null:
			return false
		# An upward stream counts as something to stand on, when `grounded.launchFromFan` says so.
		# Without it a squishy ball hovering in a fan would have no shot available and no way down
		# but to drift out -- held up by the level and stuck in it at the same time. Anywhere the
		# stream would push a stationary ball counts, so its taper and its edges are included, not
		# just the core.
		if BallSim.fan_support(state, form, _world):
			return true
		# ...and so does having stopped dead just above something flat. Same reasoning as the fan:
		# the player is somewhere the level put them, and no shot from there is a dead end.
		return BallSim.hovering_support(state, form, _world)


## True while Grounded mode would let a shot go: on launchable ground, or inside the coyote
## window just after leaving it. Ported from LaunchLimiter.grounded.
##
## Every mode is handed this answer, because every mode still treats a grounded shot differently
## from an airborne one -- a shot off a surface is cheaper in heat and in wear, and is the only
## shot Grounded mode permits at all.
var grounded_launch_ok: bool:
	get:
		if held or on_launchable_ground:
			return true
		return since_launchable <= maxf(0.0, TuningData.get_active().grounded_coyote_time)


## True while the ACTIVE limiter mode will let a shot go. This is what the slingshot asks.
var can_launch_now: bool:
	get:
		return limiter.can_launch(grounded_launch_ok)


## Throw the ball. Ported from Ball.launch: a launch always leaves the ground and uses up the
## coyote grace, so one shot can never become two.
func launch(vx: float, vy: float, power: float = 1.0) -> void:
	# Read this BEFORE anything below, because the launch itself burns the coyote grace and the
	# ground material -- after that there is no way to tell a grounded shot from an airborne one,
	# and every limiter mode charges differently for the two.
	var was_grounded: bool = grounded_launch_ok
	held = false
	air_time = INF
	since_launchable = INF  # A launch uses up the coyote grace, so one shot cannot become two.
	state.vx = vx
	state.vy = vy
	state.ground_material = SurfaceKind.NONE
	state.settle_hops = 0
	limiter.note_launch(power, was_grounded)
	launched.emit(power)


## Swap form, keeping position and velocity. Gravity changes at once; bounce rules apply from the
## next contact. Ported from Ball.setForm plus resolveOverlap.
func set_form(form_id: int) -> void:
	if form_id == form.id:
		return
	form = BallForm.make(form_id)
	_resolve_overlap()
	form_switched.emit(form_id)


## A bigger radius after a switch must not leave the ball inside a wall. Ported from
## Ball.resolveOverlap: step outward in rings until a free spot is found.
func _resolve_overlap() -> void:
	if _world == null or not _overlaps_solid(state.x, state.y):
		return
	var r: float = form.radius
	var max_push: int = int(ceil(r * 2.0 + 32.0))
	var dirs: Array[Vector2] = [
		Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0),
		Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(),
		Vector2(-1, 1).normalized(), Vector2(1, 1).normalized(),
	]
	for d: int in range(1, max_push + 1):
		for dir: Vector2 in dirs:
			var nx: float = state.x + dir.x * float(d)
			var ny: float = state.y + dir.y * float(d)
			if not _overlaps_solid(nx, ny):
				state.x = nx
				state.y = ny
				return


func _overlaps_solid(x: float, y: float) -> bool:
	for shape: ShapeBody in _world.shapes:
		if shape.contact(x, y, form.radius) != null:
			return true
	return false


func squash_from(contact: Contact) -> void:
	var amount: float = form.squash_amount
	if amount <= 0.0:
		return
	var s: float = clampf(contact.impact_speed / maxf(1.0, form.max_launch_speed), 0.0, 1.0) * amount
	_squash = Vector2(
		1.0 - s * absf(contact.nx) + s * 0.6 * absf(contact.ny),
		1.0 - s * absf(contact.ny) + s * 0.6 * absf(contact.nx),
	)
	_squash_recover = 1.0


func _on_form_changed(form_id: int) -> void:
	set_form(form_id)


func _draw() -> void:
	var r: float = form.radius
	draw_set_transform(Vector2.ZERO, state.spin, _squash)
	if form.id == BallForm.ROCKY:
		draw_circle(Vector2.ZERO, r, INK)
		# A mark so the spin is visible on a solid ball.
		draw_line(Vector2(0, -r * 0.55), Vector2(0, r * 0.55), PAPER, 2.0)
	else:
		draw_circle(Vector2.ZERO, r, PAPER)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, INK, 2.5)
		draw_line(Vector2(0, -r * 0.5), Vector2(0, r * 0.5), INK, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The ball's own policy: squash and report, never move. Mirrors Ball's CollisionPolicy in Phaser.
class BallContactPolicy extends StepPolicy:
	var _ball: Ball

	func _init(ball: Ball) -> void:
		_ball = ball

	func on_contact(contact: Contact) -> bool:
		# Charges refill from here, and deliberately not only on an impact: a touch is a touch.
		# It has to be a contact rather than the support probe, because a wall or ceiling bounce
		# refills too and neither of those ever becomes `ground_material`.
		_ball.limiter.note_contact(contact, _ball.form)
		if contact.is_impact:
			_ball.squash_from(contact)
			_ball.contacted.emit(contact)
		return true

	## The real ball really breaks the pane: it is gone for everyone from here on.
	func on_glass(shape: ShapeBody, _state: BallState, _impact_speed: float) -> int:
		_ball.glass_broken.emit(shape)
		return StepPolicy.GLASS_BREAK

	func on_spikes(strip: SpikeStrip, _state: BallState) -> void:
		_ball.spiked.emit(strip)
