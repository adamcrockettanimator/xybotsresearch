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
	game.player_states[0]["world_position"] = Vector2(5.5, 5.5)
	game.player_states[1]["world_position"] = Vector2(1.2, 2.5)
	game.player_states[1]["grid_position"] = Vector2i(1, 2)
	game.player_states[2]["world_position"] = Vector2(5.5, 4.5)
	game.player_states[3]["world_position"] = Vector2(4.5, 5.5)
	game.world_barrels.append({"id": 1, "position": Vector2(1.8, 2.5), "half_extents": Vector2(0.16, 0.16), "projectile_height": 0.7})
	game.bot_brains[1] = {"state": "INVESTIGATE", "investigation_kind": "footstep", "investigate_cell": Vector2i(2, 2), "goal_cell": Vector2i(2, 2), "next_search_scan": INF}
	var origin := Vector2(1.2, 2.5)
	var reached := false
	for tick in range(240):
		origin = game.player_states[1]["world_position"]
		var brain: Dictionary = game._update_bot_brain(1, game.player_states[1], origin, 0, Vector2.ZERO, 10.0, Vector2.RIGHT, 0.05)
		game.bot_inputs[1] = {"crouch": bool(brain.get("crouch", false))}
		game._process_virtual_bot_world_context(1, 0.05)
		if Vector2(game.player_states[1]["world_position"]).x > 2.0:
			reached = true
			break
	assert(reached)
	# Both circular and rectangular props receive a real two-segment detour.
	for prop in [{"id": 2, "position": Vector2(1.8, 2.5), "collision_radius": 0.16}, {"id": 3, "position": Vector2(1.8, 2.5), "half_extents": Vector2(0.16, 0.16)}]:
		game.world_barrels.clear()
		game.world_barrels.append(prop)
		var detour: Vector2 = game._bot_prop_detour_waypoint(Vector2(1.5, 2.5), Vector2(2.5, 2.5))
		assert(detour.is_finite())
		assert(game._move_world_with_wall_slide(Vector2(1.5, 2.5), detour - Vector2(1.5, 2.5), "e", "w", "s", "n").distance_to(detour) < 0.03)
		assert(game._move_world_with_wall_slide(detour, Vector2(2.5, 2.5) - detour, "e", "w", "s", "n").distance_to(Vector2(2.5, 2.5)) < 0.03)
	game.world_barrels.clear()
	var recovery: Vector2 = game._bot_recovery_waypoint(1, Vector2(1.5, 2.5), Vector2.RIGHT, Vector2i(3, 2), {})
	assert(recovery.is_finite() and absf(recovery.y - 2.5) > 0.2)
	# A watchdog replan commits to the recovery waypoint across subsequent ticks.
	game.player_states[1]["world_position"] = Vector2(1.5, 2.5)
	game.player_states[1]["grid_position"] = Vector2i(1, 2)
	game.bot_brains[1] = {"state": "INVESTIGATE", "investigation_kind": "footstep", "investigate_cell": Vector2i(3, 2), "goal_cell": Vector2i(3, 2), "move_direction": Vector2.RIGHT, "progress_anchor": Vector2(1.5, 2.5), "stuck_time": 1.0, "next_search_scan": INF}
	var recovery_brain: Dictionary = game._update_bot_brain(1, game.player_states[1], Vector2(1.5, 2.5), 0, Vector2.ZERO, 10.0, Vector2.RIGHT, 0.05)
	assert(recovery_brain["state"] == "RECOVER ROUTE")
	var held: Vector2 = recovery_brain["recovery_waypoint"]
	recovery_brain = game._update_bot_brain(1, game.player_states[1], Vector2(1.5, 2.5), 0, Vector2.ZERO, 10.0, Vector2.RIGHT, 0.05)
	assert(recovery_brain["state"] == "RECOVER ROUTE" and Vector2(recovery_brain["recovery_waypoint"]) == held)
	# A blocked bot turns toward its movement even when the wall stops it.
	game._set_wall_between(Vector2i(1, 2), Vector2i.RIGHT, true)
	game.physical_wall_edges_cache_dirty = true
	game.player_states[1]["world_position"] = Vector2(1.899, 2.5)
	game.player_states[1]["continuous_camera_yaw"] = 0.0
	game.bot_brains[1] = {"move_direction": Vector2.RIGHT, "has_line_of_sight": false}
	game.bot_inputs[1] = {"crouch": false}
	game._process_virtual_bot_world_context(1, 0.1)
	assert(game._view_forward_vector_for_state(game.player_states[1]).dot(Vector2.RIGHT) > 0.99)
	assert(Vector2(game.player_states[1]["world_position"]).x < 1.91)
	print("Bot navigated around props and faces its route when blocked")
	game.queue_free()
	quit()
