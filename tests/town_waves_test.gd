extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene := (load("res://outdoor_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	assert(not game.town_waves_enabled)
	assert(game.player_joined[0] and not game.player_joined[1])
	assert(game.options_overlay.get_node("PauseBroadside/TownWavesCheck") is CheckBox)
	game._set_town_waves_enabled(true)
	game._advance_town_waves(5.1)
	assert(game.town_wave_active and game.town_wave_number == 1)
	assert(game._living_enemy_count() == 3)
	for frame in range(3):
		game._process(0.016)
	game._update_combat_hud()
	assert(game.combat_round_timer_labels[0].visible and "WAVE 1" in game.combat_round_timer_labels[0].text)
	var origin: Vector2 = game._player_state_world_position(game.player_states[0])
	for index in range(1, 4):
		assert(game.player_joined[index] and game.player_bots[index])
		var bot: Dictionary = game.player_states[index]
		assert(bot.enemy_type != "player")
		assert(game._player_state_world_position(bot).distance_to(origin) >= 2.9)
		game._update_bot_input(index, 0.016)
		assert(game.bot_brains.has(index))
		game.player_states[index]["health"] = 0
		game._begin_combat_death(index)
	game._process_combat(10.0)
	for index in range(1, 4):
		assert(game.player_states[index].is_dying)
	game._advance_town_waves(0.1)
	assert(not game.town_wave_active and game.town_wave_countdown > 0.0)
	game._advance_town_waves(12.1)
	assert(game.town_wave_active and game.town_wave_number == 2 and game._living_enemy_count() == 4)
	var respawn: Dictionary = game._combat_respawn_destination(0)
	assert(not respawn.is_empty() and game._respawn_cell_is_safe(0, respawn.cell))
	game._set_town_waves_enabled(false)
	assert(not game.town_waves_enabled and game._living_enemy_count() == 0)
	for index in range(1, game.player_joined.size()):
		assert(not game.player_joined[index])
	print("Town wave lifecycle passed")
	scene.queue_free()
	quit()
