extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	set_meta("grudge_public_build", true)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.match_paused = true
	Input.action_press(game.ACTION_TOGGLE_DEBUG_MENU)
	game._process(0.016)
	assert(game.debug_menu_open)
	assert(game.debug_menu_panel.visible)
	assert(game.debug_menu_checks.has("bot_navigation"))
	var check: CheckBox = game.debug_menu_checks["bot_navigation"]
	check.button_pressed = true
	assert(game.show_bot_navigation_debug)
	Input.action_release(game.ACTION_TOGGLE_DEBUG_MENU)
	game._process(0.016)
	Input.action_press(game.ACTION_TOGGLE_DEBUG_MENU)
	game._process(0.016)
	assert(not game.debug_menu_open and not game.debug_menu_panel.visible)
	Input.action_release(game.ACTION_TOGGLE_DEBUG_MENU)
	print("F3 debug menu and Bot Navigation work in public-title mode while paused")
	game.queue_free()
	quit()
