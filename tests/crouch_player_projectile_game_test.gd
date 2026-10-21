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
	game.player_joined[0] = true
	game.player_joined[1] = true
	game.player_two_joined = true
	game.player_joined[2] = false
	game.player_joined[3] = false
	game.world_barrels.clear()
	var origin := Vector2.ZERO
	var found := false
	for y in range(game.MAP_HEIGHT):
		for x in range(game.MAP_WIDTH):
			var cell := Vector2i(x, y)
			var candidate := Vector2(x + 0.5, y + 0.5)
			if game._is_open_cell(cell) and game._nearest_projectile_wall_distance(candidate, Vector2.UP, 1.2) > 1.2:
				origin = candidate
				found = true
				break
		if found:
			break
	if not found:
		push_error("No open lane for projectile test")
		quit(1)
		return
	game._bind_player_context(0)
	game.continuous_third_person_camera = true
	game.player_states[0]["world_position"] = origin
	game.player_states[0]["grid_position"] = Vector2i(floori(origin.x), floori(origin.y))
	game.player_states[0]["continuous_camera_yaw"] = 0.0
	var failures: Array[String] = []
	# Also change stance after firing to ensure bullets keep their launch stance
	# and targets use their current stance at the moment of contact.
	var cases := [
		{"name": "standing to crouched", "shooter": false, "target_at_spawn": true, "target_at_hit": true, "hit": false},
		{"name": "standing to standing", "shooter": false, "target_at_spawn": false, "target_at_hit": false, "hit": true},
		{"name": "crouched to crouched", "shooter": true, "target_at_spawn": true, "target_at_hit": true, "hit": true},
		{"name": "crouched to standing", "shooter": true, "target_at_spawn": false, "target_at_hit": false, "hit": true},
		{"name": "target ducks after shot", "shooter": false, "target_at_spawn": false, "target_at_hit": true, "hit": false},
		{"name": "target stands after shot", "shooter": false, "target_at_spawn": true, "target_at_hit": false, "hit": true},
	]
	for scenario in cases:
		game.active_projectiles.clear()
		game.active_wall_bullet_holes.clear()
		game.active_blood_splatters.clear()
		game.player_states[0]["character_is_crouching"] = scenario["shooter"]
		game.player_states[0]["fire_cooldown"] = 0.0
		var sprite: AnimatedSprite2D = game.player_views[0]["player_sprite"]
		sprite.animation = &"CrouchIdleN" if scenario["shooter"] else &"IdleN"
		var muzzle: Dictionary = game._world_muzzle_anchor(0, origin, Vector2.UP, &"right")
		var target := Vector2(Vector2(muzzle["position"]).x, origin.y - 0.85)
		game.player_states[1]["world_position"] = target
		game.player_states[1]["grid_position"] = Vector2i(floori(target.x), floori(target.y))
		game.player_states[1]["character_is_crouching"] = scenario["target_at_spawn"]
		game.player_states[1]["health"] = 4
		game.player_states[1]["is_dying"] = false
		game.player_states[1]["fire_cooldown"] = 100.0
		game._spawn_pistol_shot(0)
		var shot: Dictionary = game.active_projectiles.back()
		var predicted := int(shot["visual_target_player_index"])
		var expected_prediction := 1 if scenario["shooter"] or not scenario["target_at_spawn"] else -1
		if predicted != expected_prediction:
			failures.append("%s predicted target %d, expected %d" % [scenario["name"], predicted, expected_prediction])
		game.player_states[0]["character_is_crouching"] = not scenario["shooter"]
		game.player_states[0]["fire_cooldown"] = 100.0
		game.player_states[1]["character_is_crouching"] = scenario["target_at_hit"]
		for step in range(3):
			game._process_combat(0.04)
		var was_hit := int(game.player_states[1]["health"]) == 3
		if was_hit != scenario["hit"]:
			failures.append("%s hit=%s, expected %s" % [scenario["name"], was_hit, scenario["hit"]])
		if not scenario["hit"] and (game.active_projectiles.is_empty() or not game.active_blood_splatters.is_empty()):
			failures.append("%s did not continue cleanly past the crouched player" % scenario["name"])
	level.queue_free()
	await process_frame
	if failures.is_empty():
		print("Player projectile stance combinations and stance changes passed in the real level")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
