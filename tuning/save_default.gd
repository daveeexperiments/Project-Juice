extends SceneTree

## One-shot helper: rewrite tuning/default.tres from the values authored in TuningData, and report
## anywhere the frozen Phaser export disagrees with them.
##
##   godot --headless --path . --script tuning/save_default.gd
##
## It used to write default.tres *from* phaser_tuning.json, which is the wrong direction now. The
## authored defaults in `tuning/tuning_data.gd` are the only source of truth; the JSON is the
## retired Phaser project's export, kept as history. Writing the JSON into the committed resource
## is how the two would silently drift apart again -- see the comment on
## `TuningData.PHASER_JSON_PATH`.
##
## So this script now does the opposite: the resource is written from the authored values, and any
## disagreement with the frozen export is PRINTED rather than adopted. A difference is not an
## error -- it is a number that has been deliberately changed since the port -- but it should be a
## number someone changed on purpose, and this is how you see the list.


func _initialize() -> void:
	var authored: TuningData = TuningData.new()

	var error: int = ResourceSaver.save(authored, "res://tuning/default.tres")
	if error != OK:
		printerr("could not write tuning/default.tres (error %d)" % error)
		quit(1)
		return
	print("wrote tuning/default.tres from the authored defaults")

	_report_drift_from_phaser(authored)
	quit(0)


## Print every field where the frozen Phaser export disagrees with what is authored here.
func _report_drift_from_phaser(authored: TuningData) -> void:
	var original: TuningData = TuningData.new()
	var unmapped: PackedStringArray = original.load_phaser_json(TuningData.PHASER_JSON_PATH)

	var drifted: int = 0
	for path: String in TuningData.FIELD_BY_PATH.keys():
		var field: String = TuningData.FIELD_BY_PATH[path] as String
		var now: Variant = authored.get(field)
		var then: Variant = original.get(field)
		if now == then:
			continue
		drifted += 1
		print("  %s (%s): authored %s, Phaser had %s" % [field, path, now, then])

	if drifted == 0:
		print("no field differs from the frozen Phaser export")
	else:
		print("%d field(s) deliberately changed since the port" % drifted)
	print("%d Phaser values have no field here (see docs/PORTING.md)" % unmapped.size())
