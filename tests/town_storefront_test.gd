extends SceneTree

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
	assert(rect.size == Vector2i(1, 2))
	assert(game.town_has_roof(rect.position) and game.town_has_roof(rect.end - Vector2i.ONE))
	assert(not game.town_has_roof(rect.position + Vector2i.RIGHT))
	assert(is_equal_approx(game.town_walk_height(Vector2(2.65, 7.8)), style.porch_height))
	assert(is_zero_approx(game.town_walk_height(Vector2(2.35, 10.2))))
	assert(is_equal_approx(game.town_walk_height(Vector2(2.65, 8.2)), style.porch_height))
	assert(game.storefront_open_doors.is_empty())
	assert(_move(game, Vector2(2.65, 7.7), Vector2(0, 0.6), false).y < 8.0)
	assert(game.storefront_open_doors.is_empty())
	assert(style.roof_height(8.0) > style.roof_height(10.0))
	_move(game, Vector2(2.65, 7.7), Vector2(0, 0.6))
	game._advance_storefront_doors(0.08)
	assert(float(game.storefront_open_doors["front"]) > 0.0 and float(game.storefront_open_doors["front"]) < 1.0)
	game._advance_storefront_doors(0.25)
	assert(_move(game, Vector2(2.65, 7.7), Vector2(0, 0.6)).y > 8.0)
	assert(game.storefront_open_doors.has("front") and not game.storefront_open_doors.has("rear"))
	assert(_move(game, Vector2(2.25, 7.7), Vector2(0, 0.6)).y < 8.0)
	assert(_move(game, Vector2(2.25, 7.25), Vector2(0, 0.45)).y < 7.53)
	_move(game, Vector2(2.5, 9.7), Vector2(0, 0.6))
	game._advance_storefront_doors(0.25)
	assert(_move(game, Vector2(2.5, 9.7), Vector2(0, 0.6)).y > 10.0)
	assert(game.storefront_open_doors.has("rear"))
	assert(_move(game, Vector2(2.15, 9.7), Vector2(0, 0.6)).y < 10.0)
	assert(_move(game, Vector2(2.5, 9.5), Vector2(0.7, 0)).x < 3.0)
	# Pushing toward the closing side of the open front leaf reverses its swing.
	_move(game, Vector2(2.66, 8.26), Vector2(0.17, 0.0))
	assert(not game.storefront_closing_doors.has("front"))
	_move(game, Vector2(2.895, 8.30), Vector2(-0.25, 0.0))
	assert(game.storefront_closing_doors.has("front"))
	game._advance_storefront_doors(0.25)
	assert(not game.storefront_open_doors.has("front"))
	assert(_move(game, Vector2(2.65, 7.7), Vector2(0, 0.6), false).y < 8.0)
	_test_dive_roll_doors(game)
	_test_window(game)
	_test_dive_vaults(game)
	_test_furnishing_clearance(game)
	_test_footstep_surfaces(game)
	var renderer: Node = game.get_node("CoordinateFrameRuntimeRendererP1")
	assert(renderer.storefront_planes.size() == 3)
	var floor_material: ShaderMaterial = renderer.storefront_planes[1].material
	assert(floor_material.get_shader_parameter("use_semantic_floor_material"))
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
	assert(_move(game, Vector2(style.door_frame_center(true).x, 7.3), Vector2.DOWN * 0.4, false).y > 7.67)
	_test_fence(game, renderer)
	print("Storefront checks passed")
	quit()


func _move(game: Node, position: Vector2, delta: Vector2, push := true) -> Vector2:
	return game._move_world_with_wall_slide(position, delta, "E", "W", "S", "N", push)


func _test_dive_roll_doors(game: Node) -> void:
	assert(not game.storefront_open_doors.has("front"))
	var entered := _dive(game, Vector2(2.65, 7.68), KEY_S)
	assert(game.storefront_open_doors.has("front"))
	assert(entered.y > 8.12)
	_dive(game, Vector2(2.895, 8.30), KEY_A)
	assert(not game.storefront_open_doors.has("front"))
	assert(not game.storefront_closing_doors.has("front"))

	game.storefront_closing_doors["rear"] = true
	game._advance_storefront_doors(0.25)
	assert(not game.storefront_open_doors.has("rear"))
	var entered_from_rear := _dive(game, Vector2(2.50, 10.34), KEY_W)
	assert(game.storefront_open_doors.has("rear"))
	assert(entered_from_rear.y < 9.88)


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
	var crate := {"id": -100, "position": Vector2(5.75, 6.6), "half_extents": Vector2(0.08, 0.08), "vault_height": 0.16}
	game.world_barrels.append(crate)
	var start := Vector2(5.75, 6.31)
	assert(_move(game, start, Vector2(0, 0.6)).y < 6.6)
	assert(_dive(game, start, KEY_S).y > 6.80)
	crate["vault_height"] = 0.24
	assert(_dive(game, start, KEY_S).y < 6.6)
	game.world_barrels.erase(crate)

	game.storefront_glass_broken = false
	var window_start := Vector2(2.23, 7.69)
	assert(_dive(game, Vector2(2.405, 7.69), KEY_S).y < 8.0)
	assert(not game.storefront_glass_broken)
	assert(_dive(game, window_start, KEY_S).y > 8.12)
	assert(game.storefront_window_vaulted and game.storefront_glass_broken)
	assert(game._nearest_projectile_wall_distance(Vector2(2.23, 8.2), Vector2.UP, 0.6, 0.38) > 0.6)
	assert(_move(game, Vector2(2.23, 8.25), Vector2.UP * 0.45).y >= 8.09)
	assert(_dive(game, Vector2(2.23, 8.27), KEY_W).y < 7.86)


func _test_furnishing_clearance(game: Node) -> void:
	var dining_pieces: Array = game.semantic_lod_floor_footprints.filter(func(piece: Dictionary) -> bool: return piece.has("dining_set_id"))
	assert(dining_pieces.size() == 3)
	assert(_move(game, Vector2(2.65, 7.68), Vector2(-0.41, 0)).x < 2.25)
	assert(_move(game, Vector2(2.24, 7.68), Vector2(0, 0.25)).y < 7.84)
	assert(_move(game, Vector2(2.24, 8.43), Vector2(0, 0.72)).y < 8.73)
	assert(_move(game, Vector2(2.53, 8.50), Vector2(0, 1.05)).y > 9.54)


func _test_footstep_surfaces(game: Node) -> void:
	assert(game._footstep_surface(Vector2(2.65, 7.45)) == "Dirt")
	assert(game._footstep_surface(Vector2(2.65, 7.70)) == "Wood")
	assert(game._footstep_surface(Vector2(2.65, 8.25)) == "Wood")
	assert(game._footstep_surface(Vector2(2.50, 3.50)) == "Wood")
	assert(game._footstep_surface(Vector2(2.50, 10.30)) == "Dirt")

	for kind in game.FOOTSTEP_KINDS:
		assert(game._play_actor_surface_sound(0, kind, Vector2(2.65, 7.45)))
		var channel: Dictionary = game._footstep_channel(0)
		assert("/Dirt/" in channel["player"].stream.resource_path)
		assert(game._play_actor_surface_sound(0, kind, Vector2(2.65, 7.70)))
		assert("/Wood/" in channel["player"].stream.resource_path)

	game.footstep_last_samples.clear()
	_dive(game, Vector2(2.65, 7.29), KEY_S)
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
	var pane_lane := Vector2(2.31, 7.70)
	var frame_lane := Vector2(2.05, 7.70)
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
	target["world_position"] = Vector2(2.23, 8.4)
	target["grid_position"] = Vector2i(2, 8)
	target["character_is_crouching"] = false
	target["dive_active"] = false
	target["is_dying"] = false
	target["health"] = 3
	var shooter := Vector2(2.273, 7.75)
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
	var porch_lane := Vector2(2.23, 7.3)
	var style: Resource = game.STOREFRONT_STYLE
	var rail_top: float = style.porch_rail_top()
	assert(game._nearest_projectile_wall_distance(porch_lane, Vector2.DOWN, 0.6, rail_top + 0.02) > 0.6)
	assert(game._nearest_projectile_wall_distance(porch_lane, Vector2.DOWN, 0.6, rail_top - style.porch_handrail_section.y * 0.5) < 0.6)
	assert(_move(game, pane_lane, Vector2(0.0, 0.6), false).y < 8.0)


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
