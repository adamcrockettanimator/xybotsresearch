extends SceneTree

func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(960, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	print("Window ", root.size, " actual visible ", root.get_visible_rect())
	set_meta("grudge_mobile_wide", true)
	set_meta("grudge_mobile_viewport_test_size", Vector2(1280, 720))
	set_meta("grudge_public_build", true)
	var scene = load("res://coordinate_frame_navigation.tscn").instantiate()
	root.add_child.call_deferred(scene)
	for i in range(8):
		await process_frame
	var game = scene.get_node("CoordinateFrameGame")
	var renderer = game.get_node("CoordinateFrameRuntimeRendererP1")
	print("Wide view: ", game.VIEWPORT_SIZE, "; renderer: ", renderer.VIEW_SIZE, "; available: ", root.get_visible_rect().size)
	assert(game.VIEWPORT_SIZE.x > 160.0)
	assert(game.VIEWPORT_SIZE == renderer.VIEW_SIZE)
	var center: Vector2 = renderer._project_view_point_unframed(Vector2(0, 2), 0.0)
	assert(is_equal_approx(center.x, game.VIEWPORT_SIZE.x * 0.5))
	assert(renderer._segment_intersects_view_frustum(Vector2(1.6, 2.0), Vector2(1.7, 2.0)))
	var stool = load("res://scripts/semantic_stool.gd").new()
	stool.set_meta("logical_view_size", Vector2i(213, 120))
	scene.add_child(stool)
	assert(stool.viewport.size == Vector2i(213, 120))
	assert(stool.raster_layer.logical_size == Vector2i(213, 120))
	var crate = load("res://scripts/semantic_gpu_lattice_crate.gd").new()
	crate.set_meta("logical_view_size", Vector2i(213, 120))
	scene.add_child(crate)
	assert(crate.viewport.size == Vector2i(213, 120))
	var barrel = load("res://scripts/semantic_gpu_cage_barrel.gd").new()
	barrel.set_meta("logical_view_size", Vector2i(213, 120))
	scene.add_child(barrel)
	assert(barrel.viewport.size == Vector2i(213, 120))
	for logical_width in [160.0, 213.0, 259.0]:
		game.VIEWPORT_SIZE.x = logical_width
		renderer.VIEW_SIZE.x = logical_width
		for yaw in [-0.9, 0.0, 0.75]:
			var forward := Vector2.UP.rotated(yaw)
			var right := Vector2(-forward.y, forward.x)
			for origin in [Vector2(1.0, 3.0), Vector2(1.7, 2.4)]:
				var target: Vector2 = origin + forward * 2.0 + right * 0.35
				var offset: Vector2 = game._semantic_legacy_projection_offset(renderer)
				var expected: Vector2 = renderer._project_view_point_unframed(Vector2(0.35, 2.0), 0.0) + renderer._overscan_projection_offset()
				var dining: Dictionary = stool._project(Vector3.ZERO, target, origin, forward, right, offset)
				var crate_point: Vector2 = crate._project_face_uv_exact(5, 0.5, 0.5, target, 0.5, 0.5, 0.5, origin, forward, right, offset)
				var barrel_point: Dictionary = barrel._debug_project_point(target, 0.0, 0.5, origin, forward, right, offset, 0, 0.0, 0.0)
				assert(Vector2(dining.pixel).distance_to(expected) < 0.001)
				assert(crate_point.distance_to(expected) < 0.001)
				assert(Vector2(barrel_point.point).distance_to(expected) < 0.001)
				crate.set_crate(target, 0.5, 0.5, 0.5, origin, forward, right, offset)
				barrel.set_barrel(target, 0.25, 0.5, origin, forward, right, offset)
				assert(Vector2(crate.materials[0].get_shader_parameter("projection_offset")).distance_to(offset) < 0.001)
				assert(Vector2(barrel.materials[0].get_shader_parameter("projection_offset")).distance_to(offset) < 0.001)
	stool.queue_free()
	crate.queue_free()
	barrel.queue_free()
	print("Mobile wide viewport and semantic projection alignment passed")
	scene.queue_free()
	quit()

