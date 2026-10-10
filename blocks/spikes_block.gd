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
## Hazards are drawn in warning red rather than ink: a deadly region has to be unmistakable while
## placing, and it is not part of the art it sits on.
const DANGER: Color = Color(0.85, 0.15, 0.15, 0.85)

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

## A strip, or a disc that is deadly all the way round.
##
## Disc is what a saw blade and a spiked gear are. It stays the same block, in the same `spikes`
## group, built by the same loop in the level -- the shape is the only thing that differs, and
## everything else a hazard needs already works in terms of this class.
@export_enum("Strip:0", "Disc:1") var shape: int = SHAPE_STRIP:
	set(value):
		shape = value
		_refresh()

## Disc only: how far the teeth reach from the centre.
##
## This should be the piece's OUTER extent -- the tooth tips -- not its collision radius. An
## imported blade collides as the largest circle that fits its art, so the deadly disc is the
## larger of the two and the ball meets the teeth before it reaches the solid hub. Make it smaller
## than the collision and the solid fences the ball away from the hazard, which goes silently
## inert; `core/spike_strip.gd` opens with that warning for a reason.
@export_range(2.0, 2000.0, 1.0) var radius: float = 60.0:
	set(value):
		radius = value
		_refresh()

const SHAPE_STRIP: int = 0
const SHAPE_DISC: int = 1


func _ready() -> void:
	add_to_group(&"spikes")
	color = Color(0, 0, 0, 0)
	_refresh()


## Keep the click target the same size as the block it draws.
func _refresh() -> void:
	if shape == SHAPE_DISC:
		# A ring of points: Polygon2D is what gives this node its editor rect, so the click target
		# has to follow the disc rather than stay a rectangle nobody can see.
		var ring: PackedVector2Array = PackedVector2Array()
		for i: int in DISC_HANDLE_POINTS:
			var a: float = TAU * float(i) / float(DISC_HANDLE_POINTS)
			ring.append(Vector2(cos(a), sin(a)) * radius)
		polygon = ring
		queue_redraw()
		return

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
	if shape == SHAPE_DISC:
		# Scale can be uneven on a placed piece; the larger axis keeps the deadly region at least
		# as big as the art rather than letting it shrink inside the teeth.
		var sx: float = transform.basis_xform(Vector2.RIGHT).length()
		var sy: float = transform.basis_xform(Vector2.UP).length()
		return SpikeStrip.make_disc(strip_id, centre, radius * maxf(sx, sy))
	# Local up is the spiked face; the node's rotation turns it.
	var normal: Vector2 = transform.basis_xform(Vector2.UP).normalized()
	var scale_along: float = transform.basis_xform(Vector2.RIGHT).length()
	return SpikeStrip.make(strip_id, centre, normal, width * 0.5 * scale_along, thickness)


func _draw() -> void:
	if shape == SHAPE_DISC:
		_draw_disc()
		return

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


## How many points the disc's click target is built from.
const DISC_HANDLE_POINTS: int = 24


## A disc hazard, drawn as an outline rather than a filled shape.
##
## It sits ON a piece that already has its own art, so filling it would hide the blade it is
## marking. What is wanted here is the opposite of the strip's placeholder look: a boundary you can
## see while placing, showing exactly how far the deadly region reaches, and nothing in the way of
## the sprite underneath.
func _draw_disc() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, DISC_HANDLE_POINTS * 2, DANGER, 2.0)
	if not Engine.is_editor_hint():
		return
	# In the editor only, a few spokes so a disc with nothing drawn inside it is still obviously a
	# hazard rather than an empty circle somebody left behind.
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var d: Vector2 = Vector2(cos(a), sin(a))
		draw_line(d * radius * 0.78, d * radius, DANGER, 2.0)
