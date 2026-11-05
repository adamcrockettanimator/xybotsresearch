extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game.player_joined = [true, true, false, false]
	game.player_states[0] = game._make_player_state(0, Vector2i(0, 0), 0)
	game.player_states[1] = game._make_player_state(1, Vector2i(4, 4), 0)
	game.player_states[1]["world_position"] = Vector2(4.5, 4.5)
	assert(not game._respawn_cell_is_safe(0, Vector2i(4, 3)))
	assert(not game._respawn_cell_is_safe(0, Vector2i(4, 0)))
	var destination: Dictionary = game._combat_respawn_destination(0)
	assert(not destination.is_empty())
	assert(game._respawn_cell_is_safe(0, destination["cell"]))
	game.player_states[0]["world_position"] = Vector2(4.5, 0.4)
	game.bot_brains.clear()
	var brain: Dictionary = game._update_bot_brain(1, game.player_states[1], Vector2(4.5, 4.5), 0, Vector2(0, -4.1), 4.1, Vector2.UP, 0.016)
	assert(not brain["has_line_of_sight"])
	game.player_states[0]["world_position"] = Vector2(4.5, 1.5)
	brain = game._update_bot_brain(1, game.player_states[1], Vector2(4.5, 4.5), 0, Vector2(0, -3.0), 3.0, Vector2.UP, 0.016)
	assert(brain["has_line_of_sight"])
	print("Respawn safety and bot sight range passed")
	game.queue_free()
	quit()
