extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://outdoor_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	assert(not game.world_coins.is_empty())
	assert(not game.world_hearts.is_empty())
	assert(not game.machine_gun_pickup.is_empty())
	var inside := Vector2.INF
	var outside_found := false
	for item in game.world_coins + game.world_hearts:
		var cell := Vector2i(Vector2(item.position).floor())
		assert(game._bot_cell_is_clear(cell))
		if game.town_has_roof(cell):
			inside = item.position
		else:
			outside_found = true
	assert(inside.is_finite() and outside_found)

	# Exercise the normal pickup code on a clear interior cell for each type.
	game.world_coins.clear()
	game.world_coins.append({"id": 100001, "position": inside, "value": 1})
	game.world_hearts.clear()
	game.world_hearts.append({"id": 100002, "position": inside})
	game.machine_gun_pickup = {"id": 100003, "position": inside, "ammo": game.DUAL_WIELD_AMMO}
	game.player_states[0]["world_position"] = inside
	game.player_states[0]["health"] = 1
	game.player_states[0]["machine_gun_ammo"] = 0
	var before: int = game.player_states[0]["coins"]
	game._collect_combat_pickups(0.0)
	assert(game.player_states[0]["coins"] == before + 1)
	assert(game.player_states[0]["health"] == 2)
	assert(game.player_states[0]["machine_gun_ammo"] == game.DUAL_WIELD_AMMO)
	assert(game.world_coins.is_empty() and game.world_hearts.is_empty() and game.machine_gun_pickup.is_empty())

	# The contested weapon's normal spawn pool also includes interior cells.
	seed(12345)
	var gun_inside := false
	for attempt in range(500):
		game._spawn_machine_gun_pickup()
		var cell := Vector2i(Vector2(game.machine_gun_pickup.position).floor())
		assert(game._bot_cell_is_clear(cell))
		if game.town_has_roof(cell):
			gun_inside = true
			break
	assert(gun_inside)
	print("Town indoor and outdoor pickups passed")
	scene.queue_free()
	quit()
