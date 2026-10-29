extends SceneTree

# Measure the actual normal-maze semantic-prop workload. The gallery is not
# instantiated here, so its comparison barrels cannot affect these timings.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var report := FileAccess.open("user://semantic_typical_prop_profile.csv", FileAccess.WRITE)
	if report == null:
		push_error("Could not open semantic typical prop profile report")
		quit(1)
		return
	report.store_line("group,count,cpu_ms_per_pass")
	var scene: Node = load("res://tests/calibration/semantic_typical_game.tscn").instantiate()
	root.add_child(scene)
	for frame in 5:
		await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	game._bind_player_context(0)
	var all_props: Array = game.semantic_lod_floor_footprints.duplicate()
	var groups := {"empty": [], "crates": [], "canvas_barrels": [], "all": all_props}
	for prop in all_props:
		if String(prop.get("id", "")).begins_with("barrel_projected_canvas_experiment_room_"):
			groups["canvas_barrels"].append(prop)
		else:
			groups["crates"].append(prop)
	for group_name in ["empty", "crates", "canvas_barrels", "all"]:
		game.semantic_lod_floor_footprints.clear()
		game.semantic_lod_floor_footprints.append_array(groups[group_name])
		for warmup_pass in 3:
			game._render_live_semantic_floor_footprints()
		var started_us := Time.get_ticks_usec()
		for sample in 30:
			game._render_live_semantic_floor_footprints()
		var milliseconds_per_pass := float(Time.get_ticks_usec() - started_us) / 30000.0
		print("PROFILE normal_scene group=%s count=%d cpu_ms_per_pass=%.3f" % [group_name, groups[group_name].size(), milliseconds_per_pass])
		report.store_line("%s,%d,%.3f" % [group_name, groups[group_name].size(), milliseconds_per_pass])
	game.semantic_lod_floor_footprints.clear()
	game.semantic_lod_floor_footprints.append_array(all_props)
	scene.queue_free()
	report.close()
	quit()
