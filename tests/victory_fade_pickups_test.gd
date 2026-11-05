extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._start_clear_map_round()
	game.bots_enabled = false
	game.world_coins.clear()
	game.world_hearts.clear()
	game.world_barrel_guns.clear()
	game.machine_gun_pickup = {}
	var pos: Vector2 = game._player_state_world_position(game.player_states[0])
	game.player_states[0]["coins"] = 4
	game.player_states[0]["health"] = 2
	game.player_states[0]["machine_gun_ammo"] = 0
	game._finish_clear_map(true)
	assert(game.clear_map_finish_pending)
	game.world_coins.append({"id": 900001, "position": pos, "value": 2})
	game.world_hearts.append({"id": 900002, "position": pos})
	game.world_barrel_guns.append({"id": 900003, "position": pos, "ammo": 7})
	# Exercise the actual final frame: pickup processing must precede capture.
	game.clear_map_finish_timer = game.CLEAR_MAP_RESULT_FADE_SECONDS - 0.01
	game._process(0.016)
	assert(not game.clear_map_finish_pending)
	assert(game.clear_map_carried_inventory["coins"] == 6)
	assert(game.clear_map_carried_inventory["health"] == 3)
	assert(game.clear_map_carried_inventory["machine_gun_ammo"] == 7)
	assert(game.world_coins.is_empty() and game.world_hearts.is_empty() and game.world_barrel_guns.is_empty())
	# Completed results and the ordinary timed match still freeze coin/hearts.
	game.world_coins.append({"id": 900004, "position": pos, "value": 1})
	game.world_hearts.append({"id": 900005, "position": pos})
	game._collect_combat_pickups(0.0)
	assert(game.world_coins.size() == 1 and game.world_hearts.size() == 1)
	game.clear_map_finish_pending = true
	game.clear_map_finish_victory = false
	game._collect_combat_pickups(0.0)
	assert(game.world_coins.size() == 1 and game.world_hearts.size() == 1)
	game.clear_the_map_mode = false
	game.clear_map_finish_pending = true
	game.clear_map_finish_victory = true
	game._collect_combat_pickups(0.0)
	assert(game.world_coins.size() == 1 and game.world_hearts.size() == 1)
	print("Victory fade collects and carries final-frame pickups without extending the fade")
	game.queue_free()
	quit()
