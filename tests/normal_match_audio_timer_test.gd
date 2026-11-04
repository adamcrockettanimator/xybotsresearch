extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	assert(not game.match_started)
	assert(game.clear_map_waiting_to_start)
	assert(game.semantic_typical_props_enabled)
	assert(game.semantic_lod_floor_footprints.size() == 11)
	var barrel_count := 0
	var crate_count := 0
	var dining_count := 0
	for footprint in game.semantic_lod_floor_footprints:
		if String(footprint["id"]).begins_with("barrel_gpu_lattice_instanced_room_"):
			barrel_count += 1
		elif String(footprint["id"]).begins_with("crate_gpu_fragment_raster_room_"):
			crate_count += 1
		elif String(footprint["id"]).contains("_dining"):
			dining_count += 1
	assert(barrel_count == 4 and crate_count == 4 and dining_count == 3)
	assert(game.music_enabled and game.music_player.playing and game.clear_map_intro_music_active)
	assert(not game.pause_round_timer_for_debug)
	var before: float = game.combat_round_time_remaining
	game._advance_combat_round(1.0)
	assert(game.clear_the_map_mode)
	assert(is_equal_approx(game.combat_round_time_remaining, before))
	assert(game.player_joined[0] and game.player_joined[1] and not game.player_joined[2])
	# Opening cards are introduced one at a time rather than arriving as a finished row.
	assert(not game.wanted_tally_posters[1]["card"].visible)
	game._advance_wanted_tally(0.5)
	assert(game.wanted_tally_posters[1]["card"].visible)
	game._start_clear_map_round()
	assert(game.match_started and not game.clear_map_waiting_to_start and not game.clear_map_intro_music_active)
	assert(game.music_player.playing and not game.wanted_tally_overlay.visible)
	assert(game.music_player.get_playback_position() >= game.CLEAR_MAP_INTRO_LOOP_SECONDS - 0.01)
	# A final kill uses a one-second audiovisual fade before exposing victory cards.
	game.clear_map_tally_loot[1] = {"coins": 2, "hearts": 1, "guns": 0}
	game.player_states[0]["coins"] = 7
	game._finish_clear_map(true)
	assert(game.clear_map_finish_pending)
	game._advance_clear_map_finish(0.5)
	assert(game.clear_map_result_fade.visible)
	assert(is_equal_approx(game.clear_map_result_fade.color.a, 0.5))
	game._advance_clear_map_finish(0.5)
	assert(not game.clear_map_finish_pending)
	assert(game.combat_round_result == "YOU WIN!")
	assert(game.clear_map_carried_inventory["coins"] == 7)
	assert(game.clear_map_reward["coins"] == 2 and game.clear_map_reward["hearts"] == 1)
	assert(game.clear_map_result_player.playing)
	# The roster grows with the round number instead of stopping at the original
	# three hidden player slots; round five has five independently simulated bots.
	game.clear_map_round = 5
	game._apply_session_roster()
	assert(game.player_states.size() >= 6)
	for player_index in range(1, 6):
		assert(game.player_joined[player_index] and game.player_bots[player_index])
	assert(game.player_views[0]["opponent_sprites"].has(5))
	game._update_bot_input(5, 0.1)
	game._process_virtual_bot_world_context(5, 0.1)
	assert(game.bot_inputs.has(5))
	var virtual_actor_sprite: AnimatedSprite2D = game._actor_sprite_for_world_player(5)
	assert(virtual_actor_sprite != null and virtual_actor_sprite.sprite_frames != null)
	assert(not virtual_actor_sprite.visible)
	var shots_before: int = game.active_projectiles.size()
	game._spawn_pistol_shot(5)
	assert(game.active_projectiles.size() == shots_before + 1)
	# Result choreography opens with the full poster row already visible, then
	# stamps each dead bot and tallies rewards in poster order.
	game.clear_map_tally_loot = {1: {"coins": 1, "hearts": 0, "guns": 0}, 2: {"coins": 0, "hearts": 1, "guns": 0}}
	game.combat_round_result = "YOU WIN!"
	game._begin_wanted_tally(true)
	for player_index in range(1, 6):
		assert(game.wanted_tally_posters[player_index]["card"].visible)
	assert(game.wanted_tally_queue[0]["kind"] == "blood" and game.wanted_tally_queue[0]["player_index"] == 1)
	assert(game.wanted_tally_queue[1]["kind"] == "coin" and game.wanted_tally_queue[1]["player_index"] == 1)
	assert(game.wanted_tally_queue[2]["kind"] == "blood" and game.wanted_tally_queue[2]["player_index"] == 2)
	assert(game.wanted_tally_queue[3]["kind"] == "heart" and game.wanted_tally_queue[3]["player_index"] == 2)
	game.combat_round_result = "YOU LOSE"
	game._begin_wanted_tally(true)
	assert(game.wanted_tally_queue.size() == 2)
	assert(game.wanted_tally_queue[0]["kind"] == "blood" and game.wanted_tally_queue[1]["kind"] == "blood")
	# The actual fatal shot identifies its shooter on the loss board only.
	game._reset_combat_round()
	game.player_states[5] = game.player_states[0].duplicate()
	game.player_states[0]["health"] = 1
	assert(game._apply_projectile_hit(0, Vector2.RIGHT, 5))
	assert(game.clear_map_killer_index == 5)
	game._advance_clear_map_finish(game.CLEAR_MAP_RESULT_FADE_SECONDS)
	for player_index in range(1, 6):
		assert(game.wanted_tally_posters[player_index]["killer_label"].visible == (player_index == 5))
	game.combat_round_result = "YOU WIN!"
	game._begin_wanted_tally(true)
	assert(not game.wanted_tally_posters[5]["killer_label"].visible)
	game._reset_combat_round()
	assert(game.clear_map_killer_index == -1)
	# Posters advance across batches, wrap, and stay fixed when the result changes
	# the round number before building the terminal board.
	for example in [[1, 0], [2, 1], [3, 3], [4, 6], [17, 0], [18, 0]]:
		game.clear_map_round = example[0]
		game._apply_session_roster()
		game._begin_wanted_tally(false)
		var count: int = mini(example[0], game.MAX_CLEAR_MAP_GREENSHIRTS)
		for index in range(count):
			var poster: TextureRect = game.wanted_tally_posters[index + 1]["card"].get_child(0)
			assert(poster.texture == game.WANTED_POSTER_TEXTURES[(example[1] + index) % 8])
		game.clear_map_round += 1
		game.combat_round_result = "YOU WIN!"
		game._begin_wanted_tally(true)
		var result_poster: TextureRect = game.wanted_tally_posters[1]["card"].get_child(0)
		assert(result_poster.texture == game.WANTED_POSTER_TEXTURES[example[1]])
	game.clear_map_round = 4
	game._begin_wanted_tally(false)
	game.clear_map_round = 1
	game.combat_round_result = "YOU LOSE"
	game._begin_wanted_tally(true)
	assert(game.clear_map_poster_start == 6)
	print("Normal match expands to five greenshirts and runs full-row posters before ordered tallies")
	game.queue_free()
	quit()
