extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	set_meta("grudge_public_build", true)
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.clear_map_waiting_to_start = false
	game._set_map_display_mode("fullscreen", false)
	game._bind_player_context(0)
	game._layout_viewport()
	game._render_bound_player_context()
	var map: Node2D = game.match_minimap_overlay
	var clip := map.get_parent() as Control
	assert(clip != null and clip.clip_contents)
	assert(not map.get_node("Backdrop").visible)
	assert(game.match_minimap_dynamic_layer.get_child_count() > 0)
	assert(game.match_minimap_static_layer.get_child_count() > 0)
	var point: Vector2 = game._match_minimap_point(game._player_state_world_position(game.player_states[0]))
	var map_anchor: Vector2 = map.transform * point
	var sprite_screen: Vector2 = game.player_sprite.get_global_transform_with_canvas().origin
	var expected: Vector2 = clip.get_global_transform_with_canvas().affine_inverse() * sprite_screen
	assert(map_anchor.distance_to(expected) < 0.01)
	game.continuous_camera_yaw = PI / 2.0
	game.player_states[0]["continuous_camera_yaw"] = PI / 2.0
	game._update_match_minimap_overlay()
	assert(is_equal_approx(map.rotation, -PI / 2.0))
	assert((map.transform * point).distance_to(expected) < 0.01)
	game._set_map_display_mode("minimap", false)
	game._bind_player_context(0)
	game._update_match_minimap_overlay()
	assert(map.get_node("Backdrop").visible)
	assert(is_zero_approx(map.rotation))
	assert(is_equal_approx(map.scale.x, 1.0))
	assert(is_equal_approx(map.position.x, clip.size.x - game.MATCH_MINIMAP_SIZE - game.MATCH_MINIMAP_MARGIN))
	assert(game.map_display_button.text.contains("MINI-MAP"))
	game._set_map_display_mode("fullscreen", false)
	assert(game.map_display_button.text.contains("FULLSCREEN"))
	print("Rotating overlay aligns with the player, clips to the view, and switches to the original minimap")
	game.queue_free()
	quit()
