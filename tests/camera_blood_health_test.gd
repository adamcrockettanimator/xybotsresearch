extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	assert(game._apply_projectile_hit(0, Vector2.RIGHT))
	assert(game.combat_camera_blood_droplets[0].size() == game.CAMERA_BLOOD_DROPS_PER_HEALTH)
	for droplet in game.combat_camera_blood_droplets[0]:
		var p: Vector2 = droplet.position
		assert(p.x <= game.VIEWPORT_SIZE.x * 0.17 or p.x >= game.VIEWPORT_SIZE.x * 0.83 or p.y <= game.VIEWPORT_SIZE.y * 0.17 or p.y >= game.VIEWPORT_SIZE.y * 0.83)
	assert(game._apply_projectile_hit(0, Vector2.RIGHT))
	assert(game.combat_camera_blood_droplets[0].size() == 2 * game.CAMERA_BLOOD_DROPS_PER_HEALTH)
	game.player_states[0]["health"] += 1
	game._clear_camera_blood_for_heart(0)
	assert(game.combat_camera_blood_droplets[0].size() == game.CAMERA_BLOOD_DROPS_PER_HEALTH)
	game.player_states[0]["health"] += 1
	game._clear_camera_blood_for_heart(0)
	assert(game.combat_camera_blood_droplets[0].is_empty())
	game.player_states[0]["health"] = 6
	assert(game._apply_projectile_hit(0, Vector2.RIGHT))
	assert(game.combat_camera_blood_droplets[0].is_empty())
	game.player_states[0]["health"] = 3
	assert(game._apply_projectile_hit(0, Vector2.RIGHT))
	game._regenerate_runtime_map()
	assert(game.combat_camera_blood_droplets[0].is_empty())
	assert(game.combat_player_blood_decals[0].is_empty())
	print("camera blood health test passed")
	game.queue_free()
	quit()
