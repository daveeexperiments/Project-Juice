@tool
class_name CableBlock
extends Polygon2D

## A slack rope strung between two anchors.
##
## Extends Polygon2D for the same reason every other block does: Godot only offers the
## point-dragging gizmo to the Polygon2D family. Here the polygon is just the two ANCHORS -- drag
## point 0 and point 1 and the rope hangs between them.
##
## ONE CAVEAT, and it is a real one. A two-anchor polygon has a flat bounding box, so a dead
## horizontal or vertical cable is hard to click in the empty space around it: pick it up by one of
## its two handles, or from the scene tree. Overriding `_edit_get_rect` would be the obvious fix
## and is not available -- it is a CanvasItem virtual that GDScript may not override, and this
## project turns that warning into an error. Point-editing, which is what the Polygon2D rule is
## chiefly about, works normally. The rope is drawn at its full collision thickness partly so the
## handles are easy to find.

const ROPE: Color = Color("141414")
const ANCHOR: Color = Color(0.1, 0.1, 0.1, 0.9)
const HANDLE_HINT: Color = Color(0.55, 0.55, 0.55, 0.5)
## How finely the hanging curve is DRAWN. Cosmetic only: the simulated rope uses
## `cables.segments`, and the two need not match.
const DRAW_STEPS: int = 24

## Extra rope beyond the straight-line distance, as a fraction. 0 is a taut line; 0.25 is a
## comfortable hammock.
@export_range(0.0, 1.5, 0.01) var slack: float = 0.25:
	set(value):
		slack = value
		queue_redraw()

## This rope's own collision radius. -1 takes the global `cables.thickness`.
@export_range(-1.0, 40.0, 0.5) var thickness_override: float = -1.0:
	set(value):
		thickness_override = value
		queue_redraw()


func _ready() -> void:
	add_to_group(&"cables")
	# Polygon2D's own fill is switched off; everything visible comes from _draw().
	color = Color(0, 0, 0, 0)
	if polygon.size() < 2:
		polygon = PackedVector2Array([Vector2(-90.0, 0.0), Vector2(90.0, 0.0)])
	queue_redraw()


func _process(_delta: float) -> void:
	# In the editor only, redraw while the anchors are being dragged. `polygon` is inherited, so
	# there is no setter to hook.
	if Engine.is_editor_hint():
		queue_redraw()


## The rope for the simulation, in WORLD space. The level asks for this once on load.
func build_cable(cable_id: int) -> Cable:
	var transform: Transform2D = get_global_transform()
	return Cable.new(cable_id, transform * _anchor(0), transform * _anchor(1), slack, thickness_override)


func _anchor(which: int) -> Vector2:
	if polygon.size() < 2:
		return Vector2.ZERO
	return polygon[0] if which == 0 else polygon[polygon.size() - 1]


## Where the rope hangs, in LOCAL space. The same parabola `Cable.rebuild` lays the rope out
## along, so what the designer sees is where the rope actually starts from.
##
## The droop follows global DOWN rather than local +Y, so a rotated cable still hangs downwards
## instead of sideways.
func _hanging_curve() -> PackedVector2Array:
	var curve: PackedVector2Array = PackedVector2Array()
	if polygon.size() < 2:
		return curve
	var a: Vector2 = _anchor(0)
	var b: Vector2 = _anchor(1)
	var span: float = a.distance_to(b)
	var sag: float = minf(span * slack * 0.5, maxf(0.0, TuningData.get_active().cables_max_sag))
	var down: Vector2 = get_global_transform().affine_inverse().basis_xform(Vector2.DOWN).normalized()

	for i: int in DRAW_STEPS + 1:
		var along: float = float(i) / float(DRAW_STEPS)
		var droop: float = sag * 4.0 * along * (1.0 - along)
		curve.append(a.lerp(b, along) + down * droop)
	return curve


func _draw() -> void:
	var curve: PackedVector2Array = _hanging_curve()
	if curve.size() < 2:
		return
	var width: float = thickness_override if thickness_override >= 0.0 else TuningData.get_active().cables_thickness
	draw_polyline(curve, ROPE, maxf(1.0, width))

	# The anchors, so the two draggable points are obvious even when the rope is slack enough to
	# hang well below them.
	for which: int in 2:
		draw_circle(_anchor(which), 4.0, ANCHOR)

	# In the editor, show the straight line between the anchors faintly as well: the handles sit
	# on that line while the rope the ball hits is the curve below it.
	if Engine.is_editor_hint():
		draw_line(_anchor(0), _anchor(1), HANDLE_HINT, 1.0)
