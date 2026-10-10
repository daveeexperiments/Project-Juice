class_name LaunchLimiter
extends RefCounted

## What stops a player launching for ever. Ported from src/systems/LaunchLimiter.ts.
##
## Four modes, one at a time, chosen by `limiter.mode`:
##
##   Grounded   -- a shot only goes from a surface you could stand on (phase 1; the Phaser default)
##   Charges    -- a budget of shots, refilled by touching the right kind of surface
##   Heat       -- every shot heats the ball; a hot ball still fires, just weakly
##   Elasticity -- the band wears out with use and recovers with time
##
## THE REASON THIS IS NOT IN `BallSim.step_ball`: the limiter never moves the ball. It answers
## "may this shot go?" and "how hard?", which the slingshot asks at the moment of release. Keeping
## it out of the step means the ghost line cannot be thrown off by it, and the headless tests can
## drive a limiter with no ball and no scene at all.
##
## It is deliberately a RefCounted rather than an autoload, for the same reason the simulation is:
## a `--script` SceneTree has no autoloads, so anything the tests must exercise cannot rely on one.

const MODE_GROUNDED: int = 0
const MODE_CHARGES: int = 1
const MODE_HEAT: int = 2
const MODE_ELASTICITY: int = 3

## Contact orientation, by the same flat-enough rule the settle and grounded launches use.
const FACE_FLOOR: int = 0
const FACE_WALL: int = 1
const FACE_CEILING: int = 2

## Shots left, in Charges mode.
var charges: int = 0
## 0 is cold, 1 is as hot as it gets, in Heat mode.
var heat: float = 0.0
## 1 is a fresh band, `elasticity.min` is a worn one, in Elasticity mode.
var elasticity: float = 1.0
## How long the ball has been settled on something that would refill its charges. Compared against
## `charges.settleTime`, which is 0 by default, so a touch is normally enough.
var _dwell: float = 0.0
## The last qualifying surface is remembered so the dwell only counts while still on it.
var _dwell_armed: bool = false


static func mode() -> int:
	return TuningData.get_active().limiter_mode


## Back to full: called on spawn and on every respawn, so a death never leaves the player stranded
## with an empty budget.
func reset() -> void:
	var t: TuningData = TuningData.get_active()
	charges = maxi(0, t.charges_max)
	heat = 0.0
	elasticity = 1.0
	_dwell = 0.0
	_dwell_armed = false


## Per-step upkeep: cooling, regeneration and the settle dwell. `ground_material` is
## SurfaceKind.NONE while airborne.
func tick(dt: float, ground_material: int, form: BallForm) -> void:
	var t: TuningData = TuningData.get_active()
	var supported: bool = ground_material != SurfaceKind.NONE

	# -- Heat: cool at a rate that depends on what the ball is resting on. Rock sheds heat quickly,
	# glass slowly, and air barely at all -- which is what makes a chain of airborne shots cost
	# something. The rocky ball cools on glass as fast as on rock, because it is not sitting on the
	# pane so much as standing on what it just broke.
	if heat > 0.0:
		var cool: float = t.heat_cool_rate_air
		if supported:
			if ground_material == SurfaceKind.GLASS:
				cool = t.heat_rocky_cool_rate_glass if form.breaks_glass else t.heat_cool_rate_glass
			else:
				cool = t.heat_cool_rate_wall
		heat = maxf(0.0, heat - maxf(0.0, cool) * dt)

	# -- Elasticity: the band creeps back towards full on its own.
	if elasticity < 1.0:
		elasticity = minf(1.0, elasticity + maxf(0.0, t.elasticity_regen_per_second) * dt)

	# -- Charges: `note_contact` arms the dwell when the ball touches a qualifying surface; this
	# serves it out. Only Charges mode keeps a dwell, but heat and elasticity above are left to
	# settle whatever the mode, so switching mode in the Inspector mid-play finds sane state.
	if mode() != MODE_CHARGES or not _dwell_armed:
		return
	if not supported:
		# Left before the dwell was served, so the refill is forfeited.
		_dwell = 0.0
		_dwell_armed = false
		return
	_dwell += dt
	if _dwell >= maxf(0.0, t.charges_settle_time):
		_refill_charges()


## A contact the step just resolved. Charges mode refills from here, because a wall or ceiling
## bounce is a contact and never a support: waiting for `ground_material` would miss both.
func note_contact(contact: Contact, form: BallForm) -> void:
	if mode() != MODE_CHARGES:
		return
	if not _contact_refills(contact, form):
		return
	# With no settle time required, touching it is enough. With one, the ball has to stay.
	if maxf(0.0, TuningData.get_active().charges_settle_time) <= 0.0:
		_refill_charges()
		return
	_dwell_armed = true
	_dwell = 0.0


## May a shot go? `grounded_ok` is the Grounded-mode answer the ball works out for itself (on a
## launchable surface, inside the coyote window, or held in the cradle).
##
## Only Charges can refuse outright. Heat and Elasticity always fire -- they just fire weakly,
## which is the whole point of them: the player is never stuck, only slowed.
func can_launch(grounded_ok: bool) -> bool:
	match mode():
		MODE_CHARGES:
			if charges <= 0:
				return false
			return grounded_ok or _air_launch_allowed()
		MODE_HEAT, MODE_ELASTICITY:
			return grounded_ok or _air_launch_allowed()
	return grounded_ok


## Charge the shot to the limiter. `power` is the slingshot's 0..1 pull, `was_grounded` false for a
## shot taken in mid-air, which every mode charges more for.
func note_launch(power: float, was_grounded: bool) -> void:
	var t: TuningData = TuningData.get_active()
	match mode():
		MODE_CHARGES:
			charges = maxi(0, charges - 1)
			_dwell = 0.0
			_dwell_armed = false
		MODE_HEAT:
			var gain: float = t.heat_per_ground_launch if was_grounded else t.heat_per_air_launch
			heat = clampf(heat + maxf(0.0, gain), 0.0, 1.0)
		MODE_ELASTICITY:
			var loss: float = maxf(0.0, t.elasticity_loss_per_launch)
			if t.elasticity_scale_loss_by_power:
				loss *= clampf(power, 0.0, 1.0)
			if not was_grounded:
				loss *= maxf(0.0, t.elasticity_air_launch_multiplier)
			elasticity = maxf(clampf(t.elasticity_min, 0.0, 1.0), elasticity - loss)


## What the launch speed is multiplied by. 1 is a shot at full strength.
##
## Heat scales down to `1 - heat.powerLossAtMaxHeat` at full heat; Elasticity simply IS its own
## multiplier. Grounded and Charges never weaken a shot: they gate it instead.
func launch_scale() -> float:
	var t: TuningData = TuningData.get_active()
	match mode():
		MODE_HEAT:
			return maxf(0.0, 1.0 - clampf(t.heat_power_loss_at_max_heat, 0.0, 1.0) * clampf(heat, 0.0, 1.0))
		MODE_ELASTICITY:
			return clampf(elasticity, 0.0, 1.0)
	return 1.0


## What the drawn ghost line is shortened by, on top of whatever the weaker shot does to it.
##
## Heat mode hides the far end of the line as the ball heats up: the shot gets not just weaker but
## less certain, which is what stops a hot ball being used for fine work.
func preview_scale() -> float:
	var t: TuningData = TuningData.get_active()
	if mode() != MODE_HEAT:
		return 1.0
	return maxf(0.0, 1.0 - clampf(t.heat_preview_shrink_at_max_heat, 0.0, 1.0) * clampf(heat, 0.0, 1.0))


## Which way a contact's surface faces, by the SAME flat-enough rule the settle and grounded
## launches use. Three things having one definition is deliberate: a surface that refills a charge
## but cannot be launched from would read as the game being broken.
static func face_of(ny: float) -> int:
	if BallSim.is_horizontal_surface(ny):
		return FACE_FLOOR
	# The mirror of the floor test: a ceiling is as steeply downward-facing as a floor is upward.
	var tolerance: float = clampf(TuningData.get_active().grounded_surface_tolerance, 0.0, 89.0)
	if ny >= cos(deg_to_rad(tolerance)):
		return FACE_CEILING
	return FACE_WALL


## Does this contact put charges back?
##
## A trampoline answers for itself and ignores the facing and material rules, because
## `trampoline.refillsSquishy/Rocky` are unconditional: a pad is a way back into a level, and one
## you catch a glancing hit off still counts. Everything else goes through the surface rules.
static func _contact_refills(contact: Contact, form: BallForm) -> bool:
	if contact.material == SurfaceKind.TRAMPOLINE:
		return form.refilled_by_trampoline
	return _surface_refills(face_of(contact.ny), contact.material, form)


## Does touching this surface put charges back? Both the orientation and the material have to
## agree, which is what lets glass be a dead end for the squishy ball and a refill for the rocky
## one.
static func _surface_refills(face: int, material: int, form: BallForm) -> bool:
	var t: TuningData = TuningData.get_active()
	var by_face: bool = false
	match face:
		FACE_FLOOR:
			by_face = t.charges_refill_on_floor
		FACE_WALL:
			by_face = t.charges_refill_on_wall
		FACE_CEILING:
			by_face = t.charges_refill_on_ceiling
	if not by_face:
		return false

	if material == SurfaceKind.GLASS:
		# The rocky exception wins where it applies: it is the only way glass gives anything back.
		if form.breaks_glass and t.charges_refill_on_glass_for_rocky:
			return true
		return t.charges_refill_on_glass_material
	return t.charges_refill_on_wall_material


func _refill_charges() -> void:
	charges = maxi(0, TuningData.get_active().charges_max)
	_dwell = 0.0
	_dwell_armed = false


## Air launches are permitted per mode by one global switch. Grounded mode never consults it: that
## mode IS the refusal.
static func _air_launch_allowed() -> bool:
	return TuningData.get_active().slingshot_allow_air_launch


## A short line for the debug overlay. The HUD is deliberately not ported, so this is the only
## place the limiter's state is shown.
func describe() -> String:
	match mode():
		MODE_CHARGES:
			return "charges %d/%d" % [charges, maxi(0, TuningData.get_active().charges_max)]
		MODE_HEAT:
			return "heat %.2f (power x%.2f)" % [heat, launch_scale()]
		MODE_ELASTICITY:
			return "elasticity %.2f" % elasticity
	return "grounded"
