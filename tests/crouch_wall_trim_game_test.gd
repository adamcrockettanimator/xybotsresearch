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
	game.world_barrels.clear()
	game._bind_player_context(0)
	game.continuous_camera_yaw = 0.0
	game.facing = 0
	var found := false
	var origin := Vector2.ZERO
	for y in range(game.MAP_HEIGHT):
		for x in range(game.MAP_WIDTH):
			var cell := Vector2i(x, y)
			if not game._is_open_cell(cell):
				continue
			var candidate := Vector2(x + 0.5, y + 0.5)
			var wall_distance: float = game._nearest_projectile_wall_distance(candidate, Vector2.UP, 2.5)
			if wall_distance >= 0.8 and wall_distance <= 1.9:
				origin = candidate
				found = true
				break
		if found:
			break
	var devices := Input.get_connected_joypads()
	if not found or devices.is_empty():
		push_error("Test needs an open firing lane and a connected controller")
		quit(1)
		return
	game._set_player_world_position_for_current_view(origin)
	var device: int = devices[0]
	game.player_bots[0] = false
	game.player_device_ids[0] = device
	_set_axis(device, JOY_AXIS_TRIGGER_LEFT, 1.0)
	await process_frame
	game._process_player_context(0.016)
	game._save_player_context(0)
	game._spawn_pistol_shot(0)
	var shot: Dictionary = game.active_projectiles.back()
	for i in range(40):
		game._process_combat(0.02)
		if not game.active_wall_bullet_holes.is_empty():
			break
	_set_axis(device, JOY_AXIS_TRIGGER_LEFT, 0.0)
	if game.active_wall_bullet_holes.is_empty():
		push_error("Crouched shot did not hit the wall")
		quit(1)
		return
	var hole: Dictionary = game.active_wall_bullet_holes.back()
	var renderer = game.coordinate_renderers[0]
	var wall_height: float = renderer.WALL_HEIGHT
	var trim_height := wall_height * (1.0 - 62.0 / 88.0) # First row below the rail in Wall_Layer1.png.
	var projection: Dictionary = renderer.runtime_project_world_point_for_current_pose(hole["position"], trim_height, true, false)
	var trim_y := float(projection["feet_y"]) - float(projection["continuous_actor_height"])
	var impact_projection: Dictionary = renderer.runtime_project_world_point_for_current_pose(hole["position"], float(hole["height"]) * renderer.WORLD_ACTOR_HEIGHT, true, false)
	var impact_y := float(impact_projection["feet_y"]) - float(impact_projection["continuous_actor_height"])
	game.active_wall_impact_smokes.clear()
	game.active_wall_debris.clear()
	game.active_muzzle_smoke_particles.clear()
	game._bind_player_context(0)
	game._render_bound_player_context()
	await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("xybots_crouch_wall_trim_test.png"))
	var passed := impact_y > trim_y and is_equal_approx(float(shot["height"]), float(hole["height"])) and float(shot["height"]) < float(shot["muzzle_height"])
	print("crouch shot height=", shot["height"], " muzzle=", shot["muzzle_height"], " impact_y=", impact_y, " trim_y=", trim_y, " below trim=", passed)
	level.queue_free()
	await process_frame
	quit(0 if passed else 1)
