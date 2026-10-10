class_name Cable
extends RefCounted

## A slack rope strung between two anchors, simulated as a verlet chain. Ported from the cable
## actor in src/systems/Actors.ts.
##
## A cable is the squishy ball's route, the way a trampoline is the rocky ball's and glass is the
## squishy ball's: `squishy.cableBounce` 0.31 against `rocky.cableBounce` 0.04 means one ball is
## thrown by a rope and the other lands on it dead.
##
## IT IS THE FIRST ACTOR IN THIS PORT THAT HOLDS STATE THE BALL CAN CHANGE, which makes it the
## first one `StepWorld.ghost()` has to copy rather than share. If the ghost swung the real rope,
## drawing a preview would physically disturb the level the player is standing in -- aiming would
## move the world. `snapshot()` and `restore()` exist for exactly that, and the prediction test
## pins it: the ghost must leave the real rope untouched AND still match the real ball step for
## step, which only works because both run this same code from the same state.
##
## The rope is advanced once per `BallSim.step_ball`, never per substep, so the ball and the ghost
## see the same rope at the same points in time.

## How many relaxation passes per step. Verlet constraints are solved by repetition rather than
## by algebra; three is the usual compromise between a rope that stretches and one that costs.
const RELAX_PASSES: int = 3

var id: int = 0
## The pinned ends, in world space.
var anchor_a: Vector2 = Vector2.ZERO
var anchor_b: Vector2 = Vector2.ZERO
## Where each knot is now, and where it was last step. Verlet keeps velocity as the difference
## between the two rather than storing it, which is what makes the constraints stable.
var points: PackedVector2Array = PackedVector2Array()
var previous: PackedVector2Array = PackedVector2Array()
## Natural distance between neighbouring knots.
var rest_length: float = 0.0
## This cable's own collision thickness. -1 takes the global `cables.thickness`.
var thickness_override: float = -1.0
## Extra slack beyond the straight-line distance, as a fraction. 0 is a taut line.
var slack: float = 0.25


func _init(cable_id: int, from: Vector2, to: Vector2, extra_slack: float = 0.25, thickness: float = -1.0) -> void:
	id = cable_id
	anchor_a = from
	anchor_b = to
	slack = maxf(0.0, extra_slack)
	thickness_override = thickness
	rebuild()


## Lay the rope out between its anchors, hanging slack. Called on load and whenever an anchor
## moves in the editor.
func rebuild() -> void:
	var count: int = maxi(2, TuningData.get_active().cables_segments + 1)
	points = PackedVector2Array()
	previous = PackedVector2Array()
	var span: float = anchor_a.distance_to(anchor_b)
	rest_length = (span * (1.0 + slack)) / float(count - 1)

	# Start it already drooping rather than straight, so the first step settles instead of
	# dropping the whole rope at once.
	var sag: float = minf(span * slack * 0.5, maxf(0.0, TuningData.get_active().cables_max_sag))
	for i: int in count:
		var along: float = float(i) / float(count - 1)
		var flat: Vector2 = anchor_a.lerp(anchor_b, along)
		# A parabola, zero at both ends and deepest in the middle.
		var droop: float = sag * 4.0 * along * (1.0 - along)
		var p: Vector2 = Vector2(flat.x, flat.y + droop)
		points.append(p)
		previous.append(p)


func thickness() -> float:
	if thickness_override >= 0.0:
		return thickness_override
	return maxf(1.0, TuningData.get_active().cables_thickness)


# ---------------------------------------------------------------- the rope itself

## Advance the rope by one step. Pure verlet: integrate, then relax the links, then re-pin the
## ends and cap the droop.
func step(dt: float) -> void:
	var t: TuningData = TuningData.get_active()
	var count: int = points.size()
	if count < 2:
		return

	var keep: float = clampf(1.0 - maxf(0.0, t.cables_damping), 0.0, 1.0)
	var fall: float = t.world_gravity * dt * dt

	for i: int in range(1, count - 1):
		var here: Vector2 = points[i]
		var velocity: Vector2 = (here - previous[i]) * keep
		previous[i] = here
		points[i] = Vector2(here.x + velocity.x, here.y + velocity.y + fall)

	var stiffness: float = clampf(t.cables_stiffness, 0.0, 1.0)
	for _pass: int in RELAX_PASSES:
		_relax(stiffness)

	points[0] = anchor_a
	points[count - 1] = anchor_b
	_cap_sag(maxf(0.0, t.cables_max_sag))


## Pull every link back towards its rest length. Both knots move half the error each, except where
## one of them is a pinned end and the other takes all of it.
func _relax(stiffness: float) -> void:
	var count: int = points.size()
	for i: int in count - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var delta: Vector2 = b - a
		var distance: float = delta.length()
		if distance <= 0.00001:
			continue
		var error: float = (distance - rest_length) / distance * stiffness
		var shift: Vector2 = delta * error
		var a_pinned: bool = i == 0
		var b_pinned: bool = i + 1 == count - 1
		if a_pinned and b_pinned:
			continue
		if a_pinned:
			points[i + 1] = b - shift
		elif b_pinned:
			points[i] = a + shift
		else:
			points[i] = a + shift * 0.5
			points[i + 1] = b - shift * 0.5


## Stop the rope drooping further than `cables.maxSag` below the line between its anchors, so a
## long cable cannot sink to the floor and stop being a route.
func _cap_sag(limit: float) -> void:
	if limit <= 0.0:
		return
	var count: int = points.size()
	for i: int in range(1, count - 1):
		var along: float = float(i) / float(count - 1)
		var flat: Vector2 = anchor_a.lerp(anchor_b, along)
		var drop: float = points[i].y - flat.y
		if drop > limit:
			points[i].y = flat.y + limit


# ---------------------------------------------------------------- the ball against the rope

## The closest point on the rope to a ball, as {index, point, normal, depth, along}, or {} when the
## ball is clear of it.
##
## Measured against every segment before deciding, exactly as `ShapeBody.contact` does over an
## outline: taking the first segment that hits would snag a ball rolling across a knot.
func contact_for(cx: float, cy: float, r: float) -> Dictionary:
	var count: int = points.size()
	if count < 2:
		return {}
	var reach: float = r + thickness()

	var best_dist_sq: float = INF
	var best_point: Vector2 = Vector2.ZERO
	var best_index: int = 0
	var best_along: float = 0.0

	for i: int in count - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var ab: Vector2 = b - a
		var len_sq: float = ab.length_squared()
		var t: float = 0.0 if len_sq == 0.0 else clampf(((cx - a.x) * ab.x + (cy - a.y) * ab.y) / len_sq, 0.0, 1.0)
		var p: Vector2 = a + ab * t
		var dist_sq: float = (cx - p.x) * (cx - p.x) + (cy - p.y) * (cy - p.y)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_point = p
			best_index = i
			best_along = (float(i) + t) / float(count - 1)

	var distance: float = sqrt(best_dist_sq)
	if distance >= reach:
		return {}

	var normal: Vector2 = Vector2(cx - best_point.x, cy - best_point.y)
	if distance < 0.00001:
		# Dead on the rope: push straight up rather than dividing by zero.
		normal = Vector2.UP
	else:
		normal /= distance
	return {
		"index": best_index,
		"point": best_point,
		"normal": normal,
		"depth": reach - distance,
		"along": best_along,
	}


## Is the rope solid to a ball here, or does the ball go through it?
##
## A cable is a ONE-WAY FLOOR, and the rule is pure geometry: a ball whose centre is above the
## rope lands on it, a ball underneath passes up through it. Nothing else is needed -- the normal
## already points from the rope to the ball, so a ball below gets pushed further down and simply
## leaves, which is the behaviour one-way asks for.
##
## `cables.clearAbove` (128) and `clearBelow` (96) are deliberately NOT used here. A contact only
## ever happens within the ball's radius plus the rope's thickness, about 17 px, so bands of 128
## and 96 px would be satisfied every single time and decide nothing. Beside `padding.*` and
## `padding.actorClearance` in the Phaser tuning, they read as level-generation clearance -- how
## much room to leave around a cable so it is landable and passable -- rather than collision. They
## are left unmapped so they show up in docs/unmapped_tuning_keys.txt as "not ported" instead of
## being bent into a role where they do nothing.
func is_solid_from(cy: float, hit: Dictionary) -> bool:
	return cy <= (hit["point"] as Vector2).y


## How far the knots nearest the ball are shoved along the rope's normal when it lands. The rope
## gives before it throws, which is what makes a cable feel like rope and not like a rail.
func absorb(index: int, normal: Vector2, impact_speed: float) -> void:
	var t: TuningData = TuningData.get_active()
	var give: float = maxf(0.0, t.cables_recoil) * clampf(t.cables_softness, 0.0, 1.0)
	if give <= 0.0 or impact_speed <= 0.0:
		return
	var count: int = points.size()
	# Scaled by the impact so a gentle touch barely moves the rope, measured against the game's
	# own speed ceiling rather than a number of its own: `world.maxBallSpeed` is the fastest a ball
	# can arrive, so `cables.recoil` reads as "how far the rope gives under the hardest hit there
	# is". No gameplay number lives outside the tuning, so an invented constant here would be a
	# worse answer than reusing the ceiling.
	var push: float = give * clampf(impact_speed / maxf(1.0, t.world_max_ball_speed), 0.0, 1.0)
	for offset: int in [0, 1]:
		var i: int = index + offset
		if i <= 0 or i >= count - 1:
			continue
		points[i] -= normal * push


## Extra damping applied to the rope right after it has been hit, so it stops ringing instead of
## wobbling for the rest of the level.
func settle_after_impact() -> void:
	var extra: float = clampf(TuningData.get_active().cables_extra_decay, 0.0, 1.0)
	if extra <= 0.0:
		return
	var count: int = points.size()
	for i: int in range(1, count - 1):
		previous[i] = previous[i].lerp(points[i], extra)


## The rope's direction at a point along it, pointing from anchor A towards anchor B.
func tangent_at(index: int) -> Vector2:
	var count: int = points.size()
	var i: int = clampi(index, 0, count - 2)
	var along: Vector2 = points[i + 1] - points[i]
	return along.normalized() if along.length() > 0.00001 else Vector2.RIGHT


# ---------------------------------------------------------------- ghosting

## Everything the prediction could change. Shallow arrays are duplicated, not shared.
func snapshot() -> Dictionary:
	return {"points": points.duplicate(), "previous": previous.duplicate()}


func restore(saved: Dictionary) -> void:
	points = (saved["points"] as PackedVector2Array).duplicate()
	previous = (saved["previous"] as PackedVector2Array).duplicate()


## A copy the prediction can swing about without touching the real rope.
func ghost_copy() -> Cable:
	var copy: Cable = Cable.new(id, anchor_a, anchor_b, slack, thickness_override)
	copy.rest_length = rest_length
	copy.points = points.duplicate()
	copy.previous = previous.duplicate()
	return copy
