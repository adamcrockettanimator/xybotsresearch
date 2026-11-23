extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://outdoor_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	for start in [Vector2i(0, 0), Vector2i(4, 4), Vector2i(9, 8)]:
		var distances: Dictionary = game._bot_cell_distances(start)
		for y in range(game.MAP_HEIGHT):
			for x in range(game.MAP_WIDTH):
				var target := Vector2i(x, y)
				var route: Array = game._bot_cell_route(start, target)
				assert(distances.has(target) == not route.is_empty())
				if not route.is_empty():
					assert(int(distances[target]) + 1 == route.size())
	assert(game._bot_cell_distances(Vector2i(-1, -1)).is_empty())
	# A changed topology must be searched afresh, including unreachable cells.
	var isolated := Vector2i(4, 4)
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		game._set_wall_between(isolated, direction, true)
	var isolated_distances: Dictionary = game._bot_cell_distances(isolated)
	assert(isolated_distances.size() == 1 and isolated_distances[isolated] == 0)
	assert(game._bot_cell_route(isolated, Vector2i(5, 4)).is_empty())
	print("Bot distance field matches routes")
	scene.queue_free()
	quit()
