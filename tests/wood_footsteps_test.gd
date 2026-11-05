extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game.player_joined[0] = true
	game.player_joined[1] = true
	game.player_bots[0] = false
	game.player_bots[1] = true
	game.player_states[0] = game._make_player_state(0, Vector2i(1, 1), 1)
	game.player_states[1] = game._make_player_state(1, Vector2i(3, 1), 3)
	game.player_states[0]["world_position"] = Vector2(1.5, 1.5)
	game.player_states[1]["world_position"] = Vector2(3.5, 1.5)
	game.bot_brains.clear()
	game.footstep_tracks.clear()
	var sprite: AnimatedSprite2D = game.player_views[0]["player_sprite"]
	sprite.play("RunN_AimN")
	sprite.set_frame_and_progress(0, 0.0)
	# No displacement makes no sound, including when pressed against a wall.
	game._update_actor_footsteps(1.0)
	game._update_actor_footsteps(1.0)
	assert(game.footstep_last_samples.is_empty())
	# Frame changes while blocked do not play a footstep.
	sprite.set_frame_and_progress(2, 0.0)
	game._update_actor_footsteps(1.0)
	assert(game.footstep_last_samples.is_empty())
	sprite.set_frame_and_progress(3, 0.0)
	game._update_actor_footsteps(1.0)
	# A loop and reverse playback both detect a crossed planted frame.
	var probe: Dictionary = {}
	sprite.set_frame_and_progress(4, 0.0)
	assert(not game._player_footstep_frame_crossed(probe, sprite))
	sprite.set_frame_and_progress(0, 0.0)
	assert(game._player_footstep_frame_crossed(probe, sprite))
	sprite.play_backwards("RunN_AimN")
	sprite.set_frame_and_progress(3, 0.0)
	assert(not game._player_footstep_frame_crossed(probe, sprite))
	sprite.set_frame_and_progress(2, 0.0)
	assert(game._player_footstep_frame_crossed(probe, sprite))
	sprite.play("RunN_AimN")
	sprite.set_frame_and_progress(0, 0.0)
	game._update_actor_footsteps(1.0)
	# A planted-foot frame while moving triggers a walk and investigation.
	sprite.set_frame_and_progress(2, 0.0)
	game.player_states[0]["world_position"] = Vector2(1.82, 1.5)
	game._update_actor_footsteps(1.0)
	assert(game.footstep_last_samples.has("0:Walk"))
	assert(game.bot_brains[1].has("footstep_pending"))
	game._set_wall_between(Vector2i(2, 1), Vector2i(1, 0), true)
	var brain: Dictionary = game._update_bot_brain(1, game.player_states[1], Vector2(3.5, 1.5), 0, Vector2(-1.68, 0), 1.68, Vector2.LEFT, 0.016)
	assert(brain["state"] == "INVESTIGATE" and brain["investigation_kind"] == "footstep")
	assert(brain["investigate_cell"] == Vector2i(1, 1))
	assert(game.BOT_BARKS["hearing"].has(game.bot_bark_last_line[1]))
	# Sneaking is audible to the listener but cannot create a bot alert.
	game.bot_brains.clear()
	game.player_states[0]["character_is_crouching"] = true
	sprite.play("CrouchWalkN")
	sprite.set_frame_and_progress(0, 0.0)
	game._update_actor_footsteps(1.0)
	sprite.set_frame_and_progress(2, 0.0)
	game.player_states[0]["world_position"] = Vector2(2.1, 1.5)
	game._update_actor_footsteps(1.0)
	assert(game.footstep_last_samples.has("0:Sneak"))
	assert(not game.bot_brains.has(1))
	# Fast movement uses run; range limits and gunshot priority are independent.
	game.player_states[0]["character_is_crouching"] = false
	sprite.play("RunN_AimN")
	sprite.set_frame_and_progress(0, 0.0)
	game._update_actor_footsteps(1.0)
	sprite.set_frame_and_progress(2, 0.0)
	game.player_states[0]["world_position"] = Vector2(2.55, 1.5)
	game._update_actor_footsteps(0.5)
	assert(game.footstep_last_samples.has("0:Run"))
	assert(game.bot_brains[1].has("footstep_pending"))
	game.bot_brains[1] = {"investigation_kind": "shot"}
	game._notify_bots_of_footstep(0, "Run", Vector2(2.5, 1.5))
	assert(not game.bot_brains[1].has("footstep_pending"))
	game.bot_brains.clear()
	game._notify_bots_of_footstep(0, "Walk", Vector2(0, 5))
	assert(not game.bot_brains.has(1))
	# A falling actor emits one drop sound when the fall reaches the floor.
	game.player_states[1]["is_dying"] = true
	game.player_states[1]["death_phase"] = "fall"
	game.player_states[1]["death_timer"] = float(game.DEATH_FALL_SECONDS) - 0.1
	game.player_states[1]["death_ground_sound_played"] = false
	game.clear_the_map_mode = true
	game._process_combat(0.2)
	assert(game.footstep_last_samples.has("1:Drop"))
	assert(game.player_states[1]["death_ground_sound_played"])
	print("Wood footsteps: speed, sneak, sound investigation, priority, and body fall passed")
	game.queue_free()
	quit()
