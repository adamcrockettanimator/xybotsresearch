extends SceneTree

# Exercise a small lateral camera move in the real scene. A single controlled
# wall crosses the barrel's center ray while part of its sprite is still exposed.
func bind(game: Node, pos: Vector2) -> void:
	var state: Dictionary = game._make_player_state(0, Vector2i(floori(pos.x), floori(pos.y)), 0)
	state["world_position"] = pos
	game.player_states[0] = state
	game._bind_player_context(0)

func difference(first: Image, second: Image) -> int:
	var result := 0
	for y in range(first.get_height() / 2):
		for x in range(first.get_width() / 2):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				result += 1
	return result

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var wrapper: Node = load("res://coordinate_frame_navigation.tscn").instantiate()
	root.add_child(wrapper)
	await process_frame
	await process_frame
	var game = wrapper.get_node("CoordinateFrameGame")
	wrapper.process_mode = Node.PROCESS_MODE_DISABLED
	game.continuous_third_person_camera = true
	game.player_joined = [true, false, false, false]
	game.world_coins.clear()
	game.world_hearts.clear()
	game.machine_gun_pickup = {}
	var a := Vector2(1, 2)
	var b := Vector2(2, 2)
	game.physical_wall_edges_cache = [{"a": a, "b": b, "key": game._physical_edge_key(a, b), "delta": Vector2i.UP}]
	game.physical_wall_edges_cache_dirty = false
	var before := Vector2(1.20, 3.20)
	var after := before + Vector2(0.06, 0.0)
	bind(game, before)
	var camera: Vector2 = game._runtime_camera_origin_for_visibility()
	var target_y := 1.2
	var ratio := (camera.y - 2.0) / (camera.y - target_y)
	var target := Vector2(camera.x + (1.0 - camera.x) / ratio - 0.012, target_y)
	var before_clear: bool = game._world_point_has_clear_camera_line(target)
	bind(game, after)
	var after_clear: bool = game._world_point_has_clear_camera_line(target)
	var origin_after: Vector2 = game._runtime_camera_origin_for_visibility()
	print("before=", before, " camera=", camera, " after camera=", origin_after, " target=", target, " ray before=", before_clear, " after=", after_clear)
	game.world_barrels.clear()
	game.world_barrels.append({"id": 4567, "position": target})
	var renderer: Node = game.coordinate_renderers[0]
	renderer._rebuild()
	game._render_bound_player_context()
	await process_frame
	await RenderingServer.frame_post_draw
	var nodes: Dictionary = game.player_views[0]["combat_nodes"]
	var sprite: Sprite2D = nodes.get("barrel_4567")
	if sprite == null:
		push_error("barrel missing")
		quit(1)
		return
	var shadow: Sprite2D = nodes.get("barrel_4567_shadow")
	shadow.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	print("sprite visible=", sprite.visible, " pos=", sprite.position, " scale=", sprite.scale, " z=", sprite.z_index)
	for entry in renderer.last_wall_entries:
		print("wall ", entry["edge_key"], " z=", game._character_layer_for_view_depth(float(entry["depth"])), " quad=", entry["quad"])
	var normal := root.get_texture().get_image()
	sprite.visible = false
	shadow.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden := root.get_texture().get_image()
	sprite.visible = true
	sprite.z_index = 4000
	await process_frame
	await RenderingServer.frame_post_draw
	var front := root.get_texture().get_image()
	var shown := difference(normal, hidden)
	var covered := difference(front, normal)
	print("image=", normal.get_size(), " pixels_visible=", shown, " pixels_wall_covered=", covered)
	bind(game, before)
	renderer._rebuild()
	game._render_bound_player_context()
	shadow.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var before_image := root.get_texture().get_image()
	sprite.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var before_visible := difference(before_image, root.get_texture().get_image())
	bind(game, before + Vector2(0.35, 0.0))
	renderer._rebuild()
	game._render_bound_player_context()
	shadow.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var covered_image := root.get_texture().get_image()
	var retained_when_covered := sprite.visible
	sprite.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var fully_covered := difference(covered_image, root.get_texture().get_image())
	print("pixels before=", before_visible, " partly covered=", shown, " fully covered=", fully_covered, " sprite retained=", retained_when_covered)
	wrapper.queue_free()
	await process_frame
	if before_clear and not after_clear and shown > 0 and covered > 0 and before_visible > shown and fully_covered == 0 and retained_when_covered:
		print("Wall edge test passed")
		quit(0)
	else:
		push_error("Wall edge scenario did not meet criteria")
		quit(1)
