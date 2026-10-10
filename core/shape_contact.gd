class_name ShapeContact
extends RefCounted

## One circle-vs-outline contact. Ported from the `ShapeContact` interface in
## src/systems/ShapeBody.ts.
##
## The normal is a unit vector pointing OUT of the surface towards the ball, and `depth` is the
## overlap: move the ball along the normal by that much and it is exactly touching.

var nx: float = 0.0
var ny: float = 0.0
var depth: float = 0.0


static func make(normal_x: float, normal_y: float, overlap: float) -> ShapeContact:
	var c: ShapeContact = ShapeContact.new()
	c.nx = normal_x
	c.ny = normal_y
	c.depth = overlap
	return c


func normal() -> Vector2:
	return Vector2(nx, ny)
