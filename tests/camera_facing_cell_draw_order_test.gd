extends SceneTree

# A thin wall belongs to the grid cell on the camera-facing side. A body in
# that cell must draw after the wall; otherwise its own room incorrectly cuts
# across it. Nearer cells are still allowed to draw over both groups.
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
	var renderer = game.coordinate_renderers[0]
	var failures: Array[String] = []
	var checked := 0
	for entry in renderer.last_wall_entries:
		var facing_cell: Vector2i = entry.get("facing_cell", Vector2i(-1, -1))
		if facing_cell.x < 0 or facing_cell.y < 0:
			continue
		var actor_world := Vector2(float(facing_cell.x) + 0.5, float(facing_cell.y) + 0.5)
		var actor_layer: int = game._world_actor_draw_layer(actor_world)
		var wall_layer: int = game._character_layer_for_view_depth(float(entry["cell_draw_depth"])) + 1
		checked += 1
		if actor_layer <= wall_layer:
			failures.append("Actor in camera-facing cell %s did not draw after wall %s" % [facing_cell, entry["edge_key"]])
			break
	print("FACING_CELL_SORT checked=", checked, " failures=", failures.size())
	wrapper.queue_free()
	await process_frame
	if checked == 0:
		push_error("No camera-facing wall cells were available to test")
		quit(1)
	elif failures.is_empty():
		print("Camera-facing cell draw order passed")
		quit(0)
	else:
		push_error("; ".join(failures))
		quit(1)
