@tool
class_name SheetManifest
extends Resource

## Every piece found on one sprite sheet, and the collision each one gets.
##
## One of these per sheet, checked in under `art/manifest/`. It is the bridge between the art,
## which carries no names or metadata of any kind, and the game, which needs to know that piece 34
## is a gear and collides as a disc. The art cannot tell us that -- it is final and nothing goes
## back to the designer -- so this file is where that knowledge lives.
##
## It is a text resource on purpose: a collision change shows up in a diff as one line, which is
## what makes "the art and the collision have drifted apart" a thing you can notice. See
## `docs/ROADMAP.md`, Risk 1.

## The sheet this describes, as a `res://` path.
@export var sheet: String = ""

## The simplification tolerance used, in source pixels. Recorded so a manifest regenerated at a
## different tolerance is visible as a change rather than a mystery.
@export var epsilon: float = 8.0

## Which collision family this sheet's pieces belong to, taken from the folder the sheet sits in.
## `terrain/` pieces get traced outlines; `props/` pieces get primitives.
@export var family: String = ""

@export var pieces: Array[PieceEntry] = []


## The piece with this id, or null. Used by the slicer to carry decisions across a re-run.
func by_id(piece_id: String) -> PieceEntry:
	for piece: PieceEntry in pieces:
		if piece.id == piece_id:
			return piece
	return null


## How many pieces nobody has confirmed the collision of yet.
func unreviewed_count() -> int:
	var count: int = 0
	for piece: PieceEntry in pieces:
		if not piece.reviewed:
			count += 1
	return count


## Pieces grouped by kind, for the report: `{"circle": 26, "polygon": 51, ...}`.
func counts_by_kind() -> Dictionary:
	var counts: Dictionary = {}
	for piece: PieceEntry in pieces:
		var name: String = PieceEntry.kind_name(piece.kind)
		counts[name] = (counts.get(name, 0) as int) + 1
	return counts
