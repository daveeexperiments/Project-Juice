@tool
class_name FanBlock
extends Polygon2D

## A fan: a mouth, and a direction it blows.
##
## Extends Polygon2D like every other block, and the polygon is the MOUTH -- its width across the
## stream is the width of the stream. Which way it blows is the node's own rotation, so a fan is
## aimed by rotating it rather than by typing an angle: straight up at rotation 0.
##
## The stream itself is simulated by `FanField`, which holds no state. This node only describes
## where it starts and how wide it is.

const INK: Color = Color("141414")
const WIND: Color = Color(0.35, 0.55, 0.62, 0.55)
const FAINT: Color = Color(0.55, 0.55, 0.55, 0.5)
## How many puffs are drawn up the stream, as a hint rather than a simulation.
const PUFFS: int = 5

## How far this fan reaches. -1 takes the global `fans.range`.
@export_range(-1.0, 2000.0, 10.0) var range_override: float = -1.0:
	set(value):
		range_override = value
		queue_redraw()

## This fan's strength, multiplying the global one. 1 is a standard fan; 0 switches it off.
@export_range(0.0, 4.0, 0.05) var strength_scale: float = 1.0:
	set(value):
		strength_scale = value
		queue_redraw()


func _ready() -> void:
	add_to_group(&"fans")
	color = Color(0, 0, 0, 0)
	if polygon.size() < 3:
		polygon = PackedVector2Array([
			Vector2(-56.0, 0.0), Vector2(56.0, 0.0), Vector2(56.0, 18.0), Vector2(-56.0, 18.0),
		])
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


## The stream for the simulation, in WORLD space. The level asks for this once on load.
func build_fan(fan_id: int) -> FanField:
	var transform: Transform2D = get_global_transform()
	return FanField.new(
		fan_id,
		transform * _mouth_centre(),
		transform.basis_xform(Vector2.UP).normalized(),
		_mouth_width() * transform.get_scale().x,
		range_override,
		strength_scale,
	)


## The middle of the mouth, in local space.
func _mouth_centre() -> Vector2:
	if polygon.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for p: Vector2 in polygon:
		total += p
	return total / float(polygon.size())


## How wide the mouth is ACROSS the stream. The stream blows along local up, so that is the
## polygon's extent on X.
func _mouth_width() -> float:
	if polygon.is_empty():
		return 0.0
	var low: float = INF
	var high: float = -INF
	for p: Vector2 in polygon:
		low = minf(low, p.x)
		high = maxf(high, p.x)
	return maxf(1.0, high - low)


func _draw() -> void:
	if polygon.size() < 3:
		return
	draw_colored_polygon(polygon, INK)

	# The stream, as a tapering set of puffs up the local up axis, so the direction and the reach
	# are both visible without selecting the node.
	var reach: float = range_override if range_override >= 0.0 else TuningData.get_active().fans_range
	var centre: Vector2 = _mouth_centre()
	var half: float = _mouth_width() * 0.5
	for i: int in PUFFS:
		var along: float = float(i + 1) / float(PUFFS + 1)
		var y: float = -reach * along
		var fade: float = 1.0 - along
		var colour: Color = Color(WIND, WIND.a * fade)
		draw_line(
			centre + Vector2(-half * fade, y),
			centre + Vector2(half * fade, y),
			colour,
			2.0,
		)

	if Engine.is_editor_hint():
		# The edges of the stream, so its width is unambiguous while it is being placed.
		draw_line(centre + Vector2(-half, 0.0), centre + Vector2(-half, -reach), FAINT, 1.0)
		draw_line(centre + Vector2(half, 0.0), centre + Vector2(half, -reach), FAINT, 1.0)
