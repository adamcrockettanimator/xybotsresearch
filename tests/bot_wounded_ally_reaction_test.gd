extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.clear_the_map_mode = true
	game.clear_map_round = 5
	game._apply_session_roster()
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game.player_states[0]["world_position"] = Vector2(3.5, 2.5)
	game.player_states[1]["world_position"] = Vector2(2.5, 2.5)
	game.player_states[1]["health"] = 3
	# A first hit must register even when no prior health observation exists.
	game.bot_brains.erase(1)
	assert(game._apply_projectile_hit(1, Vector2.LEFT, 0))
	assert(game.bot_brains[1]["reaction_kind"] == "retreat")
	var origin := Vector2(2.5, 2.5)
	var brain: Dictionary = game._update_bot_brain(1, game.player_states[1], origin, 0, Vector2.RIGHT, 1.0, Vector2.RIGHT, 0.1)
	assert(brain["state"] in ["FALL_BACK", "RETREAT_TO_COVER", "DUCK_AFTER_HIT"])
	assert(brain["state"] == "DUCK_AFTER_HIT" or Vector2(brain["move_direction"]).length() > 0.9)
	assert(not brain["allow_fire"])
	assert(brain["debug_tactical_reason"] == "SHOT / SEEK COVER")
	# Witnesses face the casualty; one retreats, one advances. A witness behind
	# a closed wall does neither and does not acquire the unseen killer.
	game.bot_brains.clear()
	game.player_states[1]["health"] = 1
	game.player_states[2]["world_position"] = Vector2(2.1, 2.5)
	game.player_states[2]["continuous_camera_yaw"] = PI * 0.5
	game.player_states[3]["world_position"] = Vector2(2.5, 3.3)
	game.player_states[3]["continuous_camera_yaw"] = 0.0
	game.player_states[4]["world_position"] = Vector2(1.5, 2.5)
	game.player_states[4]["continuous_camera_yaw"] = PI * 0.5
	game._set_wall_between(Vector2i(1, 2), Vector2i.RIGHT, true)
	game.bot_bark_last_global = -INF
	assert(game._apply_projectile_hit(1, Vector2.LEFT, 0))
	assert(game.bot_brains[2]["reaction_kind"] == "aggressive")
	assert(game.bot_brains[3]["reaction_kind"] == "retreat")
	assert(not game.bot_brains.has(4) or not game.bot_brains[4].has("reaction_kind"))
	assert(game.bot_bark_speaker == 2 and game.BOT_BARKS["ally_attack"].has(game.bot_bark_last_line[2]))
	game.bot_bark_last_global = -INF
	assert(game._request_bot_bark(3, "ally_retreat"))
	assert(game.bot_bark_speaker == 3 and game.BOT_BARKS["ally_retreat"].has(game.bot_bark_last_line[3]))
	assert(not game.bot_brains[2].has("last_seen_position"))
	assert(Vector2(game.bot_brains[3]["reaction_threat"]) == Vector2(2.5, 2.5))
	var witness_origin := Vector2(2.1, 2.5)
	brain = game._update_bot_brain(2, game.player_states[2], witness_origin, 0, Vector2(1.4, 0), 1.4, Vector2.RIGHT, 0.1)
	assert(brain["state"] == "ADVANCE_AFTER_ALLY_FALL")
	assert(Vector2(brain["move_direction"]).dot(Vector2.RIGHT) > 0.9)
	# Both fallback and attack sounds are actual available resources.
	for category in ["ally_retreat", "ally_attack"]:
		for filename in game.BOT_BARKS[category]:
			assert(load(filename if String(filename).begins_with("res://") else game.BOT_BARK_ROOT + filename) is AudioStream)
	print("Wounded retreat, visible ally-fall reactions, bark choice and occlusion passed")
	game.queue_free()
	quit()
