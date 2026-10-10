extends SceneTree

## One-shot helper: write tuning/default.tres from the values in phaser_tuning.json.
##
##   godot --headless --path . --script tuning/save_default.gd
##
## phaser_tuning.json is a FROZEN set of starting values -- the Phaser project it came from is
## finished and nothing will be exported from it again. Run this after adding a field to
## TuningData, so the committed resource carries it too.


func _initialize() -> void:
	var data: TuningData = TuningData.new()
	var unmapped: PackedStringArray = data.load_phaser_json(TuningData.PHASER_JSON_PATH)
	var error: int = ResourceSaver.save(data, "res://tuning/default.tres")
	if error != OK:
		printerr("could not write tuning/default.tres (error %d)" % error)
		quit(1)
		return
	print("wrote tuning/default.tres from phaser_tuning.json (%d values unmapped)" % unmapped.size())
	quit(0)
