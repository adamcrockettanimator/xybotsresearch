extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://tests/calibration/semantic_canvas_barrel_lab.tscn").instantiate()
	root.add_child(scene)
	for frame in 12:
		await process_frame
	assert(scene.canvas_barrel != null)
	assert(scene.canvas_barrel.pixel_viewport != null)
	assert(scene.canvas_barrel.barrel_rasters.size() == 1)
	assert(scene.telemetry_label != null and scene.telemetry_label.text.contains("TELEMETRY"))
	assert(scene.canvas_barrel.get_telemetry()["active_layers"] > 0)
	print("Semantic Canvas barrel lab smoke check passed")
	scene.queue_free()
	await process_frame
	quit()
