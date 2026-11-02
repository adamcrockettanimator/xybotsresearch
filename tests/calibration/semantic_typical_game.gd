## A separate, playable normal-maze workload; the original comparison scene is untouched.
extends "res://scripts/coordinate_frame_navigation.gd"


func _ready() -> void:
	# Direct scene launch deliberately bypasses the lobby.  This is a one-player
	# fullscreen sandbox: keyboard and the first controller both drive player one,
	# while the ordinary maze and its breakable props stay enabled.
	var game := ORIGINAL_GAME.instantiate()
	game.name = "CoordinateFrameGame"
	game.BARREL_LOD_REVIEW_LEVEL = false
	game.barrel_authoring_single_player_mode = true
	game.single_player_sandbox_mode = true
	game.semantic_typical_props_enabled = true
	game.pause_round_timer_for_debug = true
	game.music_enabled = false
	add_child(game)
	call_deferred("_attach_coordinate_renderers", game)
