class_name Contact
extends RefCounted

## One resolved collision, reported to whoever is watching the step. Ported from the `Contact`
## interface in src/systems/MaterialCollision.ts, minus the fields that belong to systems not yet
## ported (glass breaking, trampoline launches, the rising assist).

var nx: float = 0.0
var ny: float = 0.0
var x: float = 0.0
var y: float = 0.0
var material: int = SurfaceKind.WALL
## Speed into the surface along the normal, before the response.
var impact_speed: float = 0.0
## Speed back out along the normal, after the response.
var out_speed: float = 0.0
## False for a resting contact (gravity pressing in); true for a real impact.
var is_impact: bool = false
## True when the ball came down onto something that faces up.
var landing: bool = false
## True when this contact shattered a pane and the ball carried on through.
var broke_glass: bool = false
## True when glass threw the ball back in Boost mode, rather than plainly reflecting it.
var boosted: bool = false


static func make(
	state: BallState,
	normal_x: float,
	normal_y: float,
	surface: int,
	impact: float,
	out: float,
	impacted: bool,
	was_landing: bool,
) -> Contact:
	var c: Contact = Contact.new()
	c.nx = normal_x
	c.ny = normal_y
	c.x = state.x
	c.y = state.y
	c.material = surface
	c.impact_speed = impact
	c.out_speed = out
	c.is_impact = impacted
	c.landing = was_landing
	return c


func normal() -> Vector2:
	return Vector2(nx, ny)
