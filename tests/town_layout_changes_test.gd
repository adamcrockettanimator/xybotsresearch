extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene := (load("res://outdoor_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	var store: Resource = game.TOWN_BUILDINGS[0]
	var hotel: Resource = game.TOWN_BUILDINGS[1]
	assert(store.partitions.is_empty())
	assert(hotel.ground_windows("front").size() == 3)
	for building in game.TOWN_BUILDINGS:
		for span in building.porch_rail_spans():
			assert(is_equal_approx(span.a.y, span.b.y))
	var table_count := 0
	var store_cover := 0
	for piece in game.semantic_lod_floor_footprints:
		if Rect2(store.footprint).has_point(piece.position):
			if String(piece.id).begins_with("chair_semantic_table_dining"):
				table_count += 1
			if piece.get("town_cover", false):
				store_cover += 1
	var pile_counts := {}
	for piece in game.semantic_lod_floor_footprints:
		var id := String(piece.get("id", ""))
		if "front_pile" in id:
			for name in ["coffee", "general store", "hotel", "bank", "saloon"]:
				if "_" + name + "_front_pile" in id:
					pile_counts[name] = int(pile_counts.get(name, 0)) + 1
	print("Porch pile counts: ", pile_counts)
	assert(table_count == 2)
	assert(store_cover >= 4)

	var coffee: Rect2i = game.STOREFRONT_STYLE.FOOTPRINT
	var bank: Resource = game.TOWN_BUILDINGS[2]
	var saloon: Resource = game.TOWN_BUILDINGS[3]
	assert(coffee == Rect2i(1, 6, 1, 2))
	assert(bank.footprint == Rect2i(7, 6, 2, 2))
	assert(saloon.footprint == Rect2i(3, 6, 4, 2))
	assert(game._has_wall_edge(Vector2i(6, 6), Vector2i.RIGHT))
	assert(bank.partition_doors.size() == 1 and hotel.partition_doors.size() == 7 and saloon.partition_doors.size() == 4)
	assert(game.town_roof_rects().size() == 5)
	game.world_barrels.clear()
	for building in [bank, hotel, saloon]:
		for door in building.partition_doors:
			game.storefront_open_doors.clear()
			game.storefront_closing_doors.clear()
			game.physical_wall_edges_cache_dirty = true
			var cell: Vector2i = building.footprint.position + Vector2i(door.x, door.y)
			var dir := Vector2i(door.z, door.w)
			var midpoint := Vector2(cell) + Vector2(0.5, 0.5) + Vector2(dir) * 0.5
			var normal := Vector2(dir)
			game._move_world_with_wall_slide(midpoint - normal * 0.25, normal * 0.45, "e", "w", "s", "n", true)
			assert(not game.storefront_open_doors.is_empty(), "Room door failed to open at %s" % midpoint)
			game._advance_storefront_doors(0.3)
			var landing: Vector2 = game._move_world_with_wall_slide(midpoint - normal * 0.25, normal * 0.5, "e", "w", "s", "n", true)
			assert((landing - midpoint).dot(normal) > 0.05, "Room door blocked at %s" % midpoint)
	print("Town store and porch changes passed")
	scene.queue_free()
	quit()
