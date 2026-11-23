extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func key(game: Node, code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	game._input(event)
func bumper(game: Node, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 5
	event.button_index = button
	event.pressed = true
	game._input(event)
	event.pressed = false
	game._input(event)
func run() -> void:
	var scene := (load("res://outdoor_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	game.player_device_ids[0] = 5
	game.player_states[0]["coins"] = 40
	game.player_states[0]["health"] = 3
	key(game, KEY_Q, true)
	game._process(0.016)
	key(game, KEY_Q, false)
	assert(game.player_states[0].coins == 35 and game.player_states[0].health == 4, "Q purchase failed in town game loop")
	game._process(0.016)
	key(game, KEY_E, true)
	game._process(0.016)
	key(game, KEY_E, false)
	assert(game.player_states[0].coins == 25 and game.player_states[0].machine_gun_ammo == game.DUAL_WIELD_AMMO, "E purchase failed in town game loop")
	game._process(0.016)
	bumper(game, JOY_BUTTON_LEFT_SHOULDER)
	game._process(0.016)
	assert(game.player_states[0].coins == 20 and game.player_states[0].health == 5, "LB purchase failed in town game loop")
	game._process(0.016)
	bumper(game, JOY_BUTTON_RIGHT_SHOULDER)
	game._process(0.016)
	assert(game.player_states[0].coins == 10 and game.player_states[0].machine_gun_ammo == game.DUAL_WIELD_AMMO, "RB purchase failed in town game loop")
	print("Town full-loop keyboard and bumper purchases passed")
	scene.queue_free()
	quit()
