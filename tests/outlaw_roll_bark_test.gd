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
	game.player_states[1] = game._make_player_state(1, Vector2i(2, 2), 0)
	game.player_states[1].voice_actor = "rowan"
	var origin := Vector2(2.5, 2.5)
	game.player_states[1].world_position = origin
	var forward: Vector2 = game._view_forward_vector_for_state(game.player_states[1]).normalized()
	game.player_states[0].world_position = origin + forward
	game.player_states[0].dive_active = true
	game.bot_bark_player.stop()
	game.bot_bark_reverb_player.stop()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	game.bot_bark_used_lines.clear()
	game.bot_brains.clear()
	game.bot_brains[1] = {"first_sighting_barked": true}
	var brain: Dictionary = game._update_bot_brain(1, game.player_states[1], origin, 0, forward, 1.0, forward, 0.016)
	assert(brain.bark_visible_roll)
	assert(game.bot_bark_used_lines.has("where are you rolling off to") or game.bot_bark_used_lines.has("acting like a goddamn tumbleweed"))
	for actor in ["zach", "devin", "adam"]:
		assert(not game.BOT_BARK_BANK.data[actor].has("player_roll"))
	print("Only Rowan reacts to a visibly observed dive roll")
	game.queue_free()
	quit()
