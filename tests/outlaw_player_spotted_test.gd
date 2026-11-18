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
	var origin := Vector2(1.5, 1.5)
	game.player_states[1].world_position = origin
	var forward: Vector2 = game._view_forward_vector_for_state(game.player_states[1]).normalized()
	game.player_states[0].world_position = origin + forward
	# Use a known playable recording as a fixture, without changing the catalog.
	var bank: Dictionary = game.BOT_BARK_BANK.data.rowan
	bank["player_spotted"] = [bank.first_sighting[0].duplicate(true)]
	bank.player_spotted[0].id = "reacquisition test"
	bank.player_spotted[0].repeatable = false
	bank.player_spotted[0].min_enemies = 1
	bank.player_spotted[0].max_enemies = 999
	bank.player_spotted[0].weight = 1.0
	game.bot_brains[1] = {"first_sighting_barked": true}
	game.bot_bark_player.stop()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	game._update_bot_brain(1, game.player_states[1], origin, 0, forward, 1.0, forward, 0.1)
	assert(not game.bot_bark_used_lines.has("reacquisition test"), "initial sight is not reacquisition")
	game.bot_bark_player.stop()
	game.bot_bark_reverb_player.stop()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	# Turning away is sufficient to lose visual contact, without moving walls.
	game.player_states[0].world_position = origin - forward
	game._update_bot_brain(1, game.player_states[1], origin, 0, -forward, 1.0, -forward, 1.1)
	game.player_states[0].world_position = origin + forward
	game._update_bot_brain(1, game.player_states[1], origin, 0, forward, 1.0, forward, 0.1)
	assert(game.bot_bark_used_lines.has("reacquisition test"), "reacquisition should play its own tag")
	game.bot_bark_player.stop()
	game.bot_bark_reverb_player.stop()
	game.bot_bark_last_global = -INF
	game.bot_bark_last_by_bot.clear()
	game.bot_bark_used_lines.clear()
	game.player_states[0].world_position = origin - forward
	game._update_bot_brain(1, game.player_states[1], origin, 0, -forward, 1.0, -forward, 0.2)
	game.player_states[0].world_position = origin + forward
	game._update_bot_brain(1, game.player_states[1], origin, 0, forward, 1.0, forward, 0.1)
	assert(not game.bot_bark_used_lines.has("reacquisition test"), "brief occlusion should not retrigger")
	bank.erase("player_spotted")
	print("Player reacquisition has a distinct bark and ignores brief occlusion")
	game.queue_free()
	quit()
