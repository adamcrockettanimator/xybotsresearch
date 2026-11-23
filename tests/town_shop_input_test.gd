extends SceneTree
func _initialize() -> void:
	call_deferred("run")
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
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	game.player_device_ids[0] = 5
	game.player_states[0]["coins"] = 20
	game.player_states[0]["health"] = 3
	bumper(game, JOY_BUTTON_LEFT_SHOULDER)
	game._update_scoreboard_shop_input()
	assert(game.player_states[0].coins == 15 and game.player_states[0].health == 4)
	game._update_scoreboard_shop_input()
	assert(game.player_states[0].coins == 15)
	bumper(game, JOY_BUTTON_RIGHT_SHOULDER)
	game._update_scoreboard_shop_input()
	assert(game.player_states[0].coins == 5 and game.player_states[0].machine_gun_ammo == game.DUAL_WIELD_AMMO)
	print("Town bumper purchase input passed")
	scene.queue_free()
	quit()
