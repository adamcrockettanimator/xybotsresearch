extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.player_bots[0] = false
	var forward: Vector2 = game._view_forward_vector_for_state(game.player_states[0]).normalized()
	game._spawn_pistol_shot(0)
	assert(Vector2(game.active_projectiles.back()["direction"]).is_equal_approx(forward))
	game.player_bots[0] = true
	seed(419)
	var left := false
	var right := false
	var would_miss_at_range := false
	for i in range(64):
		game._spawn_pistol_shot(0)
		var direction: Vector2 = game.active_projectiles.back()["direction"]
		var angle := forward.angle_to(direction)
		assert(absf(angle) <= deg_to_rad(game.BOT_SHOT_SPREAD_DEGREES) + 0.00001)
		left = left or angle < -0.001
		right = right or angle > 0.001
		would_miss_at_range = would_miss_at_range or absf(sin(angle)) * 3.0 > game.PLAYER_CAPSULE_RADIUS
	assert(left and right and would_miss_at_range)
	print("Bot shots vary within their spread; human shots remain accurate")
	game.queue_free()
	quit()
