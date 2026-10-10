@tool
class_name PipeBlock
extends Polygon2D

## A pipe run the ball travels inside, drawn as a centreline.
##
## Extends Polygon2D for the same reason `TerrainBlock` does: Godot only offers the point-dragging
## gizmo to the Polygon2D family, so this is the one base class that lets you lay a path out by
## hand in the viewport. The points are a POLYLINE here rather than a closed shape -- the last
## point does not join the first -- which is why nothing is filled.
##
## **Draw it through the art, not around it.** The path is authored, exactly like collision: a run
## is an elbow, a straight and another elbow, and recovering a centreline from the union of their
## silhouettes would be fragile work for no gain. Put the first point in one mouth, the last in the
## other, and a point at each bend.
##
## The pipe pieces themselves are placed as ordinary art. Usually you want their collision off --
## untick `collides` on them -- because the pipe's walls are not what stops the ball; being on the
## rail is.

const INK: Color = Color(0.25, 0.55, 0.95, 0.9)
const MOUTH: Color = Color(0.25, 0.55, 0.95, 0.35)
const FAINT: Color = Color(0.25, 0.55, 0.95, 0.18)

## How close the ball must come to a mouth to be drawn in. -1 uses `pipes.mouthRadius`.
##
## Per-object rather than a tuning number, because it is a property of this placed run: a wide
## hopper and a tight tube are different openings, not a different game.
@export_range(-1.0, 400.0, 1.0) var mouth_radius: float = -1.0:
	set(value):
		mouth_radius = value
		queue_redraw()


func _ready() -> void:
	add_to_group(&"pipes")
	color = Color(0, 0, 0, 0)
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


## The effective mouth radius in world units, falling back to the global.
func effective_mouth_radius() -> float:
	var r: float = mouth_radius
	if r < 0.0:
		r = TuningData.get_active().pipes_mouth_radius
	return r * maxf(0.01, get_global_transform().get_scale().x)


## The run in WORLD space. The level asks for this once on load.
func build_pipe(pipe_id: int) -> Pipe:
	var transform: Transform2D = get_global_transform()
	var points: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in polygon:
		points.append(transform * p)
	return Pipe.make(pipe_id, points, effective_mouth_radius())


func _draw() -> void:
	if polygon.size() < 2:
		return

	# The centreline, and a faint band either side of it showing roughly where the ball will run.
	# Not collision -- nothing here collides -- just somewhere to aim while placing.
	var r: float = mouth_radius if mouth_radius >= 0.0 else TuningData.get_active().pipes_mouth_radius
	for i: int in range(1, polygon.size()):
		draw_line(polygon[i - 1], polygon[i], FAINT, r * 1.2)
	for i: int in range(1, polygon.size()):
		draw_line(polygon[i - 1], polygon[i], INK, 3.0)

	# Both ends accept a ball, so both are drawn the same way. Which one a shot enters by is
	# decided by where it arrives, not by anything set here.
	draw_circle(polygon[0], r, MOUTH)
	draw_circle(polygon[polygon.size() - 1], r, MOUTH)

	if not Engine.is_editor_hint():
		return
	for p: Vector2 in polygon:
		draw_circle(p, 4.0, INK)
