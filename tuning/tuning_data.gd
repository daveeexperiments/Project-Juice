@tool
class_name TuningData
extends Resource

## Every gameplay number the ported systems read, in one Resource.
##
## Ported from src/config/tuning.ts. The rule from the Phaser project carries over: no gameplay
## numbers live anywhere else. Values are read live every frame, so editing them in the Inspector
## (including the remote inspector while the game is running) changes the feel immediately.
##
## Names are snake_case versions of the Phaser paths, flattened one level: `world.gravity` becomes
## `world_gravity`, `squishy.restitution.wall` becomes `squishy_restitution_wall`.

# ---------------------------------------------------------------- world

@export_group("World")
## Downward acceleration in px/s^2, before each ball's own multiplier.
@export_range(0.0, 12000.0, 1.0) var world_gravity: float = 3600.0
## Nothing may travel faster than this (px/s). Keeps fast shots solvable by the substepper.
@export_range(300.0, 12000.0, 10.0) var world_max_ball_speed: float = 4200.0
## Fixed steps per second. Must match the project's physics ticks, or prediction drifts.
@export_range(30.0, 240.0, 1.0) var world_physics_step_rate: float = 120.0
## Global slow/fast motion. 1 is normal.
@export_range(0.05, 4.0, 0.05) var world_time_scale: float = 1.0
## How much harder than gravity a ball is tipped off a ledge edge. 1 = no help.
@export_range(1.0, 5.0, 0.05) var world_roll_off_strength: float = 2.2
## Scales the per-material rolling friction.
@export_range(0.0, 4.0, 0.05) var world_rolling_friction: float = 1.0
## How far below the ball the support probe looks (px).
@export_range(0.0, 60.0, 0.5) var world_edge_support_margin: float = 6.0
## At or below this speed a grounded ball counts as resting (px/s).
@export_range(0.0, 1200.0, 1.0) var world_rest_max_speed: float = 120.0

# ---------------------------------------------------------------- surfaces

@export_group("Surfaces")
## Multiplies every ball's bounce off rock.
@export_range(0.0, 2.0, 0.01) var surface_wall_restitution_multiplier: float = 1.0
## Rolling/sliding slowdown while resting on rock (px/s^2).
@export_range(0.0, 12000.0, 10.0) var surface_wall_friction: float = 2700.0
## Multiplies every ball's bounce off glass.
@export_range(0.0, 2.0, 0.01) var surface_glass_restitution_multiplier: float = 1.0
## Rolling/sliding slowdown while resting on glass (px/s^2).
@export_range(0.0, 12000.0, 10.0) var surface_glass_friction: float = 1200.0

# ---------------------------------------------------------------- squishy ball

@export_group("Squishy ball")
@export_range(0.0, 3.0, 0.05) var squishy_gravity_multiplier: float = 0.7
@export_range(12.0, 120.0, 0.5) var squishy_radius: float = 36.0
@export_range(0.0, 6000.0, 10.0) var squishy_min_launch_speed: float = 600.0
@export_range(300.0, 7500.0, 10.0) var squishy_max_launch_speed: float = 3000.0
@export_range(0.0, 1.5, 0.01) var squishy_restitution_wall: float = 0.35
@export_range(0.0, 1.5, 0.01) var squishy_restitution_glass: float = 0.65
## Fraction of sideways speed KEPT on a floor impact. Lower is grippier.
@export_range(0.0, 1.0, 0.01) var squishy_landing_friction: float = 0.92
@export_range(0.0, 3.0, 0.05) var squishy_air_drag: float = 0.0
## Below this bounce speed the ball simply stops (px/s).
@export_range(0.0, 1200.0, 1.0) var squishy_stop_bounce_threshold: float = 135.0
@export_range(0.0, 1.0, 0.01) var squishy_squash_amount: float = 0.5
## Landing on something flat: a couple of shrinking hops, then it stays put.
@export var squishy_settles_on_landing: bool = true
@export_range(0.0, 600.0, 1.0) var squishy_settle_bounce_height: float = 78.0
@export_range(0.0, 6.0, 1.0) var squishy_settle_hops: int = 2
## Fraction of sideways speed REMOVED on a landing. 1 sticks where it lands.
@export_range(0.0, 1.0, 0.01) var squishy_landing_grip: float = 0.86
## Weight. Unused until levers arrive in a later phase, but ported for completeness.
@export_range(0.0, 40.0, 0.1) var squishy_mass: float = 1.0

# ---------------------------------------------------------------- rocky ball

@export_group("Rocky ball")
@export_range(0.0, 3.0, 0.05) var rocky_gravity_multiplier: float = 1.6
@export_range(12.0, 120.0, 0.5) var rocky_radius: float = 36.0
@export_range(0.0, 6000.0, 10.0) var rocky_min_launch_speed: float = 540.0
@export_range(300.0, 7500.0, 10.0) var rocky_max_launch_speed: float = 2550.0
@export_range(0.0, 1.5, 0.01) var rocky_restitution_wall: float = 0.0
@export_range(0.0, 1.5, 0.01) var rocky_restitution_glass: float = 0.0
@export_range(0.0, 1.0, 0.01) var rocky_landing_friction: float = 0.3
@export_range(0.0, 3.0, 0.05) var rocky_air_drag: float = 0.0
@export_range(0.0, 1200.0, 1.0) var rocky_stop_bounce_threshold: float = 180.0
@export_range(0.0, 1.0, 0.01) var rocky_squash_amount: float = 0.0
@export var rocky_settles_on_landing: bool = false
@export_range(0.0, 600.0, 1.0) var rocky_settle_bounce_height: float = 0.0
@export_range(0.0, 6.0, 1.0) var rocky_settle_hops: int = 0
@export_range(0.0, 1.0, 0.01) var rocky_landing_grip: float = 0.7
@export_range(0.0, 40.0, 0.1) var rocky_mass: float = 6.0

# ---------------------------------------------------------------- grounded launches

@export_group("Grounded launches")
## How far off flat a surface may face and still be launchable (degrees).
@export_range(0.0, 89.0, 1.0) var grounded_surface_tolerance: float = 30.0
## Grace after leaving the ground where a shot still fires (seconds).
@export_range(0.0, 0.5, 0.01) var grounded_coyote_time: float = 0.1
## Releasing just before landing fires the shot on touchdown.
@export var grounded_launch_buffer: bool = false
@export_range(0.0, 0.6, 0.01) var grounded_buffer_time: float = 0.15
## A fan stream counts as something to launch from, so a player held up by one is not stranded.
@export var grounded_launch_from_fan: bool = true
## How far off straight up a fan may blow and still be launchable (degrees).
@export_range(0.0, 89.0, 1.0) var grounded_fan_launch_angle: float = 45.0

# ---------------------------------------------------------------- the launch limiter

@export_group("Launch limiter")
## Which rule stops a player launching for ever. Grounded is the Phaser default.
@export_enum("Grounded:0", "Charges:1", "Heat:2", "Elasticity:3") var limiter_mode: int = 0

@export_subgroup("Charges")
## Shots in a full budget.
@export_range(0.0, 12.0, 1.0) var charges_max: int = 3
## How long the ball must stay on a qualifying surface before the refill lands (seconds).
@export_range(0.0, 3.0, 0.05) var charges_settle_time: float = 0.0
## Which way a surface must face to give charges back.
@export var charges_refill_on_floor: bool = true
@export var charges_refill_on_wall: bool = true
@export var charges_refill_on_ceiling: bool = false
## ...and what it must be made of.
@export var charges_refill_on_wall_material: bool = true
@export var charges_refill_on_glass_material: bool = false
## The exception that makes glass worth hitting as the rocky ball.
@export var charges_refill_on_glass_for_rocky: bool = true

@export_subgroup("Heat")
## Heat added by one shot. An airborne shot costs nearly twice a grounded one.
@export_range(0.0, 1.0, 0.01) var heat_per_ground_launch: float = 0.25
@export_range(0.0, 1.0, 0.01) var heat_per_air_launch: float = 0.45
## Heat shed per second, by what the ball is resting on. Air barely cools at all, which is what
## makes a chain of airborne shots cost something.
@export_range(0.0, 4.0, 0.01) var heat_cool_rate_wall: float = 1.5
@export_range(0.0, 4.0, 0.01) var heat_cool_rate_glass: float = 0.6
## The rocky ball is standing on what it broke rather than resting on the pane, so it cools fast.
@export_range(0.0, 4.0, 0.01) var heat_rocky_cool_rate_glass: float = 1.5
@export_range(0.0, 4.0, 0.01) var heat_cool_rate_air: float = 0.08
## Fraction of launch power lost at full heat. A hot ball still fires, just weakly.
@export_range(0.0, 1.0, 0.01) var heat_power_loss_at_max_heat: float = 0.6
## ...and how much of the ghost line is hidden, so a hot shot is less certain as well as weaker.
@export_range(0.0, 1.0, 0.01) var heat_preview_shrink_at_max_heat: float = 0.7

@export_subgroup("Elasticity")
## How worn the band can get. 1 is fresh.
@export_range(0.0, 1.0, 0.01) var elasticity_min: float = 0.3
@export_range(0.0, 1.0, 0.01) var elasticity_loss_per_launch: float = 0.18
## On: a gentle shot wears the band less than a full pull.
@export var elasticity_scale_loss_by_power: bool = true
## Extra wear for a shot taken in mid-air.
@export_range(0.0, 4.0, 0.05) var elasticity_air_launch_multiplier: float = 1.0
@export_range(0.0, 2.0, 0.01) var elasticity_regen_per_second: float = 0.15

# ---------------------------------------------------------------- slingshot

@export_group("Slingshot")
## Drags shorter than this are not a shot at all (px).
@export_range(0.0, 300.0, 1.0) var slingshot_dead_zone: float = 36.0
## Drag distance that gives full power (px).
@export_range(120.0, 1800.0, 5.0) var slingshot_drag_for_max_power: float = 660.0
## How far the fork lifts the ball off a surface, in ball radii.
@export_range(0.0, 4.0, 0.1) var slingshot_cradle_lift: float = 1.5
## Shift snaps the aim to multiples of this (degrees). 0 = no snapping.
@export_range(0.0, 45.0, 1.0) var slingshot_angle_snap_step: float = 5.0
## 0 = full 360, 1 = upward only, 2 = custom (uses the min/max below).
@export_enum("Full 360:0", "Upward only:1", "Custom:2") var slingshot_aim_range_mode: int = 1
@export_range(-360.0, 360.0, 1.0) var slingshot_aim_range_min: float = 15.0
@export_range(-360.0, 360.0, 1.0) var slingshot_aim_range_max: float = 165.0
## On: the arc turns with the surface the ball rests on.
@export var slingshot_aim_relative_to_surface: bool = false
## Grace after leaving a surface during which a shot still counts as grounded (seconds).
@export_range(0.0, 0.5, 0.01) var slingshot_coyote_time: float = 0.1
## Whether a mid-air shot is permitted at all. Grounded mode refuses one regardless: that mode IS
## the refusal. The other three modes consult this, then charge for the shot their own way.
@export var slingshot_allow_air_launch: bool = true
## How fast the world runs while aiming. Never 0: the world slows, it never stops.
@export_range(0.05, 1.0, 0.05) var slingshot_aim_time_scale: float = 0.3
## Seconds to ease into and out of slow motion.
@export_range(0.0, 0.6, 0.01) var slingshot_aim_ramp_seconds: float = 0.1

# ---------------------------------------------------------------- prediction

@export_group("Prediction")
## How far the ghost line runs (px of path length).
@export_range(300.0, 12000.0, 10.0) var preview_length: float = 4200.0
## The first contact plus this many further bounces.
@export_range(0.0, 5.0, 1.0) var preview_bounces: int = 3
## How much the line fades along its length (0 = no fade).
@export_range(0.0, 1.0, 0.05) var preview_fade: float = 0.7
## How much dimmer each bounce segment is than the one before.
@export_range(0.0, 1.0, 0.05) var preview_bounce_fade: float = 0.4
@export_range(3.0, 120.0, 1.0) var preview_dash_length: float = 27.0
@export_range(6.0, 180.0, 1.0) var preview_dash_spacing: float = 51.0

# ---------------------------------------------------------------- camera

@export_group("Camera")
## Fraction of the view height the ball sits below centre while climbing.
@export_range(-0.5, 0.5, 0.01) var camera_climb_offset: float = 0.12
## Per-frame follow factor at 60fps; converted to frame-rate independent internally.
@export_range(0.01, 1.0, 0.01) var camera_follow_lerp: float = 0.12
## Look-ahead in the direction of travel, as a multiple of speed.
@export_range(0.0, 1.0, 0.01) var camera_look_ahead: float = 0.3
@export_range(0.0, 1800.0, 10.0) var camera_look_ahead_max: float = 840.0

# ---------------------------------------------------------------- glass

@export_group("Glass")
## Minimum speed off glass in Boost mode (px/s), however gently it was hit.
@export_range(0.0, 6000.0, 10.0) var glass_boost_strength: float = 1560.0
## How much of the impact speed is added on top of that.
@export_range(0.0, 3.0, 0.05) var glass_boost_impact_gain: float = 0.55
## Fraction of the sideways speed kept, so the angle of approach still carries through.
@export_range(0.0, 1.5, 0.01) var glass_boost_sideways_keep: float = 0.65
## Hard cap on the speed leaving a glass bounce, which keeps zig-zags controllable.
@export_range(300.0, 7500.0, 10.0) var glass_boost_max_speed: float = 2700.0
## What the ROCKY ball does to glass. Squishy is unaffected by all of this.
@export_enum("Break obstructions only:0", "Always break:1", "Hard hits only:2", "Never break:3", "Pass through:4") var glass_rocky_mode: int = 1
## "Hard hits only": the speed INTO the pane needed to shatter it (px/s).
@export_range(0.0, 6000.0, 10.0) var glass_hard_break_speed: float = 1560.0
## "Pass through": fraction of speed shed per second while inside a pane.
@export_range(0.0, 8.0, 0.05) var glass_pass_through_drag: float = 1.2
## On: the global mode wins over every piece's own rocky_breaks setting.
@export var glass_panel_overrides_level: bool = false
## "Break obstructions only": how close a pane must lie to the rock behind it to be cladding.
@export_range(0.0, 72.0, 0.5) var glass_wall_gap: float = 12.0
## ...and how far off parallel it may sit and still count as lying flat (degrees).
@export_range(0.0, 45.0, 1.0) var glass_wall_angle: float = 10.0
## Seconds until broken glass returns. -1 = use each piece's own setting, 0 = never.
@export_range(-1.0, 30.0, 0.5) var glass_respawn_seconds_override: float = -1.0

# ---------------------------------------------------------------- rising assist

@export_group("Rising assist")
## Steer a climbing bounce upward off glass.
@export var rising_glass_enabled: bool = true
## ...and off walls and curved terrain.
@export var rising_wall_enabled: bool = true
## 0 = pure physics, 1 = the full steer.
@export_range(0.0, 1.0, 0.01) var rising_glass_strength: float = 1.0
@export_range(0.0, 1.0, 0.01) var rising_wall_strength: float = 0.8
## Degrees above horizontal the bounce is lifted to.
@export_range(0.0, 89.0, 1.0) var rising_glass_min_angle: float = 30.0
@export_range(0.0, 89.0, 1.0) var rising_wall_min_angle: float = 20.0
## ...and the upward speed it climbs at, so it climbs rather than nudging up and dropping.
@export_range(0.0, 3600.0, 10.0) var rising_glass_min_up_speed: float = 1260.0
@export_range(0.0, 3600.0, 10.0) var rising_wall_min_up_speed: float = 900.0
## Below this upward speed at contact the ball counts as falling, so an apex behaves normally.
@export_range(0.0, 1200.0, 1.0) var rising_threshold: float = 180.0
## A ceiling cannot throw a ball up through itself, so hold the lift until it clears the edge.
@export var rising_skim_lift: bool = true

# ---------------------------------------------------------------- per-ball glass behaviour

@export_group("Ball vs glass")
## Only the rocky ball breaks glass.
@export var squishy_breaks_glass: bool = false
@export var rocky_breaks_glass: bool = true
## How hard this ball must hit glass to break it at all (px/s).
@export_range(0.0, 3000.0, 5.0) var squishy_glass_break_min_impact: float = 0.0
@export_range(0.0, 3000.0, 5.0) var rocky_glass_break_min_impact: float = 15.0
## Fraction of speed kept when smashing through a pane.
@export_range(0.0, 1.0, 0.01) var squishy_glass_break_speed_keep: float = 1.0
@export_range(0.0, 1.0, 0.01) var rocky_glass_break_speed_keep: float = 0.85
## Which ball the rising assist is for.
@export var squishy_rising_assist: bool = true
@export var rocky_rising_assist: bool = false

# ---------------------------------------------------------------- spikes and flags

@export_group("Spikes and flags")
## After a respawn, spikes cannot trigger again for this long (seconds).
@export_range(0.0, 2.0, 0.05) var spikes_grace_seconds: float = 0.5
## How long the wipe-out takes before the ball reappears at the flag (seconds).
@export_range(0.0, 1.5, 0.05) var spikes_respawn_delay: float = 0.35
## How close the ball must come to raise a flag (px beyond its own radius).
@export_range(0.0, 360.0, 2.0) var flags_touch_radius: float = 78.0
## On: a rope the ball has come to REST in is a checkpoint in its own right. Off in the shipped
## tuning, which is why cables are a route rather than a safety net.
@export var flags_cables_are_checkpoints: bool = false

# ---------------------------------------------------------------- fans

@export_group("Fans")
## How hard the stream closes the gap to its target speed, per second. The fan makes up only the
## SHORTFALL below the target, so it never brakes a ball that is already going faster.
@export_range(0.0, 40.0, 0.1) var fans_strength: float = 9.0
## The speed the stream carries a ball at (px/s).
@export_range(0.0, 6000.0, 10.0) var fans_target_speed: float = 1290.0
## How far the stream reaches (px).
@export_range(0.0, 6000.0, 10.0) var fans_range: float = 1920.0
## Exponent on the fade along the stream. 1 is a straight taper; higher keeps the push strong near
## the mouth and then drops it off a cliff.
@export_range(0.0, 4.0, 0.05) var fans_falloff: float = 1.1
## How much push survives at the very edge of the mouth, so a ball slides out of a stream rather
## than falling off a shelf of air.
@export_range(0.0, 1.0, 0.01) var fans_sustain: float = 0.55
## On: a pane holds the air back. Off: the wind blows straight through it.
@export var fans_blocked_by_glass: bool = true

# ---------------------------------------------------------------- trampolines

@export_group("Trampolines")
## The speed a pad throws a launching ball off at, however gently it was hit (px/s).
@export_range(0.0, 7500.0, 10.0) var trampoline_launch_speed: float = 3450.0
## How much of the impact speed is added on top, so arriving fast is rewarded.
@export_range(0.0, 3.0, 0.05) var trampoline_impact_bonus: float = 0.45
## Fraction of the sideways speed kept, so the approach still decides where the ball goes.
@export_range(0.0, 1.5, 0.01) var trampoline_horizontal_keep: float = 0.6
## What a ball that CANNOT launch off a pad gets instead: nearly nothing, which is what makes a
## trampoline the rocky ball's route and a dead end for the squishy one.
@export_range(0.0, 1.5, 0.01) var trampoline_squishy_bounce: float = 0.12
## Whether a pad puts a spent launch budget back.
@export var trampoline_refills_squishy: bool = true
@export var trampoline_refills_rocky: bool = true

# ---------------------------------------------------------------- cables

@export_group("Cables")
## How many links the rope is built from. More is smoother and costs more.
@export_range(2.0, 48.0, 1.0) var cables_segments: int = 14
## How hard each link pulls back to its rest length, per relaxation pass. 1 is an inelastic rope.
@export_range(0.0, 1.0, 0.01) var cables_stiffness: float = 0.8
## Speed the rope loses per step, which is what stops it swinging for ever.
@export_range(0.0, 1.0, 0.01) var cables_damping: float = 0.04
## How far the middle may droop below the line between the anchors (px). Stops a long cable
## sinking to the floor and ceasing to be a route.
@export_range(0.0, 1200.0, 1.0) var cables_max_sag: float = 168.0
## How much the rope gives rather than throwing. 0 is a rail; 1 is all give.
@export_range(0.0, 1.0, 0.01) var cables_softness: float = 0.55
## The rope's collision radius (px).
@export_range(3.0, 120.0, 0.5) var cables_thickness: float = 15.0
## How far the rope is shoved aside by the hardest hit there is (px).
@export_range(0.0, 360.0, 1.0) var cables_recoil: float = 42.0
## Sideways slowdown while rolling along a rope (px/s^2).
@export_range(0.0, 6000.0, 10.0) var cables_rolling_friction: float = 210.0
## How strongly a resting ball is drawn towards the middle of the rope (px/s^2), so it rolls to
## the low point instead of balancing near an anchor.
@export_range(0.0, 6000.0, 10.0) var cables_centring_bias: float = 210.0
## On: a rope always throws the ball to the same height, whatever the drop. Off: an ordinary
## physical bounce at the ball's own `cableBounce`. The same reflect-or-boost choice glass has.
@export var cables_sustain_bounce: bool = false
## How much of the impact speed is added on top of the throw.
@export_range(0.0, 3.0, 0.05) var cables_impact_bonus: float = 0.55
## Extra damping applied the moment the rope is hit, so it stops ringing rather than wobbling for
## the rest of the level.
@export_range(0.0, 1.0, 0.01) var cables_extra_decay: float = 0.55
## Whether a rope puts a spent launch budget, or a worn band, back.
@export var cables_refills_charges: bool = true
@export var cables_restores_elasticity: bool = false

# ---------------------------------------------------------------- pipes

@export_group("Pipes")
## How wide a pipe's mouth is: how close the ball must come to be drawn in (px).
@export_range(4.0, 400.0, 1.0) var pipes_mouth_radius: float = 60.0
## The slowest a ball may travel through a pipe (px/s).
##
## **This is a floor, not a speed.** A pipe carries the speed the ball arrived with, so the shot
## still matters and the preview stays honest -- but without a minimum, a ball that dribbles into
## a mouth crawls to a halt somewhere inside, and in a game with no walking that is an
## unrecoverable soft-lock with nothing on screen to explain it.
@export_range(10.0, 4000.0, 10.0) var pipes_min_speed: float = 600.0
## Fraction of the entry speed kept. 1 carries it through untouched; lower makes a pipe a cost.
@export_range(0.0, 2.0, 0.01) var pipes_speed_keep: float = 1.0

# ---------------------------------------------------------------- levers

@export_group("Levers")
## What each ball weighs as far as a plank is concerned. The whole lever puzzle is the gap: the
## rocky ball tips a seesaw the squishy ball barely disturbs. Separate from the balls' own `mass`
## so a lever can be rebalanced without changing what a ball weighs everywhere else.
@export_range(0.0, 40.0, 0.1) var lever_mass_squishy: float = 1.0
@export_range(0.0, 40.0, 0.1) var lever_mass_rocky: float = 6.0
## The plank's own mass, which is all its resistance to being turned.
@export_range(0.1, 40.0, 0.1) var lever_plank_mass: float = 2.5
## Proportional damping on the swing, which settles it.
@export_range(0.0, 20.0, 0.05) var lever_angular_damping: float = 2.2
## A constant drag at the hinge, which brings a settling plank to a dead stop rather than letting
## it creep.
@export_range(0.0, 18000.0, 1.0) var lever_pivot_friction: float = 360.0
## A weight hung on the A end, holding that side down until something outweighs it.
@export_range(-40.0, 40.0, 0.1) var lever_counterweight: float = 1.5
## How hard a landing kicks the plank, on top of the ball's standing weight.
@export_range(0.0, 10.0, 0.05) var lever_impact_strength: float = 1.0
## Scales every torque at once. The knob to reach for if levers feel uniformly too stiff or too
## loose.
@export_range(0.0, 10.0, 0.05) var lever_torque_scale: float = 1.0

# ---------------------------------------------------------------- per-ball actor response

@export_group("Ball vs actors")
## How much of a fan's push each ball feels. The squishy ball is flown by a stream; the rocky ball
## barely drifts in one, because 0.3 of the push cannot beat its own gravity.
@export_range(0.0, 6.0, 0.05) var squishy_fan_multiplier: float = 2.4
@export_range(0.0, 6.0, 0.05) var rocky_fan_multiplier: float = 0.3
## Which ball a trampoline throws. The mirror image of glass, which bounces the squishy ball and
## ignores the rocky one.
@export var squishy_launches_off_trampoline: bool = false
@export var rocky_launches_off_trampoline: bool = true
## ...and how much of the pad's launch it gets. Squishy's 0 agrees with the switch above rather
## than contradicting it: it neither launches nor would get anything if it did.
@export_range(0.0, 2.0, 0.01) var squishy_trampoline_bounce: float = 0.0
@export_range(0.0, 2.0, 0.01) var rocky_trampoline_bounce: float = 1.0
## How much a rope throws each ball. A cable is the squishy ball's route: 0.31 against the rocky
## ball's 0.04, which lands on a rope dead.
@export_range(0.0, 2.0, 0.01) var squishy_cable_bounce: float = 0.31
@export_range(0.0, 2.0, 0.01) var rocky_cable_bounce: float = 0.04
## The height a rope throws each ball to when `cables.sustainBounce` is on, whatever the drop (px).
@export_range(0.0, 1800.0, 1.0) var squishy_sustained_cable_height: float = 450.0
@export_range(0.0, 1800.0, 1.0) var rocky_sustained_cable_height: float = 186.0

# ---------------------------------------------------------------- helpers

## Which bounce rules apply. Phase 1 ports "physical" only; "rising" arrives with the assist.
@export_enum("Physical:0", "Rising assist:1") var bounce_style: int = 0
## 0 = reflect (plain bounce), 1 = boost (trampoline-style). Phase 1 ports reflect only.
@export_enum("Reflect:0", "Boost:1") var glass_bounce_mode: int = 0


## The fixed timestep the simulation advances by, in seconds.
func fixed_delta() -> float:
	return 1.0 / maxf(1.0, world_physics_step_rate)


# ---------------------------------------------------------------- the live instance

## The values everything reads.
##
## The `Tuning` autoload points this at the resource it holds, which is what makes Inspector
## edits (including from the remote inspector during play) take effect immediately. It lives
## here rather than only on the autoload so the simulation can run with no SceneTree at all --
## that is what lets the headless tests exercise the real code.
static var active: TuningData = null


static func get_active() -> TuningData:
	if active == null:
		active = TuningData.new()
	return active


# ---------------------------------------------------------------- the frozen Phaser export

## The exported Phaser values, kept as history. **Not loaded on startup, and not a source to
## re-import from.**
##
## It used to be loaded over the top of these defaults every time the game booted and every time
## the tests called `get_active()`, which made it the real source of truth for all 171 fields
## below -- the `@export` defaults were dead values that the Inspector displayed and nothing used.
## Five of them had already drifted away from the JSON without any effect
## (`slingshot_cradle_lift` among them, which is a physical number), and nobody noticed, because
## nothing they affected could change.
##
## That was harmless while the port was being transcribed and the Phaser project was the
## authority. It is not harmless now: the Phaser project is retired, this is the game, and an
## edit to a number here has to be the edit that takes effect. A scale change made against these
## defaults would have been silently discarded and every test would still have passed.
##
## So the defaults below are now the only source, and this file is archaeology. `load_phaser_json`
## still works for a one-off comparison, and `tuning/save_default.gd` still uses it; neither runs
## by itself.
const PHASER_JSON_PATH: String = "res://tuning/phaser_tuning.json"

## Phaser paths that have no field here, filled in by the last load. Reported in docs/PORTING.md,
## so a value that quietly failed to port is visible rather than silently default.
var unmapped_keys: PackedStringArray = PackedStringArray()


## Overwrite these values from the exported Phaser JSON. Returns the keys that had nowhere to go.
##
## Only called deliberately now -- see PHASER_JSON_PATH above.
func load_phaser_json(path: String) -> PackedStringArray:
	unmapped_keys = PackedStringArray()
	if not FileAccess.file_exists(path):
		push_warning("TuningData: no exported Phaser JSON at %s; using the values as authored." % path)
		return unmapped_keys

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TuningData: %s is not valid JSON." % path)
		return unmapped_keys

	var values: Dictionary = (parsed as Dictionary).get("values", {}) as Dictionary
	_apply_tree(values, "")
	return unmapped_keys


func _apply_tree(node: Dictionary, prefix: String) -> void:
	for key: Variant in node.keys():
		var leaf: String = str(key)
		var value: Variant = node[key]
		var path: String = leaf if prefix.is_empty() else "%s.%s" % [prefix, leaf]
		if typeof(value) == TYPE_DICTIONARY:
			_apply_tree(value as Dictionary, path)
		elif not _assign(path, value):
			unmapped_keys.append(path)


## Assign one Phaser path. Returns false when this port has no field for it.
func _assign(path: String, value: Variant) -> bool:
	if not FIELD_BY_PATH.has(path):
		return false
	var field: String = FIELD_BY_PATH[path] as String
	var current: Variant = get(field)

	match typeof(current):
		TYPE_FLOAT:
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
				set(field, float(value))
				return true
		TYPE_INT:
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
				set(field, int(value))
				return true
			if typeof(value) == TYPE_STRING:
				var index: int = _enum_index(path, str(value))
				if index >= 0:
					set(field, index)
					return true
		TYPE_BOOL:
			if typeof(value) == TYPE_BOOL:
				set(field, value as bool)
				return true
	return false


## The handful of Phaser values that are strings there and indices here.
func _enum_index(path: String, value: String) -> int:
	match path:
		"slingshot.aimRangeMode":
			return ["full", "upward", "custom"].find(value)
		"bounce.style":
			return ["physical", "rising"].find(value)
		"surfaces.glass.bounceMode":
			return ["reflect", "boost"].find(value)
		"surfaces.glass.rockyMode":
			return ["obstruction", "always", "hard", "never", "pass"].find(value)
		"limiter.mode":
			return ["grounded", "charges", "heat", "elasticity"].find(value)
	return -1


## Phaser path -> field here. Anything absent is reported as unmapped on load, which is how the
## later phases (fans, levers, spikes, juice, audio...) show up as "not ported yet" rather than
## vanishing without trace.
const FIELD_BY_PATH: Dictionary = {
	"world.gravity": "world_gravity",
	"world.maxBallSpeed": "world_max_ball_speed",
	"world.physicsStepRate": "world_physics_step_rate",
	"world.timeScale": "world_time_scale",
	"world.rollOffStrength": "world_roll_off_strength",
	"world.rollingFriction": "world_rolling_friction",
	"world.edgeSupportMargin": "world_edge_support_margin",
	"world.restMaxSpeed": "world_rest_max_speed",

	"surfaces.wall.restitutionMultiplier": "surface_wall_restitution_multiplier",
	"surfaces.wall.friction": "surface_wall_friction",
	"surfaces.glass.restitutionMultiplier": "surface_glass_restitution_multiplier",
	"surfaces.glass.friction": "surface_glass_friction",
	"surfaces.glass.bounceMode": "glass_bounce_mode",
	"bounce.style": "bounce_style",

	"squishy.gravityMultiplier": "squishy_gravity_multiplier",
	"squishy.radius": "squishy_radius",
	"squishy.minLaunchSpeed": "squishy_min_launch_speed",
	"squishy.maxLaunchSpeed": "squishy_max_launch_speed",
	"squishy.restitution.wall": "squishy_restitution_wall",
	"squishy.restitution.glass": "squishy_restitution_glass",
	"squishy.landingFriction": "squishy_landing_friction",
	"squishy.airDrag": "squishy_air_drag",
	"squishy.stopBounceThreshold": "squishy_stop_bounce_threshold",
	"squishy.squashAmount": "squishy_squash_amount",
	"squishy.settlesOnLanding": "squishy_settles_on_landing",
	"squishy.settleBounceHeight": "squishy_settle_bounce_height",
	"squishy.settleHops": "squishy_settle_hops",
	"squishy.landingGrip": "squishy_landing_grip",
	"squishy.mass": "squishy_mass",

	"rocky.gravityMultiplier": "rocky_gravity_multiplier",
	"rocky.radius": "rocky_radius",
	"rocky.minLaunchSpeed": "rocky_min_launch_speed",
	"rocky.maxLaunchSpeed": "rocky_max_launch_speed",
	"rocky.restitution.wall": "rocky_restitution_wall",
	"rocky.restitution.glass": "rocky_restitution_glass",
	"rocky.landingFriction": "rocky_landing_friction",
	"rocky.airDrag": "rocky_air_drag",
	"rocky.stopBounceThreshold": "rocky_stop_bounce_threshold",
	"rocky.squashAmount": "rocky_squash_amount",
	"rocky.settlesOnLanding": "rocky_settles_on_landing",
	"rocky.settleBounceHeight": "rocky_settle_bounce_height",
	"rocky.settleHops": "rocky_settle_hops",
	"rocky.landingGrip": "rocky_landing_grip",
	"rocky.mass": "rocky_mass",

	"grounded.surfaceTolerance": "grounded_surface_tolerance",
	"grounded.coyoteTime": "grounded_coyote_time",
	"grounded.launchBuffer": "grounded_launch_buffer",
	"grounded.bufferTime": "grounded_buffer_time",
	"grounded.launchFromFan": "grounded_launch_from_fan",
	"grounded.fanLaunchAngle": "grounded_fan_launch_angle",

	"limiter.mode": "limiter_mode",

	"charges.max": "charges_max",
	"charges.settleTime": "charges_settle_time",
	"charges.refillOnFloor": "charges_refill_on_floor",
	"charges.refillOnWall": "charges_refill_on_wall",
	"charges.refillOnCeiling": "charges_refill_on_ceiling",
	"charges.refillOnWallMaterial": "charges_refill_on_wall_material",
	"charges.refillOnGlassMaterial": "charges_refill_on_glass_material",
	"charges.refillOnGlassForRocky": "charges_refill_on_glass_for_rocky",

	"heat.perGroundLaunch": "heat_per_ground_launch",
	"heat.perAirLaunch": "heat_per_air_launch",
	"heat.coolRateWall": "heat_cool_rate_wall",
	"heat.coolRateGlass": "heat_cool_rate_glass",
	"heat.rockyCoolRateGlass": "heat_rocky_cool_rate_glass",
	"heat.coolRateAir": "heat_cool_rate_air",
	"heat.powerLossAtMaxHeat": "heat_power_loss_at_max_heat",
	"heat.previewShrinkAtMaxHeat": "heat_preview_shrink_at_max_heat",

	"elasticity.min": "elasticity_min",
	"elasticity.lossPerLaunch": "elasticity_loss_per_launch",
	"elasticity.scaleLossByPower": "elasticity_scale_loss_by_power",
	"elasticity.airLaunchMultiplier": "elasticity_air_launch_multiplier",
	"elasticity.regenPerSecond": "elasticity_regen_per_second",

	"slingshot.deadZone": "slingshot_dead_zone",
	"slingshot.dragForMaxPower": "slingshot_drag_for_max_power",
	"slingshot.cradleLift": "slingshot_cradle_lift",
	"slingshot.angleSnapStep": "slingshot_angle_snap_step",
	"slingshot.aimRangeMode": "slingshot_aim_range_mode",
	"slingshot.aimRangeMin": "slingshot_aim_range_min",
	"slingshot.aimRangeMax": "slingshot_aim_range_max",
	"slingshot.aimRelativeToSurface": "slingshot_aim_relative_to_surface",
	"slingshot.coyoteTime": "slingshot_coyote_time",
	"slingshot.allowAirLaunch": "slingshot_allow_air_launch",
	"slingshot.aimTimeScale": "slingshot_aim_time_scale",
	"slingshot.aimRampSeconds": "slingshot_aim_ramp_seconds",
	"slingshot.previewLength": "preview_length",
	"slingshot.previewBounces": "preview_bounces",
	"slingshot.previewFade": "preview_fade",
	"slingshot.previewBounceFade": "preview_bounce_fade",
	"slingshot.dashLength": "preview_dash_length",
	"slingshot.dashSpacing": "preview_dash_spacing",


	"surfaces.glass.boostStrength": "glass_boost_strength",
	"surfaces.glass.boostImpactGain": "glass_boost_impact_gain",
	"surfaces.glass.boostSidewaysKeep": "glass_boost_sideways_keep",
	"surfaces.glass.boostMaxSpeed": "glass_boost_max_speed",
	"surfaces.glass.rockyMode": "glass_rocky_mode",
	"surfaces.glass.hardBreakSpeed": "glass_hard_break_speed",
	"surfaces.glass.passThroughDrag": "glass_pass_through_drag",
	"surfaces.glass.panelOverridesLevel": "glass_panel_overrides_level",
	"surfaces.glass.wallGlassGap": "glass_wall_gap",
	"surfaces.glass.wallGlassAngle": "glass_wall_angle",
	"surfaces.glass.respawnSecondsOverride": "glass_respawn_seconds_override",

	"risingAssist.glassEnabled": "rising_glass_enabled",
	"risingAssist.wallEnabled": "rising_wall_enabled",
	"risingAssist.glassStrength": "rising_glass_strength",
	"risingAssist.wallStrength": "rising_wall_strength",
	"risingAssist.glassMinAngle": "rising_glass_min_angle",
	"risingAssist.wallMinAngle": "rising_wall_min_angle",
	"risingAssist.glassMinUpSpeed": "rising_glass_min_up_speed",
	"risingAssist.wallMinUpSpeed": "rising_wall_min_up_speed",
	"risingAssist.risingThreshold": "rising_threshold",
	"risingAssist.skimLift": "rising_skim_lift",

	"squishy.breaksGlass": "squishy_breaks_glass",
	"rocky.breaksGlass": "rocky_breaks_glass",
	"squishy.glassBreakMinImpact": "squishy_glass_break_min_impact",
	"rocky.glassBreakMinImpact": "rocky_glass_break_min_impact",
	"squishy.glassBreakSpeedKeep": "squishy_glass_break_speed_keep",
	"rocky.glassBreakSpeedKeep": "rocky_glass_break_speed_keep",
	"squishy.risingAssist": "squishy_rising_assist",
	"rocky.risingAssist": "rocky_rising_assist",

	"lever.massSquishy": "lever_mass_squishy",
	"lever.massRocky": "lever_mass_rocky",
	"lever.plankMass": "lever_plank_mass",
	"lever.angularDamping": "lever_angular_damping",
	"lever.pivotFriction": "lever_pivot_friction",
	"lever.counterweight": "lever_counterweight",
	"lever.impactStrength": "lever_impact_strength",
	"lever.torqueScale": "lever_torque_scale",

	# cables.clearAbove and cables.clearBelow are deliberately absent: they read as
	# level-generation clearance rather than collision, and bending them into the one-way floor
	# rule would have them decide nothing. See the note in core/cable.gd.
	"cables.segments": "cables_segments",
	"cables.stiffness": "cables_stiffness",
	"cables.damping": "cables_damping",
	"cables.maxSag": "cables_max_sag",
	"cables.softness": "cables_softness",
	"cables.thickness": "cables_thickness",
	"cables.recoil": "cables_recoil",
	"cables.rollingFriction": "cables_rolling_friction",
	"cables.centringBias": "cables_centring_bias",
	"cables.sustainBounce": "cables_sustain_bounce",
	"cables.impactBonus": "cables_impact_bonus",
	"cables.extraDecay": "cables_extra_decay",
	"cables.refillsCharges": "cables_refills_charges",
	"cables.restoresElasticity": "cables_restores_elasticity",
	"squishy.cableBounce": "squishy_cable_bounce",
	"rocky.cableBounce": "rocky_cable_bounce",
	"squishy.sustainedCableHeight": "squishy_sustained_cable_height",
	"rocky.sustainedCableHeight": "rocky_sustained_cable_height",

	"trampoline.launchSpeed": "trampoline_launch_speed",
	"trampoline.impactBonus": "trampoline_impact_bonus",
	"trampoline.horizontalKeep": "trampoline_horizontal_keep",
	"trampoline.squishyBounce": "trampoline_squishy_bounce",
	"trampoline.refillsSquishy": "trampoline_refills_squishy",
	"trampoline.refillsRocky": "trampoline_refills_rocky",
	"squishy.launchesOffTrampoline": "squishy_launches_off_trampoline",
	"rocky.launchesOffTrampoline": "rocky_launches_off_trampoline",
	"squishy.trampolineBounce": "squishy_trampoline_bounce",
	"rocky.trampolineBounce": "rocky_trampoline_bounce",

	"fans.strength": "fans_strength",
	"fans.targetSpeed": "fans_target_speed",
	"fans.range": "fans_range",
	"fans.falloff": "fans_falloff",
	"fans.sustain": "fans_sustain",
	"fans.blockedByGlass": "fans_blocked_by_glass",
	"squishy.fanMultiplier": "squishy_fan_multiplier",
	"rocky.fanMultiplier": "rocky_fan_multiplier",

	"spikes.graceSeconds": "spikes_grace_seconds",
	"spikes.respawnDelay": "spikes_respawn_delay",
	"flags.touchRadius": "flags_touch_radius",
	"flags.cablesAreCheckpoints": "flags_cables_are_checkpoints",
	"camera.climbOffset": "camera_climb_offset",
	"camera.followLerp": "camera_follow_lerp",
	"camera.fallLookAhead": "camera_look_ahead",
	"camera.fallLookAheadMax": "camera_look_ahead_max",
}
