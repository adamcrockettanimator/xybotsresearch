extends SceneTree

# Exercise the real game scene: backing the rendering camera through a wall
# must not independently hide an opponent who remains inside the camera view.
func _initialize() -> void:
	call_deferred("run")

func wall_between(game: Node, origin: Vector2, target: Vector2) -> bool:
	var delta := target - origin
	var distance := delta.length()
	if distance <= 0.002:
		return false
	for edge in game._all_physical_wall_edges():
		if game._ray_segment_hit_distance_limited(origin, delta / distance, edge["a"], edge["b"], distance - 0.002) >= 0.0:
			return true
	return false

func bind_view(game: Node, player: Vector2, facing: int) -> void:
	var state: Dictionary = game._make_player_state(0, Vector2i(floori(player.x), floori(player.y)), facing)
	state["world_position"] = player
	game.player_states[0] = state
	game._bind_player_context(0)

func run() -> void:
	var wrapper: Node = load("res://coordinate_frame_navigation.tscn").instantiate()
	root.add_child(wrapper)
	await process_frame
	await process_frame
	var game = wrapper.get_node("CoordinateFrameGame")
	game.set_process(false)
	game.set_physics_process(false)
	game.player_joined = [true, true, false, false]
	var chosen: Dictionary = {}
	for facing in range(4):
		if not chosen.is_empty(): break
		for py in range(game.MAP_HEIGHT):
			if not chosen.is_empty(): break
			for px in range(game.MAP_WIDTH):
				if not chosen.is_empty(): break
				if not game._is_open_cell(Vector2i(px, py)): continue
				for ox in [0.15, 0.35, 0.55, 0.75, 0.85]:
					if not chosen.is_empty(): break
					for oy in [0.15, 0.35, 0.55, 0.75, 0.85]:
						var before := Vector2(px + ox, py + oy)
						bind_view(game, before, facing)
						var forward: Vector2 = game._view_forward_vector().normalized()
						var right: Vector2 = game._view_right_vector().normalized()
						var camera_before: Vector2 = game._runtime_camera_origin_for_visibility()
						var after := before - forward * 0.25
						if not game._is_open_cell(Vector2i(floori(after.x), floori(after.y))): continue
						if wall_between(game, before, after): continue
						bind_view(game, after, facing)
						var camera_after: Vector2 = game._runtime_camera_origin_for_visibility()
						if not wall_between(game, camera_before, camera_after): continue
						for distance in [0.8, 1.1, 1.4, 1.8, 2.3]:
							if not chosen.is_empty(): break
							for side in [0.0, -0.25, 0.25]:
								var target: Vector2 = before + forward * distance + right * side
								if not game._is_open_cell(Vector2i(floori(target.x), floori(target.y))): continue
								if wall_between(game, before, target) or wall_between(game, after, target): continue
								if wall_between(game, camera_before, target) or not wall_between(game, camera_after, target): continue
								var projection: Dictionary = game._opponent_projection_from_current_camera(target, true, true)
								if float(projection["screen_x"]) < 20.0 or float(projection["screen_x"]) > 140.0: continue
								chosen = {"before": before, "after": after, "target": target, "facing": facing, "camera_before": camera_before, "camera_after": camera_after}
								break
						if not chosen.is_empty(): break
	if chosen.is_empty():
		push_error("Could not find a camera-through-wall test arrangement")
		wrapper.queue_free()
		quit(1)
		return
	var target: Vector2 = chosen["target"]
	var other: Dictionary = game._make_player_state(1, Vector2i(floori(target.x), floori(target.y)), (int(chosen["facing"]) + 2) % 4)
	other["world_position"] = target
	game.player_states[1] = other
	bind_view(game, chosen["before"], chosen["facing"])
	game._render_bound_player_context()
	await process_frame
	var sprite: AnimatedSprite2D = game.player_views[0]["opponent_sprites"][1]
	var before_visible := sprite.visible
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	bind_view(game, chosen["after"], chosen["facing"])
	game._render_bound_player_context()
	await process_frame
	var after_visible := sprite.visible
	var blocked_camera := wall_between(game, chosen["camera_after"], target)
	var clear_body: bool = game._world_actor_has_clear_line_of_sight(target)
	print("camera before=", chosen["camera_before"], " after=", chosen["camera_after"], " target=", target, " wall_crossed=", blocked_camera, " body_clear=", clear_body, " sprite_visible_before=", before_visible, " sprite_visible_after=", after_visible)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	wrapper.queue_free()
	await process_frame
	if not before_visible or not after_visible or not blocked_camera or not clear_body:
		push_error("Opponent visibility changed when the camera passed through a wall")
		quit(1)
	else:
		print("Camera-through-wall opponent visibility passed")
		quit(0)
