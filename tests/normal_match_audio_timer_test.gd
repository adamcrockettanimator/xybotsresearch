extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	assert(game.match_started)
	assert(game.semantic_typical_props_enabled)
	assert(game.semantic_lod_floor_footprints.size() == 8)
	var barrel_count := 0
	var crate_count := 0
	for footprint in game.semantic_lod_floor_footprints:
		if String(footprint["id"]).begins_with("barrel_ground_gpu_ray_experiment"):
			barrel_count += 1
		elif bool(footprint.get("flat_faces", false)):
			crate_count += 1
	assert(barrel_count == 4 and crate_count == 4)
	assert(game.music_enabled and game.music_player.playing)
	assert(not game.pause_round_timer_for_debug)
	var before: float = game.combat_round_time_remaining
	game._advance_combat_round(1.0)
	assert(is_equal_approx(game.combat_round_time_remaining, before - 1.0))
	print("Normal match starts music and timer with four semantic barrels and four semantic crates")
	game.queue_free()
	quit()
