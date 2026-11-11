extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game._set_wall_between(Vector2i(1, 1), Vector2i.RIGHT, true)
	var half := Vector2(0.096, 0.096)
	var edges: Array = game._all_physical_wall_edges()
	var near: Vector2 = game._ensure_prop_wall_passage(Vector2(2.22, 1.5), half)
	assert(near.is_finite())
	assert(game._prop_wall_position_clear(near, half, edges))
	assert(near.x - 2.0 - half.x <= game.PROP_CLOSED_WALL_GAP)
	var wide := Vector2(2.5, 1.5)
	assert(game._ensure_prop_wall_passage(wide, half).is_equal_approx(wide))
	game.world_barrels.append({"id": 1, "position": wide, "collision_radius": 0.096})
	var passed: Vector2 = game._move_world_with_wall_slide(Vector2(2.16, 1.15), Vector2(0.0, 0.7), "east", "west", "south", "north")
	assert(passed.y > 1.8)
	game.world_barrels.clear()
	# A gap diagonally beyond a wall end is also checked, not just the wall face.
	var diagonal: Vector2 = game._ensure_prop_wall_passage(Vector2(2.20, 2.20), half)
	assert(diagonal.is_finite())
	assert(game._prop_wall_position_clear(diagonal, half, edges))
	var endpoint_gap := Vector2(maxf(diagonal.x - half.x - 2.0, 0.0), maxf(diagonal.y - half.y - 2.0, 0.0)).length()
	assert(endpoint_gap <= game.PROP_CLOSED_WALL_GAP or endpoint_gap >= game.PROP_MIN_PASSAGE_WIDTH)
	var clusters := 0
	for trial in 12:
		game._build_random_maze_wall_edges()
		game._reset_world_barrels()
		for footprint in game.semantic_lod_floor_footprints:
			if not bool(footprint.get("typical_spawn", false)) or bool(footprint.get("dining_set_spawn", false)):
				continue
			if bool(footprint.get("cluster_spawn", false)):
				clusters += 1
			var position := Vector2(footprint["position"])
			var width := float(footprint["side_length"])
			var extent := Vector2.ONE * width * (0.6 if String(footprint["id"]).begins_with("barrel_") else 0.5)
			assert(game._prop_wall_position_clear(position, extent, game._all_physical_wall_edges()), "Invalid generated prop gap: %s" % position)
	assert(clusters > 0, "Expected at least one cluster across generated maps")
	print("Near-wall and diagonal gaps, open passages, and generated clusters verified")
	game.queue_free()
	quit()
