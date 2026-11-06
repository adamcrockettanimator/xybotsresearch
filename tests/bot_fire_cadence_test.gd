extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.single_player_combat_view = true
	game.clear_the_map_mode = true
	game.clear_map_round = 1
	game._apply_session_roster()
	assert(not game._is_bot_controlled_slot(0))
	assert(game._is_bot_controlled_slot(1))
	for dual_rounds in [0, 4]:
		for index in [0, 1]:
			game.player_states[index]["machine_gun_ammo"] = dual_rounds
			game.player_states[index]["pistol_ammo"] = 6
			game._spawn_pistol_shot(index)
		var player_interval := float(game.player_states[0]["fire_cooldown"])
		var bot_interval := float(game.player_states[1]["fire_cooldown"])
		var expected: float = game.DUAL_WIELD_FIRE_INTERVAL if dual_rounds > 0 else game.PISTOL_FIRE_INTERVAL
		assert(is_equal_approx(player_interval, expected))
		assert(is_equal_approx(bot_interval, player_interval * 2.0))
	print("Player and bot weapon cadence passed")
	game.queue_free()
	quit()
