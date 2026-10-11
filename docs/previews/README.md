# Piece previews

One image per sliced piece, named by the id you use everywhere else — so
`prop_sheet_1_46.png` is the piece you place from
`res://art/scenes/props/prop_sheet_1_46.tscn` and review in
`art/manifest/prop_sheet_1.tres`. One name, three places.

`index_<sheet>.jpg` is the whole sheet laid out at once, each piece labelled with its id, the
collision `kind` it currently has, and its size in source pixels. That is the one to scan when you
are deciding what to place; the individual files are for looking at something closely.

Godot's FileSystem dock shows thumbnails of `art/scenes/` too, and those are live. These exist
because the art is near-black on a dark editor theme at a thumbnail size where the names truncate,
which makes picking a piece harder than it should be. Here the background is mid grey and the
names are written out.

**Reference only.** Nothing in the game reads this folder. Deleting it breaks nothing.

That is also why there is a `.gdignore` here. Without it Godot treats these as game art and imports
all 162, which produces 162 `.import` sidecars, 162 entries in the resource cache, and a diff of
several thousand lines every time someone opens the project — for images no scene will ever
reference. `.gdignore` makes Godot skip the directory entirely; they stay perfectly good PNGs to
anything else that opens them.

## Regenerating

```bash
python3 tools/make_previews.py      # needs Pillow: pip install pillow
```

It reads the regions out of `art/manifest/` and crops them from the sheets in `art/source/`, so it
always matches what the slicer last found. Worth re-running after changing a piece's `kind`, since
the labels carry it.

Python rather than GDScript for one reason: drawing a text label headless needs a font, and Godot
has no default one without a scene. Nothing else in the project depends on it.
