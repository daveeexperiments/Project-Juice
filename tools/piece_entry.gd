@tool
class_name PieceEntry
extends Resource

## One shape found on a sprite sheet, and the collision it gets.
##
## The fields split into two halves, and the split is the whole point of this file:
##
## - **Geometry** (`region`, `outline`, the measurements) is MEASURED. The slicer overwrites it
##   every run.
## - **Decisions** (`kind`, `radius`, `inner_radius`, `reviewed`) are KEPT. The slicer never
##   overwrites them once set.
##
## That is why this is a checked-in resource rather than something the importer recomputes from
## the art each time: re-running the slicer must never cost you a decision you made by hand. An
## art pipeline that loses your corrections on re-import is one you stop re-importing, and then
## the art and the game drift apart for good.
##
## Everything here is in SOURCE PIXELS, as delivered. Nothing in this file knows about the world
## scale; the importer applies that when it builds the piece's scene.

## What collides for this piece.
##
## Collision is authored, not traced -- see `docs/ROADMAP.md`. A gear's teeth are visual detail,
## and tracing them wedges the ball between them, so a gear is a disc. The one case that genuinely
## needs its outline is terrain.
enum Kind {
	POLYGON, ## The traced outline, closed by the ball's radius. Terrain blobs.
	CIRCLE, ## One radius. Gears, pulleys, wheels, saw blades.
	RECT, ## The region's box. Beams, straight pipes, platforms.
	ANNULUS, ## Two radii -- a ring the ball travels INSIDE. Needs no hole support anywhere.
	NONE, ## Never reaches the simulation. Pure decoration.
}

# ---------------------------------------------------------------- identity

## Stable key, e.g. `blob_sheet_1_07`. This is what the manifest matches on across runs, so it
## must not move when the slicer runs again -- which is why pieces are sorted deterministically
## (row-major by bounding box) rather than in whatever order the trace happens to produce.
@export var id: String = ""

## The sheet this came from, as a `res://` path.
@export var sheet: String = ""

# ---------------------------------------------------------------- measured: the slicer owns these

## Where the piece sits on the sheet. Becomes the AtlasTexture region for the sprite.
@export var region: Rect2i = Rect2i()

## The simplified outline, in source pixels **relative to `region`'s top-left corner**.
##
## Relative rather than absolute so that moving a piece on a re-exported sheet changes `region`
## and leaves this alone.
@export var outline: PackedVector2Array = PackedVector2Array()

## Opaque pixels divided by the outline's area. Near 1 is solid; well under 1 means the trace
## enclosed empty space, which is how a ring or a hollow gear gives itself away.
@export var solidity: float = 0.0

## Opaque pixels divided by the bounding box's area. Near 1 means the piece fills its box, which
## is what a beam or a straight pipe looks like.
@export var box_fill: float = 0.0

## The outline's area divided by that of a circle filling the box. Near 1 on a square-ish box
## means a disc.
@export var circularity: float = 0.0

## How many vertices the simplified outline has. Only `POLYGON` pieces pay for these at runtime,
## since `ShapeBody.contact` is O(edges) -- a `CIRCLE` costs one number however spiky it looked.
@export var vertex_count: int = 0

## What the slicer's measurements suggested, kept even after a human overrides `kind`. Worth
## keeping: a piece where the guess and the decision disagree is where the classifier is weak, and
## that is the list you want when tuning its thresholds.
@export var guessed: Kind = Kind.POLYGON

# ---------------------------------------------------------------- decided: a human owns these

## The collision this piece actually gets. Starts as `guessed` and is yours to change.
@export var kind: Kind = Kind.POLYGON

## For `CIRCLE` and `ANNULUS`: the outer radius in source pixels. 0 means "measure it from the
## region", which is nearly always right.
@export var radius: float = 0.0

## For `ANNULUS`: the inner radius in source pixels -- the surface the ball rolls along inside the
## ring.
@export var inner_radius: float = 0.0

## Set true once you have looked at this piece and agree with its `kind`. The slicer reports how
## many are still unreviewed, so the pass has a visible finish line instead of being "probably
## fine by now".
@export var reviewed: bool = false

## What this piece DOES, as opposed to what it collides as.
##
## `kind` answers "what shape does the ball hit"; `role` answers "and then what happens". They are
## separate because a saw blade and a pulley are the same circle and nothing alike.
##
## Like `kind`, this is a property of the PIECE, so setting it here makes every copy in every level
## deadly on the next import. Whether a particular copy reaches the simulation at all is the
## `collides` box on the placed node.
enum Role {
	PLAIN, ## A solid. Most pieces.
	HAZARD, ## Kills on contact. Saw blades, spiked gears.
}

@export var role: Role = Role.PLAIN

## For `HAZARD`: how far the teeth reach from the centre, in source pixels. 0 measures it from the
## region.
##
## This is the piece's OUTER extent, and it must be larger than `effective_radius()`, which is the
## largest circle that FITS the art. The ball then meets the teeth before it reaches the solid hub.
## The other way round, the solid fences the ball away from the deadly region and the hazard goes
## silently inert -- the failure `core/spike_strip.gd` opens by warning about.
@export var hazard_radius: float = 0.0


## The outer radius to collide with, measured from the region when `radius` is left at 0.
##
## Uses the SMALLER half-extent, not the larger. A disc drawn with a couple of stray pixels on one
## side has a box slightly wider than the disc, and the larger half-extent would put collision
## outside the art -- which reads as an invisible wall. Too small reads as a soft edge, which is
## the kinder failure.
func effective_radius() -> float:
	if radius > 0.0:
		return radius
	return minf(float(region.size.x), float(region.size.y)) * 0.5


## The deadly radius for a `HAZARD`, measured from the region when `hazard_radius` is left at 0.
##
## Uses the LARGER half-extent, where `effective_radius()` uses the smaller. That is the whole
## ordering this depends on: collision is the disc that fits inside the art, the hazard reaches the
## tips of the teeth that stick out past it.
func effective_hazard_radius() -> float:
	if hazard_radius > 0.0:
		return hazard_radius
	var outer: float = maxf(float(region.size.x), float(region.size.y)) * 0.5
	# The outer extent alone is not enough, and the gap is easy to miss: a gear is very nearly
	# square, so its two half-extents are nearly equal -- 403 x 415 gives 208 against 202 -- and on
	# a piece that IS square they are identical. The ball would then come to rest exactly on the
	# boundary, where `SpikeStrip.touches` uses a strict less-than, and the blade would never bite.
	#
	# A resting ball sits at the collision radius plus its own, and the push-out pass leaves it a
	# fraction short of even that, so the deadly region needs real clearance rather than a tie.
	return maxf(outer, effective_radius() * HAZARD_CLEARANCE)


## How far past its collision a hazard must reach. 5% of a 200px gear is 10px -- far more than the
## sub-pixel slack in a resting contact, and small enough that the deadly region still reads as the
## blade rather than a halo around it.
const HAZARD_CLEARANCE: float = 1.05


## Human-readable name of a kind, for reports.
static func kind_name(value: Kind) -> String:
	match value:
		Kind.POLYGON: return "polygon"
		Kind.CIRCLE: return "circle"
		Kind.RECT: return "rect"
		Kind.ANNULUS: return "annulus"
		Kind.NONE: return "none"
	return "?"
