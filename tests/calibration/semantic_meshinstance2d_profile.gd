extends SceneTree


const SAMPLE_FRAMES := 90
const PROP_COUNTS := [1, 8]
const REPORT_PATH := "user://semantic_meshinstance2d_profile.csv"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var report := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if report == null:
		push_error("Could not create %s" % REPORT_PATH)
		quit(1)
		return
	report.store_line("pipeline,count,cpu_render_ms_per_pass,gpu_viewport_ms_per_frame,frame_setup_cpu_ms_per_frame")
	var scene: Node = load("res://tests/calibration/semantic_crate_authoring.tscn").instantiate()
	root.add_child(scene)
	for frame in 8:
		await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	game._bind_player_context(0)
	var gpu_cage_template := _find_fixture(game.semantic_lod_floor_footprints, "barrel_gpu_lattice_instanced")
	var mesh_template := _find_fixture(game.semantic_lod_floor_footprints, "barrel_meshinstance2d_3d_source")
	assert(not gpu_cage_template.is_empty(), "GPU cage comparison fixture was not found")
	assert(not mesh_template.is_empty(), "MeshInstance2D comparison fixture was not found")
	var viewport_rid := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	for count in PROP_COUNTS:
		await _measure_group(game, report, viewport_rid, "gpu_cage", _copies(gpu_cage_template, "barrel_gpu_lattice_profile", count))
		await _measure_group(game, report, viewport_rid, "meshinstance2d", _copies(mesh_template, "barrel_meshinstance2d_3d_source_profile", count))
	report.close()
	print("MeshInstance2D semantic comparison profile: %s" % ProjectSettings.globalize_path(REPORT_PATH))
	scene.queue_free()
	await process_frame
	quit()


func _measure_group(game: Node, report: FileAccess, viewport_rid: RID, pipeline: String, props: Array) -> void:
	# Free each group so inactive MeshInstance2D source SubViewports cannot
	# keep UPDATE_ALWAYS 3D work alive and contaminate the next measurement.
	for node in game.semantic_lod_floor_outline_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	game.semantic_lod_floor_outline_nodes.clear()
	await process_frame
	game.semantic_lod_floor_footprints.clear()
	game.semantic_lod_floor_footprints.append_array(props)
	for warmup in 8:
		game._render_live_semantic_floor_footprints()
		await process_frame
	var cpu_total_us := 0
	var gpu_total_ms := 0.0
	var setup_total_ms := 0.0
	for sample in SAMPLE_FRAMES:
		var started_us := Time.get_ticks_usec()
		game._render_live_semantic_floor_footprints()
		cpu_total_us += Time.get_ticks_usec() - started_us
		await process_frame
		gpu_total_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		setup_total_ms += RenderingServer.get_frame_setup_time_cpu()
	var cpu_ms := float(cpu_total_us) / float(SAMPLE_FRAMES * 1000)
	var gpu_ms := gpu_total_ms / float(SAMPLE_FRAMES)
	var setup_ms := setup_total_ms / float(SAMPLE_FRAMES)
	print("PROFILE pipeline=%s count=%d cpu_ms_per_pass=%.4f gpu_viewport_ms=%.4f frame_setup_cpu_ms=%.4f" % [pipeline, props.size(), cpu_ms, gpu_ms, setup_ms])
	report.store_line("%s,%d,%.4f,%.4f,%.4f" % [pipeline, props.size(), cpu_ms, gpu_ms, setup_ms])


func _find_fixture(fixtures: Array, fixture_id: String) -> Dictionary:
	for fixture in fixtures:
		if fixture is Dictionary and String(fixture.get("id", "")) == fixture_id:
			return (fixture as Dictionary).duplicate()
	return {}


func _copies(template: Dictionary, id_prefix: String, count: int) -> Array:
	var copies: Array = []
	for index in count:
		var prop := template.duplicate()
		prop["id"] = "%s_%d" % [id_prefix, index]
		# Same position prevents culling and distance differences from changing
		# the measured per-prop work between the two render pipelines.
		copies.append(prop)
	return copies
