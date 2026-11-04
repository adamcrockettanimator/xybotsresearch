extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _piece(game: Node, part: String) -> Dictionary:
	for prop in game.world_barrels:
		if String(prop.get("footprint_key", "")).contains(part):
			return prop
	return {}

func _destroy(game: Node, prop: Dictionary) -> void:
	for i in 3:
		game._damage_barrel(int(prop["id"]), Vector2.RIGHT, prop["position"], 0.5)

func _proxies(game: Node) -> Array:
	return game.world_barrels.filter(func(prop): return bool(prop.get("dining_navigation_proxy", false)))

func _run() -> void:
	var scene: Node = load("res://tests/calibration/semantic_typical_game.tscn").instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	var table := _piece(game, "table_dining")
	var near := _piece(game, "stool_dining")
	var far := _piece(game, "bench_dining")
	assert(not table.is_empty() and not near.is_empty() and not far.is_empty())
	var center: Vector2 = table["position"]
	assert(_proxies(game).size() == 1)
	_destroy(game, near)
	var proxies := _proxies(game)
	assert(proxies.size() == 1)
	var proxy: Dictionary = proxies[0]
	assert(is_equal_approx(Vector2(proxy["position"]).y + Vector2(proxy["half_extents"]).y, center.y + 0.125))
	assert(bool(_piece(game, "bench_dining").get("skip_character_collision", false)))
	_destroy(game, table)
	assert(_proxies(game).is_empty())
	assert(game._bot_cell_is_clear(Vector2i(center)))
	assert(not bool(_piece(game, "bench_dining").get("skip_character_collision", true)))
	_destroy(game, far)
	assert(_proxies(game).is_empty())
	game._reset_world_barrels()
	table = _piece(game, "table_dining")
	center = table["position"]
	_destroy(game, table)
	assert(_proxies(game).is_empty())
	assert(game._barrel_sweep_hit(center + Vector2(-0.3, 0), Vector2(0.6, 0)).is_empty())
	assert(not game._barrel_sweep_hit(center + Vector2(-0.3, 0.22), Vector2(0.6, 0)).is_empty())
	var steering: Vector2 = game._bot_avoid_world_barrels(center, Vector2.RIGHT)
	assert(steering.x > 0.99)
	print("Dining collision transitions and passage passed")
	scene.queue_free()
	quit()
