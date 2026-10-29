## Runs the normal coordinate-frame game with the temporary cropped-sprite gallery.
extends "res://scripts/coordinate_frame_navigation.gd"


func _ready() -> void:
	var game := ORIGINAL_GAME.instantiate()
	game.name = "CoordinateFrameGame"
	game.BARREL_LOD_REVIEW_LEVEL = true
	game.barrel_authoring_single_player_mode = true
	game.semantic_typical_props_enabled = false
	game.pause_round_timer_for_debug = true
	game.music_enabled = false
	add_child(game)
	call_deferred("_attach_coordinate_renderers", game)
	call_deferred("_enable_gallery_after_game_start")


func _enable_gallery_after_game_start() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var game := get_node_or_null("CoordinateFrameGame")
	if game != null and game.has_method("enable_calibration_primitive_gallery"):
		game.call("enable_calibration_primitive_gallery")
