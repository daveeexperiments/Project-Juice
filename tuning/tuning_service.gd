extends Node

## Autoload that owns the live tuning values.
##
## Ported from src/config/tuning.ts, where a single mutable `tuning` object is read live by every
## system. Same idea here: one Resource instance, read every frame, never copied.
##
## Select this node in the REMOTE inspector while the game is running and the `data` resource's
## properties are editable live -- that is the Godot equivalent of the Phaser tuning panel, which
## is not ported until a later phase.
##
## The simulation reads `TuningData.get_active()` rather than this autoload, so it can also run
## with no SceneTree (the headless tests). All this node does is decide which resource is active.

const DEFAULT_RESOURCE_PATH: String = "res://tuning/default.tres"

## The live values. Everything the player feels comes from here.
@export var data: TuningData = null
## Set false to keep default.tres exactly as authored, ignoring the exported Phaser values.
@export var load_phaser_json: bool = true


func _ready() -> void:
	if data == null:
		var saved: Resource = load(DEFAULT_RESOURCE_PATH) if ResourceLoader.exists(DEFAULT_RESOURCE_PATH) else null
		data = saved as TuningData if saved is TuningData else TuningData.new()

	if load_phaser_json:
		var unmapped: PackedStringArray = data.load_phaser_json(TuningData.PHASER_JSON_PATH)
		if unmapped.size() > 0:
			# Not an error: these are the systems later phases will bring over. Printed once so
			# the gap between the two projects is visible rather than assumed.
			print("Tuning: %d Phaser values have no field in this phase (see docs/PORTING.md)." % unmapped.size())

	TuningData.active = data


## Swap in a different set of values wholesale, for presets in a later phase.
func use(values: TuningData) -> void:
	data = values
	TuningData.active = data
