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
	stool.queue_free()
	var crate = load("res://scripts/semantic_gpu_lattice_crate.gd").new()
	crate.set_meta("logical_view_size", Vector2i(213, 120))
	scene.add_child(crate)
	assert(crate.viewport.size == Vector2i(213, 120))
	crate.queue_free()
	print("Mobile wide viewport, projection, frustum and prop raster passed")
	scene.queue_free()
	quit()

