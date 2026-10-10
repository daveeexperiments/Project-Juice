# Source art

Exports from the designer, exactly as delivered. **Nothing in here is ever edited by the game
side** — not retouched, not re-exported, not asked for again. The art is final and every adaptation
happens in Godot, so a bad import is always fixed by re-running the importer.

Drop files into the folder that matches what they *are*, because that is what decides their
collision:

| Folder | What goes in it | Collision it gets |
|---|---|---|
| `terrain/` | the organic silhouette blobs you stand on | a simplified polygon, closed by the ball radius |
| `props/` | gears, pulleys, saws, pipes, springs, vents, pistons, chains | a primitive — circle, rectangle, annulus, or an existing system |
| `character/` | the worm, its forms and the morph between them | none; the player is a circle in code |
| `deco/` | art that is never touched in *any* placement | **none, and that is the point** — it never reaches the simulation |

The folder decides terrain-versus-prop, which is a property of the piece. It does **not** decide
whether a particular instance is scenery: the same gear can be machinery in one beat and background
in another, so that is set per placement. `deco/` is for art that is decoration everywhere.

## Two properties the delivered sheets have, and why they matter

Both are already satisfied by what was delivered. They are recorded here because the importer
depends on them, not as requests.

**Transparent backgrounds.** The importer finds pieces by their alpha. On an opaque white page it
would have to guess from darkness instead, which works for black ink and silently drops anything
light-coloured — the pink and purple worm, the props with pale fills. Those would simply vanish.
All six sheets have alpha, so that path is never taken.

**One kind per sheet.** A page of many pieces is what the importer wants — it finds each separate
shape. Terrain and props are on separate sheets, which is what lets the folder decide their
collision.

## What happens to them

`BitMap.opaque_to_polygons()` finds each separate shape on a sheet and simplifies its outline in
one pass. The bounding box becomes the sprite's atlas region; the polygon becomes the starting
outline. On these 4096 px sheets a tolerance of ~8 px gives 40–58 vertices per terrain piece, which
is a comfortable budget. (An earlier figure of 4 was measured on a 2000 px sheet — the tolerance is
in source pixels, so it tracks the resolution.)

Because the sheets carry no layer names or metadata, **which collision a piece gets is recorded in a
manifest we own**, not read out of the art: one checked-in resource per sheet, listing each piece's
atlas region and its collision kind. The importer guesses the kind by measuring the shape, a human
corrects the few it gets wrong, and re-running the importer never overwrites those corrections.

See `docs/ROADMAP.md` for the manifest, the collision model, and why collision is authored rather
than traced.
