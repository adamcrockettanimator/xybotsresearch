extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://tests/calibration/semantic_typical_game.tscn").instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	assert(not game.BARREL_LOD_REVIEW_LEVEL)
	assert(game.semantic_typical_props_enabled)
	assert(game.single_player_sandbox_mode)
	assert(game.world_barrels.size() == 11)
	assert(game.semantic_lod_floor_footprints.size() == 11)
	var gpu_cage_barrels := 0
	var fragment_raster_crates := 0
	var dining_pieces := 0
	var dining_target: Dictionary = {}
	for prop in game.world_barrels:
		var key := String(prop["footprint_key"])
		if key.contains("_dining"):
			assert(prop.has("half_extents"))
			assert(float(prop.get("projectile_height", 0.0)) >= 1.0)
			dining_pieces += 1
			dining_target = prop
		elif key.begins_with("barrel_gpu_lattice_instanced_room_"):
			gpu_cage_barrels += 1
		elif key.begins_with("crate_gpu_fragment_raster_room_"):
			fragment_raster_crates += 1
		else:
			assert(false)
	assert(gpu_cage_barrels == 4)
	assert(fragment_raster_crates == 4)
	assert(dining_pieces == 3)
	var target: Dictionary = dining_target
	var key := String(target["footprint_key"])
	var position: Vector2 = target["position"]
	for i in 3:
		game._damage_barrel(int(target["id"]), Vector2.RIGHT, position, 0.5)
	assert(game.world_barrels.size() == 10)
	var destroyed := false
	for footprint in game.semantic_lod_floor_footprints:
		if footprint["id"] == key:
			destroyed = bool(footprint.get("destroyed", false))
	assert(destroyed)
	game._reset_world_barrels()
	assert(game.world_barrels.size() == 11)
	assert(game.semantic_lod_floor_footprints.size() == 11)
	print("Typical maze semantic props: 4 GPU cage barrels, 4 fragment-raster crates, and a destructible three-piece dining set passed")
	scene.queue_free()
	quit()
