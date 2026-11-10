extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game.player_states[0] = game._make_player_state(0, Vector2i(3, 2), 3)
	game.player_states[1] = game._make_player_state(1, Vector2i(2, 2), 1)
	game.player_states[0]["world_position"] = Vector2(3.5, 2.5)
	game.player_states[1]["world_position"] = Vector2(2.5, 2.5)
	# Two completed peeks are permitted, then the bot exits the loop.
	var cover := Vector2(2.3, 2.5)
	var peek := Vector2(2.6, 2.5)
	var target := Vector2(3.5, 2.5)
	var brain := {"tactical_mode": "wall_cover", "wall_cover_point": cover, "wall_peek_point": peek, "tactical_timer": 0.0, "tactical_target": 0}
	for cycle in range(2):
		brain["tactical_timer"] = 0.0
		game._update_bot_tactics(1, cover, 0, target - cover, false, 0.1, brain)
		assert(brain["tactical_mode"] == "wall_peek")
		game._update_bot_tactics(1, peek, 0, target - peek, true, 0.1, brain)
		assert(brain["wall_peek_arrived"] and brain["wall_peek_count"] == cycle + 1)
		brain["tactical_timer"] = 0.0
		game._update_bot_tactics(1, peek, 0, target - peek, true, 0.1, brain)
		assert(brain["tactical_mode"] == "wall_approach")
		game._update_bot_tactics(1, cover, 0, target - cover, false, 0.1, brain)
		assert(brain["tactical_mode"] == "wall_cover")
	brain["tactical_timer"] = 0.0
	game._update_bot_tactics(1, cover, 0, target - cover, false, 0.1, brain)
	assert(brain["tactical_mode"] == "" and brain["tactical_cooldown"] > 0.0)
	# A blocked peek times out without counting as a completed peek.
	brain = {"tactical_mode": "wall_peek", "wall_cover_point": cover, "wall_peek_point": peek, "tactical_timer": 0.0, "tactical_target": 0, "wall_peek_arrived": false}
	game._update_bot_tactics(1, cover, 0, target - cover, false, 0.1, brain)
	assert(brain["tactical_mode"] == "" and int(brain.get("wall_peek_count", 0)) == 0)
	# Short glimpses during a search cannot repeatedly restart the last-seen state.
	game.bot_brains[1] = {"state": "SEARCH", "combat_memory": 1.0, "last_seen_target": 0, "last_seen_position": target, "last_seen_cell": Vector2i(3, 2), "lost_sight_time": 0.5, "tactical_cooldown": 100.0}
	var origin := Vector2(2.5, 2.5)
	for i in range(5):
		game._set_wall_between(Vector2i(2, 2), Vector2i.RIGHT, false)
		brain = game._update_bot_brain(1, game.player_states[1], origin, 0, target - origin, 1.0, Vector2.RIGHT, 0.05)
		assert(brain["state"] in ["SEARCH", "FLANK"])
		game._set_wall_between(Vector2i(2, 2), Vector2i.RIGHT, true)
		brain = game._update_bot_brain(1, game.player_states[1], origin, 0, target - origin, 1.0, Vector2.RIGHT, 0.05)
		assert(brain["state"] in ["SEARCH", "FLANK"])
		brain["stuck_time"] = 0.0
	game._set_wall_between(Vector2i(2, 2), Vector2i.RIGHT, false)
	for i in range(3):
		brain = game._update_bot_brain(1, game.player_states[1], origin, 0, target - origin, 1.0, Vector2.RIGHT, 0.1)
	assert(brain["has_line_of_sight"] and brain["state"] in ["FIRING_POINT", "FLANK"])
	print("Wall peeks terminate and intermittent sight does not restart search")
	game.queue_free()
	quit()
