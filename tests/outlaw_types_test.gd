extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	assert(game.wanted_tally_overlay.get_node("RoundInstruction").text == "KILL ALL THE OUTLAWS!")
	var expected := ["weak", "weak", "clever", "clever", "strong", "weak", "clever", "weak", "weak", "strong"]
	for round_number in range(1, 11):
		game.clear_map_round = round_number
		game._apply_session_roster()
		var counts := {"weak": 0, "clever": 0, "strong": 0}
		for index in range(1, round_number + 1):
			assert(game.player_joined[index])
			var state: Dictionary = game._make_player_state(index, Vector2i(1, 1), 0)
			assert(state.enemy_type == expected[index - 1])
			counts[state.enemy_type] += 1
			match state.enemy_type:
				"weak":
					assert(state.health == 1 and state.voice_actor in ["zach", "devin"])
					assert(game._enemy_heart_cap(state) == 3 and not game._can_use_dual_pistols(state))
				"clever":
					assert(state.health == 2 and state.voice_actor in ["devin", "rowan"])
					assert(game._enemy_heart_cap(state) == 4 and game._can_use_dual_pistols(state))
				"strong":
					assert(state.health == 3 and state.voice_actor in ["rowan", "adam"])
					assert(game._enemy_heart_cap(state) == game.PLAYER_MAX_HEALTH and game._can_use_dual_pistols(state))
		if round_number == 10:
			assert(counts == {"weak": 5, "clever": 3, "strong": 2})
		game._reset_player_states_after_map(Vector2i(0, 0))
		for attempt in range(50):
			game._assign_round_bot_voices()
			var voices: Array = []
			for index in range(1, round_number + 1):
				var voice: String = game.player_states[index].voice_actor
				assert(voice in game.BOT_BARK_VOICES)
				if index <= 4:
					assert(not voices.has(voice), "The first four outlaws must have different voices")
				if index <= 2:
					assert(voice in ["zach", "devin"])
				if index == 3:
					assert(voice == "rowan")
				if index == 4:
					assert(voice == "adam")
				if index > 4:
					var kind: String = game.player_states[index].enemy_type
					var preferred := ["zach", "devin"] if kind == "weak" else ["devin", "rowan"] if kind == "clever" else ["rowan", "adam"]
					assert(voice in preferred)
				voices.append(voice)
	game.clear_map_round = 3
	game._apply_session_roster()
	game._reset_player_states_after_map(Vector2i(0, 0))
	assert(game.player_states[1].health == 1 and game.player_states[2].health == 1 and game.player_states[3].health == 2)
	var sample := Sprite2D.new()
	game._apply_runtime_world_sprite_style(sample, 1.0, 1, 0.0, true, true)
	var green: Color = sample.material.get_shader_parameter("costume_hue")
	game._apply_runtime_world_sprite_style(sample, 1.0, 3, 0.0, true, true)
	var yellow: Color = sample.material.get_shader_parameter("costume_hue")
	assert(green.g > green.r and yellow.r > yellow.b and yellow.g > yellow.b)
	sample.free()
	game.player_states[0].world_position = Vector2(0.5, 0.5)
	game.player_states[1].world_position = Vector2(1.5, 1.5)
	game.player_states[2].world_position = Vector2(3.5, 3.5)
	game.player_states[3].world_position = Vector2(2.5, 2.5)
	game.player_states[1].health = 3
	game.world_hearts.clear()
	game.world_hearts.append({"id": 1, "position": Vector2(1.5, 1.5)})
	game.world_barrel_guns.clear()
	game.world_barrel_guns.append({"id": 2, "position": Vector2(1.5, 1.5), "ammo": 12})
	game._collect_combat_pickups(0.0)
	assert(game.player_states[1].health == 3 and game.world_hearts.size() == 1)
	assert(game.player_states[1].machine_gun_ammo == 0 and game.world_barrel_guns.size() == 1)
	game.player_states[1].health = 2
	game._collect_combat_pickups(0.0)
	assert(game.player_states[1].health == 3 and game.world_hearts.is_empty())
	game.player_states[1].world_position = Vector2(0.5, 3.5)
	game.player_states[3].world_position = Vector2(1.5, 1.5)
	game._collect_combat_pickups(0.0)
	assert(game.player_states[3].machine_gun_ammo == 12 and game.world_barrel_guns.is_empty())
	print("Round roster, voice assignment, health limits and pickup restrictions passed")
	game.queue_free()
	quit()
