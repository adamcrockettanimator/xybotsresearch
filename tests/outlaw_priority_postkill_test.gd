extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game.clear_map_round = 2
	game._apply_session_roster()
	game.player_states[0] = game._make_player_state(0, Vector2i(2, 2), 0)
	game.player_states[1] = game._make_player_state(1, Vector2i(2, 2), 0)
	game.player_states[2] = game._make_player_state(2, Vector2i(0, 0), 0)
	game.player_states[1].voice_actor = "zach"
	game.player_states[2].voice_actor = "devin"
	game.player_states[1].world_position = Vector2(2.5, 2.5)
	var forward: Vector2 = game._view_forward_vector_for_state(game.player_states[1]).normalized()
	game.player_states[0].world_position = Vector2(2.5, 2.5) + forward
	game.player_states[2].world_position = Vector2(0.5, 0.5)
	# First sight is urgent and independent of an existing conversation.
	game.bot_bark_player.stream = load(game.BOT_BARK_BANK.data.devin.hearing[0].path)
	game.bot_bark_speaker = 2
	game.bot_bark_player.play()
	var brain: Dictionary = game._update_bot_brain(1, game.player_states[1], Vector2(2.5, 2.5), 0, forward, 1.0, forward, 0.016)
	assert(brain.get("first_sighting_barked", false))
	assert(game.bot_bark_player.playing and game.bot_bark_speaker == 2)
	assert(game.bot_damage_channels[1].player.playing)
	var spotting_path: String = game.bot_damage_channels[1].player.stream.resource_path
	var is_spotting := false
	for line in game.BOT_BARK_BANK.data.zach.first_sighting:
		is_spotting = is_spotting or String(line.path) == spotting_path
	assert(is_spotting)
	# A shot interrupts lower-priority speech, and a first-sight call waits
	# behind a hit instead of cutting it off or disappearing.
	game.bot_damage_channels[1].player.stop()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	assert(game._request_bot_bark(1, "hit"))
	assert(not game._request_bot_bark(1, "first_sighting"))
	assert(game.bot_bark_pending_mandatory.size() == 1)
	game.bot_damage_channels[1].player.stop()
	game._process_pending_mandatory_barks()
	assert(game.bot_bark_pending_mandatory.is_empty())
	assert(game.bot_damage_channels[1].player.playing)
	# Duration weighting favors short speech during combat and user weight zero disables it.
	var samples := [{"duration_seconds": 0.5, "weight": 1.0}, {"duration_seconds": 4.0, "weight": 1.0}]
	game.bot_combat_started = true
	var short_count := 0
	for i in range(2000):
		if float(game._choose_bark_line(samples, "attacking").duration_seconds) < 1.0:
			short_count += 1
	assert(short_count > 1800)
	assert(game._choose_bark_line([{"duration_seconds": 0.5, "weight": 0.0}], "hit").is_empty())
	# Killing the player requests an immediate kill line and leaves the scene live.
	game.bot_bark_player.stop()
	game.bot_bark_reverb_player.stop()
	game.bot_damage_channels[1].player.stop()
	game.player_states[0].health = 1
	assert(game._apply_projectile_hit(0, -forward, 1))
	assert(game.post_kill_active and game.clear_map_finish_pending and game.combat_round_complete)
	assert(not game.clear_map_result_fade.visible)
	assert(game.bot_damage_channels[1].player.playing)
	var kill_path: String = game.bot_damage_channels[1].player.stream.resource_path
	var is_kill := false
	for line in game.BOT_BARK_BANK.data.zach.kill_player:
		is_kill = is_kill or String(line.path) == kill_path
	assert(is_kill)
	game._advance_clear_map_finish(60.0)
	assert(game.post_kill_active and game.clear_map_finish_pending)
	game._update_bot_input(2, 0.1)
	assert(not game.bot_inputs[2].fire and Vector2(game.bot_brains[2].move_direction).length() > 0.5)
	for frame in range(400):
		game._update_bot_input(2, 0.025)
		game._process_virtual_bot_world_context(2, 0.025)
	assert(Vector2(game.player_states[2].world_position).distance_to(Vector2(game.player_states[0].world_position)) <= 1.5)
	# A prop in the approach path must not leave a survivor stuck in place.
	game.player_states[2].world_position = Vector2(0.5, 2.5)
	game.player_states[2].grid_position = Vector2i(0, 2)
	game.world_barrels.append({"id": 99, "position": Vector2(1.5, 2.5), "collision_radius": 0.16})
	game.bot_brains[2].erase("gather_detour")
	game.bot_brains[2].erase("gather_recovery")
	for frame in range(600):
		game._update_bot_input(2, 0.025)
		game._process_virtual_bot_world_context(2, 0.025)
	assert(Vector2(game.player_states[2].world_position).distance_to(Vector2(game.player_states[0].world_position)) < 1.0)
	game.world_barrels.clear()
	game.bot_damage_channels[1].player.stop()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	game._advance_post_kill_scene(2.0)
	assert(game.bot_bark_player.playing and game.bot_bark_speaker in [1, 2])
	game._skip_post_kill_scene()
	assert(not game.post_kill_active and game.clear_map_round == 1 and not game.clear_map_waiting_to_start and game.match_started)
	print("Urgent first sight and kill, weighted lines, gathering, taunts and skip passed")
	game.queue_free()
	quit()
