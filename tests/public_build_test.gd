extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var scene = load("res://public_title.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	assert(bool(get_meta("grudge_public_build", false)))
	assert(scene.get_node_or_null("/root/GrudgeMusic") != null)
	scene._begin_public_match(-1)
	await process_frame
	await process_frame
	assert(current_scene != null)
	assert(current_scene.name == "CoordinateFrameNavigation")
	var game = current_scene.get_node("CoordinateFrameGame")
	assert(game._public_build())
	assert(not game.show_top_down_source_overlay)
	assert(not game.bot_decision_trace_enabled)
	assert(game._is_human_controlled_slot(0))
	game.clear_map_waiting_to_start = false
	game.player_states[0]["coins"] = 20
	game.player_states[0]["health"] = 5
	game.held_keycodes[KEY_Q] = true
	game._update_scoreboard_shop_input()
	assert(game.player_states[0]["health"] == 6)
	assert(game.player_states[0]["coins"] == 15)
	game.held_keycodes[KEY_Q] = false
	game.held_keycodes[KEY_E] = true
	game._update_scoreboard_shop_input()
	assert(game.player_states[0]["coins"] == 5)
	assert(game.player_states[0]["machine_gun_ammo"] > 0)
	print("Public title starts a solo match with diagnostics disabled and Q/E shop controls")
	quit()
