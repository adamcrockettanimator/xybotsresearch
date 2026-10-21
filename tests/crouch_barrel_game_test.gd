extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _set_axis(device: int, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)

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
			var cell := Vector2i(x, y)
			if not game._is_open_cell(cell):
				continue
			var candidate := Vector2(x + 0.5, y + 0.5)
			if game._nearest_projectile_wall_distance(candidate, Vector2.UP, 1.2) > 1.2:
				origin = candidate
				found = true
				break
		if found:
			break
	if not found:
		push_error("No suitable open lane for the real-level test")
		quit(1)
		return
	game._set_player_world_position_for_current_view(origin)
	game.character_is_moving = false
	var devices := Input.get_connected_joypads()
	if devices.is_empty():
		push_error("Input-driven test needs a connected controller")
		quit(1)
		return
	var device: int = devices[0]
	game.player_bots[0] = false
	game.player_device_ids[0] = device
	_set_axis(device, JOY_AXIS_TRIGGER_LEFT, 1.0)
	await process_frame
	game._process_player_context(0.016)
	game._save_player_context(0)
	var muzzle: Dictionary = game._world_muzzle_anchor(0, origin, Vector2.UP, &"right")
	game.world_barrels.clear()
	game.world_barrels.append({"id": 9999, "position": Vector2(Vector2(muzzle["position"]).x, origin.y - 0.9)})
	game._render_bound_player_context()
	await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("xybots_barrel_before_shot.png"))
	game.player_states[0]["fire_cooldown"] = 0.0
	_set_axis(device, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await process_frame
	game._process_combat(0.001)
	_set_axis(device, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	if game.active_projectiles.is_empty():
		push_error("Right trigger did not spawn a crouched projectile")
		quit(1)
		return
	var crouch_height := float(game.active_projectiles.back()["height"])
	for i in range(12):
		game._process_combat(0.015)
		game._bind_player_context(0)
		game._render_bound_player_context()
		await process_frame
	var barrel_hit := false
	for hole in game.active_wall_bullet_holes:
		barrel_hit = barrel_hit or bool(hole.get("barrel_hit", false))
	var image_path := OS.get_environment("TEMP").path_join("xybots_crouch_barrel_game_test.png")
	root.get_texture().get_image().save_png(image_path)
	game.active_projectiles.clear()
	game.active_wall_bullet_holes.clear()
	game._bind_player_context(0)
	_set_axis(device, JOY_AXIS_TRIGGER_LEFT, 0.0)
	await process_frame
	game._process_player_context(0.016)
	game._save_player_context(0)
	game.player_states[0]["fire_cooldown"] = 0.0
	_set_axis(device, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await process_frame
	game._process_combat(0.001)
	_set_axis(device, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	if game.active_projectiles.is_empty():
		push_error("Right trigger did not spawn a standing projectile")
		quit(1)
		return
	var standing_height := float(game.active_projectiles.back()["height"])
	for i in range(8):
		game._process_combat(0.015)
	var passed_over: bool = game.active_wall_bullet_holes.is_empty() and not game.active_projectiles.is_empty()
	print("real level barrel hit=", barrel_hit, " standing passes=", passed_over, " crouch=", crouch_height, " standing=", standing_height, " screenshot=", image_path)
	level.queue_free()
	await process_frame
	quit(0 if barrel_hit and passed_over and crouch_height < standing_height else 1)
