class_name SpikeStrip
extends RefCounted

## A strip of spikes. Ported from the `Spikes` actor in src/systems/Actors.ts.
##
## The WHOLE block bites, from every side: a strip brushed past sideways is as fatal as one
## landed on, and a ball that ends up behind one is not somewhere it should survive. The strip is
## also solid (its slab is registered as a wall shape by the level), but solid and deadly must
## not be the same region unless the deadly one is the larger -- in the Phaser project a slab
## that covered the teeth fenced the ball off from the very zone that kills it, and every strip
## in the game went quietly inert.

var id: int = 0
## Centre of the spiked FACE, which is the side the teeth stand on.
var x: float = 0.0
var y: float = 0.0
## Unit normal out of the face.
var nx: float = 0.0
var ny: float = -1.0
## Half the strip's length, along its face.
var half: float = 60.0
## How far the points stand out of the base.
var depth: float = 10.0
## The solid slab behind the teeth.
var base: float = 7.0

## A DISC hazard instead of a strip, when greater than zero: a saw blade or a spiked gear, deadly
## all the way round, centred on `x, y`.
##
## The same class rather than a new one because everything around a hazard already works in terms
## of this one: `StepWorld.spikes`, the sharing in `ghost()`, the swept test, the route check, and
## `StepPolicy.on_spikes` -- which is what makes the ghost line stop dead at a hazard. A second
## hazard type would have to earn all of that again, and the only thing that actually differs is
## which points are inside.
##
## A disc carries NO slab (`corners()` is empty), and that is deliberate. An imported blade already
## has its own solid collision from the manifest, and it is the smaller circle: collision uses the
## largest disc that fits the art, while the hazard reaches the tooth tips. That ordering is the
## one the warning at the top of this file is about -- the deadly region has to be the larger, or
## the solid one fences the ball off from the very zone that kills it and the hazard goes quietly
## inert.
var radius: float = 0.0


## A disc hazard: deadly from every direction, with no solid body of its own.
static func make_disc(hazard_id: int, centre: Vector2, hazard_radius: float) -> SpikeStrip:
	var s: SpikeStrip = SpikeStrip.new()
	s.id = hazard_id
	s.x = centre.x
	s.y = centre.y
	s.radius = maxf(1.0, hazard_radius)
	return s


## True for the disc form.
func is_disc() -> bool:
	return radius > 0.0


static func make(strip_id: int, centre: Vector2, normal: Vector2, half_length: float, thickness: float) -> SpikeStrip:
	var s: SpikeStrip = SpikeStrip.new()
	s.id = strip_id
	s.x = centre.x
	s.y = centre.y
	var n: Vector2 = normal.normalized()
	s.nx = n.x
	s.ny = n.y
	s.half = maxf(1.0, half_length)
	# The rectangle's thickness is the whole block: points at the front, slab behind them.
	s.depth = maxf(2.0, thickness * TOOTH_SHARE)
	s.base = maxf(1.0, thickness * (1.0 - TOOTH_SHARE))
	return s


## How much of a spike block is teeth; the rest is the solid slab they stand on.
const TOOTH_SHARE: float = 0.6


## Circle against the whole block, from every side.
func touches(cx: float, cy: float, r: float) -> bool:
	if is_disc():
		var ddx: float = cx - x
		var ddy: float = cy - y
		var reach: float = radius + r
		return ddx * ddx + ddy * ddy < reach * reach

	# Work in the strip's own frame: along its length, and across it (+ towards the points).
	var tx: float = -ny
	var ty: float = nx
	var dx: float = cx - x
	var dy: float = cy - y
	var along: float = dx * tx + dy * ty
	var across: float = dx * nx + dy * ny

	# Closest point on the block -- teeth in front, slab behind -- then a circle test.
	var ca: float = clampf(along, -half, half)
	var cr: float = clampf(across, -base, depth)
	var ox: float = along - ca
	var oy: float = across - cr
	return ox * ox + oy * oy < r * r


## The same test along the path the ball travelled this substep.
##
## A thin strip and a fast ball are a bad combination for a point-in-time check: the ball can be
## in front of the spikes on one step and past them on the next, having never been measured
## inside. Sampling the segment closes that, and the samples are a half-radius apart so nothing
## narrower than the ball can fall between two of them.
func sweep(x0: float, y0: float, x1: float, y1: float, r: float) -> bool:
	var dx: float = x1 - x0
	var dy: float = y1 - y0
	var distance: float = sqrt(dx * dx + dy * dy)
	var steps: int = maxi(1, int(ceil(distance / maxf(2.0, r * 0.5))))
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		if touches(x0 + dx * t, y0 + dy * t, r):
			return true
	return false


## The four corners of the block, for drawing and for the solid slab the level registers.
##
## Empty for a disc, which has no slab of its own -- see `radius`.
func corners() -> PackedVector2Array:
	if is_disc():
		return PackedVector2Array()
	var tx: float = -ny
	var ty: float = nx
	return PackedVector2Array([
		Vector2(x - tx * half + nx * depth, y - ty * half + ny * depth),
		Vector2(x + tx * half + nx * depth, y + ty * half + ny * depth),
		Vector2(x + tx * half - nx * base, y + ty * half - ny * base),
		Vector2(x - tx * half - nx * base, y - ty * half - ny * base),
	])
