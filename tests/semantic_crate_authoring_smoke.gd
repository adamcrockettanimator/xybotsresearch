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
	var found_fragment_raster_crate := false
	var found_gpu_lattice_barrel := false
	var found_semantic_chair := false
	var found_semantic_chair_edges := false
	var found_semantic_stool := false
	for key in nodes:
		if String(key).contains("crate_gpu_fragment_raster"):
			var gpu_crate = nodes[key]
			var logical_viewport = gpu_crate.get_node_or_null("GpuCageCrateLogicalViewport_160x120")
			var cube_faces = gpu_crate.get_node_or_null("GpuCageCrateLogicalViewport_160x120/GpuCageCrateEightCorners")
			var valid_crate: bool = is_instance_valid(logical_viewport) and logical_viewport is SubViewport and is_instance_valid(cube_faces) and cube_faces.get_child_count() >= 6
			found_fragment_raster_crate = valid_crate
		elif String(key).contains("barrel_gpu_lattice_instanced"):
			found_gpu_lattice_barrel = is_instance_valid(nodes[key])
		elif String(key).contains("chair_semantic_imported"):
			var chair = nodes[key]
			var chair_viewport = chair.get_node_or_null("ChairSharedLogicalRaster_160x120")
			var chair_geometry = chair.get_node_or_null("ChairSharedLogicalRaster_160x120/ChairSemanticPolygonsAndHardEdges")
			var hard_edge_count := 0
			var convex_edge_count := 0
			var concave_edge_count := 0
			if chair_geometry != null:
				for piece in chair_geometry.get_children():
					if piece.name == "ChairHardEdgeRaster":
						hard_edge_count += 1
			for edge in chair.get("_edges"):
				if bool(edge["convex"]):
					convex_edge_count += 1
				else:
					concave_edge_count += 1
			found_semantic_chair = is_instance_valid(chair) and is_instance_valid(chair_viewport) and is_instance_valid(chair.get_node_or_null("ChairSemanticPixels")) and is_instance_valid(chair_geometry) and chair_geometry.get_child_count() > 100 and hard_edge_count > 0 and convex_edge_count > 0 and concave_edge_count > 0
		elif String(key).contains("chair_semantic_edges"):
			var edge_chair = nodes[key]
			var edge_geometry = edge_chair.get_node_or_null("ChairEdgesLogicalRaster_160x120/ChairEdgeMarkupStrokes")
			# Two source rectangles become closed slabs and four loose source vectors
			# become posts: six inferred boxes, each with 12 physical raster edges.
			found_semantic_chair_edges = is_instance_valid(edge_chair) and is_instance_valid(edge_geometry) and edge_chair.get("_edges").size() == 72 and edge_geometry.get_child_count() >= 900
		elif String(key).contains("chair_semantic_stool") or String(key).contains("chair_semantic_bench"):
			var stool = nodes[key]
			var stool_viewport = stool.get_node_or_null("SemanticStoolLogicalRaster_160x120")
			var stool_layers = stool.get_node_or_null("SemanticStoolLogicalRaster_160x120/StoolRasterLayers_Shadow_Legs_Seat")
			# One compact logical-canvas node owns the shadow and all cube faces.
			# The visible semantic construction remains inspectable through the
			# window-only overlay without flooding Remote Inspector resources.
			found_semantic_stool = is_instance_valid(stool) and is_instance_valid(stool_viewport) and stool_viewport is SubViewport and is_instance_valid(stool_layers) and stool_layers.get_child_count() == 1 and is_instance_valid(stool.get("debug_overlay"))
	assert(found_fragment_raster_crate, "The GPU fragment-raster crate did not initialize")
	assert(found_gpu_lattice_barrel, "The GPU lattice barrel did not initialize")
	assert(found_semantic_chair, "The imported semantic chair did not initialize")
	assert(found_semantic_chair_edges, "The Blender edge-markup chair did not initialize")
	assert(found_semantic_stool, "The point-footprint semantic stool did not initialize")
	assert(nodes.size() == 7, "The authoring room must contain the crate, barrel, two chairs, two benches, and table dining set")
	print("Crate, barrel, two chairs, matching bench pair, and table dining-set authoring-room check passed")
	scene.queue_free()
	quit()
