extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	for index in range(4):
		game.player_joined[index] = true
		game.player_bots[index] = index > 0
		game.player_states[index] = game._make_player_state(index, Vector2i(2, 2), 0)
		game.player_states[index].world_position = Vector2(2.5, 2.5)
		if index > 0:
			game.player_states[index].voice_actor = "devin"
	var forward: Vector2 = game._view_forward_vector_for_state(game.player_states[1]).normalized()
	game.player_states[0].world_position = Vector2(2.5, 2.5) + forward
	assert(game._request_bot_bark(1, "first_sighting"))
	assert(game._request_bot_bark(2, "first_sighting"))
	assert(not game._request_bot_bark(3, "first_sighting"))
	assert(game.bot_bark_pending_mandatory.size() == 1)
	game.bot_damage_channels[1].player.stop()
	game._process_pending_mandatory_barks()
	assert(game.bot_bark_pending_mandatory.is_empty())
	assert(game.bot_damage_channels[3].player.playing)
	# A hit interrupts the same actor's sighting and schedules it to finish later.
	assert(game._request_bot_bark(3, "hit"))
	assert(game.bot_damage_channels[3].priority == 90)
	assert(game.bot_bark_pending_mandatory.size() == 1)
	game.bot_damage_channels[3].player.stop()
	game._process_pending_mandatory_barks()
	assert(game.bot_bark_pending_mandatory.is_empty())
	assert(game.bot_damage_channels[3].priority == 70)
	print("First-sighting reactions are staggered and survive interruption by a hit")
	game.queue_free()
	quit()
