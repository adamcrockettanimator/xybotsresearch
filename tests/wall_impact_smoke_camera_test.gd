extends SceneTree
# Exercise the real impact cards in two independently moving camera views.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var wrapper: Node = load("res://coordinate_frame_navigation.tscn").instantiate()
	root.add_child(wrapper)
	await process_frame
	await process_frame
	var game = wrapper.get_node("CoordinateFrameGame")
	game.set_process(false)
	game.set_physics_process(false)
	game.wall_edges.clear()
	for y in game.MAP_HEIGHT:
		for x in game.MAP_WIDTH:
			game.wall_edges[Vector2i(x, y)] = {game.WALL_EDGE_N: y == 0, game.WALL_EDGE_E: x == game.MAP_WIDTH - 1, game.WALL_EDGE_S: y == game.MAP_HEIGHT - 1, game.WALL_EDGE_W: x == 0}
	game.physical_wall_edges_cache_dirty = true
	game._reset_player_states_after_map(Vector2i(2, 3))
	game._bind_player_context(0)
	game._set_player_world_position_for_current_view(Vector2(2.5, 3.5))
	game._save_player_context(0)
	game._render_bound_player_context()
	var renderer = game.coordinate_renderers[0]
	var camera: Vector2 = game._runtime_camera_origin_for_visibility()
	var forward: Vector2 = game._view_forward_vector().normalized()
	var chosen := {}
	for entry in renderer.last_wall_entries:
		var hit: Vector2 = (Vector2(entry["world_a"]) + Vector2(entry["world_b"])) * 0.5
		var direction: Vector2 = (hit - camera).normalized()
		var point: Vector2 = hit - direction * 0.006
		if direction.dot(forward) < 0.95 or not game._world_actor_overlaps_current_camera_fan(point, 0.08) or not game._world_point_has_clear_camera_line(point):
			continue
		if renderer.runtime_wall_impact_layer(String(entry["edge_key"]), direction) < 0:
			continue
		if chosen.is_empty() or direction.dot(forward) > Vector2(chosen["direction"]).dot(forward):
			chosen = {"hit": hit, "direction": direction, "edge": entry["edge_key"]}
	if chosen.is_empty():
		push_error("Could not find a visible wall for the smoke test")
		quit(1)
		return
	print("Smoke test wall=", chosen, " camera=", camera)
	seed(38493)
	game.player_joined = [true, false, false, false]
	game._spawn_pistol_shot(0)
	for frame in 90:
		game._process_combat(1.0 / 60.0)
		if not game.active_wall_impact_smokes.is_empty():
			break
	if game.active_wall_impact_smokes.is_empty():
		push_error("The projectile did not create a wall impact")
		wrapper.queue_free()
		quit(1)
		return
	chosen["edge"] = game.active_wall_impact_smokes[0]["wall_edge_key"]
	chosen["direction"] = game.active_wall_impact_smokes[0]["direction"]
	game.player_joined = [true, true, false, false]
	game.player_states[1] = game._make_player_state(1, Vector2i(2, 3), 0)
	var mismatches := 0
	var positions_wrong := 0
	var observed := [0, 0]
	for frame in 36:
		for player in 2:
			game._bind_player_context(player)
			game.continuous_camera_yaw = 0.003 * float(frame) * (1.0 if player == 0 else -1.0)
			game._set_player_world_position_for_current_view(Vector2(2.5 + 0.1 * player, 3.5) + Vector2.UP * (0.014 * float(frame)))
			game._save_player_context(player)
		game._bind_player_context(0)
		game._process_combat(1.0 / 60.0)
		for player in 2:
			game._bind_player_context(player)
			game._render_bound_player_context()
			var view_renderer = game.coordinate_renderers[player]
			var expected_layer: int = view_renderer.runtime_wall_impact_layer(chosen["edge"], chosen["direction"])
			for smoke in game.active_wall_impact_smokes:
				var sprite = game.player_views[player]["combat_nodes"].get("wall_smoke_%d" % smoke["id"])
				if sprite != null and sprite.visible and expected_layer >= 0:
					observed[player] += 1
					if sprite.z_index != expected_layer:
						mismatches += 1
					var world_position: Vector2 = smoke["display_position"]
					var projection: Dictionary = game._opponent_projection_from_current_camera(world_position, true, true)
					var height: float = projection.get("continuous_actor_height", projection.get("actor_height", 0.0))
					var expected: Vector2 = (game._projectile_screen_position(projection) - Vector2(0, height * float(smoke["display_height"]))).round()
					if sprite.position != expected:
						positions_wrong += 1
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	print("MOTION frames=36 visible_by_view=%s layer_mismatches=%d position_mismatches=%d" % [str(observed), mismatches, positions_wrong])
	wrapper.queue_free()
	await process_frame
	quit(1 if mismatches > 0 or positions_wrong > 0 or observed[0] == 0 or observed[1] == 0 else 0)

