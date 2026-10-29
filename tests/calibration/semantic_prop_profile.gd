extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://tests/calibration/semantic_crate_authoring.tscn").instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	game._bind_player_context(0)
	var all_props: Array = game.semantic_lod_floor_footprints.duplicate()
	var groups := {"all": [], "barrels": [], "ray": [], "old_same_position": [], "crates": [], "empty": []}
	for prop in all_props:
		groups["all"].append(prop)
		if String(prop.id) == "barrel_ground_gpu_ray_experiment":
			groups["ray"].append(prop)
		elif String(prop.id).begins_with("barrel_ground_gpu_"):
			groups["barrels"].append(prop)
		elif bool(prop.get("flat_faces", false)):
			groups["crates"].append(prop)
	if not groups["ray"].is_empty():
		var old_prop: Dictionary = groups["ray"][0].duplicate()
		old_prop["id"] = "barrel_ground_gpu_reference"
		groups["old_same_position"].append(old_prop)
	for group in ["all", "barrels", "ray", "old_same_position", "ray", "crates", "empty", "all"]:
		game.semantic_lod_floor_footprints.clear()
		game.semantic_lod_floor_footprints.append_array(groups[group])
		for i in 3:
			game._render_live_semantic_floor_footprints()
		var start := Time.get_ticks_usec()
		for i in 20:
			game._render_live_semantic_floor_footprints()
		print("PROFILE group=%s count=%d cpu_ms_per_pass=%.3f" % [group, groups[group].size(), float(Time.get_ticks_usec() - start) / 20000.0])
	var ring_canvas: Variant = game.semantic_lod_floor_outline_nodes.get("0:barrel_ground_gpu_circle")
	if is_instance_valid(ring_canvas):
		var quad := PackedVector2Array([Vector2(40, 20), Vector2(80, 23), Vector2(75, 45), Vector2(42, 42)])
		var start := Time.get_ticks_usec()
		for i in 500:
			ring_canvas.low_resolution_canvas.ring_from_quad(quad)
		print("PROFILE ring_from_quad cpu_ms_per_ring=%.3f" % (float(Time.get_ticks_usec() - start) / 500000.0))
	game.semantic_lod_floor_footprints.clear()
	game.semantic_lod_floor_footprints.append_array(all_props)
	scene.queue_free()
	quit()
