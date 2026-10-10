@tool
class_name FlagBlock
extends Marker2D

## A checkpoint. Ported from the `Flag` object (the `checkpoint` trigger renamed) in the Phaser
## levels.
##
## Extends Marker2D so it can be clicked and dragged in the viewport: a bare Node2D drawn only
## in `_draw()` has no editor rect, so clicks pass straight through it.
##
## Raises and changes colour when the ball comes close; the most recently raised flag is where a
## spiked ball comes back to. The node's origin is the FOOT of the pole, so it stands on whatever
## it is placed on.

const INK: Color = Color("141414")
const OFF: Color = Color("8a867d")
const ON: Color = Color("2f8f4e")

signal raised()

## Height of the pole.
@export_range(20.0, 160.0, 2.0) var pole_height: float = 56.0:
	set(value):
		pole_height = value
		queue_redraw()

## Extra reach beyond the ball's own radius. -1 follows the global flags_touch_radius.
@export_range(-1.0, 160.0, 2.0) var touch_radius: float = -1.0

var activated: bool = false:
	set(value):
		if value == activated:
			return
		activated = value
		queue_redraw()
		if activated:
			raised.emit()


func _ready() -> void:
	add_to_group(&"flags")
	queue_redraw()


## Where the ball reappears: the foot of the pole, lifted by its own radius by the caller.
func respawn_point() -> Vector2:
	return global_position


func reach() -> float:
	if touch_radius >= 0.0:
		return touch_radius
	return TuningData.get_active().flags_touch_radius


func _draw() -> void:
	# The pole.
	draw_line(Vector2.ZERO, Vector2(0.0, -pole_height), INK, 3.0)
	# The flag itself: raised and green once activated, drooping and grey before.
	var top: Vector2 = Vector2(0.0, -pole_height)
	var colour: Color = ON if activated else OFF
	var droop: float = 0.0 if activated else 10.0
	draw_colored_polygon(PackedVector2Array([
		top + Vector2(2.0, 0.0),
		top + Vector2(2.0, 16.0),
		top + Vector2(26.0, 8.0 + droop),
	]), colour)
	draw_polyline(PackedVector2Array([
		top + Vector2(2.0, 0.0),
		top + Vector2(2.0, 16.0),
		top + Vector2(26.0, 8.0 + droop),
		top + Vector2(2.0, 0.0),
	]), INK, 1.5)
