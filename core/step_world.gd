class_name StepWorld
extends RefCounted

## Everything the step needs besides the ball. Ported from `StepWorld` in
## src/systems/MaterialCollision.ts.
##
## The level builds one of these from the block scenes in the tree; the prediction takes a
## shallow copy that shares the shapes but keeps its OWN set of predicted breaks, so the ghost
## can smash a pane and carry on without touching the real world. That mirrors `GhostTiles` in
## the Phaser project.

var shapes: Array[ShapeBody] = []
## Hazard strips. Touching one ends the run: the ball goes back to its last flag.
var spikes: Array[SpikeStrip] = []
## Seconds since the level started. Unused until cycling fans arrive, but part of the contract.
var time: float = 0.0
## Shape ids the PREDICTION has decided are broken. Empty for the real world.
var predicted_broken: Dictionary = {}


## A copy for the prediction: same geometry, its own broken set.
func ghost() -> StepWorld:
	var copy: StepWorld = StepWorld.new()
	copy.shapes = shapes
	copy.spikes = spikes
	copy.time = time
	copy.predicted_broken = {}
	return copy


## Is this pane still standing, as far as this world is concerned?
func is_shape_solid(shape: ShapeBody) -> bool:
	return not shape.broken and not predicted_broken.has(shape.id)


## The whole level's extent, for clamping the camera.
func bounds() -> Rect2:
	if shapes.is_empty():
		return Rect2()
	var total: Rect2 = shapes[0].bounds
	for shape: ShapeBody in shapes:
		total = total.merge(shape.bounds)
	return total
