extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game.bot_brains.clear()
	var start := Vector2i(2, 2)
	var cleared := {}
	for y in range(game.MAP_HEIGHT):
		for x in range(game.MAP_WIDTH):
			cleared[Vector2i(x, y)] = 100.0
	var unseen := Vector2i(5, 2)
	cleared.erase(unseen)
	assert(game._bot_search_goal(1, start, cleared, 100.0, 1) == unseen)
	assert(game._nearest_projectile_topology_clear(Vector2(2.5, 2.5), Vector2(2.0, 0.0)))
	game._set_wall_between(Vector2i(3, 2), Vector2i(1, 0), true)
	assert(not game._nearest_projectile_topology_clear(Vector2(2.5, 2.5), Vector2(2.0, 0.0)))
	var route: Array = game._bot_cell_route(start, unseen)
	assert(route.size() > 4)
	# A recently visited adjacent cell must lose to a farther unvisited cell.
	var visited := {Vector2i(3, 2): 100.0}
	cleared.clear()
	for y in range(game.MAP_HEIGHT):
		for x in range(game.MAP_WIDTH):
			var candidate := Vector2i(x, y)
			if candidate != unseen:
				visited[candidate] = 100.0
	assert(game._bot_search_goal(1, start, cleared, 100.0, 2, visited) == unseen)
	game._set_wall_between(Vector2i(3, 2), Vector2i(1, 0), false)
	var straight_route: Array = game._bot_cell_route(start, unseen)
	assert(game._bot_route_start_index(Vector2(2.8, 2.5), straight_route) == 1)
	assert(game._bot_route_start_index(Vector2(2.8, 2.75), straight_route) == 0)
	# Seeing a long-term destination during travel must not cause a reversal.
	var state: Dictionary = game._make_player_state(1, start, 1)
	var origin := Vector2(2.5, 2.5)
	game.bot_brains[1] = {"goal_cell": unseen, "route": straight_route, "route_index": 1, "cleared_cells": {unseen: float(Time.get_ticks_msec()) * 0.001}, "next_search_scan": INF}
	for i in range(40):
		origin.x = 2.5 + float(i) * 0.008
		var brain: Dictionary = game._update_bot_brain(1, state, origin, 0, Vector2.ZERO, 10.0, Vector2.RIGHT, 0.016)
		assert(brain["goal_cell"] == unseen)
		assert(brain["state"] == "SEARCH")
		assert(Vector2(brain["move_direction"]).x > 0.0)
	# Reproduce visibility flicker at a corner: combat movement and aim must
	# retain their committed target, and firing must still require actual LOS.
	game.bot_brains.clear()
	game.player_states[1] = game._make_player_state(1, Vector2i(2, 2), 1)
	game.player_states[0] = game._make_player_state(0, Vector2i(3, 2), 3)
	game.player_states[1]["world_position"] = Vector2(2.5, 2.5)
	game.player_states[0]["world_position"] = Vector2(3.5, 2.5)
	game.bot_brains[1] = {"tactical_cooldown": 100.0}
	var combat: Dictionary = game._update_bot_brain(1, game.player_states[1], Vector2(2.5, 2.5), 0, Vector2.RIGHT, 1.0, Vector2.RIGHT, 0.016)
	assert(combat["state"] == "FIRING_POINT" and combat["has_line_of_sight"])
	assert(Vector2(combat["move_direction"]).length() > 0.9)
	var combat_goal: Vector2i = combat["goal_cell"]
	var combat_move: Vector2 = combat["move_direction"]
	game._set_wall_between(Vector2i(2, 2), Vector2i(1, 0), true)
	game.player_states[0]["world_position"] = Vector2(3.7, 2.5)
	combat = game._update_bot_brain(1, game.player_states[1], Vector2(2.5, 2.5), 0, Vector2(1.2, 0), 1.2, Vector2.RIGHT, 0.016)
	assert(combat["state"] == "LOOK_LAST_SEEN" and not combat["has_line_of_sight"])
	assert(combat["goal_cell"] == combat_goal and Vector2(combat["move_direction"]).dot(combat_move) > 0.99)
	assert(combat["last_seen_position"] == Vector2(3.5, 2.5))
	game._set_wall_between(Vector2i(2, 2), Vector2i(1, 0), false)
	combat = game._update_bot_brain(1, game.player_states[1], Vector2(2.5, 2.5), 0, Vector2(1.2, 0), 1.2, Vector2.RIGHT, 0.016)
	assert(combat["state"] == "FIRING_POINT" and combat["goal_cell"] == combat_goal)
	assert(Vector2(combat["move_direction"]).dot(combat_move) > 0.99)
	game.player_bots[1] = true
	game.player_joined[0] = true
	game.continuous_third_person_camera = true
	game.player_states[1]["continuous_camera_yaw"] = PI * 0.5
	game._update_bot_input(1, 0.016)
	var controls: Dictionary = game.bot_inputs[1]
	assert(controls["fire"])
	assert(controls["move_left"] or controls["move_right"] or controls["move_forward"] or controls["move_backward"])
	# Recreate the trace: crossing the old 2.25-cell boundary must not
	# replace pursuit with a waypoint back in the cell just left.
	game._build_empty_grid_audit_wall_edges()
	game.bot_brains.clear()
	game.player_states[0] = game._make_player_state(0, Vector2i(0, 4), 1)
	game.player_states[0]["world_position"] = Vector2(0.32, 4.46)
	game.player_states[1] = game._make_player_state(1, Vector2i(2, 3), 0)
	game.bot_brains[1] = {"tactical_cooldown": 100.0}
	for position in [Vector2(2.5, 3.92), Vector2(2.5, 3.94), Vector2(2.5, 4.36)]:
		game.player_states[1]["world_position"] = position
		game.player_states[1]["grid_position"] = Vector2i(floori(position.x), floori(position.y))
		var toward: Vector2 = Vector2(0.32, 4.46) - position
		combat = game._update_bot_brain(1, game.player_states[1], position, 0, toward, toward.length(), Vector2.LEFT, 0.016)
		assert(combat["has_line_of_sight"])
		assert(combat["goal_cell"] == Vector2i(0, 4))
	# The ordinary bot simulation must retain combat aim after moving sideways.
	game.player_states[1] = game._make_player_state(1, Vector2i(2, 2), 1)
	game.player_states[1]["world_position"] = Vector2(2.5, 2.5)
	game.player_states[0] = game._make_player_state(0, Vector2i(3, 2), 3)
	game.player_states[0]["world_position"] = Vector2(3.5, 2.5)
	game.bot_brains[1] = {"has_line_of_sight": true, "target_index": 0, "move_direction": Vector2.DOWN}
	game._bind_player_context(1)
	game._process_bot_world_context(0.1)
	assert(game._view_forward_vector().dot(Vector2.RIGHT) > 0.99)
	assert(game.player_world_position.y > 2.5)
	print("Bot pursuit stays committed across range changes and maintains aim while moving")
	game.queue_free()
	quit()
