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
	var found_meshinstance2d_barrel := false
	var found_gpu_cage_barrel := false
	for key in nodes:
		if String(key).contains("barrel_meshinstance2d_3d_source"):
			var mesh_barrel = nodes[key]
			var display = mesh_barrel.get_node_or_null("Barrel3DAsMeshInstance2D")
			var debug_overlay = mesh_barrel.get_node_or_null("MeshInstance2DBarrelDebug")
			var source_viewport = mesh_barrel.get_node_or_null("Barrel3DSourceViewport")
			var source_model = mesh_barrel.get_node_or_null("Barrel3DSourceViewport/Barrel3DSource/SM_Prop_Barrel_01_3D")
			var source_meshes: Array[Node] = source_model.find_children("*", "MeshInstance3D", true, false) if is_instance_valid(source_model) else []
			var authored_textures_bound := false
			var imported_ao_uv := false
			for source_mesh in source_meshes:
				var source_mesh_instance := source_mesh as MeshInstance3D
				var source_material := source_mesh_instance.material_override as StandardMaterial3D
				authored_textures_bound = authored_textures_bound or (source_material != null and source_material.albedo_texture != null and source_material.ao_enabled and source_material.ao_texture != null and source_material.ao_on_uv2 and source_material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
				if source_mesh_instance.mesh != null and source_mesh_instance.mesh.get_surface_count() > 0:
					var arrays := source_mesh_instance.mesh.surface_get_arrays(0)
					var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
					imported_ao_uv = imported_ao_uv or not uv2.is_empty()
			found_meshinstance2d_barrel = is_instance_valid(display) and display is MeshInstance2D and display.texture == source_viewport.get_texture() and is_instance_valid(source_viewport) and source_viewport is SubViewport and source_meshes.size() > 0 and authored_textures_bound and imported_ao_uv and is_instance_valid(debug_overlay)
			assert(mesh_barrel.source_resolution_for_distance(0.5) == Vector2i(64, 64))
			assert(mesh_barrel.source_resolution_for_distance(0.8) == Vector2i(56, 56))
			assert(mesh_barrel.source_resolution_for_distance(1.0) == Vector2i(48, 48))
			assert(mesh_barrel.source_resolution_for_distance(1.3) == Vector2i(40, 40))
			assert(mesh_barrel.source_resolution_for_distance(1.7) == Vector2i(32, 32))
			assert(mesh_barrel.source_resolution_for_distance(2.1) == Vector2i(28, 28))
			assert(mesh_barrel.source_resolution_for_distance(2.6) == Vector2i(24, 24))
			assert(mesh_barrel.source_resolution_for_distance(3.1) == Vector2i(20, 20))
			assert(mesh_barrel.source_resolution_for_distance(3.4) == Vector2i(16, 16))
			assert(mesh_barrel.source_resolution_for_distance(4.0) == Vector2i(12, 12))
		if String(key).contains("barrel_gpu_lattice_instanced"):
			var gpu_cage = nodes[key]
			var logical_viewport = gpu_cage.get_node_or_null("GpuCageLogicalViewport_160x120")
			var semantic_pieces = gpu_cage.get_node_or_null("GpuCageLogicalViewport_160x120/GpuCageSemanticPieces")
			found_gpu_cage_barrel = is_instance_valid(logical_viewport) and logical_viewport is SubViewport and is_instance_valid(semantic_pieces)
	assert(found_meshinstance2d_barrel, "The 3D barrel MeshInstance2D comparison fixture did not initialize")
	assert(found_gpu_cage_barrel, "The GPU cage barrel comparison fixture did not initialize")
	assert(nodes.size() == 2, "The authoring gallery must contain only the two selected barrel candidates")
	print("Two-barrel authoring comparison check passed")
	scene.queue_free()
	quit()
