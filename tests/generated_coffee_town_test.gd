extends SceneTree

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://generated_coffee_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	var layout: GeneratedTown = game.generated_town
	assert(layout.size == Vector2i(14, 14))
	assert(layout.prototype.FOOTPRINT == Rect2i(1, 11, 1, 2))
	assert(is_equal_approx(layout.prototype.porch_depth, game.LEGACY_STOREFRONT_STYLE.porch_depth))
	assert(game.LEGACY_STOREFRONT_STYLE.FOOTPRINT == Rect2i(1, 6, 1, 2))
	var copy: Resource = layout.prototype_copy
	assert(copy.get_script() == layout.prototype.get_script())
	assert(copy.FOOTPRINT == Rect2i(3, 11, 1, 2))
	assert(copy.porch_rect() == Rect2(3, 10, 1, 1))
	var shift := Vector2(2, 0)
	var original_faces: Array = layout.prototype.footprint_faces()
	var copied_faces: Array = copy.footprint_faces()
	for index in original_faces.size():
		var original: Dictionary = original_faces[index]
		var duplicate: Dictionary = copied_faces[index]
		assert(duplicate["a"] == original["a"] + shift and duplicate["b"] == original["b"] + shift)
		assert(duplicate.get("doorway") == original.get("doorway") and duplicate.get("window") == original.get("window"))
	var original_leaves: Array = layout.prototype.door_leaf_spans({})
	var copy_leaves: Array = copy.door_leaf_spans({})
	for index in original_leaves.size():
		var leaf: Dictionary = copy_leaves[index]
		assert(Vector2(leaf["a"]).is_equal_approx(original_leaves[index]["a"] + shift))
		assert(Vector2(leaf["b"]).is_equal_approx(original_leaves[index]["b"] + shift))
		assert(leaf["paint"] == original_leaves[index]["paint"] and leaf["push_door"] != original_leaves[index]["push_door"])

	assert(layout.buildings.size() == 5)
	var gable := layout.buildings[0]
	var hall := layout.buildings[3]
	var east_shop := layout.buildings[4]
	assert(gable.blueprint_gable and gable.footprint == Rect2i(5, 11, 1, 2))
	assert(gable.footprint.position.x - copy.FOOTPRINT.end.x == 1)
	assert(gable.porch() == Rect2(5, 10.5, 1, 0.5))
	assert(is_equal_approx(gable.door_x(), 5.725))
	var gable_leaves := gable.door_leaf_spans({})
	var front_leaf := gable_leaves[0]
	var rear_leaf := gable_leaves[1]
	assert(Vector2(front_leaf["a"]).x > Vector2(front_leaf["b"]).x)
	assert(Vector2(rear_leaf["a"]).x < Vector2(rear_leaf["b"]).x)
	assert(front_leaf["gable_knob_normal"] == Vector2.UP and rear_leaf["gable_knob_normal"] == Vector2.DOWN)
	assert(front_leaf["gable_knob_uv"] == gable.coffee_kit.gable_front_knob)
	assert(rear_leaf["gable_knob_uv"] == gable.coffee_kit.gable_rear_knob)
	var open_leaves := gable.door_leaf_spans({front_leaf["push_door"]: 1.0})
	assert(Vector2(open_leaves[0]["b"]).y > gable.frontage())
	assert(open_leaves[0]["gable_knob_normal"] != front_leaf["gable_knob_normal"])
	assert(gable.roof_planes().size() == 4)
	assert(gable.roof_planes()[0]["heights"] == Vector2(gable.eave, gable.eave + gable.rise))
	assert(gable.roof_planes()[1]["heights"] == Vector2(gable.eave + gable.rise, gable.eave))
	assert(gable.ground_windows("west").is_empty() and gable.ground_windows("rear").is_empty())
	assert(hall.footprint == Rect2i(1, 1, 6, 6))
	assert(hall.porch() == Rect2(1, 7, 6, 1))
	assert(east_shop.footprint == Rect2i(8, 5, 4, 2) and east_shop.faces_south)
	assert(east_shop.porch() == Rect2(8, 7, 4, 1))
	assert(hall.exterior_door_cells().size() == 4)
	assert(hall.partition_doors.size() == 10 and hall.partition_edges().size() > 8)
	assert(hall.ground_windows("front").size() == 10)
	assert(hall.ground_windows("west").size() == 5)
	assert(hall.ground_windows("east").size() == 5)
	assert(hall.ground_windows("rear").size() == 2)
	var previous_end := gable.footprint.end.x
	for index in 2:
		var shop := layout.buildings[index + 1]
		assert(shop.footprint.size == Vector2i(index + 2, 2))
		assert(shop.footprint.position.x - previous_end == 1)
		assert(shop.porch() == Rect2(shop.footprint.position.x, 10, index + 2, 1))
		previous_end = shop.footprint.end.x
	for shop in [layout.buildings[1], layout.buildings[2], east_shop]:
		assert(shop.exterior_door_cells().size() == 2)
		assert(shop.ground_windows("front").size() == (shop.footprint.size.x - 1) * 2)
		assert(shop.ground_windows("rear").size() == (shop.footprint.size.x - 1) * 2)
		assert(shop.ground_windows("west").size() == 4 and shop.ground_windows("east").size() == 4)
	for shop in layout.buildings:
		assert(not shop.step_bounds().has_area())
		var apron_bottom: float = copy.apron_bottom()
		var apron_members: Array = shop.porch_members().filter(func(member: Dictionary) -> bool:
			return is_equal_approx(member["bottom"], apron_bottom) and is_equal_approx(member["variant"]["top"], copy.porch_height))
		assert(apron_members.size() == 4)
		for leaf in shop.door_leaf_spans({}):
			assert(leaf["paint"] == 3 and is_equal_approx(Vector2(leaf["a"]).distance_to(leaf["b"]), shop.door_half_width() * 2.0))

	var visited := {layout.spawn: true}
	var pending: Array[Vector2i] = [layout.spawn]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for delta in DIRECTIONS:
			var neighbor := cell + delta
			if not visited.has(neighbor) and game._can_cross_edge(cell, delta):
				visited[neighbor] = true
				pending.append(neighbor)
	assert(visited.size() == layout.size.x * layout.size.y, "The street, outside loop and all rooms must connect.")

	for shop: TownBuildingStyle in [hall, gable]:
		for door in shop.exterior_door_cells():
			var door_span := shop.door_edge(door)
			var midpoint := door_span[0].lerp(door_span[1], shop.door_offset())
			var outward := Vector2(door.z, door.w)
			var approach := midpoint + outward * 0.27
			game._move_world_with_wall_slide(approach, -outward * 0.50, "e", "w", "s", "n", true)
			assert(game.storefront_open_doors.has("exterior_%s" % door))
			game._advance_storefront_doors(0.25)
			var exit: Vector2 = game._move_world_with_wall_slide(approach, -outward * 0.57, "e", "w", "s", "n", true)
			assert((exit - midpoint).dot(outward) < -0.12, "Generated exterior door failed to clear the opening.")

	var copied_pane: Dictionary = game._all_physical_wall_edges().filter(func(edge: Dictionary) -> bool:
		return edge.get("storefront_style") == copy and edge.get("window", false))[0]
	var copied_pane_point := Vector2(copied_pane["a"]).lerp(copied_pane["b"], 0.5)
	assert(game._try_break_storefront_glass(copied_pane["key"], copied_pane_point, Vector2.DOWN, 0.33))
	assert(game.town_storefront_glass_broken(copy) and not game.town_storefront_glass_broken(layout.prototype))

	var window_key := ""
	for key: String in game.town_window_edges:
		var pane: Dictionary = game.town_window_edges[key]
		if pane.has("more"):
			window_key = key
			break
	assert(not window_key.is_empty())
	var two_panes: Dictionary = game.town_window_edges[window_key]
	var second: Dictionary = two_panes["more"][0]
	var window_edge: Dictionary = game._all_physical_wall_edges().filter(func(edge: Dictionary) -> bool: return edge.key == window_key)[0]
	var first_point := Vector2(window_edge["a"])
	var second_point := first_point
	first_point[two_panes["axis"]] = Rect2(two_panes["aperture"]).get_center().x
	second_point[second["axis"]] = Rect2(second["aperture"]).get_center().x
	assert(game.town_window_has_opening(window_edge, first_point, 0.33))
	assert(game.town_window_has_opening(window_edge, second_point, 0.33))
	assert(game._try_break_storefront_glass(window_key, second_point, Vector2.UP, 0.33))
	assert(not game._projectile_edge_blocks_at_height(window_edge, second_point, 0.33))
	assert(game._projectile_edge_blocks_at_height(window_edge, first_point, 0.33))
	var gable_pane: Dictionary = game._all_physical_wall_edges().filter(func(edge: Dictionary) -> bool:
		return edge.get("town_window", {}).get("id", "") == gable.window_id(0))[0]
	var gable_window_point := Vector2(gable.ground_windows()[0].get_center().x, gable.frontage())
	assert(game.town_window_has_opening(gable_pane, gable_window_point, 0.425))
	var gable_vault: Dictionary = game._dive_town_edge_vault(gable_window_point + Vector2.UP * 0.25, Vector2.DOWN, 0.8)
	assert(gable_vault.get("window_id") == gable.window_id(0))
	assert(game._projectile_edge_blocks_at_height(gable_pane, gable_window_point, 0.425))
	assert(game._try_break_storefront_glass(gable_pane["key"], gable_window_point, Vector2.DOWN, 0.425))
	assert(not game._projectile_edge_blocks_at_height(gable_pane, gable_window_point, 0.425))

	var cover_count := 0
	var room_furniture := 0
	for prop: Dictionary in game.semantic_lod_floor_footprints:
		if prop.get("town_cover", false):
			cover_count += 1
		if prop.get("dining_set_spawn", false) and Rect2(hall.footprint).has_point(prop["position"]):
			room_furniture += 1
	assert(cover_count >= 10 and room_furniture == 12, "Town spawned %d cover props and %d pieces of room furniture." % [cover_count, room_furniture])

	var renderer: Node = game.coordinate_renderers[0]
	assert(renderer.town_roof_bounds.size() == 8)
	assert(renderer.town_porch_supports[east_shop]["count"] == 5)
	assert(renderer.town_porch_supports[hall]["count"] == 7)
	assert(renderer.storefront_planes.size() == 6)
	var roofs: Array[Rect2i] = game.town_roof_rects()
	for index in roofs.size():
		var has_flat_ceiling: bool = game.town_has_ceiling(roofs[index].position)
		assert(bool(renderer.town_ceiling_mask & (1 << index)) == has_flat_ceiling)
	assert(game.town_has_ceiling(hall.footprint.position))
	assert(game.town_has_roof(gable.footprint.position) and not game.town_has_ceiling(gable.footprint.position))
	assert(not game.town_has_ceiling(copy.FOOTPRINT.position))
	var copy_roof := renderer.storefront_planes[3].material as ShaderMaterial
	assert(copy_roof.get_shader_parameter("town_ceiling_mask") == renderer.town_ceiling_mask)
	var hall_floor: ShaderMaterial
	for index in renderer.town_variant_plane_specs.size():
		var specification: Dictionary = renderer.town_variant_plane_specs[index]
		if specification["style"] == hall and specification.get("wood", false):
			hall_floor = renderer.town_variant_planes[index].material as ShaderMaterial
			break
	assert(hall_floor != null)
	renderer.set_depth_dither_matrix_size(4)
	assert(hall_floor.get_shader_parameter("floor_light_dither_matrix_size") == 4)
	assert(not game.town_room_shading_enabled)
	for plane in renderer.storefront_planes + renderer.town_variant_planes:
		assert(not plane.material.get_shader_parameter("use_town_room_shading"))
	game.storefront_open_doors.erase("exterior_(4, 6, 0, 1)")
	renderer._update_storefront_planes()
	assert(is_zero_approx(hall_floor.get_shader_parameter("floor_door_open_fraction")))
	game.storefront_open_doors["exterior_(4, 6, 0, 1)"] = 1.0
	renderer._update_storefront_planes()
	assert(is_equal_approx(hall_floor.get_shader_parameter("floor_door_open_fraction"), 1.0))
	var overlay_key := InputEventKey.new()
	overlay_key.pressed = true
	overlay_key.keycode = KEY_F5
	game._input(overlay_key)
	assert(not game.show_town_wall_carriers and game.town_room_shading_enabled)
	assert(hall_floor.get_shader_parameter("use_town_room_shading"))
	game._input(overlay_key)
	assert(not game.town_room_shading_enabled and not hall_floor.get_shader_parameter("use_town_room_shading"))
	overlay_key.keycode = KEY_F1
	game._input(overlay_key)
	assert(game.show_town_wall_carriers)
	game._input(overlay_key)
	assert(not game.show_town_wall_carriers)
	# The same back wall receives street haze only for the uncovered ray.
	var back_wall := Vector2(4.5, 1.0)
	assert(is_equal_approx(renderer.town_outdoor_depth(Vector2(4.5, 9.0), back_wall, 8.0), 2.0))
	assert(is_zero_approx(renderer.town_outdoor_depth(Vector2(4.5, 6.0), back_wall, 5.0)))
	# Looking out retains the uncovered distance beyond the doorway.
	assert(is_equal_approx(renderer.town_outdoor_depth(Vector2(4.5, 6.0), Vector2(4.5, 9.0), 3.0), 2.0))
	# A closed movable leaf lies on the facade line but must use the Coffee
	# door material, with a leaf-sized carrier rather than a wall-height one.
	game.storefront_open_doors.clear()
	game.physical_wall_edges_cache_dirty = true
	game.player_states[0]["world_position"] = Vector2(4.47, 8.85)
	game.player_states[0]["grid_position"] = Vector2i(4, 8)
	game.player_states[0]["continuous_camera_yaw"] = 0.0
	game._render_all_player_views()
	var hall_doors: Array = renderer.last_wall_entries.filter(func(entry: Dictionary) -> bool:
		return (entry["generated_door"] and is_equal_approx(Vector2(entry["world_a"]).y, hall.frontage())
			and Rect2(hall.footprint).grow(0.01).has_point(entry["world_a"])))
	assert(hall_doors.size() == 1)
	assert(hall_doors[0]["storefront_paint"] == 3 and hall_doors[0]["variant"].is_empty())
	assert(Vector2(hall_doors[0]["face_top"]).is_equal_approx(Vector2.ONE * copy.DOOR_TOP))
	assert(not game.town_waves_enabled)
	game._set_town_waves_enabled(true)
	game._advance_town_waves(5.1)
	assert(game.town_wave_active and game._living_enemy_count() == 3)
	print("Generated Coffee Town layout, doors, paired windows, furnishings and waves passed")
	scene.queue_free()
	quit()
