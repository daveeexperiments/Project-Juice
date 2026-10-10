@tool
class_name SpawnBlock
extends Marker2D

## Where the level starts, and the first checkpoint. Extends Marker2D so it is clickable in the
## viewport.
## Ported from the `spawn` object in the Phaser
## levels: the point is where the ball's FEET go, so the ball itself sits a radius above it.

const INK: Color = Color("141414")
const ON: Color = Color("2f8f4e")


func _ready() -> void:
	add_to_group(&"spawn")
	queue_redraw()


## Where the ball's feet go.
func respawn_point() -> Vector2:
	return global_position


func _draw() -> void:
	# A small ring sitting on the ground line, so the foot position is unambiguous in the editor.
	draw_arc(Vector2(0.0, -12.0), 12.0, 0.0, TAU, 24, ON, 2.0)
	draw_line(Vector2(-16.0, 0.0), Vector2(16.0, 0.0), INK, 2.0)
