extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _axis(device: int, axis: JoyAxis, value: float) -> void:
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
	game._bind_player_context(0)
	game.continuous_third_person_camera = true
	game.continuous_camera_yaw = 0.0
	var devices := Input.get_connected_joypads()
	if devices.is_empty():
		push_error("Input-driven test needs a connected controller")
		quit(1)
		return
	var device: int = devices[0]
	game.player_bots[0] = false
	game.player_device_ids[0] = device
	var failures: Array[String] = []
	for direction in ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]:
		var idle := StringName("CrouchIdle" + direction)
		if not game.player_sprite.sprite_frames.has_animation(idle) or game.player_sprite.sprite_frames.get_frame_count(idle) != 12:
			failures.append("Missing twelve-frame crouch idle " + direction)
		for side in ["Left", "Right"]:
			var animation := StringName("CrouchWalk" + side + direction)
			if not game.player_sprite.sprite_frames.has_animation(animation) or game.player_sprite.sprite_frames.get_frame_count(animation) != 6:
				failures.append("Missing six-frame animation " + side + direction)
	await process_frame
	_axis(device, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_axis(device, JOY_AXIS_LEFT_X, 1.0)
	_axis(device, JOY_AXIS_LEFT_Y, 0.0)
	_axis(device, JOY_AXIS_RIGHT_X, 0.0)
	Input.flush_buffered_events()
	game._process_player_context(0.016)
	game._save_player_context(0)
	if game.player_sprite.animation != &"CrouchWalkRightN" or not game.player_sprite.is_playing():
		failures.append("Crouch plus right movement did not start the right walk")
	var first_frame: int = game.player_sprite.frame
	await create_timer(0.3).timeout
	if game.player_sprite.frame == first_frame:
		failures.append("Right walk did not advance")
	game._render_bound_player_context()
	await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("xybots_crouch_walk_right_test.png"))
	await process_frame
	_axis(device, JOY_AXIS_LEFT_X, -1.0)
	_axis(device, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_axis(device, JOY_AXIS_RIGHT_X, 0.0)
	Input.flush_buffered_events()
	game._process_player_context(0.016)
	if game.player_sprite.animation != &"CrouchWalkLeftN" or not game.player_sprite.is_playing():
		failures.append("Crouch plus left movement did not start the left walk")
	first_frame = game.player_sprite.frame
	await create_timer(0.3).timeout
	if game.player_sprite.frame == first_frame:
		failures.append("Left walk did not advance")
	game._render_bound_player_context()
	await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("xybots_crouch_walk_left_new_test.png"))
	_axis(device, JOY_AXIS_LEFT_X, 0.0)
	_axis(device, JOY_AXIS_LEFT_Y, -1.0)
	_axis(device, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_axis(device, JOY_AXIS_RIGHT_X, 0.0)
	Input.flush_buffered_events()
	game._process_player_context(0.016)
	if game.player_sprite.animation != &"CrouchWalkN":
		failures.append("Forward movement did not keep the forward crouch animation")
	_axis(device, JOY_AXIS_LEFT_Y, 0.0)
	_axis(device, JOY_AXIS_TRIGGER_LEFT, 1.0)
	Input.flush_buffered_events()
	game._process_player_context(0.016)
	if game.player_sprite.animation != &"CrouchIdleN" or not game.player_sprite.is_playing():
		failures.append("Stopping while crouched did not start the crouch idle")
	game._position_player()
	var idle_scale: Vector2 = game.player_sprite.scale
	var idle_feet: float = game.player_sprite.position.y + (game._texture_foot_anchor_y(game.player_sprite.sprite_frames.get_frame_texture(game.player_sprite.animation, game.player_sprite.frame)) - 24.0) * idle_scale.y
	game.player_sprite.animation = &"CrouchWalkN"
	game._position_player()
	var walk_scale: Vector2 = game.player_sprite.scale
	var walk_feet: float = game.player_sprite.position.y + (game._texture_foot_anchor_y(game.player_sprite.sprite_frames.get_frame_texture(game.player_sprite.animation, game.player_sprite.frame)) - 24.0) * walk_scale.y
	# Sprite centers snap to whole logical pixels, so feet may differ by up to one pixel.
	if not idle_scale.is_equal_approx(walk_scale) or absf(idle_feet - walk_feet) > 1.0:
		failures.append("Crouch idle and walk differ in scale or floor anchoring: %s/%s, feet %.3f/%.3f" % [idle_scale, walk_scale, idle_feet, walk_feet])
	game._play_idle_animation()
	for frame_index in game.player_sprite.sprite_frames.get_frame_count(&"CrouchIdleN"):
		game.player_sprite.frame = frame_index
		game._position_player()
		var frame_feet: float = game.player_sprite.position.y + (game._sprite_foot_anchor_y(game.player_sprite) - 24.0) * game.player_sprite.scale.y
		if not game.player_sprite.scale.is_equal_approx(walk_scale) or absf(frame_feet - walk_feet) > 1.0:
			failures.append("Crouch idle frame %d changed scale or floor anchoring" % frame_index)
	first_frame = game.player_sprite.frame
	await create_timer(0.3).timeout
	if game.player_sprite.frame == first_frame:
		failures.append("Crouch idle did not advance")
	game._render_bound_player_context()
	await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("xybots_crouch_idle_test.png"))
	_axis(device, JOY_AXIS_TRIGGER_LEFT, 0.0)
	Input.flush_buffered_events()
	game._process_player_context(0.016)
	if String(game.player_sprite.animation).begins_with("CrouchWalk"):
		failures.append("Releasing crouch did not restore standing animation")
	game.facing = 0
	for aim in ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]:
		var forward: Vector2 = game._world_vector_for_direction_string(aim)
		var right := Vector2(-forward.y, forward.x)
		var state := {"character_is_moving": true, "character_is_crouching": true, "world_aim_dir": aim, "world_run_dir": game._direction_string_for_world_vector(right)}
		game._apply_opponent_animation(state)
		var relative_aim: String = game._view_relative_dir(aim, 0)
		if game.opponent_sprite.animation != StringName("CrouchWalkRight" + relative_aim):
			failures.append("Opponent right movement incorrect for aim " + aim)
		state["world_run_dir"] = game._direction_string_for_world_vector(-right)
		game._apply_opponent_animation(state)
		if game.opponent_sprite.animation != StringName("CrouchWalkLeft" + relative_aim):
			failures.append("Opponent left movement incorrect for aim " + aim)
		state["character_is_moving"] = false
		game._apply_opponent_animation(state)
		if game.opponent_sprite.animation != StringName("CrouchIdle" + relative_aim) or not game.opponent_sprite.is_playing():
			failures.append("Opponent crouch idle incorrect for aim " + aim)
	if not game._muzzle_anchor_for_animation(&"CrouchWalkRightN", &"right") is Vector2i:
		failures.append("Right walk lost its authored muzzle marker")
	if not game._muzzle_anchor_for_animation(&"CrouchWalkLeftN", &"right") is Vector2i:
		failures.append("Left walk did not inherit the forward crouch muzzle marker")
	level.queue_free()
	await process_frame
	if failures.is_empty():
		print("Crouch walks: left/right controller input, animation advance, and eight opponent views passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
