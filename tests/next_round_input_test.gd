extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._start_clear_map_round()
	var music: AudioStreamPlayer = root.get_node("GrudgeMusic")
	music.seek(12.0)
	game._finish_clear_map(true)
	game._advance_clear_map_finish(3.0)
	assert(music.playing and music.get_playback_position() >= 11.9 and is_zero_approx(music.volume_db))
	game.held_keycodes[KEY_X] = true
	game._process(0.016)
	assert(game.clear_map_waiting_to_start and not game.match_started and not game.combat_round_complete)
	assert(game.wanted_tally_overlay.visible and not game.wanted_tally_terminal)
	assert(game.wanted_tally_overlay.get_node("BeginButton").visible)
	assert(game.clear_map_round == 2 and game.wanted_tally_posters.size() == 2)
	assert(music.playing and music.get_playback_position() >= 11.9)
	assert(root.get_node("GrudgeMusic").current_mode == "menu")
	# One held press cannot skip the poster screen.
	game.held_keycodes[KEY_X] = true
	game._process(0.016)
	assert(game.clear_map_waiting_to_start and game.wanted_tally_overlay.visible)
	game.held_keycodes[KEY_X] = false
	game._process(0.016)
	game.held_keycodes[KEY_X] = true
	game._process(0.016)
	assert(not game.clear_map_waiting_to_start and game.match_started and not game.wanted_tally_overlay.visible)
	assert(root.get_node("GrudgeMusic").current_mode == "menu")
	# A loss leads to the round-one poster screen too.
	game.held_keycodes[KEY_X] = false
	game._read_next_round()
	music.seek(24.0)
	game._finish_clear_map(false)
	game._advance_clear_map_finish(3.0)
	assert(game.post_kill_active and game.clear_map_finish_pending)
	assert(music.playing and music.get_playback_position() >= 23.9 and is_zero_approx(music.volume_db))
	game.held_keycodes[KEY_X] = true
	game._process(0.016)
	assert(not game.clear_map_waiting_to_start and game.match_started and not game.wanted_tally_overlay.visible)
	assert(game.clear_map_round == 1 and game.wanted_tally_posters.size() == 1)
	assert(music.playing and music.get_playback_position() >= 23.9)
	assert(root.get_node("GrudgeMusic").current_mode == "menu")
	print("Win returns to the briefing; loss skips directly to a fresh round")
	game.queue_free()
	quit()
