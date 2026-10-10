class_name ShatterEffect
extends Node2D

## Placeholder shatter: a handful of shards that fly out and fade. The full juice layer is a
## later phase; this exists so a break reads as a break rather than a pane blinking out.
##
## Purely visual, and deliberately not in the `terrain` group: nothing here can touch the
## simulation, which is the rule the Phaser project holds to as well.

const INK: Color = Color("141414")
const LIFETIME: float = 0.55
const SHARDS_PER_BURST: int = 8

var _shards: Array[Dictionary] = []


func _ready() -> void:
	z_index = 20


## Scatter shards from a broken pane.
func burst(at: Vector2, size: Vector2) -> void:
	var spread: float = maxf(8.0, minf(size.x, size.y))
	for _i: int in SHARDS_PER_BURST:
		var angle: float = randf() * TAU
		var speed: float = randf_range(90.0, 260.0)
		_shards.append({
			"position": at + Vector2(randf_range(-size.x, size.x), randf_range(-size.y, size.y)) * 0.25,
			"velocity": Vector2(cos(angle), sin(angle)) * speed,
			"spin": randf_range(-8.0, 8.0),
			"angle": angle,
			"size": randf_range(2.5, 5.0) + spread * 0.02,
			"life": LIFETIME,
		})


func _process(delta: float) -> void:
	if _shards.is_empty():
		return
	var gravity: float = TuningData.get_active().world_gravity * 0.6
	var alive: Array[Dictionary] = []
	for shard: Dictionary in _shards:
		var life: float = (shard["life"] as float) - delta
		if life <= 0.0:
			continue
		var velocity: Vector2 = shard["velocity"] as Vector2
		velocity.y += gravity * delta
		shard["velocity"] = velocity
		shard["position"] = (shard["position"] as Vector2) + velocity * delta
		shard["angle"] = (shard["angle"] as float) + (shard["spin"] as float) * delta
		shard["life"] = life
		alive.append(shard)
	_shards = alive
	queue_redraw()


func _draw() -> void:
	for shard: Dictionary in _shards:
		var fade: float = clampf((shard["life"] as float) / LIFETIME, 0.0, 1.0)
		var size: float = shard["size"] as float
		var at: Vector2 = shard["position"] as Vector2
		var angle: float = shard["angle"] as float
		# A small triangle, turned as it tumbles.
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in 3:
			var a: float = angle + float(i) * TAU / 3.0
			points.append(at + Vector2(cos(a), sin(a)) * size)
		draw_colored_polygon(points, Color(INK, fade))
