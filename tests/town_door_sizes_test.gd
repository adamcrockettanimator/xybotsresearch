extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene := (load("res://outdoor_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	for building in game.TOWN_BUILDINGS:
		for edge in building.room_door_spans({}):
			if edge.has("push_door"):
				assert(is_equal_approx(Vector2(edge.a).distance_to(edge.b), game.STOREFRONT_STYLE.FRONT_DOOR.y - game.STOREFRONT_STYLE.FRONT_DOOR.x))
				assert(edge.paint == 3)
	var saloon: Resource = game.TOWN_BUILDINGS[3]
	var leaves: Array = saloon.door_leaf_spans({})
	var gates := leaves.filter(func(leaf: Dictionary) -> bool: return leaf.push_door == "saloon_swing_front")
	assert(gates.size() == 2)
	assert(gates.all(func(gate: Dictionary) -> bool: return gate.bottom > saloon.FLOOR_HEIGHT and gate.height < saloon.DOOR_HEIGHT))
	var rear := leaves.filter(func(leaf: Dictionary) -> bool: return leaf.push_door != "saloon_swing_front")
	assert(rear.size() == 2 and rear[0].height == saloon.DOOR_HEIGHT)
	game.player_states[0]["world_position"] = Vector2(saloon.door_x(), saloon.frontage() - 0.15)
	game.storefront_open_doors["saloon_swing_front"] = 0.05
	game._advance_storefront_doors(0.3)
	assert(is_equal_approx(game.storefront_open_doors["saloon_swing_front"], 1.0))
	game._advance_storefront_doors(0.3)
	assert(game.storefront_open_doors.has("saloon_swing_front"))
	game.player_states[0]["world_position"] = Vector2(saloon.door_x(), saloon.frontage() + 0.8)
	game._advance_storefront_doors(0.3)
	assert(not game.storefront_open_doors.has("saloon_swing_front"))

	game.world_barrels.clear()
	var midpoint := Vector2(saloon.door_x(), saloon.frontage())
	for normal: Vector2 in [Vector2.UP, Vector2.DOWN]:
		game.storefront_open_doors.clear()
		game.storefront_closing_doors.clear()
		game.physical_wall_edges_cache_dirty = true
		var approach := midpoint + normal * 0.28
		game.player_states[0]["world_position"] = approach
		game._move_world_with_wall_slide(approach, -normal * 0.55, "e", "w", "s", "n", true)
		assert(game.storefront_open_doors.has("saloon_swing_front"))
		game._advance_storefront_doors(0.3)
		var exit: Vector2 = game._move_world_with_wall_slide(approach, -normal * 0.70, "e", "w", "s", "n", true)
		assert((exit - midpoint).dot(normal) < -0.15, "Saloon gate blocked passage from %s" % normal)

	for building in [game.TOWN_BUILDINGS[1], game.TOWN_BUILDINGS[2], saloon]:
		for definition in building.partition_doors:
			game.storefront_open_doors.clear()
			game.storefront_closing_doors.clear()
			var all_closed: Array = building.room_door_spans({})
			var closed_leaves: Array = all_closed.filter(func(edge: Dictionary) -> bool: return not String(edge.get("push_door", "")).is_empty())
			var id := "room_%s_%s_%s" % [building.footprint.position, building.footprint.position + Vector2i(definition.x, definition.y), Vector2i(definition.z, definition.w)]
			assert(closed_leaves.any(func(edge: Dictionary) -> bool: return edge.push_door == id))
			game.storefront_open_doors[id] = 1.0
			game.physical_wall_edges_cache_dirty = true
			var leaf: Dictionary = building.room_door_spans(game.storefront_open_doors).filter(func(edge: Dictionary) -> bool: return edge.get("close_door", "") == id)[0]
			var along: Vector2 = Vector2(leaf.b) - Vector2(leaf.a)
			var movement := along.orthogonal().normalized() * 0.35
			var middle: Vector2 = Vector2(leaf.a).lerp(Vector2(leaf.b), 0.65)
			game._move_world_with_wall_slide(middle - movement.normalized() * 0.19, movement, "e", "w", "s", "n", true)
			assert(game.storefront_closing_doors.has(id), "Door did not close when pushed: %s" % id)
	var edges: Array = game._all_physical_wall_edges()
	for building in [game.TOWN_BUILDINGS[1], game.TOWN_BUILDINGS[2], saloon]:
		for door in building.room_door_spans({}):
			if not door.get("room_lintel", false):
				continue
			var lintel_key: String = game._physical_edge_key(door.a, door.b) + ":room_lintel"
			assert(edges.any(func(edge: Dictionary) -> bool: return edge.key == lintel_key))
	print("Coffee-sized room doors and saloon gates passed")
	scene.queue_free()
	quit()
