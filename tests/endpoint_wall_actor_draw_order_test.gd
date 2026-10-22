extends SceneTree

# An actor in the neighbouring cell can overlap a wall endpoint on screen. If
# it is closer at that precise screen-side coordinate, a yaw that moves the
# virtual camera across the wall line must not put the wall over the actor.
func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var wrapper: Node = load("res://coordinate_frame_navigation.tscn").instantiate()
	root.add_child(wrapper)
	await process_frame
	await process_frame
	var game = wrapper.get_node("CoordinateFrameGame")
	var renderer = game.coordinate_renderers[0]
	var wall_layer: int = game._character_layer_for_view_depth(2.0) + 1
	var entries: Array[Dictionary] = [{
		"facing_cell": Vector2i(2, 2),
		"first_local": Vector2(-0.5, 2.0),
		"second_local": Vector2(0.5, 2.0),
		"cell_draw_depth": 2.0,
	}]
	var failures: Array[String] = []
	var actor_cell := Vector2i(2, 1)
	var front_layer: int = renderer.runtime_actor_layer_after_wall_entries(Vector2(0.0, 1.8), actor_cell, entries, wall_layer - 24)
	if front_layer != wall_layer + 1:
		failures.append("A neighbouring-cell actor in front of an endpoint was not promoted above its wall")
	var front_cap_layer: int = renderer.runtime_actor_layer_after_wall_entries(Vector2(0.54, 1.8), actor_cell, entries, wall_layer - 24)
	if front_cap_layer != wall_layer + 1:
		failures.append("The endpoint margin did not cover a body overlapping the wall cap")
	var behind_layer: int = renderer.runtime_actor_layer_after_wall_entries(Vector2(0.0, 2.2), actor_cell, entries, wall_layer + 24)
	if behind_layer != wall_layer - 1:
		failures.append("A neighbouring-cell actor behind an endpoint was not kept behind its wall")
	var own_cell_layer: int = renderer.runtime_actor_layer_after_wall_entries(Vector2(0.0, 1.8), Vector2i(2, 2), entries, wall_layer + 2)
	if own_cell_layer != wall_layer + 2:
		failures.append("The camera-facing cell's established character tie-breaker changed")
	print("ENDPOINT_WALL_ACTOR_SORT failures=", failures.size())
	wrapper.queue_free()
	await process_frame
	if failures.is_empty():
		print("Endpoint wall actor draw order passed")
		quit(0)
	else:
		push_error("; ".join(failures))
		quit(1)
