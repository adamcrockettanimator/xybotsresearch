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
	assert(game.world_barrels.size() == 8)
	assert(game.semantic_lod_floor_footprints.size() == 8)
	var gpu_cage_barrels := 0
	for prop in game.world_barrels:
		assert(String(prop["footprint_key"]).begins_with("barrel_gpu_lattice_instanced_room_"))
		assert(prop.has("collision_radius"))
		assert(not prop.has("half_extents"))
		gpu_cage_barrels += 1
	assert(gpu_cage_barrels == 8)
	var target: Dictionary = game.world_barrels[0]
	var key := String(target["footprint_key"])
	var position: Vector2 = target["position"]
	for i in 3:
		game._damage_barrel(int(target["id"]), Vector2.RIGHT, position, 0.5)
	assert(game.world_barrels.size() == 7)
	var destroyed := false
	for footprint in game.semantic_lod_floor_footprints:
		if footprint["id"] == key:
			destroyed = bool(footprint.get("destroyed", false))
	assert(destroyed)
	game._reset_world_barrels()
	assert(game.world_barrels.size() == 8)
	assert(game.semantic_lod_floor_footprints.size() == 8)
	print("Typical maze semantic props: 8 GPU cage barrels, destruction and reset passed")
	scene.queue_free()
	quit()
