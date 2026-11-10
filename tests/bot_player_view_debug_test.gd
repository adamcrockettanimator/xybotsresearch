extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node = load("res://coordinate_frame_navigation.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	assert(not game.coordinate_renderers.is_empty())
	game.clear_the_map_mode = true
	game.clear_map_round = 3
	game._apply_session_roster()
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game._bind_player_context(0)
	game.show_bot_navigation_debug = true
	var origin: Vector2 = game._runtime_camera_origin_for_visibility()
	var forward: Vector2 = game._view_forward_vector().normalized()
	var bot: Vector2 = origin + forward * 1.4
	game.player_states[1]["world_position"] = bot
	game.player_joined[1] = true
	game.player_bots[1] = true
	game.bot_brains[1] = {"state": "TAKE_COVER", "debug_destination": bot + forward * 0.25, "firing_samples": [{"point": bot + forward * 0.15, "wall_clear": true, "prop_clear": true}]}
	game._render_bound_player_context()
	assert(game.view_slot_overlay.visible)
	var labels_canvas: CanvasLayer = game.view_slot_overlay.get_meta("bot_label_canvas")
	assert(labels_canvas.visible and labels_canvas.layer == 1001)
	var action: Label = labels_canvas.get_child(0).get_node_or_null("BotAction_1")
	assert(action != null and action.text.contains("TAKE COVER"))
	var firing_brain := {"state": "FIRING_POINT", "firing_point": bot + forward * 0.4, "firing_target": bot + forward * 2.0, "allow_fire": true}
	game.player_states[1]["fire_cooldown"] = 0.0
	game.player_states[1]["reload_phase"] = ""
	game.bot_inputs[1] = {"fire": true}
	var firing_text: String = game._bot_debug_action_text(1, firing_brain)
	assert(firing_text.contains("FIRING POINT ADVANCE") and firing_text.contains("FIRE INPUT"))
	assert(firing_text.contains("CLEAR LOW LANE / RANGE 1.5 / TRAVEL"))
	game.player_states[1]["fire_cooldown"] = 0.4
	assert(game._bot_debug_action_text(1, firing_brain).contains("COOLDOWN"))
	firing_brain["firing_point"] = bot
	game.player_states[1]["reload_phase"] = "open"
	assert(game._bot_debug_action_text(1, firing_brain).contains("FIRING POINT HOLD") and game._bot_debug_action_text(1, firing_brain).contains("RELOAD OPEN"))
	assert(action.get_theme_font_size("font_size") == 4)
	assert(action.get_theme_font("font") is SystemFont)
	assert(not action.z_as_relative and action.z_index == RenderingServer.CANVAS_ITEM_Z_MAX)
	var heard_brain := {"state": "INVESTIGATE", "investigation_kind": "footstep", "investigate_cell": Vector2i(2, 3), "has_line_of_sight": false, "target_index": 0}
	assert(game._bot_debug_action_text(1, heard_brain).contains("HEARD FOOTSTEP (2,3)"))
	assert(not game._bot_debug_action_text(1, heard_brain).contains("SEES"))
	var memory_brain := {"state": "SEARCH", "has_line_of_sight": false, "target_index": 0, "combat_memory": 2.0, "last_seen_position": Vector2(1.0, 3.0)}
	assert(game._bot_debug_action_text(1, memory_brain).contains("LAST SEEN 1.0,3.0"))
	var firing_edges := 0
	for child in game.view_slot_overlay.get_children():
		if child is Line2D and child.has_meta("firing_point_edge"):
			firing_edges += 1
			assert(is_equal_approx(child.width, 0.5))
	assert(firing_edges == 4)
	var lines := 0
	for child in game.view_slot_overlay.get_children():
		if child is Line2D:
			lines += 1
	assert(lines == 4)
	game.show_bot_navigation_debug = false
	game._update_view_slot_debug_overlay()
	assert(not game.view_slot_overlay.visible and not labels_canvas.visible)
	print("Player view shows bot action, firing point and destination")
	scene.queue_free()
	quit()
