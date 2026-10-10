@tool
class_name LeverBlock
extends Marker2D

## A plank balanced on a pivot.
##
## Extends Marker2D rather than Polygon2D, like the Flag and Spawn blocks do, because a lever has
## nothing to point-edit: it IS a pivot, and the plank's shape is two numbers rather than an
## outline. Marker2D brings its own editor gizmo, so the node is visible and clickable where it
## stands, which is what the Polygon2D rule is really after.

const INK: Color = Color("141414")
const PIVOT: Color = Color(0.1, 0.1, 0.1, 0.9)
const FAINT: Color = Color(0.55, 0.55, 0.55, 0.5)

## Half the plank's length. The ends sit this far either side of the pivot.
@export_range(16.0, 400.0, 1.0) var half_length: float = 90.0:
	set(value):
		half_length = value
		queue_redraw()

## How thick the plank is to collide with.
@export_range(1.0, 40.0, 0.5) var thickness: float = 6.0:
	set(value):
		thickness = value
		queue_redraw()

## How far it may tilt either way (degrees). A seesaw, not a windmill: with no stop, a plank with
## a ball on one end would simply spin.
@export_range(0.0, 89.0, 1.0) var max_tilt_degrees: float = 25.0:
	set(value):
		max_tilt_degrees = value
		queue_redraw()

## Which way it is already tipped when the level loads (degrees), so a lever can start down.
@export_range(-89.0, 89.0, 1.0) var start_tilt_degrees: float = 0.0:
	set(value):
		start_tilt_degrees = value
		queue_redraw()


func _ready() -> void:
	add_to_group(&"levers")
	queue_redraw()


## The plank for the simulation, in WORLD space. The level asks for this once on load.
func build_lever(lever_id: int) -> Lever:
	var scale: float = get_global_transform().get_scale().x
	var lever: Lever = Lever.new(
		lever_id,
		global_position,
		half_length * scale,
		thickness * scale,
		max_tilt_degrees,
	)
	lever.angle = deg_to_rad(clampf(start_tilt_degrees, -max_tilt_degrees, max_tilt_degrees))
	return lever


func _draw() -> void:
	var tilt: float = deg_to_rad(clampf(start_tilt_degrees, -max_tilt_degrees, max_tilt_degrees))
	var direction: Vector2 = Vector2(cos(tilt), sin(tilt))
	draw_line(-direction * half_length, direction * half_length, INK, maxf(1.0, thickness * 2.0))
	draw_circle(Vector2.ZERO, maxf(3.0, thickness), PIVOT)

	if Engine.is_editor_hint():
		# The travel limits, so the swept area is obvious while the lever is being placed.
		for sign_of: int in [-1, 1]:
			var limit: float = deg_to_rad(max_tilt_degrees) * float(sign_of)
			var swung: Vector2 = Vector2(cos(limit), sin(limit))
			draw_line(-swung * half_length, swung * half_length, FAINT, 1.0)
