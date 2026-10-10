extends SceneTree

## One-shot helper: write tuning/default.tres from the exported Phaser values.
##
##   godot --headless --path . --script tuning/save_default.gd
##
## Run it again whenever the Phaser project's defaults change and phaser_tuning.json is
## re-exported, so the committed resource and the reference project stay in step.


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
