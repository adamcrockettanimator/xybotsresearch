extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.clear_the_map_mode = true
	game.clear_map_round = 3
	game._apply_session_roster()
	assert(game._is_human_controlled_slot(0) and game._is_bot_controlled_slot(1))
	var human_health: int = game.player_states[0]["health"]
	var bot_health: int = game.player_states[1]["health"]
	game.show_bot_navigation_debug = true
	assert(not game._apply_projectile_hit(0, Vector2.RIGHT))
	assert(game.player_states[0]["health"] == human_health)
	assert(game._apply_projectile_hit(1, Vector2.RIGHT))
	assert(game.player_states[1]["health"] == bot_health - 1)
	game.show_bot_navigation_debug = false
	assert(game._apply_projectile_hit(0, Vector2.RIGHT))
	assert(game.player_states[0]["health"] == human_health - 1)
	print("Bot navigation protects human players while NPC damage remains enabled")
	game.queue_free()
	quit()
