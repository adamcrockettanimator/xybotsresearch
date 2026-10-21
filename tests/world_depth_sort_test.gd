extends SceneTree

# The runtime must use only camera-forward world depth for painter order.
# This guards against reintroducing source-cell/near-field ordering overrides.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var wrapper: Node = load("res://coordinate_frame_navigation.tscn").instantiate()
	root.add_child(wrapper)
	await process_frame
	await process_frame
	var game = wrapper.get_node("CoordinateFrameGame")
	game.set_process(false)
	game.set_physics_process(false)
	game._bind_player_context(0)
	game._render_bound_player_context()
	await process_frame
	var camera_origin: Vector2 = game._runtime_camera_origin_for_visibility()
	var forward: Vector2 = game._view_forward_vector().normalized()
	var near_point := camera_origin + forward * 0.75
	var far_point := camera_origin + forward * 1.75
	var near_layer: int = game._world_actor_draw_layer(near_point)
	var far_layer: int = game._world_actor_draw_layer(far_point)
	var expected_near: int = game._character_layer_for_view_depth(0.75)
	var expected_far: int = game._character_layer_for_view_depth(1.75)
	var renderer = game.coordinate_renderers[0]
	var wall_debug: Array = renderer.get_wall_depth_debug_entries()
	var failures: Array[String] = []
	if near_layer != expected_near or far_layer != expected_far:
		failures.append("Actor layers are not direct camera-forward depth layers")
	if near_layer <= far_layer:
		failures.append("Near actor did not draw after far actor")
	for wall in wall_debug:
		var depth := float(wall["depth"])
		if int(wall["z_index"]) != game._character_layer_for_view_depth(depth):
			failures.append("Wall %s is not layered from camera-forward depth" % wall["edge_key"])
			break
	print("DEPTH_SORT camera=", camera_origin, " near=", near_layer, " far=", far_layer, " walls=", wall_debug.size())
	wrapper.queue_free()
	await process_frame
	if failures.is_empty():
		print("World depth sort passed")
		quit(0)
	else:
		push_error("; ".join(failures))
		quit(1)
