extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://outdoor_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	var renderer: Node = game.coordinate_renderers[0]
	assert(game._debug_option_value("town_ground_grid"))
	assert(not renderer.gpu_floor_materials.is_empty())
	assert(renderer.gpu_floor_materials[0].get_shader_parameter("show_town_ground_grid"))
	assert(renderer.storefront_planes[1].material.get_shader_parameter("show_town_ground_grid"))
	game._set_debug_option(false, "town_ground_grid")
	renderer._update_storefront_planes()
	renderer._rebuild_gpu_floor_surfaces(renderer._visible_floor_cells())
	assert(not renderer.gpu_floor_materials[0].get_shader_parameter("show_town_ground_grid"))
	assert(not renderer.storefront_planes[1].material.get_shader_parameter("show_town_ground_grid"))
	print("Town ground grid toggle passed")
	scene.queue_free()
	quit()
