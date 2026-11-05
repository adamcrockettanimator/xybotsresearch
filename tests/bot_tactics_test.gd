extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	var origin := Vector2(2.25, 2.5)
	var target := Vector2(3.5, 2.5)
	game.player_states[0]["character_is_crouching"] = true
	var brain := {}
	game._update_bot_tactics(1, origin, 0, target - origin, true, 0.1, brain)
	assert(brain["tactical_mode"] == "low_shot")
	assert(brain["crouch"] and brain["allow_fire"])
	game._update_bot_tactics(1, origin, 0, target - origin, true, 0.2, brain)
	assert(brain["crouch"])
	game.world_barrels.append({"id": 100, "position": Vector2(2.8, 2.5), "projectile_radius": 0.12, "collision_radius": 0.12, "projectile_height": 0.7})
	assert(not game._bot_low_lane_clear(origin, target))
	brain = {}
	game._update_bot_tactics(1, origin, 0, target - origin, true, 0.1, brain)
	assert(brain["tactical_mode"] == "reposition")
	assert(not brain["allow_fire"])
	brain = {"tactical_mode": "cover", "tactical_timer": 2.0, "tactical_target": 0}
	game._update_bot_tactics(1, origin, 0, target - origin, true, 0.1, brain)
	assert(brain["crouch"] and not brain["allow_fire"])
	brain["tactical_timer"] = 0.0
	game.player_states[0]["character_is_crouching"] = false
	game._update_bot_tactics(1, origin, 0, target - origin, true, 0.1, brain)
	assert(brain["tactical_mode"] == "cover_pop" and brain["allow_fire"] and not brain["crouch"])
	brain["tactical_timer"] = 0.0
	game._update_bot_tactics(1, origin, 0, target - origin, true, 0.1, brain)
	assert(brain["tactical_mode"] == "cover" and brain["crouch"])
	game.world_barrels.clear()
	game._update_bot_tactics(1, origin, 0, target - origin, true, 0.1, brain)
	assert(brain["tactical_mode"] == "reposition")
	assert(Vector2(brain["tactical_move"]).length() > 0.9)
	game.bot_brains[1] = {"move_direction": Vector2.ZERO}
	game.bot_inputs[1] = {"crouch": true}
	game._process_virtual_bot_world_context(1, 0.1)
	assert(game.player_states[1]["character_is_crouching"])
	print("Bot tactical crouch, low lane obstruction, cover and flank response passed")
	game.queue_free()
	quit()
