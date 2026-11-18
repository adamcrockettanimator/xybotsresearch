extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game.clear_map_round = 2
	game._apply_session_roster()
	game.clear_map_waiting_to_start = false
	game.match_started = true
	game.player_states[0] = game._make_player_state(0, Vector2i(2, 2), 0)
	game.player_states[1] = game._make_player_state(1, Vector2i(2, 0), 0)
	game.player_states[2] = game._make_player_state(2, Vector2i(0, 2), 0)
	game.player_states[0].world_position = Vector2(2.5, 2.5)
	game.player_states[1].world_position = Vector2(2.5, 0.5)
	game.player_states[2].world_position = Vector2(0.5, 2.5)
	game._begin_combat_death(0)
	assert(game.post_kill_active)
	game.continuous_third_person_camera = true
	var initial_yaw: float = game.player_states[0].continuous_camera_yaw
	game.held_keycodes[KEY_E] = true
	game._process(0.1)
	game.held_keycodes.erase(KEY_E)
	assert(not is_equal_approx(initial_yaw, float(game.player_states[0].continuous_camera_yaw)), "camera should still turn while the player is down")
	for frame in range(400):
		game._process(0.025)
	for index in [1, 2]:
		var distance: float = Vector2(game.player_states[index].world_position).distance_to(Vector2(game.player_states[0].world_position))
		assert(distance < 0.9, "survivor %d should gather near the body; distance %f" % [index, distance])
		assert(not bool(game.bot_inputs[index].fire))
	print("Both survivors gather during the normal frame loop")
	game.queue_free()
	quit()
