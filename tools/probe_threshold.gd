extends SceneTree

## How many regions each sheet splits into, across a range of alpha thresholds.
##
##   godot --headless --path . --script tools/probe_threshold.gd
##
## This is where `SheetSlicer.ALPHA_THRESHOLD` comes from, and it is kept because the reasoning is
## not guessable from the constant. Too high and the faint, semi-transparent parts of a piece stop
## counting, so one prop comes apart into several regions and every id after it shifts. Too low and
## halos merge neighbouring pieces into one.
##
## What to look for is a PLATEAU -- a span of thresholds where the count does not move. A sheet
## whose count climbs steadily has pieces coming apart; pick a threshold below where that starts.
## Re-run this if the slicer ever starts finding a different number of pieces than you expect.

const SHEETS: Array[String] = [
	"res://art/source/props/Prop Sheet 1.png",
	"res://art/source/props/Prop Sheet 2.png",
	"res://art/source/terrain/Blob Sheet 1.png",
]

const THRESHOLDS: Array[float] = [0.05, 0.1, 0.2, 0.35, 0.5, 0.75]


func _initialize() -> void:
	for path: String in SHEETS:
		var image: Image = Image.load_from_file(path)
		if image == null:
			continue
		var whole: Rect2i = Rect2i(Vector2i.ZERO, image.get_size())
		var line: Array[String] = []
		for threshold: float in THRESHOLDS:
			var bitmap: BitMap = BitMap.new()
			bitmap.create_from_image_alpha(image, threshold)
			var regions: Array = bitmap.opaque_to_polygons(whole, 8.0)
			# Also count how many survive the size filter, since that is what matters.
			var kept: int = 0
			for traced: Variant in regions:
				var poly: PackedVector2Array = traced as PackedVector2Array
				if poly.size() < 3:
					continue
				var low: Vector2 = poly[0]
				var high: Vector2 = poly[0]
				for point: Vector2 in poly:
					low = low.min(point)
					high = high.max(point)
				var size: Vector2 = high - low
				if size.x >= 8.0 and size.y >= 8.0:
					kept += 1
			line.append("%.2f: %d raw / %d kept" % [threshold, regions.size(), kept])
		print("%s\n    %s" % [path.get_file(), "   ".join(line)])
	quit(0)
