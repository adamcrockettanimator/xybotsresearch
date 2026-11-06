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
	game.player_states[0]["world_position"] = Vector2(4.0, 2.5)
	game.player_states[1]["world_position"] = Vector2(2.0, 2.5)
	game.player_states[2]["world_position"] = Vector2(3.0, 2.5)
	game.player_states[3]["world_position"] = Vector2(4.0, 4.0)
	var hit: Dictionary = game._nearest_projectile_player_hit(1, Vector2(2.0, 2.5), Vector2.RIGHT, 3.0, false)
	assert(int(hit.get("player_index", -1)) == 2)
	assert(game._bot_teammate_in_fire_lane(1, Vector2(2.0, 2.5), Vector2(2.0, 0.0)))
	var limited: Vector2 = game._bot_limit_actor_overlap(1, Vector2(2.0, 2.5), Vector2(3.5, 2.5))
	assert(limited.distance_to(Vector2(3.0, 2.5)) >= game.PLAYER_CAPSULE_RADIUS * 2.0)
	game.bot_brains[1] = {"move_direction": Vector2.RIGHT}
	game.bot_inputs[1] = {"crouch": false}
	game._process_virtual_bot_world_context(1, 10.0)
	assert(Vector2(game.player_states[1]["world_position"]).distance_to(Vector2(3.0, 2.5)) >= game.PLAYER_CAPSULE_RADIUS * 2.0)
	game.player_states[1]["world_position"] = Vector2(2.0, 2.5)
	game.player_states[2]["health"] = 1
	assert(game._apply_projectile_hit(2, Vector2.RIGHT, 1))
	assert(game.player_states[2]["is_dying"])
	assert(not game._bot_teammate_in_fire_lane(1, Vector2(2.0, 2.5), Vector2(2.0, 0.0)))
	game.world_barrels.append({"id": 100, "position": Vector2(2.8, 2.5), "projectile_radius": 0.12, "collision_radius": 0.12, "projectile_height": 0.7})
	game.player_states[1]["reload_phase"] = "open"
	var brain := {}
	game._update_bot_tactics(1, Vector2(2.5, 2.5), 0, Vector2(1.5, 0), true, 0.1, brain)
	assert(brain["tactical_mode"] == "reload_cover")
	assert(brain.has("tactical_move"))
	assert(not brain["allow_fire"])
	game.world_barrels.clear()
	game._set_wall_between(Vector2i(2, 2), Vector2i.RIGHT, true)
	game.physical_wall_edges_cache_dirty = true
	var peek := Vector2(2.7, 1.4)
	var target := Vector2(3.5, 2.5)
	var wall_cover: Vector2 = game._bot_wall_cover_point(peek, target)
	assert(wall_cover.is_finite())
	var cover_path := target - wall_cover
	assert(game._nearest_projectile_wall_distance(wall_cover, cover_path.normalized(), cover_path.length()) < cover_path.length())
	game.player_states[1]["reload_phase"] = "open"
	brain = {}
	game._update_bot_tactics(1, peek, 0, target - peek, true, 0.1, brain)
	assert(brain["tactical_mode"] == "reload_cover" and brain.has("tactical_move"))
	game.player_states[1]["reload_phase"] = ""
	brain = {"tactical_mode": "wall_approach", "wall_cover_point": wall_cover, "wall_peek_point": peek, "tactical_timer": 2.0, "tactical_target": 0}
	game._update_bot_tactics(1, wall_cover, 0, target - wall_cover, false, 0.1, brain)
	assert(brain["tactical_mode"] == "wall_cover" and brain["crouch"])
	brain["tactical_timer"] = 0.0
	game._update_bot_tactics(1, wall_cover, 0, target - wall_cover, false, 0.1, brain)
	assert(brain["tactical_mode"] == "wall_peek" and Vector2(brain["tactical_move"]).length() > 0.9)
	print("Bot separation, friendly fire, firing lane, and reload cover passed")
	game.queue_free()
	quit()
