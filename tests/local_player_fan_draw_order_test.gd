extends SceneTree

# The local player's animated opaque-pixel fan is the authority for its
# wall relationship: a contacting wall owns the camera-to-body path, while a
# non-contacting wall must not be layered over the player just because its
# midpoint happens to be nearer.
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
	game.continuous_third_person_camera = true
	game._bind_player_context(0)
	game._render_bound_player_context()
	await process_frame
	var renderer = game.coordinate_renderers[0]
	var player_layer: int = game._world_actor_draw_layer(game._current_player_world_position())
	var contacts := 0
	var clear_walls := 0
	var failures: Array[String] = []
	for entry in renderer.last_wall_entries:
		var wall_layer: int = int(entry.get("wall_draw_layer", -99999))
		if bool(entry.get("local_player_fan_contact", false)):
			contacts += 1
			if wall_layer <= player_layer:
				failures.append("Fan-contact wall %s was not above the local player" % entry.get("edge_key", ""))
		else:
			clear_walls += 1
			if wall_layer >= player_layer:
				failures.append("Clear wall %s was layered over the local player" % entry.get("edge_key", ""))
	print("PLAYER_FAN_SORT contacts=", contacts, " clear=", clear_walls, " failures=", failures.size())
	wrapper.queue_free()
	await process_frame
	if contacts == 0 or clear_walls == 0:
		push_error("Expected both contacting and clear walls in the runtime test view")
		quit(1)
	elif failures.is_empty():
		print("Local player fan draw order passed")
		quit(0)
	else:
		push_error("; ".join(failures))
		quit(1)
