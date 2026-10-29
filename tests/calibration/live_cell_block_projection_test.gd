## Runs the live game renderer with one Blender-rendered canonical cell block.
extends "res://scripts/coordinate_frame_navigation.gd"


func _ready() -> void:
	super._ready()
	call_deferred("_enable_cell_block_after_game_start")


func _enable_cell_block_after_game_start() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var game := get_node_or_null("CoordinateFrameGame")
	if game != null and game.has_method("enable_live_cell_block_calibration"):
		game.call("enable_live_cell_block_calibration")
