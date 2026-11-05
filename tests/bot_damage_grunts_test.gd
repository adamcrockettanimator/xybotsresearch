extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.player_bots[1] = true
	game.player_joined[0] = true
	game.player_joined[1] = true
	game.player_states[0] = game._make_player_state(0, Vector2i(2, 2), 0)
	game.player_states[0]["world_position"] = Vector2(2.5, 2.5)
	game.player_states[1] = game._make_player_state(1, Vector2i(3, 2), 0)
	game.player_states[1]["world_position"] = Vector2(3.5, 2.5)
	for sample in range(1, game.BOT_DAMAGE_SAMPLE_COUNT + 1):
		assert(load(game.BOT_DAMAGE_ROOT + "%02d. Damage Grunt (Male).wav" % sample) is AudioStream)
	assert(game._apply_projectile_hit(1, Vector2.RIGHT, 0))
	assert(game.bot_damage_channels.has(1))
	var channel: Dictionary = game.bot_damage_channels[1]
	assert(channel["player"].playing)
	assert(channel["panner"].pan > 0.8)
	var first: String = game.bot_damage_last_sample[1]
	game.player_states[1]["health"] = 1
	assert(game._apply_projectile_hit(1, Vector2.RIGHT, 0))
	assert(game.player_states[1]["is_dying"])
	assert(channel["player"].playing)
	assert(game.bot_damage_last_sample[1] != first)
	assert(not game._apply_projectile_hit(1, Vector2.RIGHT, 0))
	assert(game.bot_damage_last_sample[1].begins_with(game.EFFORT_GRUNT_ROOT))
	assert(game._play_bot_damage_grunt(0))
	assert(game.bot_damage_last_sample[0].begins_with(game.EFFORT_GRUNT_ROOT))
	for sample in game.EFFORT_HIT_SAMPLES + game.EFFORT_DEATH_SAMPLES + game.EFFORT_VICTORY_SAMPLES:
		assert(load(game.EFFORT_GRUNT_ROOT + "%02d. Effort Grunt (Male).wav" % sample) is AudioStream)
	print("NPC damage grunts: assets, hit, lethal hit, spatialization and guards passed")
	game.queue_free()
	quit()
