extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	root.push_input(event)
func joy(button: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	root.push_input(event)
func stick(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_LEFT_Y
	event.axis_value = value
	root.push_input(event)
func run() -> void:
	var scene := (load("res://outdoor_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	game.match_paused = true
	game.options_overlay.visible = true
	var check: CheckBox = game.options_overlay.get_node("PauseBroadside/TownWavesCheck")
	check.grab_focus()
	await process_frame
	assert(root.gui_get_focus_owner() == check)
	joy(JOY_BUTTON_DPAD_DOWN, true)
	joy(JOY_BUTTON_DPAD_DOWN, false)
	await process_frame
	assert(root.gui_get_focus_owner() == game.map_display_button)
	stick(-1.0)
	await process_frame
	stick(0.0)
	await process_frame
	assert(root.gui_get_focus_owner() == check)
	joy(JOY_BUTTON_A, true)
	joy(JOY_BUTTON_A, false)
	await process_frame
	assert(check.button_pressed and game.town_waves_enabled)
	joy(JOY_BUTTON_A, true)
	joy(JOY_BUTTON_A, false)
	await process_frame
	assert(not check.button_pressed and not game.town_waves_enabled)
	print("Town wave pause controller focus passed")
	scene.queue_free()
	quit()
