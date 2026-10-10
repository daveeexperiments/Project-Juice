extends Node

## Autoload for the handful of things that outlive a scene. Small on purpose.
##
## Phase 1 keeps the chosen ball form here so switching survives a level reload, plus the
## debug-overlay toggle that F1 drives.

signal form_changed(form_id: int)
signal debug_toggled(on: bool)

var form_id: int = BallForm.SQUISHY:
	set(value):
		if value == form_id:
			return
		form_id = value
		form_changed.emit(form_id)

var debug_visible: bool = false:
	set(value):
		if value == debug_visible:
			return
		debug_visible = value
		debug_toggled.emit(debug_visible)


## Where a spiked ball comes back to: the last raised flag, or the spawn before any is raised.
## Tracked here rather than on the level so it survives a reload, as the Phaser scene does.
var respawn_point: Vector2 = Vector2.ZERO:
	set(value):
		respawn_point = value
		has_flag = true
## True once any flag has been raised, so the debug overlay can say which it is.
var has_flag: bool = false


## Called by a level as it loads.
func reset_for_level(spawn: Vector2) -> void:
	respawn_point = spawn
	has_flag = false  # set AFTER the setter above has run, so the spawn is not a "flag"


func toggle_debug() -> void:
	debug_visible = not debug_visible


func switch_form() -> void:
	form_id = BallForm.next_id(form_id)
