extends SceneTree

var coffee_front: float

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://outdoor_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	var style: Resource = game.STOREFRONT_STYLE
	var rect: Rect2i = style.FOOTPRINT
	coffee_front = rect.position.y
	assert(rect.size == Vector2i(1, 2))
	assert(game.town_has_roof(rect.position) and game.town_has_roof(rect.end - Vector2i.ONE))
	assert(not game.town_has_roof(rect.position + Vector2i.RIGHT))
	assert(is_equal_approx(game.town_walk_height(_coffee(2.65, -0.20)), style.porch_height))
	assert(is_zero_approx(game.town_walk_height(_coffee(2.35, 2.20))))
	assert(is_equal_approx(game.town_walk_height(_coffee(2.65, 0.20)), style.porch_height))
	assert(game.storefront_open_doors.is_empty())
	assert(_move(game, _coffee(2.65, -0.30), Vector2(0, 0.6), false).y < coffee_front)
	assert(game.storefront_open_doors.is_empty())
	assert(style.roof_height(coffee_front) > style.roof_height(coffee_front + 2.0))
	_move(game, _coffee(2.65, -0.30), Vector2(0, 0.6))
	game._advance_storefront_doors(0.08)
	assert(float(game.storefront_open_doors["front"]) > 0.0 and float(game.storefront_open_doors["front"]) < 1.0)
	game._advance_storefront_doors(0.25)
	assert(_move(game, _coffee(2.65, -0.30), Vector2(0, 0.6)).y > coffee_front)
	assert(game.storefront_open_doors.has("front") and not game.storefront_open_doors.has("rear"))
	assert(_move(game, _coffee(2.25, -0.30), Vector2(0, 0.6)).y < coffee_front)
	assert(_move(game, _coffee(2.25, -0.75), Vector2(0, 0.45)).y < coffee_front - 0.47)
	_move(game, _coffee(2.5, 1.70), Vector2(0, 0.6))
	game._advance_storefront_doors(0.25)
	assert(_move(game, _coffee(2.5, 1.70), Vector2(0, 0.6)).y > coffee_front + 2.00)
	assert(game.storefront_open_doors.has("rear"))
	assert(_move(game, _coffee(2.15, 1.70), Vector2(0, 0.6)).y < coffee_front + 2.00)
	assert(_move(game, _coffee(2.5, 1.50), Vector2(0.7, 0)).x < 3.0)
	# Pushing toward the closing side of the open front leaf reverses its swing.
	_move(game, _coffee(2.66, 0.26), Vector2(0.17, 0.0))
	assert(not game.storefront_closing_doors.has("front"))
	_move(game, _coffee(2.895, 0.30), Vector2(-0.25, 0.0))
	assert(game.storefront_closing_doors.has("front"))
	game._advance_storefront_doors(0.25)
	assert(not game.storefront_open_doors.has("front"))
	assert(_move(game, _coffee(2.65, -0.30), Vector2(0, 0.6), false).y < coffee_front)
	_test_dive_roll_doors(game)
	_test_window(game)
	_test_dive_vaults(game)
	_test_porch_rail_vaults(game)
	_test_furnishing_clearance(game)
	_test_footstep_surfaces(game)
	var renderer: Node = game.get_node("CoordinateFrameRuntimeRendererP1")
	assert(renderer.storefront_planes.size() == 3)
	var floor_material: ShaderMaterial = renderer.storefront_planes[1].material
	assert(floor_material.get_shader_parameter("use_semantic_floor_material"))
	assert(floor_material.get_shader_parameter("town_roof_bounds") == renderer.town_roof_bounds)
	var original_matrix: int = renderer.depth_dither_matrix_size
	renderer.set_depth_dither_matrix_size(4)
	assert(floor_material.get_shader_parameter("floor_light_dither_matrix_size") == 4)
	renderer.set_depth_dither_matrix_size(original_matrix)
	var floor: Rect2 = style.floor_rect()
	assert(floor_material.get_shader_parameter("bounds") == Vector4(floor.position.x, floor.position.y, floor.end.x, floor.end.y))
	assert(floor_material.get_shader_parameter("edge_heights") == Vector2.ONE * style.porch_height)
	var rail_spans: Array[Dictionary] = style.trim_spans().filter(func(span: Dictionary) -> bool: return span.get("porch_rail", false))
	assert(rail_spans.size() == 1)
	var rail_start: Vector2 = rail_spans[0]["a"]
	assert(is_equal_approx(rail_start.x, style.FOOTPRINT.end.x - style.FRONT_DOOR.y))
	var porch: Rect2 = style.porch_rect()
	var posts: Array[Dictionary] = style.trim_spans().filter(func(span: Dictionary) -> bool: return span.get("partial", false) and span.get("overhang_height") == style.AWNING_FRONT)
	assert(posts.size() == 2)
	var outer_corners: Array[Vector2] = []
	for post in posts:
		var start: Vector2 = post["a"]
		var end: Vector2 = post["b"]
		var front_y := start.y - float(post["thickness"]) * 0.5
		var outer_x := maxf(start.x, end.x) if start.x > porch.get_center().x else minf(start.x, end.x)
		outer_corners.append(Vector2(outer_x, front_y))
	assert(outer_corners[0].is_equal_approx(Vector2(porch.end.x, porch.position.y)))
	assert(outer_corners[1].is_equal_approx(porch.position))
	assert(_move(game, _coffee(style.door_frame_center(true).x, -0.70), Vector2.DOWN * 0.4, false).y > coffee_front - 0.33)
	_test_fence(game, renderer)
	_test_town_buildings(game, renderer)
	_test_coffee_table_render(game)
	print("Storefront checks passed")
	quit()


func _test_town_buildings(game: Node, renderer: Node) -> void:
	assert(game.town_roof_rects().size() == 4)
	assert(game.MAP_WIDTH == 10 and game.MAP_HEIGHT == 9)
	assert(renderer.town_variant_planes.size() == TownBuildingStyle.PLANE_LIMIT)
	var timber: Array = renderer.town_variant_porch_faces.filter(func(face: Dictionary) -> bool: return face.has("timber_batch"))
	assert(timber.size() == 4 * game.TOWN_BUILDINGS.size())
	assert(timber.all(func(face: Dictionary) -> bool: return int(face["timber_batch"]["count"]) <= 48))
	for definition in game.TOWN_BUILDINGS:
		var building: TownBuildingStyle = definition
		var lot := building.footprint
		var porch := building.porch()
		assert(lot.get_area() > game.STOREFRONT_STYLE.FOOTPRINT.get_area())
		assert(game.town_has_roof(lot.position))
		assert(not game.town_has_roof(Vector2i(lot.get_center().x, int(game.TOWN_STREET_Y))))
		assert((porch.get_center().y - building.frontage()) * (game.TOWN_STREET_Y - building.frontage()) > 0.0)
		assert(is_equal_approx(game.town_walk_height(porch.get_center()), building.FLOOR_HEIGHT))
		var entrance := Vector2(building.door_x(), building.frontage())
		var outward := Vector2.DOWN * building.direction()
		var approach := entrance + outward * (building.porch_depth + 0.22)
		for front in [true, false]:
			var y := building.frontage() if front else float(lot.position.y + lot.end.y) - building.frontage()
			var door := Vector2(entrance.x, y)
			var normal := outward if front else -outward
			var leaves := building.door_leaf_spans({})
			assert(leaves.filter(func(leaf: Dictionary) -> bool: return is_equal_approx(Vector2(leaf["a"]).y, y)).size() == 2)
			var outside := door + normal * 0.30
			var travel := -normal * 0.62
			assert((_move(game, outside, travel, false) - door).dot(normal) > 0.0)
			_move(game, outside, travel)
			game._advance_storefront_doors(0.25)
			assert((_move(game, outside, travel, false) - door).dot(normal) < -0.15)
		assert((_move(game, approach, -outward * (building.porch_depth + 0.53), false) - entrance).dot(outward) < -0.15)
		_test_town_windows(game, building, outward)
		for partition in building.partition_edges():
			var cell := Vector2i(partition.x, partition.y)
			var direction := Vector2i(partition.z, partition.w)
			assert(not game._can_player_cross_edge(cell, direction))
			assert(game._nearest_projectile_wall_distance(Vector2(cell) + Vector2.ONE * 0.5, Vector2(direction), 0.60, 0.31) < 0.60)
		var props: Array = game.world_barrels.filter(func(prop: Dictionary) -> bool: return prop.has("projectile_top_world") and Rect2(lot).has_point(prop["position"]))
		assert(not props.is_empty())
		for cover: Dictionary in props:
			var key: String = cover["footprint_key"]
			var art: Dictionary = game.semantic_lod_floor_footprints.filter(func(prop: Dictionary) -> bool: return prop["id"] == key)[0]
			var expected_width: float = game.gpu_lattice_barrel_radius * 2.0
			var expected_height: float = game.gpu_lattice_barrel_height if key.begins_with("barrel_") else expected_width
			assert(is_equal_approx(art["side_length"], expected_width))
			assert(is_equal_approx(art["height"], expected_height))
			assert(is_equal_approx(cover["vault_height"], expected_height))
			var center: Vector2 = cover["position"]
			var top: float = cover["projectile_top_world"]
			assert(is_equal_approx(top, game.town_walk_height(center) + expected_height))
			var origin := center - Vector2.RIGHT * (expected_width * 0.66)
			var hit: Dictionary = game._projectile_cover_hit(origin, Vector2.RIGHT, expected_width, 0.86, false, top - 0.02)
			assert(hit.get("id") == cover["id"])
			var above: Dictionary = game._projectile_cover_hit(origin, Vector2.RIGHT, expected_width, 0.86, false, top + 0.02)
			assert(above.get("id") != cover["id"])
		if building.second_story:
			game._bind_player_context(0)
			game._set_player_world_position_for_current_view(Vector2(lot.get_center()) + Vector2(0.25, 0.15))
			game.continuous_camera_yaw = 0.0
			assert(renderer._visible_ceiling_cells().any(func(entry: Dictionary) -> bool: return lot.has_point(entry["cell"])))
		var rail_x := float(lot.position.x) + 0.24
		var beside_gate := Vector2(rail_x, approach.y)
		var rail_contact := _move(game, beside_gate, -outward * 0.45, false)
		assert(absf(rail_contact.y - building.frontage()) >= building.porch_depth)
		var roof := building.roof_planes()
		assert(roof[0]["slope_x"] and roof[1]["slope_x"])
		assert(is_equal_approx(roof[0]["heights"].y, roof[1]["heights"].x))
		assert(roof[0]["heights"].x < roof[0]["heights"].y and roof[1]["heights"].y < roof[1]["heights"].x)

	_test_oblique_porch_painter(game, renderer)


func _test_oblique_porch_painter(game: Node, renderer: Node) -> void:
	for pose in [[Vector2(1.36, 3.59), 0.38], [Vector2(3.83, 3.58), -0.52]]:
		game._bind_player_context(0)
		game.continuous_camera_yaw = pose[1]
		game._set_player_world_position_for_current_view(pose[0])
		game._save_player_context(0)
		game._render_all_player_views()
		var front_walls: Array[Dictionary] = []
		var porch_runs: Array[Dictionary] = []
		for entry: Dictionary in renderer.last_wall_entries:
			var variant: Dictionary = entry["variant"]
			if variant.is_empty() or variant["style"].sign_text != "STORE":
				continue
			if variant["role"] == 1:
				front_walls.append(entry)
			elif variant["role"] == 9:
				porch_runs.append(entry)
		var overlaps := 0
		for run in porch_runs:
			var bounds: Rect2 = run["quad_bounds"]
			for wall in front_walls:
				if bounds.intersects(wall["quad_bounds"]):
					overlaps += 1
					assert(wall["wall_draw_layer"] < run["wall_draw_layer"], "Store glazing must paint behind the exterior timbers")
		assert(overlaps > 0)


func _test_town_windows(game: Node, building: TownBuildingStyle, outward: Vector2) -> void:
	for face in ["front", "west", "east"]:
		var windows := building.ground_windows(face)
		for index in windows.size():
			var window := windows[index]
			var center := window.get_center()
			var normal := outward
			var pane := Vector2(center.x, building.frontage())
			if face != "front":
				normal = Vector2.LEFT if face == "west" else Vector2.RIGHT
				pane = Vector2(building.footprint.position.x if face == "west" else building.footprint.end.x, center.x)
			var outside := pane + normal * 0.26
			var direction := -normal
			assert(game._nearest_projectile_wall_distance(outside, direction, 0.50, center.y) < 0.5)
			var shooter := pane + normal * (building.porch_depth + 0.16 if face == "front" else 0.37)
			var previous_joined: Array = game.player_joined.duplicate()
			game.player_joined.fill(false)
			game.player_joined[0] = true
			game.active_projectiles.clear()
			var shot := _spawn_standing_shot(game, shooter, Vector2.UP.angle_to(direction))
			var renderer := game.get_node("CoordinateFrameRuntimeRendererP1")
			var intact_frame: String = renderer._render_signature()
			game._process_combat(0.14)
			assert(renderer._render_signature() != intact_frame, "Breaking a pane must refresh a stationary camera")
			assert(game.town_broken_windows.has(building.window_id(index, face)), "%s %s pane %d blocked at shot height %s" % [building.sign_text, face, index, shot["storefront_world_height"]])
			var follow_up := _spawn_standing_shot(game, shooter, Vector2.UP.angle_to(direction))
			var travel := (pane - Vector2(follow_up["position"])).dot(direction) + 0.07
			game._process_combat(travel / game.PROJECTILE_SPEED)
			assert(game.active_projectiles.has(follow_up) and (Vector2(follow_up["position"]) - pane).dot(normal) < -0.05)
			game.active_projectiles.clear()
			game.player_joined = previous_joined
			assert(game._nearest_projectile_wall_distance(outside, direction, 0.50, center.y) > 0.5)
			assert(game._nearest_projectile_wall_distance(outside, direction, 0.50, 0.17) < 0.5)
			assert((_move(game, outside, direction * 0.44) - pane).dot(normal) > 0.0)
			var pane_id := building.window_id(index, face)
			var movement_keys := {Vector2.UP: KEY_W, Vector2.DOWN: KEY_S, Vector2.LEFT: KEY_A, Vector2.RIGHT: KEY_D}
			for side: Vector2 in [normal, -normal]:
				game.town_broken_windows.erase(pane_id)
				var landing := _dive(game, pane + side * 0.26, movement_keys[-side])
				assert(game.town_broken_windows.has(pane_id), "%s pane did not break during a vault from %s" % [pane_id, side])
				assert((landing - pane).dot(side) < -0.12, "%s vault from %s ended at %s" % [pane_id, side, landing])


func _coffee(x: float, from_front: float) -> Vector2:
	return Vector2(x, coffee_front + from_front)


func _move(game: Node, position: Vector2, delta: Vector2, push := true) -> Vector2:
	return game._move_world_with_wall_slide(position, delta, "E", "W", "S", "N", push)


func _test_dive_roll_doors(game: Node) -> void:
	assert(not game.storefront_open_doors.has("front"))
	var entered := _dive(game, _coffee(2.65, -0.32), KEY_S)
	assert(game.storefront_open_doors.has("front"))
	assert(entered.y > coffee_front + 0.12)
	_dive(game, _coffee(2.895, 0.30), KEY_A)
	assert(not game.storefront_open_doors.has("front"))
	assert(not game.storefront_closing_doors.has("front"))

	game.storefront_closing_doors["rear"] = true
	game._advance_storefront_doors(0.25)
	assert(not game.storefront_open_doors.has("rear"))
	var entered_from_rear := _dive(game, _coffee(2.50, 2.34), KEY_W)
	assert(game.storefront_open_doors.has("rear"))
	assert(entered_from_rear.y < coffee_front + 1.88)


func _dive(game: Node, start: Vector2, movement_key: int) -> Vector2:
	game._bind_player_context(0)
	game.continuous_camera_yaw = 0.0
	game._set_player_world_position_for_current_view(start)
	game._save_player_context(0)
	game.held_keycodes[movement_key] = true
	game.held_keycodes[KEY_SPACE] = true
	const delta := 1.0 / 60.0
	var started: bool = game._advance_dive_roll(0, delta, true)
	assert(started)
	game._save_player_context(0)
	game.held_keycodes[KEY_SPACE] = false
	game.held_keycodes[movement_key] = false
	for _frame in range(66):
		game._advance_storefront_doors(delta)
		if not game._advance_dive_roll(0, delta, true):
			break
		game._save_player_context(0)
	return game.player_world_position


func _test_dive_vaults(game: Node) -> void:
	var crate := {"id": -100, "position": Vector2(4.1, 4.4), "half_extents": Vector2(0.08, 0.08), "vault_height": 0.16}
	game.world_barrels.append(crate)
	var start := Vector2(4.1, 4.11)
	assert(_move(game, start, Vector2(0, 0.6)).y < 4.4)
	assert(_dive(game, start, KEY_S).y > 4.60)
	crate["vault_height"] = 0.24
	assert(_dive(game, start, KEY_S).y < 4.4)
	game.world_barrels.erase(crate)

	game.storefront_glass_broken = false
	var window_start := _coffee(2.23, -0.31)
	assert(_dive(game, _coffee(2.405, -0.31), KEY_S).y < coffee_front)
	assert(not game.storefront_glass_broken)
	assert(_dive(game, window_start, KEY_S).y > coffee_front + 0.12)
	assert(game.storefront_window_vaulted and game.storefront_glass_broken)
	assert(game._nearest_projectile_wall_distance(_coffee(2.23, 0.20), Vector2.UP, 0.6, 0.38) > 0.6)
	assert(_move(game, _coffee(2.23, 0.25), Vector2.UP * 0.45).y >= coffee_front + 0.09)
	assert(_dive(game, _coffee(2.23, 0.27), KEY_W).y < coffee_front - 0.14)


func _test_porch_rail_vaults(game: Node) -> void:
	var rails: Array = game._all_physical_wall_edges().filter(
		func(edge: Dictionary) -> bool: return edge.get("porch_rail", false)
	)
	assert(rails.size() == 12, "Expected all authored handrail spans, got %d" % rails.size())
	var broken_windows: Dictionary = game.town_broken_windows.duplicate()
	var coffee_glass_broken: bool = game.storefront_glass_broken
	var move_keys := {Vector2.UP: KEY_W, Vector2.DOWN: KEY_S, Vector2.LEFT: KEY_A, Vector2.RIGHT: KEY_D}
	for rail: Dictionary in rails:
		var start: Vector2 = rail["a"]
		var end: Vector2 = rail["b"]
		var midpoint := start.lerp(end, 0.5)
		var normal := Vector2.RIGHT if is_equal_approx(start.x, end.x) else Vector2.DOWN
		for side: Vector2 in [normal, -normal]:
			var approach := midpoint + side * 0.20
			assert((_move(game, approach, -side * 0.42, false) - midpoint).dot(side) >= 0.09)
			var plan: Dictionary = game._plan_dive_vault(approach, -side, 0.58)
			assert(plan.get("edge") == rail["key"], "No rail vault at %s from %s" % [midpoint, side])
			assert(float(plan["lift"]) + game.town_walk_height(approach) > float(rail["height"]))
			var landing := _dive(game, approach, move_keys[-side])
			assert((landing - midpoint).dot(side) < -0.12, "Did not clear rail at %s from %s" % [midpoint, side])
	assert(game.town_broken_windows == broken_windows and game.storefront_glass_broken == coffee_glass_broken)


func _test_furnishing_clearance(game: Node) -> void:
	var dining_pieces: Array = game.semantic_lod_floor_footprints.filter(func(piece: Dictionary) -> bool: return piece.has("dining_set_id"))
	assert(dining_pieces.filter(func(piece: Dictionary) -> bool: return Rect2(game.STOREFRONT_STYLE.FOOTPRINT).has_point(piece["position"])).size() == 3)
	assert(_move(game, _coffee(2.65, -0.32), Vector2(-0.41, 0)).x < 2.25)
	assert(_move(game, _coffee(2.24, -0.32), Vector2(0, 0.25)).y < coffee_front - 0.16)
	assert(_move(game, _coffee(2.24, 0.43), Vector2(0, 0.72)).y < coffee_front + 0.73)
	assert(_move(game, _coffee(2.53, 0.50), Vector2(0, 1.05)).y > coffee_front + 1.54)


func _test_coffee_table_render(game: Node) -> void:
	var tables: Array = game.semantic_lod_floor_footprints.filter(func(piece: Dictionary) -> bool: return String(piece["id"]).begins_with("chair_semantic_table_dining"))
	assert(tables.size() == 2)
	assert(tables[0]["id"] != tables[1]["id"])
	game._bind_player_context(0)
	game._set_player_world_position_for_current_view(_coffee(2.57, 0.93))
	game.continuous_camera_yaw = -PI / 2.0
	game._save_player_context(0)
	game._render_all_player_views()
	var coffee_table: Node = game.semantic_lod_floor_outline_nodes.get("0:" + String(tables[0]["id"]))
	assert(is_instance_valid(coffee_table) and coffee_table.visible)

	# Turning near the table can put its centre and the player in different
	# grid cells even though the table stays on the same side of the player.
	for yaw: float in [-PI / 2.0, -1.28]:
		game._bind_player_context(0)
		game.continuous_camera_yaw = yaw
		game._set_player_world_position_for_current_view(_coffee(2.49, 0.97))
		game._save_player_context(0)
		game._render_all_player_views()
		assert(coffee_table.visible)
		var player_layer: int = game.player_views[0]["player_sprite"].z_index
		assert(coffee_table.z_index < player_layer, "Coffee table depth changed at yaw %s (table %d, player %d)" % [yaw, coffee_table.z_index, player_layer])


func _test_footstep_surfaces(game: Node) -> void:
	assert(game._footstep_surface(_coffee(2.65, -0.55)) == "Dirt")
	assert(game._footstep_surface(_coffee(2.65, -0.30)) == "Wood")
	assert(game._footstep_surface(_coffee(2.65, 0.25)) == "Wood")
	assert(game._footstep_surface(Vector2(2.50, 2.50)) == "Wood")
	assert(game._footstep_surface(_coffee(2.50, 2.30)) == "Dirt")

	for kind in game.FOOTSTEP_KINDS:
		assert(game._play_actor_surface_sound(0, kind, _coffee(2.65, -0.55)))
		var channel: Dictionary = game._footstep_channel(0)
		assert("/Dirt/" in channel["player"].stream.resource_path)
		assert(game._play_actor_surface_sound(0, kind, _coffee(2.65, -0.30)))
		assert("/Wood/" in channel["player"].stream.resource_path)

	game.footstep_last_samples.clear()
	_dive(game, _coffee(2.65, -0.71), KEY_S)
	assert(game.footstep_last_samples.has("0:Dirt:Jump"))
	assert(game.footstep_last_samples.has("0:Wood:Drop"))


func _test_fence(game: Node, renderer: Node) -> void:
	var posts := {}
	for edge: Dictionary in game._all_physical_wall_edges():
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		if not renderer._is_exterior_wall_entry({"world_a": a, "world_b": b}):
			continue
		var post: Vector2 = renderer._town_fence_post(a, b)
		assert(post == a or post == b)
		assert(not posts.has(post))
		posts[post] = true
	var width: int = game.MAP_WIDTH
	var height: int = game.MAP_HEIGHT
	assert(posts.size() == 2 * (width + height))
	for corner in [Vector2.ZERO, Vector2(width, 0), Vector2(width, height), Vector2(0, height)]:
		assert(posts.has(corner))
	assert(_move(game, Vector2(5.5, height - 0.2), Vector2(0, 0.4)).y < height)
	assert(_dive(game, Vector2(5.5, height - 0.2), KEY_S).y < height)
	game.active_projectiles.clear()
	game.active_wall_bullet_holes.clear()
	_spawn_standing_shot(game, Vector2(5.5, height - 0.55), PI)
	game._process_combat(0.10)
	assert(game.active_projectiles.size() == 1 and game.active_projectiles[0]["position"].y > height)
	game._process_combat(0.15)
	assert(game.active_projectiles.size() == 1 and game.active_projectiles[0]["position"].y > height + 1.0)
	for step in 14:
		game._process_combat(0.10)
	assert(game.active_projectiles.is_empty() and game.active_wall_bullet_holes.is_empty())


func _test_window(game: Node) -> void:
	var pane_lane := _coffee(2.31, -0.30)
	var frame_lane := _coffee(2.05, -0.30)
	var height := 0.28
	assert(game._nearest_projectile_wall_distance(pane_lane, Vector2.DOWN, 0.6, height) < 0.6)
	var shot := {"owner": 0, "direction": Vector2.DOWN, "lifetime": 1.0, "height": 0.68, "storefront_world_height": height}
	shot["position"] = frame_lane
	game.active_projectiles.append(shot)
	game._process_combat(0.1)
	assert(not game.storefront_glass_broken)
	var previous_joined: Array = game.player_joined.duplicate()
	var previous_player_two_joined: bool = game.player_two_joined
	var previous_target: Dictionary = game.player_states[1].duplicate(true)
	game.player_joined.fill(false)
	game.player_joined[0] = true
	game.player_joined[1] = true
	game.player_two_joined = true
	var target: Dictionary = game.player_states[1]
	target["world_position"] = _coffee(2.23, 0.40)
	target["grid_position"] = Vector2i(2, int(coffee_front))
	target["character_is_crouching"] = false
	target["dive_active"] = false
	target["is_dying"] = false
	target["health"] = 3
	var shooter := _coffee(2.273, -0.25)
	var standing_shot := _spawn_standing_shot(game, shooter, PI)
	assert(absf(float(standing_shot["storefront_world_height"]) - game.town_walk_height(shooter) - 0.31) < 0.012)
	game._process_combat(0.1)
	assert(game.storefront_glass_broken and int(game.player_states[1]["health"]) == 3)
	assert(game.active_wall_debris.any(func(shard: Dictionary) -> bool: return shard.get("glass_fragment", false)))
	_spawn_standing_shot(game, shooter, PI)
	game._process_combat(0.1)
	assert(int(game.player_states[1]["health"]) == 2)
	game.player_states[1] = previous_target
	game.player_joined = previous_joined
	game.player_two_joined = previous_player_two_joined
	assert(game._nearest_projectile_wall_distance(pane_lane, Vector2.DOWN, 0.6, height) > 0.6)
	assert(game._nearest_projectile_wall_distance(pane_lane, Vector2.DOWN, 0.6, 0.345) > 0.6)
	assert(game._nearest_projectile_wall_distance(pane_lane, Vector2.DOWN, 0.6, 0.38) > 0.6)
	assert(game._nearest_projectile_wall_distance(frame_lane, Vector2.DOWN, 0.6, height) < 0.6)
	assert(game._nearest_projectile_wall_distance(pane_lane, Vector2.DOWN, 0.6, 0.18) < 0.6)
	var porch_lane := _coffee(2.23, -0.70)
	var style: Resource = game.STOREFRONT_STYLE
	var rail_top: float = style.porch_rail_top()
	assert(game._nearest_projectile_wall_distance(porch_lane, Vector2.DOWN, 0.6, rail_top + 0.02) > 0.6)
	assert(game._nearest_projectile_wall_distance(porch_lane, Vector2.DOWN, 0.6, rail_top - style.porch_handrail_section.y * 0.5) < 0.6)
	assert(_move(game, pane_lane, Vector2(0.0, 0.6), false).y < coffee_front)


func _spawn_standing_shot(game: Node, position: Vector2, yaw: float) -> Dictionary:
	game._bind_player_context(0)
	game._set_player_world_position_for_current_view(position)
	game.continuous_camera_yaw = yaw
	game.character_is_crouching = false
	game._save_player_context(0)
	game.player_views[0]["player_sprite"].animation = &"IdleN"
	game.player_states[0]["pistol_ammo"] = 6
	game.aim_assist_enabled = false
	game._spawn_pistol_shot(0)
	return game.active_projectiles.back()
