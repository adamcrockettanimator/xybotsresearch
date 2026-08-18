# Entry scene for the coordinate-frame experiment.  It instantiates the
# untouched original game scene, then adds the reversible runtime wall layer.
extends Node2D

const ORIGINAL_GAME := preload("res://main.tscn")
const RUNTIME_RENDERER := preload("res://scripts/coordinate_frame_runtime_renderer.gd")

func _ready() -> void:
	var game := ORIGINAL_GAME.instantiate()
	game.name = "CoordinateFrameGame"
	add_child(game)
	# The controller creates its two local view contexts during _ready().  Wait one
	# frame before attaching the coordinate compositors so each receives a stable,
	# explicit player index instead of fighting over the controller's legacy globals.
	call_deferred("_attach_coordinate_renderers", game)


func _attach_coordinate_renderers(game: Node) -> void:
	if not game.has_method("register_coordinate_renderer"):
		push_error("Coordinate-frame navigation requires the Xybots controller renderer hook.")
		return
	for player_index in range(game.player_views.size()):
		var renderer := RUNTIME_RENDERER.new()
		renderer.name = "CoordinateFrameRuntimeRendererP%d" % (player_index + 1)
		renderer.target_player_index = player_index
		game.add_child(renderer)
		game.register_coordinate_renderer(player_index, renderer)
