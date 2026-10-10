class_name StepPolicy
extends RefCounted

## What to do about the side effects of a step. Ported from `CollisionPolicy` in
## src/systems/MaterialCollision.ts.
##
## This is the ONLY thing that differs between the real ball and the prediction: the ball plays
## sounds and squashes, the ghost records points and stops after a few bounces. The movement
## maths is shared, so they cannot disagree about where the ball goes.
##
## Return false from `on_contact` to end the run (the prediction uses this to stop after its
## bounce budget; nothing else does in phase 1).


## What to do with a pane the rocky ball just hit hard enough to shatter.
const GLASS_BREAK: int = 0
## Treat it as solid after all (nothing uses this yet; kept for parity with Phaser).
const GLASS_SOLID: int = 1
## End the run here. The prediction uses this when its bounce budget is spent.
const GLASS_STOP: int = 2


func on_contact(_contact: Contact) -> bool:
	return true


## A pane broke. The real ball removes it and tells the level; the ghost marks it gone for the
## rest of the prediction only.
func on_glass(_shape: ShapeBody, _state: BallState, _impact_speed: float) -> int:
	return GLASS_BREAK


## The ball touched spikes. The real ball is sent back to its last flag; the ghost line just
## stops there, which is exactly the warning the player wants.
func on_spikes(_strip: SpikeStrip, _state: BallState) -> void:
	pass
