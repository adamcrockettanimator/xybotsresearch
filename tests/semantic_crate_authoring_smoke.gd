extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://tests/calibration/semantic_crate_authoring.tscn").instantiate()
	root.add_child(scene)
	for frame in 20:
		await process_frame
	assert(scene.feature_groups.size() == 8)
	assert(scene.controls.size() == scene.settings.size())
	var group: Dictionary = scene.feature_groups["Shared edge highlight"]
	var header: Button = group["header"]
	var contents: Control = group["contents"]
	assert(not contents.visible)
	header.button_pressed = true
	assert(contents.visible)
	assert(scene.controls["edge_color_balance"].get_parent() == contents)
	header.button_pressed = false
	assert(not contents.visible)
	assert(scene.controls["shadow_color"].get_parent().get_parent() == scene.feature_groups["Upper drop shadow"]["contents"])
	var game = scene.get_node("CoordinateFrameGame")
	var nodes: Dictionary = game.get("semantic_lod_floor_outline_nodes")
	var found_cpu_raster_crate := false
	var found_fragment_raster_crate := false
	for key in nodes:
		if String(key).contains("crate_gpu_"):
			var gpu_crate = nodes[key]
			var logical_viewport = gpu_crate.get_node_or_null("GpuCageCrateLogicalViewport_160x120")
			var cube_faces = gpu_crate.get_node_or_null("GpuCageCrateLogicalViewport_160x120/GpuCageCrateEightCorners")
			var valid_crate: bool = is_instance_valid(logical_viewport) and logical_viewport is SubViewport and is_instance_valid(cube_faces) and cube_faces.get_child_count() >= 6
			if String(key).contains("fragment_raster"):
				found_fragment_raster_crate = valid_crate
			else:
				found_cpu_raster_crate = valid_crate
	assert(found_cpu_raster_crate, "The CPU Bresenham-reference crate did not initialize")
	assert(found_fragment_raster_crate, "The GPU fragment-raster crate did not initialize")
	assert(nodes.size() >= 2, "The authoring gallery must contain both crate raster backends")
	print("CPU and fragment-raster crate comparison check passed")
	scene.queue_free()
	quit()
