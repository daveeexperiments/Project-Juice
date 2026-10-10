extends SceneTree

## Build a placeable scene for every piece in the manifests.
##
##   godot --headless --path . --script tools/import_pieces.gd
##
## Run the slicer first; this reads what it produced. Safe to re-run: it regenerates everything
## under `art/scenes/`, and because levels INSTANCE these scenes, a re-import updates every
## placement already made. Change a piece's `kind` in the manifest, re-run, and the gear you put
## down an hour ago is a disc everywhere it appears.
##
## What each piece becomes:
##
##   <id>              TerrainBlock -- the collision, scaled to world size, placeholder ink off
##     Art             Sprite2D     -- the AtlasTexture from the slicer
##
## It stays a `TerrainBlock` rather than a bare sprite with a shape hung off it because that is
## what the rest of the game already understands: the level collects the `terrain` group on load,
## and collision, the route check, the editor gizmo and the debug overlay all come along for free.
##
## Decoration (`kind = NONE`) gets a Sprite2D and nothing else -- no block, no group, so it never
## reaches the simulation at all. That is the point of the category rather than a shortcut.

const MANIFEST_DIR: String = "res://art/manifest"
const SCENE_DIR: String = "res://art/scenes"
const BLOCK_SCRIPT: String = "res://blocks/terrain_block.gd"


func _initialize() -> void:
	var scale: float = PieceImporter.art_scale()
	print("art scale %.4f  (1 source px -> %.4f world px, ball radius %.0f source px)" % [
		scale, scale, PieceImporter.ball_radius_source(),
	])

	var manifests: Array[String] = _manifests()
	if manifests.is_empty():
		printerr("no manifests in %s -- run tools/slice_sheets.gd first" % MANIFEST_DIR)
		quit(1)
		return

	var totals: Dictionary = {}
	var deferred: Array[String] = []
	var budget_warnings: Array[String] = []
	var written: int = 0

	for manifest_path: String in manifests:
		var manifest: SheetManifest = ResourceLoader.load(manifest_path, "", ResourceLoader.CACHE_MODE_IGNORE) as SheetManifest
		if manifest == null:
			continue

		var family: String = manifest.family
		var out_dir: String = "%s/%s" % [SCENE_DIR, family]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

		for piece: PieceEntry in manifest.pieces:
			var outline: PackedVector2Array = PieceImporter.collision_for(piece)

			if piece.kind == PieceEntry.Kind.ANNULUS:
				deferred.append(piece.id)
			elif outline.size() >= 3 and outline.size() > 80:
				# Only POLYGON pieces can reach this; a circle is capped at 64 by construction.
				budget_warnings.append("%s (%d verts)" % [piece.id, outline.size()])

			if _write_scene(piece, outline, scale, "%s/%s.tscn" % [out_dir, piece.id]):
				written += 1
				var key: String = PieceEntry.kind_name(piece.kind)
				totals[key] = (totals.get(key, 0) as int) + 1

	print("")
	print("%d piece scenes written to art/scenes/" % written)
	for kind: String in totals:
		print("    %-8s %d" % [kind, totals[kind]])

	if not budget_warnings.is_empty():
		print("")
		print("outlines over 80 vertices (ShapeBody.contact is O(edges)):")
		for note: String in budget_warnings:
			print("    %s" % note)

	if not deferred.is_empty():
		print("")
		print("%d annulus piece(s) have NO collision yet: %s" % [deferred.size(), ", ".join(deferred)])
		print("    %s" % PieceImporter.annulus_note())

	quit(0)


## Write one piece scene. Returns false if it could not be saved.
func _write_scene(piece: PieceEntry, outline: PackedVector2Array, scale: float, path: String) -> bool:
	var art: Texture2D = ResourceLoader.load(_atlas_path(piece)) as Texture2D
	if art == null:
		printerr("no atlas texture for %s -- run tools/slice_sheets.gd first" % piece.id)
		return false

	var root: Node2D = null

	if outline.size() >= 3:
		var block: Polygon2D = Polygon2D.new()
		block.set_script(load(BLOCK_SCRIPT))
		block.polygon = outline
		block.set("show_placeholder", false)
		root = block
	else:
		# No collision: a plain sprite, which never joins the `terrain` group.
		root = Node2D.new()

	root.name = piece.id
	# Scale lives here, on the one node per piece, so the polygon above and the art below both
	# stay in source pixels and keep matching the sheet they came from.
	root.scale = Vector2(scale, scale)

	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = "Art"
	# Top-left anchored, so the sprite lines up with an outline measured from the region corner.
	sprite.centered = false
	sprite.texture = art
	root.add_child(sprite)
	sprite.owner = root

	var packed: PackedScene = PackedScene.new()
	var packed_ok: bool = packed.pack(root) == OK
	# Built outside the tree, so nothing else will ever free these. Without this the run ends with
	# several hundred leaked nodes reported, which buries the output that matters.
	root.free()
	if not packed_ok:
		printerr("could not pack %s" % piece.id)
		return false
	return ResourceSaver.save(packed, path) == OK


func _atlas_path(piece: PieceEntry) -> String:
	var family: String = "terrain" if piece.id.begins_with("blob") else "props"
	return "res://art/atlas/%s/%s.tres" % [family, piece.id]


func _manifests() -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(MANIFEST_DIR)
	if dir == null:
		return found
	for name: String in dir.get_files():
		if name.get_extension().to_lower() == "tres":
			found.append("%s/%s" % [MANIFEST_DIR, name])
	found.sort()
	return found
