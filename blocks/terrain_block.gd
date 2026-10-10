@tool
class_name TerrainBlock
extends Polygon2D

## A solid piece of level: rock or glass, any polygon, optionally rounded into a curve.
##
## Extends Polygon2D on purpose, and that is the whole reason it is editable: Godot only offers
## the point-dragging gizmo to the Polygon2D family, and a node drawn purely in `_draw()` has no
## editor rect, so clicking its shape in the viewport selects nothing. Inheriting from Polygon2D
## gives both -- drag the points with the polygon tool, click the shape to pick it up.
##
## The inherited `color` is left fully transparent: Polygon2D supplies the handles and the
## bounds, and `_draw()` supplies the ink look. The SMOOTHED outline is what is drawn and what
## the ball hits, so there is no second collision shape to keep in step.

const INK: Color = Color("141414")
const GLASS_FILL: Color = Color(0.72, 0.80, 0.84, 0.45)
const GLASS_LINE: Color = Color(0.23, 0.33, 0.38, 0.9)
const HANDLE_HINT: Color = Color(0.55, 0.55, 0.55, 0.5)
const HATCH_SPACING: float = 14.0

## Rock or glass. Glass can be broken by the rocky ball, depending on the mode.
##
## Named surface_material rather than material because CanvasItem already has a `material`
## property (the shader one) and Godot refuses to let a script redefine it.
@export_enum("Wall:0", "Glass:1") var surface_material: int = 0:
	set(value):
		surface_material = value
		queue_redraw()

## 0 keeps the drawn corners exactly; higher rounds the shape into a flowing curve.
@export_range(0.0, 1.0, 0.05) var smoothing: float = 0.0:
	set(value):
		smoothing = value
		queue_redraw()

@export_group("Glass only")
## What the rocky ball does to THIS piece. Default follows the global Rocky vs glass mode.
@export_enum("Default:-1", "Break obstructions only:0", "Always break:1", "Hard hits only:2", "Never break:3", "Pass through:4")
var rocky_breaks: int = -1
## Cladding or something in the way. Auto measures it against the terrain behind the pane.
@export_enum("Auto:-1", "Obstruction:0", "Wall glass:1") var glass_type: int = -1
## Seconds until this pane returns once broken. 0 = never. -1 = use the global setting.
@export_range(-1.0, 30.0, 0.5) var respawn_seconds: float = -1.0
## This pane throws the ball back at its own speed in Boost mode. -1 = use the global strength.
@export_range(-1.0, 2000.0, 10.0) var bounce_boost: float = -1.0


func _ready() -> void:
	add_to_group(&"terrain")
	# Polygon2D's own fill is switched off; everything visible comes from _draw().
	color = Color(0, 0, 0, 0)
	queue_redraw()


func _process(_delta: float) -> void:
	# In the editor only, redraw while the points are being dragged. `polygon` is inherited, so
	# there is no setter to hook -- watching it here is the simplest honest way to stay current.
	if Engine.is_editor_hint():
		queue_redraw()


## The collision body for this block, in WORLD space. The level asks for this once on load.
func build_shape(shape_id: int) -> ShapeBody:
	var transform: Transform2D = get_global_transform()
	var world_points: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in polygon:
		world_points.append(transform * p)

	var kind: int = SurfaceKind.GLASS if surface_material == 1 else SurfaceKind.WALL
	var shape: ShapeBody = ShapeBody.new(shape_id, world_points, kind, smoothing)
	if kind == SurfaceKind.GLASS:
		shape.rocky_breaks = rocky_breaks
		shape.glass_type_override = glass_type
		shape.respawn_seconds = respawn_seconds
		shape.bounce_boost = bounce_boost
	return shape


func _draw() -> void:
	if polygon.size() < 3:
		return
	var outline: PackedVector2Array = ShapeBody.smooth_closed_polygon(polygon, smoothing)
	if surface_material == 1:
		_draw_glass(outline)
	else:
		draw_colored_polygon(outline, INK)

	# With smoothing on, the handles sit on the drawn points while the ball hits the curve. Show
	# the straight outline faintly in the editor so the two are never confused.
	if Engine.is_editor_hint() and smoothing > 0.0:
		var raw: PackedVector2Array = polygon.duplicate()
		raw.append(polygon[0])
		draw_polyline(raw, HANDLE_HINT, 1.0)


## Ink-style glass: a pale pane with diagonal hatching, as in the Phaser renderer.
func _draw_glass(outline: PackedVector2Array) -> void:
	draw_colored_polygon(outline, GLASS_FILL)
	var bounds: Rect2 = Rect2(outline[0], Vector2.ZERO)
	for p: Vector2 in outline:
		bounds = bounds.expand(p)

	var k: float = bounds.position.x + bounds.position.y
	var limit: float = bounds.end.x + bounds.end.y
	while k < limit:
		_draw_clipped_line(
			Vector2(k - bounds.end.y, bounds.end.y),
			Vector2(k - bounds.position.y, bounds.position.y),
			outline,
		)
		k += HATCH_SPACING

	var closed: PackedVector2Array = outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, GLASS_LINE, 1.5)


## Draw only the parts of a line that fall inside the pane.
func _draw_clipped_line(a: Vector2, b: Vector2, outline: PackedVector2Array) -> void:
	var steps: int = 24
	var run_start: Vector2 = Vector2.ZERO
	var running: bool = false
	for i: int in steps + 1:
		var p: Vector2 = a.lerp(b, float(i) / float(steps))
		var inside: bool = Geometry2D.is_point_in_polygon(p, outline)
		if inside and not running:
			run_start = p
			running = true
		elif not inside and running:
			draw_line(run_start, p, GLASS_LINE, 1.0)
			running = false
	if running:
		draw_line(run_start, b, GLASS_LINE, 1.0)
