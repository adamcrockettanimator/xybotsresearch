## Confirms the editable Curved Lines barrel remains the near asset while its
## semantic reductions take over at middle and far preview distances.
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node2D = load("res://tests/calibration/semantic_canvas_barrel_editor_preview.tscn").instantiate()
	root.add_child(scene)
	for frame in 2:
		await process_frame
	var authored_vectors := scene.get_node_or_null("Rectangle") as CanvasItem
	assert(authored_vectors != null)
	assert(authored_vectors.visible)
	assert(_generated_shape_count(scene) == 0)

	scene.preview_distance = scene.near_lod_max_distance + 0.10
	await process_frame
	assert(not authored_vectors.visible)
	assert(_generated_shape_count(scene) > 0)
	assert(_has_generated_shape(scene, "Upper Hoop"))
	assert(_has_generated_shape(scene, "Lower Hoop"))
	assert(_has_generated_shape(scene, "Stave 01"))

	scene.preview_distance = scene.middle_lod_max_distance + 0.10
	await process_frame
	assert(not authored_vectors.visible)
	assert(_has_generated_shape(scene, "Upper Hoop"))
	assert(not _has_generated_shape(scene, "Lower Hoop"))
	assert(not _has_generated_shape(scene, "Stave 01"))
	print("Semantic authored-vector barrel LOD smoke check passed")
	scene.queue_free()
	await process_frame
	quit()


func _generated_shape_count(scene: Node) -> int:
	var count := 0
	for child in scene.get_children():
		if child.get_meta("semantic_barrel_generated", false):
			count += 1
	return count


func _has_generated_shape(scene: Node, shape_name: String) -> bool:
	for child in scene.get_children():
		if child.get_meta("semantic_barrel_generated", false) and child.name == shape_name:
			return true
	return false
