extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _viewport_count(root: Node, idle_sprite_target: SubViewport) -> int:
	var count := int(root is SubViewport and root != idle_sprite_target)
	for child in root.get_children():
		count += _viewport_count(child, idle_sprite_target)
	return count


func _run() -> void:
	var scene := (load("res://tests/calibration/town_shared_viewport_experiment.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for index in range(8):
		await process_frame
	assert(scene.shared_enabled and scene.shared_target.size == Vector2i(160, 120))
	assert(scene.prop_bridge.converted.size() > 0)
	assert(scene.sprite_target.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	assert(_viewport_count(scene, scene.sprite_target) == 1)
	var count: int = scene.prop_bridge.converted.size()
	for info: Dictionary in scene.prop_bridge.converted.values():
		assert(info["root"].get_parent() == info["prop"])
		assert(not info["viewport"].is_inside_tree())
		assert(not info["display"].visible)
	scene._set_shared_enabled(false)
	assert(_viewport_count(scene, scene.sprite_target) == count + 1)
	for info in scene.game.semantic_lod_floor_outline_nodes.values():
		if not is_instance_valid(info):
			continue
		var viewport: Variant = info.get("viewport")
		if viewport is SubViewport:
			assert(viewport.is_inside_tree())
	scene._set_shared_enabled(true)
	assert(scene.prop_bridge.converted.size() == count)
	assert(_viewport_count(scene, scene.sprite_target) == 1)
	# Switch while the scene is processing, not only during a static setup.
	for index in range(4):
		scene._set_shared_enabled(false)
		await process_frame
		scene._set_shared_enabled(true)
		await process_frame
	assert(_viewport_count(scene, scene.sprite_target) == 1)
	print("Town shared prop targets and restore passed: %d props" % count)
	scene.queue_free()
	quit()
