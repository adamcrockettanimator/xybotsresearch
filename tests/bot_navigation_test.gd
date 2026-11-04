extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	# The direct eastward edge is blocked and north/west are sealed. The only
	# route to the target begins south, so a dot-product steering heuristic would
	# choose incorrectly.
	var start := Vector2i(1, 1)
	var target := Vector2i(3, 1)
	game._set_wall_between(start, Vector2i(1, 0), true)
	game._set_wall_between(start, Vector2i(0, -1), true)
	game._set_wall_between(start, Vector2i(-1, 0), true)
	var direction: Vector2 = game._bot_navigation_direction(
		{"grid_position": start},
		{"grid_position": target},
		Vector2(target - start)
	)
	assert(direction == Vector2.DOWN)
	var route: Array = game._bot_cell_route(start, target)
	assert(route.size() >= 4)
	assert(Vector2i(route[0]) == start)
	assert(Vector2i(route[route.size() - 1]) == target)
	for route_index in range(route.size() - 1):
		var from_cell := Vector2i(route[route_index])
		var to_cell := Vector2i(route[route_index + 1])
		assert(abs(to_cell.x - from_cell.x) + abs(to_cell.y - from_cell.y) == 1)
		assert(game._can_cross_edge(from_cell, to_cell - from_cell))
	# Patrol targets are selected exclusively from passable navigation nodes.
	# A wall target used to make BFS fall back to a direct vector, sending NPCs
	# into corners instead of through the maze.
	var patrol_goal: Vector2i = game._bot_next_patrol_goal(1, start, Vector2i(-1, -1), 1)
	assert(game._is_open_cell(patrol_goal))
	# Close combat settles in a legal cell centre instead of continuously
	# reversing an orbit against opposite hallway walls.
	assert(game._bot_cell_center_direction({"grid_position": Vector2i(2, 2)}, Vector2(2.5, 2.5)) == Vector2.ZERO)
	assert(game._bot_cell_center_direction({"grid_position": Vector2i(2, 2)}, Vector2(2.2, 2.5)).x > 0.0)
	# Turning and strafing must remain independent in the continuous-camera
	# movement path; otherwise a bot rotates by repeatedly walking into a wall.
	game.player_bots[1] = true
	game.active_player_index = 1
	game.bot_inputs[1] = {"turn_right": true, "move_right": false, "move_forward": false}
	assert(game._is_player_turn_right_pressed())
	assert(not game._is_player_move_right_pressed())
	game.bot_inputs[1] = {"turn_right": false, "move_right": true, "move_forward": false}
	assert(not game._is_player_turn_right_pressed())
	assert(game._is_player_move_right_pressed())
	# A bot with a barrel directly on its route gets a lateral component rather
	# than pushing straight into the collision ring forever.
	game.world_barrels.clear()
	game.world_barrels.append({"id": 1, "position": Vector2(1.20, 1.0), "collision_radius": 0.10})
	var avoided: Vector2 = game._bot_avoid_world_barrels(Vector2(1.0, 1.0), Vector2.RIGHT)
	assert(avoided.dot(Vector2.RIGHT) < 0.98)
	assert(absf(avoided.y) > 0.05)
	# A stuck bot commits to an alternate lateral escape rather than reissuing the
	# blocked route vector on every frame.
	game.world_barrels.clear()
	var escape: Vector2 = game._bot_unstick_direction(1, {"grid_position": Vector2i(2, 2)}, Vector2(2.0, 2.0), Vector2.RIGHT, 2)
	assert(absf(escape.y) > absf(escape.x))
	print("Bot navigation routes around walls, strafes in combat, avoids barrel collisions, and recovers when stuck")
	game.queue_free()
	quit()
