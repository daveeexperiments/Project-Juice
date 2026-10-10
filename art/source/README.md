# Source art

Exports from the designer, exactly as delivered. **Nothing in here is ever edited by the game
side.** Everything the game uses is generated from these files, so a bad import is always fixable
by re-running the importer rather than by asking for the art again.

Drop files into the folder that matches what they *are*, because that is what decides their
collision:

| Folder | What goes in it | Collision it gets |
|---|---|---|
| `terrain/` | the organic silhouette blobs you stand on | a simplified polygon, closed by the ball radius |
| `props/` | gears, pulleys, saws, pipes, springs, vents, pistons, chains | a primitive — circle, rectangle, or an existing system |
| `character/` | the worm, its forms and the morph between them | none; the player is a circle in code |
| `deco/` | anything purely visual that is never touched | **none, and that is the point** — it never reaches the simulation |

`deco/` is the one people forget. Decorative art that reaches the collision world is most of what
makes a level slow, so if something is scenery, say so by putting it there.

## Two rules for the export

**Transparent background, not white.** The importer finds pieces by their alpha. A white
background means it has to guess from darkness instead, which works for black ink and silently
drops anything light-coloured — the pink and purple worm, the coloured props. Those would simply
vanish.

**One sheet per kind.** A page of many pieces is fine, and preferred — the importer finds each
separate shape on it. Just do not mix terrain and props on the same sheet, because the folder is
how their collision is decided.

## What happens to them

`BitMap.opaque_to_polygons()` finds each separate shape on a sheet and simplifies its outline in
one pass. The bounding box becomes the sprite's atlas region; the polygon becomes the collision
outline. Measured on a real 2000x2000 terrain sheet, a tolerance of ~4 px gives about 40 vertices
per piece, which is a comfortable budget.

See `docs/ROADMAP.md` for the collision model and why collision is authored rather than traced.
