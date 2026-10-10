class_name BallState
extends RefCounted

## Everything the simulation moves. Ported from `BodyState` in src/systems/MaterialCollision.ts.
##
## Deliberately plain data, with no node and no rendering: the real ball and the trajectory
## prediction both advance one of these through the same `BallSim.step_ball`, which is what keeps
## the ghost line and the real shot identical.

var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0

## Material under the ball while it is supported, or SurfaceKind.NONE while airborne.
var ground_material: int = SurfaceKind.NONE
## How upward-facing the support is: -1 is dead flat, 0 a vertical wall. Only meaningful while
## ground_material is set.
var ground_ny: float = 0.0
## Rolling angle in radians. Visual only.
var spin: float = 0.0
## Settle hops served on the current landing, counted down as each one is used.
var settle_hops: int = 0
## Upward speed owed because a rising bounce landed on a downward-facing surface.
##
## A ceiling cannot throw a ball up through itself, so the lift is held here and handed over the
## moment the ball is clear. Part of the body state rather than the ball so the ghost carries it
## too, and the prediction keeps matching.
var pending_lift: float = 0.0


func copy_from(other: BallState) -> void:
	x = other.x
	y = other.y
	vx = other.vx
	vy = other.vy
	ground_material = other.ground_material
	ground_ny = other.ground_ny
	spin = other.spin
	settle_hops = other.settle_hops
	pending_lift = other.pending_lift


func position() -> Vector2:
	return Vector2(x, y)


func velocity() -> Vector2:
	return Vector2(vx, vy)


func speed() -> float:
	return Vector2(vx, vy).length()
