extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.clear_the_map_mode = true
	game.clear_map_round = 3
	game._apply_session_roster()
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	var origin := Vector2(2.5, 2.5)
	var known := Vector2(3.5, 2.5)
	game.player_states[0]["world_position"] = known
	game.player_states[0]["grid_position"] = Vector2i(3, 2)
	game.player_states[1]["world_position"] = origin
	game.player_states[1]["grid_position"] = Vector2i(2, 2)
	game._set_wall_between(Vector2i(2, 2), Vector2i.RIGHT, true)
	game.physical_wall_edges_cache_dirty = true
	assert(game._bot_near_cautious_corner(origin, Vector2.UP, known))
	assert(not game._bot_near_cautious_corner(origin, Vector2.UP, Vector2(5.9, 5.9)))
	game.bot_brains[1] = {"state": "INVESTIGATE", "investigation_kind": "footstep", "investigate_cell": Vector2i(3, 2), "caution_chosen": true, "caution_time": 5.0, "caution_position": known, "caution_source": "FOOTSTEP", "tactical_cooldown": 99.0}
	var brain: Dictionary = game._update_bot_brain(1, game.player_states[1], origin, 0, known - origin, 1.0, Vector2.UP, 0.1)
	assert(brain["state"] == "INVESTIGATE" and brain["cautious_approach"] and brain["crouch"])
	assert(Vector2(brain["move_direction"]).length() > 0.9)
	game.bot_inputs[1] = {"crouch": brain["crouch"]}
	game._process_virtual_bot_world_context(1, 0.1)
	assert(game.player_states[1]["character_is_crouching"])
	assert(game._bot_debug_action_text(1, brain).contains("CAUTIOUS"))
	# An unchosen event remains upright rather than re-rolling every frame.
	brain["caution_chosen"] = false
	brain["stuck_time"] = 0.0
	brain = game._update_bot_brain(1, game.player_states[1], origin, 0, known - origin, 1.0, Vector2.UP, 0.1)
	assert(not brain["cautious_approach"] and not brain["crouch"])
	# When sight is reacquired, combat owns the stance immediately.
	brain["caution_chosen"] = true
	brain["stuck_time"] = 0.0
	game._set_wall_between(Vector2i(2, 2), Vector2i.RIGHT, false)
	game.physical_wall_edges_cache_dirty = true
	brain = game._update_bot_brain(1, game.player_states[1], origin, 0, known - origin, 1.0, Vector2.RIGHT, 0.1)
	assert(brain["has_line_of_sight"] and not brain["cautious_approach"])
	# Event selection varies, while a single event stores one decision.
	seed(42)
	var selected := 0
	for i in range(100):
		var choice := {}
		game._bot_begin_cautious_approach(choice, known, "GUNSHOT")
		if choice["caution_chosen"]:
			selected += 1
	assert(selected > 50 and selected < 90)
	print("Occasional cautious corner approach and immediate combat handoff passed")
	game.queue_free()
	quit()
