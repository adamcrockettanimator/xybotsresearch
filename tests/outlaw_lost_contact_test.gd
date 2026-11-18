extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game.player_joined[0] = true
	game.player_joined[1] = true
	game.player_bots[1] = true
	game.player_states[1] = game._make_player_state(1, Vector2i(1, 1), 0)
	game.player_states[1].voice_actor = "rowan"
	game.player_states[1].world_position = Vector2(1.5, 1.5)
	game.player_states[0].world_position = Vector2(2.5, 1.5)
	game._set_wall_between(Vector2i(1, 1), Vector2i.RIGHT, true)
	game.bot_bark_player.stop()
	game.bot_bark_reverb_player.stop()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	game.bot_bark_used_lines.clear()
	game.bot_brains[1] = {"last_seen_position": Vector2(2.5, 1.5), "last_seen_target": 0, "lost_sight_time": 4.8, "state": "SEARCH"}
	var brain: Dictionary = game._update_bot_brain(1, game.player_states[1], Vector2(1.5, 1.5), 0, Vector2.RIGHT, 1.0, Vector2.RIGHT, 0.1)
	assert(not game.bot_bark_player.playing)
	brain = game._update_bot_brain(1, game.player_states[1], Vector2(1.5, 1.5), 0, Vector2.RIGHT, 1.0, Vector2.RIGHT, 0.2)
	assert(brain.get("lost_contact_barked", false) and game.bot_bark_player.playing)
	print("Lost-contact barks wait five seconds")
	game.queue_free()
	quit()
