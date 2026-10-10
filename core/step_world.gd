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
## Columns of moving air. Stateless, so the prediction shares them rather than copying.
var fans: Array[FanField] = []
## Slack ropes. These MOVE, so the prediction gets copies -- see `ghost()`.
var cables: Array[Cable] = []
## Seconds since the level started. Unused until cycling fans arrive, but part of the contract.
var time: float = 0.0
## Shape ids the PREDICTION has decided are broken. Empty for the real world.
var predicted_broken: Dictionary = {}


## A copy for the prediction: same geometry, its own broken set.
##
## What is shared and what is copied is the whole correctness question here. Anything the ghost
## could CHANGE has to be copied, or a prediction would alter the level the player is standing in;
## anything immutable is shared, because copying it would only cost time. Fans and spikes hold no
## state, so they are shared; the broken set is the ghost's own; cables swing, so they are copied.
##
## Cables are the reason this matters in practice rather than in principle: a preview that swung
## the real ropes would mean aiming physically disturbed the level, and merely LOOKING at a shot
## would change where it went.
func ghost() -> StepWorld:
	var copy: StepWorld = StepWorld.new()
	copy.shapes = shapes
	copy.spikes = spikes
	copy.fans = fans
	copy.time = time
	copy.predicted_broken = {}
	copy.cables = []
	for cable: Cable in cables:
		copy.cables.append(cable.ghost_copy())
	return copy


## Freeze every rope, so a run can be repeated from the same start. The tests use this to prove
## the ghost and the ball agree; without it the second run would begin with ropes the first run
## had already swung.
func snapshot_cables() -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	for cable: Cable in cables:
		saved.append(cable.snapshot())
	return saved


func restore_cables(saved: Array[Dictionary]) -> void:
	for i: int in mini(saved.size(), cables.size()):
		cables[i].restore(saved[i])


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
