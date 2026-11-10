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
	game.player_states[0]["world_position"] = Vector2(3.5, 2.5)
	game.player_states[0]["grid_position"] = Vector2i(3, 2)
	game.player_states[0]["continuous_camera_yaw"] = PI * 0.5
	game.player_states[0]["character_is_crouching"] = true
	game.player_states[1]["world_position"] = Vector2(2.5, 2.5)
	game.player_states[1]["grid_position"] = Vector2i(2, 2)
	game.player_states[2]["world_position"] = Vector2(5.5, 5.5)
	game.player_states[3]["world_position"] = Vector2(5.5, 4.5)
	game._set_wall_between(Vector2i(2, 2), Vector2i.RIGHT, true)
	game.physical_wall_edges_cache_dirty = true
	var last_seen := Vector2(3.5, 2.5)
	game.bot_brains[1] = {"state": "SEARCH", "combat_memory": 1.3, "last_seen_target": 0, "last_seen_position": last_seen, "last_seen_cell": Vector2i(3, 2), "last_seen_forward": Vector2.RIGHT, "lost_sight_time": 0.4, "tactical_cooldown": 99.0, "flank_pressure_time": 0.8}
	var origin := Vector2(2.5, 2.5)
	var brain: Dictionary = game._update_bot_brain(1, game.player_states[1], origin, 0, last_seen - origin, 1.0, Vector2.RIGHT, 0.1)
	assert(brain["state"] == "FLANK")
	var route: Array = brain["flank_route"]
	assert(route.size() >= 2 and not route.has(Vector2i(3, 2)))
	for i in range(route.size() - 1):
		assert(game._can_cross_edge(Vector2i(route[i]), Vector2i(route[i + 1]) - Vector2i(route[i])))
	var flank_goal: Vector2i = brain["flank_goal"]
	assert((Vector2(flank_goal) + Vector2(0.5, 0.5) - last_seen).normalized().dot(Vector2.RIGHT) <= 0.15)
	assert(Vector2(brain["move_direction"]).length() > 0.9)
	# Moving the unseen target does not change the committed last-known route.
	game.player_states[0]["world_position"] = Vector2(4.5, 2.5)
	brain = game._update_bot_brain(1, game.player_states[1], origin, 0, Vector2(2.0, 0), 2.0, Vector2.RIGHT, 0.1)
	assert(brain["state"] == "FLANK" and brain["flank_goal"] == flank_goal and brain["flank_anchor"] == last_seen)
	# Exercise real bot movement and its normal collision solver until it arrives.
	var reached := false
	for tick in range(120):
		origin = Vector2(game.player_states[1]["world_position"])
		var target: Vector2 = game.player_states[0]["world_position"]
		brain = game._update_bot_brain(1, game.player_states[1], origin, 0, target - origin, origin.distance_to(target), Vector2.RIGHT, 0.1)
		if brain["state"] != "FLANK":
			reached = Vector2i(origin.floor()) == flank_goal
			break
		game.bot_inputs[1] = {"crouch": bool(brain.get("crouch", false))}
		game._process_virtual_bot_world_context(1, 0.1)
	assert(reached)
	# A teammate repeatedly blocking the firing lane can also trigger a flank
	# even when the opponent remains visible.
	game._build_empty_grid_audit_wall_edges()
	game.bot_brains.clear()
	game.player_states[0]["world_position"] = Vector2(4.5, 1.5)
	game.player_states[0]["grid_position"] = Vector2i(4, 1)
	game.player_states[0]["continuous_camera_yaw"] = 0.0
	game.player_states[1]["world_position"] = Vector2(1.5, 1.5)
	game.player_states[1]["grid_position"] = Vector2i(1, 1)
	game.player_states[2]["world_position"] = Vector2(2.5, 1.5)
	game.player_states[2]["grid_position"] = Vector2i(2, 1)
	game.bot_brains[1] = {"tactical_cooldown": 99.0}
	assert(game._bot_teammate_in_fire_lane(1, Vector2(1.5, 1.5), Vector2(3.0, 0)))
	for tick in range(10):
		brain = game._update_bot_brain(1, game.player_states[1], Vector2(1.5, 1.5), 0, Vector2(3.0, 0), 3.0, Vector2.RIGHT, 0.1)
		brain["stuck_time"] = 0.0
	assert(brain["state"] == "FLANK")
	# A direct wound interrupts the flank rather than forcing a plan through danger.
	game._notify_bot_wounded(1, Vector2.LEFT, 0)
	brain = game._update_bot_brain(1, game.player_states[1], Vector2(1.5, 1.5), 0, Vector2(3.0, 0), 3.0, Vector2.RIGHT, 0.1)
	assert(brain["state"] in ["FALL_BACK", "RETREAT_TO_COVER", "DUCK_AFTER_HIT"] and brain["flank_time"] == 0.0)
	# No path is invented through a sealed-off last-known region.
	game._build_empty_grid_audit_wall_edges()
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		game._set_wall_between(Vector2i(2, 2), direction, true)
	assert(game._bot_find_flank_route(1, Vector2i(2, 2), last_seen, Vector2.RIGHT).is_empty())
	print("Flank follows a real alternate route and uses only the last observation")
	game.queue_free()
	quit()
