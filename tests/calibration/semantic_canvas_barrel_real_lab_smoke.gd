extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://tests/calibration/semantic_canvas_barrel_real_lab.tscn").instantiate()
	root.add_child(scene)
	for frame in 16:
		await process_frame
	assert(scene.tracked_game != null)
	assert(scene.canvas_barrel != null)
	assert(scene.canvas_barrel.barrel_rasters.size() == 1)
	assert(scene.telemetry != null)
	print("Real Canvas barrel lab smoke check passed")
	scene.queue_free()
	await process_frame
	quit()
