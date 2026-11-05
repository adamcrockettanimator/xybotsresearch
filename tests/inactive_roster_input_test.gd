extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.single_player_combat_view = true
	game.clear_the_map_mode = true
	game.clear_map_round = 4
	game._apply_session_roster()
	assert(game._is_bot_controlled_slot(4))
	game.bot_inputs[4] = {"fire": true}
	assert(game._is_player_fire_pressed_for(4))
	game.clear_map_round = 1
	game._apply_session_roster()
	assert(not game.player_joined[4])
	assert(not game._is_player_fire_pressed_for(4))
	assert(not game._is_player_fire_pressed_for(-1))
	game._process_combat(0.016)
	print("Inactive expanded roster input passed")
	game.queue_free()
	quit()
