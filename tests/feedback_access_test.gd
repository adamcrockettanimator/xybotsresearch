extends SceneTree

const Feedback = preload("res://scripts/feedback_access.gd")

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	assert(Feedback.available())
	var info := Feedback.diagnostics("Playing, round 2", Vector2(960, 720))
	assert(info.contains("Game build: " + str(ProjectSettings.get_setting("application/config/version"))))
	assert(info.contains("Game context: Playing, round 2"))
	assert(info.contains("Game viewport: 960 x 720"))
	assert(info.contains("Controllers connected:"))
	var url := Feedback.feedback_url("Playing, round 2", Vector2(960, 720))
	assert(url.contains("entry.1263596551="))
	assert(url.get_slice("entry.1263596551=", 1).uri_decode() == info)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	assert(Feedback.is_shortcut(enter))
	enter.echo = true
	assert(not Feedback.is_shortcut(enter))
	var title = load("res://public_title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	assert(title.get_node("FeedbackButton").visible)
	title._begin_public_match(-1)
	await process_frame
	await process_frame
	var game = current_scene.get_node("CoordinateFrameGame")
	assert(game.options_overlay.get_node("FeedbackButton").visible)
	assert(game.wanted_tally_overlay.get_node("FeedbackButton").visible)
	game.held_keycodes[KEY_ENTER] = true
	assert(not game._read_next_round())
	game.held_keycodes[KEY_ENTER] = false
	game.held_keycodes[KEY_SPACE] = true
	assert(game._read_next_round())
	print("Feedback prompts and Enter/Space bindings verified")
	quit()

