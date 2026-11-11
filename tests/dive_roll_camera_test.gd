extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.continuous_third_person_camera = true
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game._bind_player_context(0)
	game.continuous_camera_yaw = 0.0
	game._set_player_world_position_for_current_view(Vector2(2.5, 2.5))
	game._save_player_context(0)
	game.held_keycodes[KEY_A] = true
	game.held_keycodes[KEY_SPACE] = true
	assert(game._advance_dive_roll(0, 0.05, true))
	var state: Dictionary = game.player_states[0]
	var direction: Vector2 = state["dive_direction"]
	var body_facing: Vector2 = state["dive_aim_vector"]
	var first_position: Vector2 = game.player_world_position
	assert(game.player_sprite.animation == &"DiveLeftN")
	game._save_player_context(0)
	game.held_keycodes[KEY_SPACE] = false
	game.held_keycodes[KEY_E] = true
	assert(game._advance_dive_roll(0, 0.4, true))
	assert(absf(game.continuous_camera_yaw) > 0.1)
	assert(Vector2(state["dive_direction"]).is_equal_approx(direction))
	assert(Vector2(state["dive_aim_vector"]).is_equal_approx(body_facing))
	var travel: Vector2 = game.player_world_position - first_position
	assert(travel.length() > 0.01 and absf(travel.cross(direction)) < 0.0001)
	assert(game.player_sprite.animation != &"DiveLeftN")
	assert(game.player_sprite.animation == StringName("DiveLeft" + game._view_relative_vector_dir(body_facing)))
	game._save_player_context(0)
	# Mouse yaw is stored in player state between frames; rebinding must preserve
	# the same locked world trajectory and body facing as controller turning.
	state["continuous_camera_yaw"] = PI
	game._bind_player_context(0)
	game.held_keycodes[KEY_E] = false
	assert(game._advance_dive_roll(0, 0.05, true))
	assert(game.player_sprite.animation == &"DiveLeftS")
	assert(Vector2(state["dive_direction"]).is_equal_approx(direction))
	game._save_player_context(0)
	game.held_keycodes[KEY_A] = false
	assert(game._advance_dive_roll(0, 1.0, true))
	assert(not game._advance_dive_roll(0, 0.01, true))
	game._process_continuous_third_person_input(0.01)
	assert(not String(game.player_sprite.animation).begins_with("Dive"))
	assert(game.world_aim_dir == game._direction_string_for_world_vector(game._view_forward_vector()))
	# Temporary forward/back views keep their selected facing as the camera orbits.
	for entry in [[KEY_W, "DiveLeftNW", Vector2.UP], [KEY_S, "DiveLeftSE", Vector2.DOWN]]:
		game.continuous_camera_yaw = 0.0
		game._set_player_world_position_for_current_view(Vector2(2.5, 2.5))
		game._save_player_context(0)
		state["dive_active"] = false
		state["dive_was_pressed"] = false
		game.held_keycodes[int(entry[0])] = true
		game.held_keycodes[KEY_SPACE] = true
		assert(game._advance_dive_roll(0, 0.05, true))
		assert(game.player_sprite.animation == StringName(entry[1]))
		assert(Vector2(state["dive_direction"]).is_equal_approx(entry[2]))
		var art_facing: Vector2 = state["dive_aim_vector"]
		game._save_player_context(0)
		game.held_keycodes[KEY_SPACE] = false
		game.held_keycodes[KEY_E] = true
		assert(game._advance_dive_roll(0, 0.2, true))
		assert(Vector2(state["dive_direction"]).is_equal_approx(entry[2]))
		assert(Vector2(state["dive_aim_vector"]).is_equal_approx(art_facing))
		game.held_keycodes[int(entry[0])] = false
		game.held_keycodes[KEY_E] = false
	print("Dive camera orbit preserves trajectory, body facing and post-roll aim")
	game.queue_free()
	quit()
