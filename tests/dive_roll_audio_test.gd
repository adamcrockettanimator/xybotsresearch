extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	game._bind_player_context(0)
	assert(not game.show_dive_roll_debug)
	assert(is_equal_approx(game.player_sprite.sprite_frames.get_animation_speed(&"IdleReloadN"), 6.0))
	assert(is_equal_approx(game.player_sprite.sprite_frames.get_animation_speed(&"CrouchIdleReloadN"), 6.0))
	assert(is_equal_approx(game.player_sprite.sprite_frames.get_animation_speed(&"RunReloadN"), 8.0))
	assert(is_equal_approx(game.player_sprite.sprite_frames.get_animation_speed(&"CrouchWalkReloadN"), 8.0))
	var state: Dictionary = game.player_states[0]
	state["reload_phase"] = "bullet"
	state["reload_elapsed"] = 0.25
	assert(game._show_reload_animation(game.player_sprite, state, "N", "RunReload"))
	assert(game.player_sprite.frame == 2)
	assert(game._show_reload_animation(game.player_sprite, state, "N", "IdleReload"))
	assert(game.player_sprite.frame == 1)
	state["reload_phase"] = ""
	game._set_player_world_position_for_current_view(Vector2(2.5, 2.5))
	game._save_player_context(0)
	game.held_keycodes[KEY_A] = true
	game.held_keycodes[KEY_SPACE] = true
	assert(game._advance_dive_roll(0, 0.1, true))
	assert(not game.footstep_last_samples.has("0:Jump"))
	game.held_keycodes[KEY_SPACE] = false
	assert(game._advance_dive_roll(0, 0.08, true))
	assert(game.footstep_last_samples.has("0:Jump"))
	assert(not game.footstep_last_samples.has("0:Drop"))
	assert(game._advance_dive_roll(0, 0.34, true))
	assert(game.footstep_last_samples.has("0:Drop"))
	for index in range(game.player_joined.size()):
		game.player_joined[index] = index < 2
	game.player_states[0]["world_position"] = Vector2(1.5, 1.5)
	game.player_states[1]["world_position"] = Vector2(4.5, 1.5)
	assert(is_equal_approx(game._actor_sound_volume_db(0, -6.0), -6.0))
	assert(is_equal_approx(game._actor_sound_volume_db(1, -6.0), -12.0))
	game._play_pickup_sound(game.coin_pickup_player, 1)
	var pickup: AudioStreamPlayer = game.get_child(game.get_child_count() - 1)
	assert(is_equal_approx(pickup.volume_db, -12.0))
	game._reload_sound("Turn", 1)
	var reload: AudioStreamPlayer = game.get_child(game.get_child_count() - 1)
	assert(is_equal_approx(reload.volume_db, -17.0))
	game._reload_sound("Turn", 0)
	var own_reload: AudioStreamPlayer = game.get_child(game.get_child_count() - 1)
	assert(is_equal_approx(own_reload.volume_db, -4.0))
	assert(game._play_wood_actor_sound(0, "Run"))
	var own_steps: AudioStreamPlayer = game._footstep_channel(0)["player"]
	assert(is_equal_approx(own_steps.volume_db, -4.0))
	assert(game._play_wood_actor_sound(1, "Run"))
	var npc_steps: AudioStreamPlayer = game._footstep_channel(1)["player"]
	assert(is_equal_approx(npc_steps.volume_db, -21.0))
	game.player_states[1]["world_position"] = Vector2(2.5, 1.5)
	assert(game._play_wood_actor_sound(1, "Run"))
	assert(is_equal_approx(npc_steps.volume_db, -15.0))
	print("Roll audio frames, reload playback speeds and actor sound attenuation passed")
	game.queue_free()
	quit()
