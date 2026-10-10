@tool
class_name SpikesBlock
extends Polygon2D

## A strip of spikes, placed like a wall. Ported from the `Spikes` object in the Phaser levels.
##
## One rectangle: the front 60% is teeth, the rest is a solid slab, and the whole block is deadly
## from every side. Rotate the node to put it on a floor, a wall, a ceiling or the underside of a
## ledge — the teeth always face the node's local "up".
##
## Extends Polygon2D so it has an editor rect and can be clicked and dragged in the viewport; its
## polygon is kept in step with `width` and `thickness` rather than edited by hand, because a
## spike strip is a rectangle by definition.

const INK: Color = Color("141414")

## Length of the strip along its face.
@export_range(16.0, 600.0, 2.0) var width: float = 120.0:
	set(value):
		width = value
		_refresh()

## Total thickness of the block: teeth at the front, slab behind.
@export_range(6.0, 60.0, 1.0) var thickness: float = 18.0:
	set(value):
		thickness = value
		_refresh()


func _ready() -> void:
	add_to_group(&"spikes")
	color = Color(0, 0, 0, 0)
	_refresh()


## Keep the click target the same size as the block it draws.
func _refresh() -> void:
	var half: float = width * 0.5
	var tooth: float = thickness * SpikeStrip.TOOTH_SHARE
	var base: float = thickness * (1.0 - SpikeStrip.TOOTH_SHARE)
	polygon = PackedVector2Array([
		Vector2(-half, -tooth), Vector2(half, -tooth),
		Vector2(half, base), Vector2(-half, base),
	])
	queue_redraw()


## The strip in WORLD space. The level asks for this once on load.
func build_strip(strip_id: int) -> SpikeStrip:
	var transform: Transform2D = get_global_transform()
	var centre: Vector2 = transform * Vector2.ZERO
	# Local up is the spiked face; the node's rotation turns it.
	var normal: Vector2 = transform.basis_xform(Vector2.UP).normalized()
	var scale_along: float = transform.basis_xform(Vector2.RIGHT).length()
	return SpikeStrip.make(strip_id, centre, normal, width * 0.5 * scale_along, thickness)


func _draw() -> void:
	var half: float = width * 0.5
	var tooth_depth: float = thickness * SpikeStrip.TOOTH_SHARE
	var base_depth: float = thickness * (1.0 - SpikeStrip.TOOTH_SHARE)

	# The solid slab, with its front edge broken into teeth, so the strip reads as a length of
	# spiked wall rather than a row of triangles floating beside one.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-half, 0.0), Vector2(half, 0.0),
		Vector2(half, base_depth), Vector2(-half, base_depth),
	]), INK)

	var tooth: float = maxf(8.0, tooth_depth)
	var count: int = maxi(1, int(round(width / tooth)))
	var step: float = width / float(count)
	for i: int in count:
		var a: float = -half + float(i) * step
		var b: float = a + step
		draw_colored_polygon(PackedVector2Array([
			Vector2(a, 0.0), Vector2(b, 0.0), Vector2((a + b) * 0.5, -tooth_depth),
		]), INK)
