extends SceneTree

var game
var device: int

func _initialize() -> void:
	call_deferred("_run")

func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)

func _distance(origin: Vector2, movement: Vector2, crouched: bool, continuous: bool) -> float:
	game._bind_player_context(0)
	game.continuous_third_person_camera = continuous
	game._set_player_world_position_for_current_view(origin)
	game._save_player_context(0)
	await process_frame
	_axis(JOY_AXIS_LEFT_X, movement.x)
	_axis(JOY_AXIS_LEFT_Y, movement.y)
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0 if crouched else 0.0)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	Input.flush_buffered_events()
	var start: Vector2 = game._current_player_world_position()
	game._process_player_context(0.04)
	var end: Vector2 = game._current_player_world_position()
	game._save_player_context(0)
	return start.distance_to(end)

func _run() -> void:
	var level := (load("res://coordinate_frame_navigation.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await create_timer(0.8).timeout
	game = level.get_node("CoordinateFrameGame")
	game.set_process(false)
	game.bots_enabled = false
	game.world_barrels.clear()
	game._bind_player_context(0)
	game.continuous_camera_yaw = 0.0
	game.facing = 0
	var devices := Input.get_connected_joypads()
	if devices.is_empty():
		push_error("Input-driven test needs a connected controller")
		quit(1)
		return
	device = devices[0]
	game.player_bots[0] = false
	game.player_device_ids[0] = device
	var origin := Vector2.ZERO
	var found := false
	for y in range(game.MAP_HEIGHT):
		for x in range(game.MAP_WIDTH):
			if game._is_open_cell(Vector2i(x, y)):
				origin = Vector2(x + 0.5, y + 0.5)
				found = true
				break
		if found:
			break
	if not found:
		push_error("No open cell for movement test")
		quit(1)
		return
	var failures: Array[String] = []
	for continuous in [true, false]:
		for direction in [Vector2(0, -1), Vector2(1, 0), Vector2(-0.7, -0.7)]:
			var standing: float = await _distance(origin, direction, false, continuous)
			var crouched: float = await _distance(origin, direction, true, continuous)
			if standing < 0.001 or absf(crouched / standing - 0.5) > 0.01:
				failures.append("Incorrect speed ratio for %s continuous=%s: %s vs %s" % [direction, continuous, crouched, standing])
	game._bind_player_context(0)
	game.continuous_third_person_camera = false
	game.turn_45_direction = 1
	game.turn_step = 2
	game._save_player_context(0)
	var diagonal_standing: float = await _distance(origin, Vector2(0, -1), false, false)
	var diagonal_crouched: float = await _distance(origin, Vector2(0, -1), true, false)
	if diagonal_standing < 0.001 or absf(diagonal_crouched / diagonal_standing - 0.5) > 0.01:
		failures.append("Diagonal camera movement did not use half speed")
	game._bind_player_context(0)
	game.turn_45_direction = 0
	game.turn_step = 0
	game._save_player_context(0)
	game.crouch_move_speed_multiplier = 0.25
	var normal: float = await _distance(origin, Vector2(1, 0), false, true)
	var tuned: float = await _distance(origin, Vector2(1, 0), true, true)
	if normal < 0.001 or absf(tuned / normal - 0.25) > 0.01:
		failures.append("Inspector multiplier did not change actual travel")
	if not is_equal_approx(game.player_sprite.speed_scale, 1.0):
		failures.append("Movement multiplier changed the player's animation cadence")
	var other := {"character_is_moving": true, "character_is_crouching": true, "world_aim_dir": "N", "world_run_dir": "N"}
	game._apply_opponent_animation(other)
	if not is_equal_approx(game.opponent_sprite.speed_scale, 1.0):
		failures.append("Movement multiplier changed the opponent's animation cadence")
	other["character_is_crouching"] = false
	game._apply_opponent_animation(other)
	if not is_equal_approx(game.opponent_sprite.speed_scale, 1.0):
		failures.append("Opponent animation speed did not return to normal")
	game.crouch_move_speed_multiplier = 0.5
	game.character_is_crouching = true
	game._keep_forward_run_animating()
	if not is_equal_approx(game.player_sprite.speed_scale, game.FORWARD_RUN_ANIMATION_SPEED):
		failures.append("Crouching changed the transition animation cadence")
	game.forward_step = 1
	game.forward_passthrough_timer = 0.0
	game._advance_forward_passthrough(0.06)
	if not is_equal_approx(game.forward_passthrough_timer, 0.03):
		failures.append("Forward cell crossing did not slow down")
	game.strafe_step = 1
	game.strafe_passthrough_timer = 0.0
	game._advance_strafe_passthrough(0.06)
	if not is_equal_approx(game.strafe_passthrough_timer, 0.03):
		failures.append("Side cell crossing did not slow down")
	game.phase_timer = 0.0
	game.active_sequence_name = "strafe_left"
	game._advance_transition(0.06)
	if not is_equal_approx(game.phase_timer, 0.03):
		failures.append("Captured movement phase did not slow down")
	game.phase_timer = 0.0
	game.active_sequence_name = "turn_left"
	game._advance_transition(0.06)
	if not is_equal_approx(game.phase_timer, 0.06):
		failures.append("Crouching changed turn timing")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	level.queue_free()
	await process_frame
	if failures.is_empty():
		print("Crouch movement: half-speed input, configurable multiplier, original animation speed, and crossings passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
