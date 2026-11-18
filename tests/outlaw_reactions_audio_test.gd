extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	for index in range(3):
		game.player_joined[index] = true
		game.player_bots[index] = index > 0
		game.player_states[index] = game._make_player_state(index, Vector2i(2, 2), 0)
	game.player_states[0].world_position = Vector2(3.5, 2.5)
	game.player_states[1].world_position = Vector2(2.5, 2.5)
	game.player_states[2].world_position = Vector2(2.1, 2.5)
	game.player_states[1].voice_actor = "adam"
	game.player_states[2].voice_actor = "rowan"
	game.player_states[2].continuous_camera_yaw = PI * 0.5
	game.player_states[1].health = 3
	game.player_states[2].health = 3
	game.bot_bark_last_global = -INF
	assert(game._request_bot_bark(1, "attacking"))
	assert(game._request_bot_bark(2, "hit"))
	assert(game.bot_bark_player.playing and game.bot_bark_speaker == 1)
	assert(game.bot_damage_channels[2].player.playing)
	# Lethal damage cuts the victim's own speech, then plays their death line;
	# the witnessing ally is queued behind ordinary chatter/cooldown.
	game.player_states[1].health = 1
	assert(game._apply_projectile_hit(1, Vector2.LEFT, 0))
	assert(not game.bot_bark_player.playing)
	assert(game.bot_damage_channels[1].player.playing)
	assert(game.bot_bark_pending_ally_falls.size() == 1)
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	game._process_pending_ally_fall_barks()
	assert(game.bot_bark_pending_ally_falls.size() == 1)
	game.bot_damage_channels[2].player.stop()
	game._process_pending_ally_fall_barks()
	assert(game.bot_bark_player.playing and game.bot_bark_speaker == 2)
	assert(game.bot_bark_pending_ally_falls.is_empty())
	assert(not game._request_bot_bark(1, "hearing"))
	# A witness who was already speaking gets a turn after that line ends,
	# without the usual personal chatter cooldown suppressing the reaction.
	game.bot_bark_player.stop()
	game.bot_bark_reverb_player.stop()
	game.bot_bark_pending_ally_falls.clear()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	game.player_states[1].health = 2
	game.player_states[1].is_dying = false
	game.player_states[1].world_position = Vector2(2.1, 2.5)
	game.player_states[1].continuous_camera_yaw = PI * 0.5
	game.player_states[2].health = 1
	game.player_states[2].is_dying = false
	game.player_states[2].world_position = Vector2(2.5, 2.5)
	game.bot_damage_channels[1].player.stop()
	assert(game._request_bot_bark(1, "attacking"))
	assert(game._apply_projectile_hit(2, Vector2.LEFT, 0))
	assert(game.bot_bark_player.playing and game.bot_bark_speaker == 1)
	assert(game.bot_damage_channels[2].player.playing)
	assert(game.bot_bark_pending_ally_falls.size() == 1)
	game.bot_bark_player.stop()
	game.bot_bark_reverb_player.stop()
	game.bot_bark_last_global = -INF
	game._process_pending_ally_fall_barks()
	assert(game.bot_bark_player.playing and game.bot_bark_speaker == 1)
	assert(game.bot_bark_pending_ally_falls.is_empty())
	game.bot_bark_player.stop()
	game.bot_bark_reverb_player.stop()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	assert(game._bot_can_see_human_for_bark(1))
	assert(not game._request_bot_bark(1, "shot"))
	# A prop near the enemy is not proof that the player is taking cover.
	game.world_barrels.clear()
	game.world_barrels.append({"id": 17, "position": Vector2(1.9, 1.5), "projectile_radius": 0.15, "projectile_height": 1.0})
	assert(not game._bot_target_has_nearby_cover(Vector2(1.5, 1.5), Vector2(3.5, 1.5)))
	game.world_barrels[0].position = Vector2(3.1, 1.5)
	assert(game._bot_target_has_nearby_cover(Vector2(1.5, 1.5), Vector2(3.5, 1.5)))
	# Zach's short exclamations remain available after unique lines are used.
	game.player_states[1].voice_actor = "zach"
	game.player_states[1].health = 1
	game.player_states[1].is_dying = false
	for line in game.BOT_BARK_BANK.data.zach.hit:
		if not bool(line.repeatable):
			game.bot_bark_used_lines[line.id] = true
	assert(game._request_bot_bark(1, "hit"))
	assert(any_short_reaction(game, "hit", game.bot_damage_channels[1].player.stream.resource_path))
	game.player_states[1].health = 0
	for line in game.BOT_BARK_BANK.data.zach.death:
		if not bool(line.repeatable):
			game.bot_bark_used_lines[line.id] = true
	assert(game._request_bot_bark(1, "death"))
	assert(any_short_reaction(game, "death", game.bot_damage_channels[1].player.stream.resource_path))
	print("Overlapping hit/death, stale chatter, queued witness, and cover attribution passed")
	game.queue_free()
	quit()

func any_short_reaction(game: Node, category: String, path: String) -> bool:
	for line in game.BOT_BARK_BANK.data.zach[category]:
		if bool(line.repeatable) and String(line.path) == path:
			return true
	return false
