extends Node2D

## Paper background, so the ink-on-paper look of the Phaser prototype carries over. Purely
## decorative: it is not in the `terrain` group, so the simulation never sees it.

const PAPER: Color = Color("f6f3ec")
const AREA: Rect2 = Rect2(-200.0, -200.0, 1600.0, 1800.0)


func _ready() -> void:
	z_index = -10


func _draw() -> void:
	draw_rect(AREA, PAPER)
