extends SceneTree

# The cutaway dither cone may shrink inside the local player's visible
# silhouette, but it must never extend beyond the left/right inset used to
# reject side-wall penetration.
func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var wrapper: Node = load("res://coordinate_frame_navigation.tscn").instantiate()
	root.add_child(wrapper)
	await process_frame
	await process_frame
	var game = wrapper.get_node("CoordinateFrameGame")
	game.continuous_third_person_camera = true
	game._bind_player_context(0)
	game._render_bound_player_context()
	await process_frame
	var renderer = game.coordinate_renderers[0]
	var camera_origin: Vector2 = renderer.runtime_camera_origin_for_current_pose()
	var data: Dictionary = renderer.get_camera_cutaway_debug_data(camera_origin)
	var failures: Array[String] = []
	if data.is_empty():
		failures.append("Expected active local-player cutaway data")
	else:
		var player_world: Vector2 = data["player_world"]
		var camera_right: Vector2 = game._view_right_vector().normalized()
		var left_half_width := absf((Vector2(data["dither_fan_left"]) - player_world).dot(camera_right))
		var right_half_width := absf((Vector2(data["dither_fan_right"]) - player_world).dot(camera_right))
		var detection_half_width: float = data["detection_half_width"]
		if left_half_width > detection_half_width + 0.0001 or right_half_width > detection_half_width + 0.0001:
			failures.append("Dither fan escaped the left/right silhouette buffer")
	print("CUTAWAY_SIDE_GUARD failures=", failures.size())
	wrapper.queue_free()
	await process_frame
	if failures.is_empty():
		print("Camera cutaway side guard passed")
		quit(0)
	else:
		push_error("; ".join(failures))
		quit(1)
