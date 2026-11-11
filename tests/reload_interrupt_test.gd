extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	for index in range(game.player_joined.size()):
		game.player_joined[index] = index == 0
	game.world_coins.clear()
	game.world_hearts.clear()
	game.world_barrel_guns.clear()
	game.machine_gun_pickup = {}
	var state: Dictionary = game.player_states[0]
	state["pistol_ammo"] = 3
	state["fire_cooldown"] = 0.0
	game._start_pistol_reload(state)
	assert(state["reload_phase"] == "open")
	game.held_keycodes[KEY_F] = true
	game._process_combat(0.01)
	assert(String(state["reload_phase"]).is_empty())
	assert(state["pistol_ammo"] == 2)
	game.held_keycodes[KEY_F] = false
	game._process_combat(0.01)
	game._process_combat(0.4)
	assert(state["pistol_ammo"] == 2 and String(state["reload_phase"]).is_empty())
	game.held_keycodes[KEY_R] = true
	game._process_combat(0.01)
	assert(not String(state["reload_phase"]).is_empty())
	game.held_keycodes[KEY_R] = false
	# The final round starts automatic reload. Holding fire must not cancel it
	# when its first new round enters the cylinder.
	state["reload_phase"] = ""
	state["pistol_ammo"] = 1
	state["fire_cooldown"] = 0.0
	state["fire_was_pressed"] = false
	game.held_keycodes[KEY_F] = true
	game._process_combat(0.01)
	assert(state["pistol_ammo"] == 0 and not String(state["reload_phase"]).is_empty())
	game._process_combat(0.22)
	assert(state["pistol_ammo"] == 1 and not String(state["reload_phase"]).is_empty())
	game._process_combat(0.3)
	assert(state["pistol_ammo"] >= 1 and not String(state["reload_phase"]).is_empty())
	# A new press with a loaded round interrupts even an automatic reload.
	game.held_keycodes[KEY_F] = false
	game._process_combat(0.01)
	game.held_keycodes[KEY_F] = true
	game._process_combat(0.01)
	assert(String(state["reload_phase"]).is_empty() or int(state["pistol_ammo"]) == 0)
	print("Fire interrupts a loaded reload; empty auto-reload survives held fire")
	game.queue_free()
	quit()
