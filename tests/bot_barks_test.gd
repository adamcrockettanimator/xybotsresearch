extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game.player_bots[1] = true
	game.player_joined[0] = true
	game.player_joined[1] = true
	game.player_states[0] = game._make_player_state(0, Vector2i(2, 2), 0)
	game.player_states[0]["world_position"] = Vector2(2.5, 2.5)
	game.player_states[0]["continuous_camera_yaw"] = 0.0
	game.player_states[1] = game._make_player_state(1, Vector2i(3, 2), 0)
	game.player_states[1]["world_position"] = Vector2(3.5, 2.5)
	for category in game.BOT_BARKS:
		for filename in game.BOT_BARKS[category]:
			assert(load(game.BOT_BARK_ROOT + filename) is AudioStream)
	assert(game._request_bot_bark(1, "hearing"))
	assert(game.bot_bark_panner.pan > 0.8)
	var near_db: float = game.bot_bark_player.volume_db
	var near_wet_delta: float = game.bot_bark_reverb_player.volume_db - near_db
	assert(not game._request_bot_bark(1, "combat"))
	game.player_states[1]["world_position"] = Vector2(0.5, 5.5)
	assert(game._update_bot_bark_spatial())
	assert(game.bot_bark_panner.pan < 0.0)
	assert(game._request_bot_bark(1, "victory"))
	assert(game.bot_bark_panner.pan < 0.0)
	assert(game.bot_bark_player.volume_db < near_db)
	assert(game.bot_bark_reverb_player.volume_db - game.bot_bark_player.volume_db > near_wet_delta)
	assert(game.bot_bark_player.playing)
	# A real NPC killing a human invokes the victory line despite cooldown.
	game.player_states[1]["world_position"] = Vector2(3.5, 2.5)
	game.player_states[1]["grid_position"] = Vector2i(3, 2)
	game.player_states[0]["health"] = 1
	game.bot_bark_last_line[1] = ""
	game.clear_the_map_mode = false
	assert(game._apply_projectile_hit(0, Vector2.LEFT, 1))
	assert(game.bot_bark_player.playing)
	# Hearing is connected to the actual investigation transition.
	game.player_states[0]["is_dying"] = false
	game.player_states[0]["health"] = 3
	game.player_states[0]["world_position"] = Vector2(2.5, 2.5)
	game.player_states[0]["grid_position"] = Vector2i(2, 2)
	game.bot_bark_player.stop()
	game.bot_bark_reverb_player.stop()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	game.bot_bark_last_line.clear()
	game.bot_brains.clear()
	game._set_wall_between(Vector2i(2, 2), Vector2i(1, 0), true)
	game.bot_heard_shot_serial += 1
	game.bot_last_heard_shot_position = Vector2(2.5, 2.5)
	var brain: Dictionary = game._update_bot_brain(1, game.player_states[1], Vector2(3.5, 2.5), 0, Vector2.LEFT, 1.0, Vector2.LEFT, 0.016)
	assert(brain["state"] == "INVESTIGATE")
	assert(game.bot_bark_last_line.has(1) and game.BOT_BARKS["hearing"].has(game.bot_bark_last_line[1]))
	print("NPC barks: imported clips, hearing, cooldown, directional distance/reverb, and kill priority passed")
	game.queue_free()
	quit()
