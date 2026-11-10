extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.clear_the_map_mode = true
	game.clear_map_round = 3
	game._apply_session_roster()
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game.show_bot_navigation_debug = true
	game.player_states[0]["world_position"] = Vector2(4.0, 2.5)
	game.player_states[1]["world_position"] = Vector2(2.0, 2.5)
	game.player_states[2]["world_position"] = Vector2(2.5, 2.5)
	game.player_states[3]["world_position"] = Vector2(4.0, 4.0)
	var brain := {}
	game._bot_firing_points(1, Vector2(2.0, 2.5), Vector2(4.0, 2.5), brain)
	assert(Vector2(brain["firing_point"]).is_finite())
	var point: Vector2 = brain["firing_point"]
	assert(is_equal_approx(fposmod(point.x, 0.25), 0.125))
	assert(is_equal_approx(fposmod(point.y, 0.25), 0.125))
	assert(point.distance_to(Vector2(2.5, 2.5)) >= game.PLAYER_CAPSULE_RADIUS * 2.5)
	# A low obstacle produces both a firing lane and an actual cover candidate.
	game.world_barrels.append({"id": 100, "position": Vector2(2.8, 2.5), "projectile_radius": 0.16, "collision_radius": 0.16, "projectile_height": 0.7})
	game._bot_firing_points(1, Vector2(2.0, 2.5), Vector2(4.0, 2.5), brain)
	var cover: Vector2 = brain["candidate_cover"]
	assert(cover.is_finite())
	assert(not game._bot_low_lane_clear(cover, Vector2(4.0, 2.5)))
	game.player_states[0]["character_is_crouching"] = false
	brain["react_to_hit"] = true
	game._update_bot_tactics(1, Vector2(2.0, 2.5), 0, Vector2(2.0, 0.0), true, 0.1, brain)
	assert(brain["tactical_mode"] == "approach_cover")
	assert(Vector2(brain["tactical_move"]).length() > 0.9)
	# A visible enemy reload interrupts a passive cover hold and permits a shot.
	game.world_barrels.clear()
	game.player_states[0]["reload_phase"] = "open"
	game.player_states[0]["character_is_crouching"] = false
	game.player_states[1]["reload_phase"] = ""
	brain = {"tactical_mode": "wall_cover", "wall_cover_point": Vector2(2.0, 2.5), "wall_peek_point": Vector2(2.0, 2.5), "tactical_timer": 2.0, "tactical_target": 0}
	game._update_bot_tactics(1, Vector2(2.0, 2.5), 0, Vector2(2.0, 0.0), true, 0.1, brain)
	assert(brain["allow_fire"] and not brain["crouch"])
	game.player_states[0]["reload_phase"] = ""
	# Simulate a bot walking toward a stationary teammate; it must progress
	# around them, not simply stop at their collision radius.
	var position := Vector2(2.0, 2.5)
	for step in range(140):
		var desired := (Vector2(3.2, 2.5) - position).normalized() * 0.02
		position = game._bot_limit_actor_overlap(1, position, position + desired)
		game.player_states[1]["world_position"] = position
		assert(position.distance_to(Vector2(2.5, 2.5)) >= game.PLAYER_CAPSULE_RADIUS * 2.0 - 0.002)
	assert(position.x > 2.7)
	# Every generated map retains a central open room and an outer loop.
	for iteration in range(12):
		game._build_random_maze_wall_edges()
		for y in [2, 3]:
			assert(game._can_cross_edge(Vector2i(2, y), Vector2i.RIGHT))
		for x in [2, 3]:
			assert(game._can_cross_edge(Vector2i(x, 2), Vector2i.DOWN))
		for x in range(game.MAP_WIDTH - 1):
			assert(game._can_cross_edge(Vector2i(x, 0), Vector2i.RIGHT))
			assert(game._can_cross_edge(Vector2i(x, game.MAP_HEIGHT - 1), Vector2i.RIGHT))
		assert(game._bot_cell_route(Vector2i(0, 0), Vector2i(4, 4)).size() > 0)
	print("Firing points, cover, passing, and generated room layout passed")
	game.queue_free()
	quit()
