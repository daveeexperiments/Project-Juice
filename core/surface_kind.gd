class_name SurfaceKind
extends RefCounted

## The materials the simulation knows about, ported from the `Material` union in
## src/config/tuning.ts.
##
## A material is how the simulation asks what a surface DOES, so that adding a surface never means
## adding a branch anywhere outside `_respond_to_shape`. Trampolines joined in phase 3 this way
## rather than as a separate actor list: a pad is a shape made of springy stuff, so it collides,
## supports a resting ball, takes friction and is walked by the route check for free.
##
## NONE stands in for Phaser's `null` ground material, because a typed int cannot be null.

const NONE: int = -1
const WALL: int = 0
const GLASS: int = 1
const TRAMPOLINE: int = 2
## A slack rope. Not a shape: it has its own list on StepWorld because it moves, but it reports
## itself as a material on contact so the limiter and the debug overlay can tell what was hit.
const CABLE: int = 3


## The name Tiled and the Phaser levels use, for metadata and debug text.
static func to_name(kind: int) -> String:
	match kind:
		WALL:
			return "wall"
		GLASS:
			return "glass"
		TRAMPOLINE:
			return "trampoline"
		CABLE:
			return "cable"
	return "none"


## Parse the `material` metadata on a terrain node. Anything unrecognised is rock, which is the
## safe default: a mislabelled piece is solid rather than invisible.
static func from_name(name: String) -> int:
	match name.strip_edges().to_lower():
		"glass":
			return GLASS
		"trampoline":
			return TRAMPOLINE
		"wall":
			return WALL
	return WALL
