extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var level := (load("res://coordinate_frame_navigation.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await create_timer(0.8).timeout
	var game = level.get_node("CoordinateFrameGame")
	game.set_process(false)
	game.bots_enabled = false
	for index in range(1, game.player_joined.size()):
		game.player_joined[index] = false
	game._bind_player_context(0)
	game.continuous_camera_yaw = 0.0
	game.facing = 0
	var origin := Vector2.ZERO
	var found := false
	for y in range(game.MAP_HEIGHT):
		for x in range(game.MAP_WIDTH):
			var candidate := Vector2(x + 0.5, y + 0.5)
			if game._is_open_cell(Vector2i(x, y)) and game._nearest_projectile_wall_distance(candidate, Vector2.UP, 1.2) > 1.2:
				origin = candidate
				found = true
				break
		if found:
			break
	if not found:
		push_error("No open lane for barrel test")
		quit(1)
		return
	game._set_player_world_position_for_current_view(origin)
	game.character_is_moving = false
	game._save_player_context(0)
	game.player_states[0]["character_is_crouching"] = true
	var sprite: AnimatedSprite2D = game.player_views[0]["player_sprite"]
	sprite.animation = &"CrouchIdleN"
	var muzzle: Dictionary = game._world_muzzle_anchor(0, origin, Vector2.UP, &"right")
	var barrel_position := Vector2(Vector2(muzzle["position"]).x, origin.y - 0.9)
	game.world_barrels.clear()
	game.world_coins.clear()
	game.world_hearts.clear()
	game.world_barrel_guns.clear()
	game.world_barrels.append({"id": 999999, "position": barrel_position})
	var failures: Array[String] = []
	seed(7469)
	for hit in range(1, 4):
		if hit == 3: seed(88)
		game._spawn_pistol_shot(0)
		for step in range(12):
			game._process_combat(0.015)
		if hit == 1:
			game._bind_player_context(0)
			game._render_bound_player_context()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("xybots_barrel_small_splinters.png"))
			# Compare the same live frame with and without the contrast treatment.
			var nodes: Dictionary = game.player_views[0]["combat_nodes"]
			var changed: Array[Dictionary] = []
			var hidden_smoke: Array[Sprite2D] = []
			for key in nodes:
				var node: Sprite2D = nodes[key]
				if node.visible and (String(key).begins_with("muzzle_smoke_") or String(key).begins_with("wall_smoke_")):
					node.visible = false
					hidden_smoke.append(node)
			for debris in game.active_wall_debris:
				if not bool(debris.get("barrel_hit", false)) or bool(debris.get("barrel_fragment", false)): continue
				var node: Sprite2D = nodes.get("wall_debris_%d" % int(debris["id"]))
				if node == null or not node.visible: continue
				changed.append({"node": node, "texture": node.texture, "color": node.self_modulate})
				var palette: Array[Color] = game._barrel_surface_colors_for_current_view(debris)
				var original: Color = palette[int(debris["color_sample_index"]) % 4]
				original.a = node.self_modulate.a
				node.self_modulate = original
				node.texture = game._wall_debris_shape_texture(String(debris["shape"]))
			await RenderingServer.frame_post_draw
			var before_image := root.get_texture().get_image()
			before_image.save_png(OS.get_environment("TEMP").path_join("xybots_barrel_small_contrast_before.png"))
			for state in changed:
				state["node"].texture = state["texture"]
				state["node"].self_modulate = state["color"]
			await RenderingServer.frame_post_draw
			var after_image := root.get_texture().get_image()
			after_image.save_png(OS.get_environment("TEMP").path_join("xybots_barrel_small_contrast_after.png"))
			if changed.is_empty() or before_image.get_data() == after_image.get_data():
				failures.append("Small splinter contrast did not change the rendered frame")
			var barrel_sprite: Sprite2D = nodes.get("barrel_999999")
			if barrel_sprite == null or changed.is_empty() or changed[0]["node"].z_index <= barrel_sprite.z_index:
				failures.append("Front-facing hit splinters were drawn behind the barrel")
			for node in hidden_smoke: node.visible = true
			print("Small splinters compared: ", changed.size())
		if hit < 3 and (game.world_barrels.size() != 1 or int(game.world_barrels[0].get("hits", 0)) != hit):
			failures.append("Barrel did not retain the expected hit count %d" % hit)
		if hit == 3 and (not game.world_barrels.is_empty() or not game._barrel_sweep_hit(origin, Vector2.UP).is_empty()):
			failures.append("Third shot did not remove barrel and its collision")
	var break_loot: Array = game.world_coins + game.world_hearts + game.world_barrel_guns
	if break_loot.is_empty() or not break_loot.any(func(item): return Vector2(item["position"]).distance_to(barrel_position) > 0.01 and bool(item.get("loot_airborne", false))):
		failures.append("Actual barrel break did not throw a visible pickup")
	if game.active_wall_debris.filter(func(d): return bool(d.get("barrel_fragment", false))).size() != 14:
		failures.append("Break did not spawn its 14 wood and metal chunks")
	if game.active_wall_impact_smokes.size() < 5:
		failures.append("Break smoke was not spawned")
	for hole in game.active_wall_bullet_holes:
		if int(hole.get("barrel_id", -1)) == 999999:
			failures.append("Broken barrel left a floating bullet hole")
	game.active_muzzle_smoke_particles.clear() # Isolate material dust from the shooter's separate muzzle smoke.
	game._bind_player_context(0)
	game._render_bound_player_context()
	await process_frame
	var image_path := OS.get_environment("TEMP").path_join("xybots_barrel_break_test.png")
	root.get_texture().get_image().save_png(image_path)
	# Inspect the real renderer's material and sprite colors, not just the sampler.
	var visible_smoke := 0
	var visible_debris := 0
	var nodes: Dictionary = game.player_views[0]["combat_nodes"]
	for smoke in game.active_wall_impact_smokes:
		if not bool(smoke.get("barrel_hit", false)): continue
		var node: Sprite2D = nodes.get("wall_smoke_%d" % int(smoke["id"]))
		if node == null or not node.visible: continue
		visible_smoke += 1
		var palette: Array[Color] = game._barrel_surface_colors_for_current_view(smoke)
		var expected: Color = palette[int(smoke["color_sample_index"]) % 4]
		var actual: Color = node.material.get_shader_parameter("tint_color")
		expected.a = actual.a
		if not expected.is_equal_approx(actual): failures.append("Barrel smoke did not use its surface sample")
	for debris in game.active_wall_debris:
		if not bool(debris.get("barrel_hit", false)): continue
		var node: Sprite2D = nodes.get("wall_debris_%d" % int(debris["id"]))
		if node == null or not node.visible: continue
		visible_debris += 1
		if not bool(debris.get("barrel_fragment", false)):
			var extremes: Array[Color] = game._barrel_small_splinter_palette()
			var mask := node.texture.get_image()
			for y in range(mask.get_height()):
				for x in range(mask.get_width()):
					var color := mask.get_pixel(x, y)
					if color.a > 0.01 and not color.is_equal_approx(extremes[0]) and not color.is_equal_approx(extremes[1]):
						failures.append("Small splinter has a color outside the barrel extremes")
			if not is_equal_approx(node.self_modulate.r, 1.0) or not is_equal_approx(node.self_modulate.g, 1.0) or not is_equal_approx(node.self_modulate.b, 1.0):
				failures.append("Small splinter colors were tinted away from the palette")
		else:
			var palette: Array[Color] = game._barrel_surface_colors_for_current_view(debris)
			var expected: Color = palette[int(debris["color_sample_index"]) % 4]
			expected.a = node.self_modulate.a
			if not expected.is_equal_approx(node.self_modulate): failures.append("Large barrel splinter did not use its surface sample")
	if visible_smoke == 0 or visible_debris == 0:
		failures.append("Could not inspect visible barrel smoke and splinters")
	# Substitute a synthetic recolored source in memory, forcing the real renderer
	# to show that both effect types follow the current sprite rather than constants.
	var texture: Texture2D = game._barrel_texture_for_current_camera()
	var texture_id := texture.get_instance_id()
	var original_image: Image = game.barrel_source_images[texture_id]
	var actual_extremes: Array[Color] = game._barrel_small_splinter_palette()
	for y in range(original_image.get_height()):
		for x in range(original_image.get_width()):
			var source_color := original_image.get_pixel(x, y)
			if source_color.a < 0.99: continue
			if source_color.get_luminance() < actual_extremes[0].get_luminance() - 0.0001 or source_color.get_luminance() > actual_extremes[1].get_luminance() + 0.0001:
				failures.append("Small splinter palette did not use the PNG's darkest and lightest colors")
	var recolored := original_image.duplicate() as Image
	var cyan := Color(0.1, 0.8, 0.9, 1.0)
	for y in range(recolored.get_height()):
		for x in range(recolored.get_width()):
			if recolored.get_pixel(x, y).a > 0.01: recolored.set_pixel(x, y, cyan)
	game.barrel_source_images[texture_id] = recolored
	game.barrel_surface_color_cache.clear()
	game.barrel_small_splinter_palettes.clear()
	game.barrel_small_splinter_textures.clear()
	game.wall_debris_color_cache.clear()
	game.wall_debris_render_cache.clear()
	game.wall_impact_smoke_render_cache.clear()
	game._render_bound_player_context()
	await process_frame
	var recolored_smoke := 0
	var recolored_debris := 0
	for smoke in game.active_wall_impact_smokes:
		if not bool(smoke.get("barrel_hit", false)): continue
		var node: Sprite2D = nodes.get("wall_smoke_%d" % int(smoke["id"]))
		if node == null or not node.visible: continue
		var actual: Color = node.material.get_shader_parameter("tint_color")
		if absf(actual.g - 0.8) < 0.01 and absf(actual.b - 0.9) < 0.01: recolored_smoke += 1
	for debris in game.active_wall_debris:
		if not bool(debris.get("barrel_hit", false)): continue
		var node: Sprite2D = nodes.get("wall_debris_%d" % int(debris["id"]))
		if node == null or not node.visible: continue
		var rendered_color: Color = node.texture.get_image().get_pixel(1, 1) if not bool(debris.get("barrel_fragment", false)) else node.self_modulate
		if absf(rendered_color.g - 0.8) < 0.01 and absf(rendered_color.b - 0.9) < 0.01: recolored_debris += 1
	if recolored_smoke != visible_smoke or recolored_debris != visible_debris:
		failures.append("Effects did not follow a changed barrel source palette")
	game.barrel_source_images[texture_id] = original_image
	game.barrel_surface_color_cache.clear()
	game.barrel_small_splinter_palettes.clear()
	game.barrel_small_splinter_textures.clear()
	game.wall_debris_color_cache.clear()
	game.wall_debris_render_cache.clear()
	game.wall_impact_smoke_render_cache.clear()
	print("Visible barrel smoke=", visible_smoke, " debris=", visible_debris, " recolored=", recolored_smoke, "/", recolored_debris)
	var saw_settled := false
	for step in range(90):
		game._process_combat(0.01)
		var fragments: Array = game.active_wall_debris.filter(func(d): return bool(d.get("barrel_fragment", false)))
		for fragment in fragments:
			if bool(fragment.get("settled", false)):
				saw_settled = true
				if not is_equal_approx(float(fragment["ground_fade_seconds"]), 2.0 * game.WALL_DEBRIS_NEAR_GROUND_FADE_SECONDS):
					failures.append("Ground lifetime is not twice the near wall splinter lifetime")
		if step == 45:
			game._bind_player_context(0)
			game._render_bound_player_context()
			await process_frame
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("xybots_barrel_debris_ground_test.png"))
	if not saw_settled:
		failures.append("No barrel fragments reached the ground")
	for step in range(130):
		game._process_combat(0.01)
	if not game.active_wall_debris.filter(func(d): return bool(d.get("barrel_fragment", false))).is_empty():
		failures.append("Barrel fragments did not expire after landing")
	var item_counts := [0, 0, 0]
	var empty_count := 0
	var multi_count := 0
	var mixed_count := 0
	seed(1248)
	for i in range(10000):
		game.world_coins.clear()
		game.world_hearts.clear()
		game.world_barrel_guns.clear()
		game._drop_barrel_loot(barrel_position)
		var counts := [game.world_coins.size(), game.world_hearts.size(), game.world_barrel_guns.size()]
		for kind in range(3):
			item_counts[kind] += counts[kind]
		var total: int = counts[0] + counts[1] + counts[2]
		if total == 0: empty_count += 1
		if total > 1: multi_count += 1
		if counts[0] > 0 and counts[1] > 0: mixed_count += 1
	if not (item_counts[0] > item_counts[1] and item_counts[1] > item_counts[2] and empty_count > 100 and empty_count < 500 and multi_count > 3000 and mixed_count > 1000):
		failures.append("Wrong loot distribution: %s empty=%d multi=%d mixed=%d" % [str(item_counts), empty_count, multi_count, mixed_count])
	# Pick a repeatable mixed drop, then inspect its real render during flight and landing.
	seed(88)
	for attempt in range(100):
		game.world_coins.clear()
		game.world_hearts.clear()
		game.world_barrel_guns.clear()
		game._drop_barrel_loot(barrel_position)
		if game.world_coins.size() >= 2 and not game.world_hearts.is_empty():
			break
	if game.world_coins.size() < 2 or game.world_hearts.is_empty():
		failures.append("Could not produce a mixed multi-item drop")
	var thrown: Array = game.world_coins + game.world_hearts + game.world_barrel_guns
	var first_velocity: Vector2 = thrown[0]["loot_velocity"]
	var second_velocity: Vector2 = thrown[1]["loot_velocity"]
	if first_velocity.normalized().dot(second_velocity.normalized()) > 0.9:
		failures.append("Loot was not launched in different directions")
	var moved := false
	var saw_bounce := false
	for step in range(180):
		game._advance_barrel_loot(0.01)
		for item in thrown:
			if Vector2(item["position"]).distance_to(barrel_position) > 0.08: moved = true
			if int(item["loot_bounces"]) == 0 and bool(item["loot_airborne"]): saw_bounce = true
		if step == 20 or step == 65:
			game._bind_player_context(0)
			game._render_bound_player_context()
			await process_frame
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("xybots_loot_flight_%d.png" % step))
	if not moved or not saw_bounce:
		failures.append("Loot did not travel outwards and bounce")
	for item in thrown:
		if bool(item["loot_airborne"]) or not is_zero_approx(float(item["loot_height"])):
			failures.append("Loot did not settle on the ground")
	# Aim an airborne item at an actual nearby maze wall and check it remains on this side.
	game.world_coins.clear()
	game.world_hearts.clear()
	game.world_barrel_guns.clear()
	var wall_direction := Vector2.ZERO
	var wall_distance := INF
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var distance: float = game._nearest_projectile_wall_distance(origin, direction, 2.0)
		if distance < wall_distance:
			wall_distance = distance
			wall_direction = direction
	if is_inf(wall_distance) or wall_distance > 2.0:
		failures.append("Could not find a wall for the loot collision test")
	else:
		var launch := origin + wall_direction * maxf(wall_distance - 0.15, 0.0)
		game.world_coins.append({"id": 999994, "position": launch, "value": 1, "loot_airborne": true, "loot_height": 0.3, "loot_vertical_velocity": 1.0, "loot_velocity": wall_direction * 0.8, "loot_bounces": 1})
		for step in range(160): game._advance_barrel_loot(0.01)
		var final_position: Vector2 = game.world_coins[0]["position"]
		if (final_position - origin).dot(wall_direction) > wall_distance - 0.02:
			failures.append("Thrown loot crossed or ended inside a wall")
	# Airborne items touching a player must wait until they land.
	game.world_coins.clear()
	game.world_hearts.clear()
	game.world_barrel_guns.clear()
	game.world_coins.append({"id": 999995, "position": origin, "value": 1, "loot_airborne": true})
	game.world_hearts.append({"id": 999992, "position": origin, "loot_airborne": true})
	game.world_barrel_guns.append({"id": 999993, "position": origin, "loot_airborne": true})
	game.player_states[0]["health"] = 1
	game._collect_combat_pickups(0.0)
	if game.world_coins.is_empty() or game.world_hearts.is_empty() or game.world_barrel_guns.is_empty(): failures.append("Airborne loot was collected before landing")
	game.world_coins[0]["loot_airborne"] = false
	game.world_hearts[0]["loot_airborne"] = false
	game.world_barrel_guns[0]["loot_airborne"] = false
	game._collect_combat_pickups(0.0)
	if not game.world_coins.is_empty() or not game.world_hearts.is_empty() or not game.world_barrel_guns.is_empty(): failures.append("Landed loot could not be collected")
	game.world_coins.clear()
	game.world_hearts.clear()
	game.world_barrel_guns.clear()
	game.world_barrel_guns.append({"id": 999998, "position": origin})
	game.player_states[0]["machine_gun_ammo"] = 0
	var existing_gun: Dictionary = game.machine_gun_pickup.duplicate()
	game.player_states[0]["health"] = 1
	game.player_states[0]["coins"] = 0
	game.world_coins.append({"id": 999996, "position": origin, "value": 1})
	game.world_hearts.append({"id": 999997, "position": origin})
	game._collect_combat_pickups(0.0)
	if not game.world_coins.is_empty() or not game.world_hearts.is_empty() or int(game.player_states[0]["coins"]) != 1 or int(game.player_states[0]["health"]) != 2:
		failures.append("Bonus coin or heart did not collect correctly")
	if not game.world_barrel_guns.is_empty() or int(game.player_states[0].get("machine_gun_ammo", 0)) != game.DUAL_WIELD_AMMO or game.machine_gun_pickup != existing_gun:
		failures.append("Bonus pistol collection failed or replaced the contested gun")
	game.player_states[0]["machine_gun_ammo"] = 5
	game._drop_machine_gun_for_defeat(0)
	if game.machine_gun_pickup != existing_gun or game.world_barrel_guns.size() != 1 or int(game.world_barrel_guns[0].get("ammo", 0)) != 5:
		failures.append("Dropping a bonus pistol on defeat replaced the contested pickup or lost ammo")
	game._collect_combat_pickups(0.0)
	if not game.world_barrel_guns.is_empty() or int(game.player_states[0].get("machine_gun_ammo", 0)) != 5:
		failures.append("Dropped bonus pistol did not retain its remaining rounds")
	print("Barrel loot items ", item_counts, " empty=", empty_count, " multi=", multi_count, " mixed=", mixed_count, "; screenshot ", image_path)
	for failure in failures:
		push_error(failure)
	level.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
