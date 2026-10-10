class_name Pipe
extends RefCounted

## A length of pipe the ball travels INSIDE, from one mouth to the other.
##
## ## Why this is cheap, and why that is not an accident
##
## Ask the question every actor has to answer: does it hold state the ball can change? **No.** A
## pipe is inert. It is the *ball* that changes, by being in transit. Everything follows from that:
##
## - The path never moves, so `StepWorld.ghost()` SHARES a pipe the way it shares a fan, rather
##   than copying it. Nothing to snapshot, nothing to restore.
## - Transit lives in two fields on `BallState` -- which pipe, and how far along. The trajectory
##   preview already copies `BallState` wholesale, so the ghost enters, travels and leaves exactly
##   as the ball will, with no new ghosting code at all.
##
## The alternative -- a pipe that owns the ball while it is inside -- would have needed its own
## copy in `ghost()`, its own snapshot and restore, and a test proving the preview does not disturb
## it. Keeping the mutable half on the ball avoids all of it.
##
## ## The path is authored, not traced
##
## The centreline is drawn in the editor, not derived from the art. A run is several pieces -- an
## elbow, a straight, another elbow -- and recovering a centreline from the union of their
## silhouettes is fragile work for no gain. Same principle as collision being authored.

var id: int = 0

## The centreline in WORLD space, at least two points. The ball travels along this.
var path: PackedVector2Array = PackedVector2Array()

## How close to a mouth the ball must be to be drawn in.
var mouth_radius: float = 40.0

## Cumulative distance to each point, so a position along the path is one lookup rather than a
## walk. Built once by `make`, because the path never changes.
var _marks: PackedFloat32Array = PackedFloat32Array()
var _length: float = 0.0


static func make(pipe_id: int, points: PackedVector2Array, radius: float) -> Pipe:
	var p: Pipe = Pipe.new()
	p.id = pipe_id
	p.path = points.duplicate()
	p.mouth_radius = maxf(1.0, radius)
	p._measure()
	return p


func _measure() -> void:
	_marks = PackedFloat32Array()
	_marks.resize(path.size())
	if path.size() < 2:
		_length = 0.0
		return
	var total: float = 0.0
	_marks[0] = 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
		_marks[i] = total
	_length = total


func length() -> float:
	return _length


func is_usable() -> bool:
	return path.size() >= 2 and _length > 0.0


## Where a given distance along the path sits, in world space.
func point_at(distance: float) -> Vector2:
	if path.size() < 2:
		return path[0] if path.size() == 1 else Vector2.ZERO
	var d: float = clampf(distance, 0.0, _length)
	for i: int in range(1, path.size()):
		if d <= _marks[i]:
			var span: float = _marks[i] - _marks[i - 1]
			var t: float = 0.0 if span <= 0.0 else (d - _marks[i - 1]) / span
			return path[i - 1].lerp(path[i], t)
	return path[path.size() - 1]


## Which way the pipe runs at a given distance, as a unit vector towards the far end.
func direction_at(distance: float) -> Vector2:
	if path.size() < 2:
		return Vector2.RIGHT
	var d: float = clampf(distance, 0.0, _length)
	for i: int in range(1, path.size()):
		if d <= _marks[i]:
			var step: Vector2 = path[i] - path[i - 1]
			return step.normalized() if step.length_squared() > 0.0 else Vector2.RIGHT
	var last: Vector2 = path[path.size() - 1] - path[path.size() - 2]
	return last.normalized() if last.length_squared() > 0.0 else Vector2.RIGHT


## Would a ball here, moving like this, be drawn into the pipe? Returns the distance along the path
## it would enter at, or -1.
##
## Both mouths accept, and the direction test is what keeps a pipe from swallowing a ball that is
## leaving it: the ball has to be moving INTO the opening, not merely touching it. Without that, a
## ball ejected from one end would be caught again on the very next step and never get out.
func entry_for(cx: float, cy: float, vx: float, vy: float) -> float:
	if not is_usable():
		return -1.0
	var here: Vector2 = Vector2(cx, cy)
	var velocity: Vector2 = Vector2(vx, vy)

	if here.distance_to(path[0]) <= mouth_radius and velocity.dot(direction_at(0.0)) > 0.0:
		return 0.0
	var far: Vector2 = path[path.size() - 1]
	if here.distance_to(far) <= mouth_radius and velocity.dot(direction_at(_length)) < 0.0:
		return _length
	return -1.0
