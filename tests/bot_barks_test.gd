extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	for i in range(3):
		game.player_joined[i] = true
		game.player_bots[i] = i > 0
		game.player_states[i] = game._make_player_state(i, Vector2i(2 + i, 2), 0)
		game.player_states[i]["world_position"] = Vector2(2.5 + i, 2.5)
	for voice in game.BOT_BARK_BANK.data.values():
		for category in voice.values():
			for line in category:
				assert(load(line["path"]) is AudioStream)
	assert(game._request_bot_bark(1, "hearing"))
	assert(not game._request_bot_bark(2, "hearing"))
	assert(game.bot_bark_used_lines.size() == 1)
	var first_line: String = game.bot_bark_used_lines.keys()[0]
	game.bot_bark_player.stop()
	game.bot_bark_reverb_player.stop()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	assert(game._request_bot_bark(2, "hearing"))
	assert(game.bot_bark_used_lines.size() == 2)
	assert(game.bot_bark_used_lines.has(first_line))
	game._reset_combat_round()
	assert(game.bot_bark_used_lines.is_empty())
	assert(not game._request_bot_bark(0, "hearing"))
	game._notify_bots_of_prop_break(Vector2(3.5, 2.5))
	assert(game.bot_brains[1].has("prop_sound_pending"))
	print("Barks: assets, voice exclusion, shared channel, round history and prop hearing passed")
	game.queue_free()
	quit()
