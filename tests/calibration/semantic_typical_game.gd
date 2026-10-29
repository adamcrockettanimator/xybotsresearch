## A separate, playable normal-maze workload; the original comparison scene is untouched.
extends "res://scripts/coordinate_frame_navigation.gd"


func _ready() -> void:
	# Direct scene launch skips the lobby. Give the keyboard to player one and
	# the first connected controller to player two; leave the remaining slots
	# to the normal bot roster. An existing lobby roster always takes precedence.
	if not get_tree().has_meta("grudge_match_human_slots"):
		var devices := Input.get_connected_joypads()
		get_tree().set_meta("grudge_match_human_slots", [true, true, false, false])
		get_tree().set_meta("grudge_match_device_ids", [-1, devices[0] if not devices.is_empty() else -1, -1, -1])
	var game := ORIGINAL_GAME.instantiate()
	game.name = "CoordinateFrameGame"
	game.BARREL_LOD_REVIEW_LEVEL = false
	game.semantic_typical_props_enabled = true
	game.pause_round_timer_for_debug = true
	game.music_enabled = false
	add_child(game)
	call_deferred("_attach_coordinate_renderers", game)
