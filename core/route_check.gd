class_name RouteCheck
extends RefCounted

## Rock must never close the route. Ported from `Level.checkRouteOpen` in
## src/systems/LevelLoader.ts.
##
## Every pane the rocky ball could get through is treated as open, then the level is flooded
## from the spawn. If a flag cannot be reached even then, rock is at fault and the level is
## broken — because the rocky ball can always get through glass one way or another, but never
## through rock.
##
## Static and tree-free on purpose, so the headless tests can seal a level and prove the check
## actually catches it.

## Grid resolution of the flood, in pixels.
const STEP: float = 16.0


## Which of `targets` the ball cannot reach. Each target is {at: Vector2, reach: float}.
## Returns the indices that were not reached; empty means the level is fine.
static func unreachable(
	shapes: Array[ShapeBody],
	start: Vector2,
	targets: Array[Dictionary],
	bounds: Rect2,
) -> PackedInt32Array:
	var missed: PackedInt32Array = PackedInt32Array()
	if targets.is_empty():
		return missed

	var cols: int = int(ceil(bounds.size.x / STEP))
	var rows: int = int(ceil(bounds.size.y / STEP))
	if cols <= 0 or rows <= 0:
		for i: int in targets.size():
			missed.append(i)
		return missed

	var blocked: Callable = func(p: Vector2) -> bool:
		for shape: ShapeBody in shapes:
			if shape.contact(p.x, p.y, 10.0) != null and GlassRules.blocks_route(shape):
				return true
		return false

	var centre_of: Callable = func(col: int, row: int) -> Vector2:
		return Vector2(
			bounds.position.x + float(col) * STEP + STEP * 0.5,
			bounds.position.y + float(row) * STEP + STEP * 0.5,
		)

	var seed_index: int = _seed_cell(start, bounds, cols, rows, blocked, centre_of)
	if seed_index < 0:
		# The spawn itself is buried: nothing is reachable, which is its own kind of broken.
		for i: int in targets.size():
			missed.append(i)
		return missed

	var seen: PackedByteArray = PackedByteArray()
	seen.resize(cols * rows)
	var queue: Array[int] = [seed_index]
	seen[seed_index] = 1
	var reached: Dictionary = {}

	while not queue.is_empty():
		var index: int = queue.pop_back()
		var col: int = index % cols
		var row: int = index / cols
		var here: Vector2 = centre_of.call(col, row)
		for i: int in targets.size():
			if reached.has(i):
				continue
			if here.distance_to(targets[i]["at"] as Vector2) <= maxf(STEP, targets[i]["reach"] as float):
				reached[i] = true
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: int = col + offset.x
			var nr: int = row + offset.y
			if nc < 0 or nr < 0 or nc >= cols or nr >= rows:
				continue
			var next: int = nr * cols + nc
			if seen[next] == 1:
				continue
			if blocked.call(centre_of.call(nc, nr)):
				continue
			seen[next] = 1
			queue.append(next)

	for i: int in targets.size():
		if not reached.has(i):
			missed.append(i)
	return missed


## An open cell at or near the spawn.
##
## The spawn marks the ball's FEET, so that cell can read as solid where it grazes the floor.
## The search stays NEARBY on purpose: an unbounded walk happily tunnels through a wall and
## seeds the flood on the far side of it, which passes any blocked level.
static func _seed_cell(
	start: Vector2,
	bounds: Rect2,
	cols: int,
	rows: int,
	blocked: Callable,
	centre_of: Callable,
) -> int:
	var start_col: int = clampi(int((start.x - bounds.position.x) / STEP), 0, cols - 1)
	var start_row: int = clampi(int((start.y - bounds.position.y) / STEP), 0, rows - 1)
	for radius: int in 4:
		for dr: int in range(-radius, radius + 1):
			for dc: int in range(-radius, radius + 1):
				var c: int = start_col + dc
				var r: int = start_row + dr
				if c < 0 or r < 0 or c >= cols or r >= rows:
					continue
				if not blocked.call(centre_of.call(c, r)):
					return r * cols + c
	return -1
