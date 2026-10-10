class_name SurfaceKind
extends RefCounted

## The materials the simulation knows about, ported from the `Material` union in
## src/config/tuning.ts. Phase 1 has only rock and glass; trampolines, cables and the rest join
## the list in later phases.
##
## NONE stands in for Phaser's `null` ground material, because a typed int cannot be null.

const NONE: int = -1
const WALL: int = 0
const GLASS: int = 1


## The name Tiled and the Phaser levels use, for metadata and debug text.
static func to_name(kind: int) -> String:
	match kind:
		WALL:
			return "wall"
		GLASS:
			return "glass"
	return "none"


## Parse the `material` metadata on a terrain node. Anything unrecognised is rock, which is the
## safe default: a mislabelled piece is solid rather than invisible.
static func from_name(name: String) -> int:
	match name.strip_edges().to_lower():
		"glass":
			return GLASS
		"wall":
			return WALL
	return WALL
