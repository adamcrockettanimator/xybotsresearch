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
	# Airborne motion is faster than running, while the finish is slower than
	# crouch walking; the integrated curve is independent of frame partition.
	var run_speed: float = game.LOCAL_TILE_WORLD_HALF_EXTENT * game.MOVE_UNITS_PER_SECOND
	var air_speed: float = (game._dive_roll_distance_at_time(0.2) - game._dive_roll_distance_at_time(0.1)) / 0.1
	var finish_speed: float = (game._dive_roll_distance_at_time(1.0) - game._dive_roll_distance_at_time(0.9)) / 0.1
	assert(air_speed > run_speed and air_speed < run_speed * 1.25)
	assert(finish_speed < run_speed * game.crouch_move_speed_multiplier)
	var accumulated := 0.0
	for step in 60:
		var t := float(step) / 60.0
		accumulated += game._dive_roll_distance_at_time(t + 1.0 / 60.0) - game._dive_roll_distance_at_time(t)
	assert(is_equal_approx(accumulated, game._dive_roll_distance_at_time(1.0)))
	var extra: float = game._dive_roll_distance_at_time(10.0 / 12.0) - game._dive_roll_base_distance_at_time(10.0 / 12.0)
	assert(extra > 0.3)
	assert(is_zero_approx(game._dive_roll_distance_at_time(3.0 / 12.0) - game._dive_roll_base_distance_at_time(3.0 / 12.0)))
	var state: Dictionary = game.player_states[0]
	game.held_keycodes[KEY_A] = true
	game.held_keycodes[KEY_SPACE] = true
	game.held_keycodes[KEY_SHIFT] = true
	var start: Vector2 = game.player_world_position
	assert(game._advance_dive_roll(0, 0.1, true))
	assert(state["dive_active"] and state["character_is_crouching"])
	assert(game.player_world_position.distance_to(start) > 0.05)
	assert(game.player_sprite.animation == &"DiveLeftN")
	assert(game.player_sprite.sprite_frames.get_frame_count(&"DiveLeftN") == 13)
	assert(game.player_sprite.sprite_frames.get_frame_count(&"DiveRightN") == 13)
	game._save_player_context(0)
	game.held_keycodes[KEY_SHIFT] = false
	game.held_keycodes[KEY_SPACE] = false
	assert(game._advance_dive_roll(0, 0.2, true))
	assert(not state["character_is_crouching"])
	assert(game._advance_dive_roll(0, 1.0, true))
	assert(not game._advance_dive_roll(0, 0.01, true))
	assert(not state["dive_active"])
	game.held_keycodes[KEY_SPACE] = true
	assert(game._advance_dive_roll(0, 0.01, true))
	assert(state["dive_active"] and float(state["dive_elapsed"]) < 0.1)
	game.held_keycodes[KEY_SPACE] = false
	assert(game._advance_dive_roll(0, 0.9, true))
	game.held_keycodes[KEY_SPACE] = true
	assert(game._advance_dive_roll(0, 0.2, true))
	assert(state.has("dive_buffer_direction"))
	game.held_keycodes[KEY_SPACE] = false
	assert(game._advance_dive_roll(0, 0.01, true))
	assert(state["dive_active"] and float(state["dive_elapsed"]) < 0.1)
	game.held_keycodes[KEY_A] = false
	# Fire is suppressed even when the weapon and fire input are ready.
	state["dive_active"] = true
	state["reload_phase"] = ""
	state["fire_cooldown"] = 0.0
	game.held_keycodes[KEY_F] = true
	var shots_before: int = game.active_projectiles.size()
	game._process_combat(0.01)
	assert(game.active_projectiles.size() == shots_before)
	state["dive_active"] = false
	game.held_keycodes[KEY_F] = false
	# Reloading freezes exactly during each roll, then resumes where it left off.
	state["pistol_ammo"] = 2
	state["reload_phase"] = ""
	game._start_pistol_reload(state)
	game._advance_pistol_reload(state, 0.1)
	var phase_before: String = state["reload_phase"]
	var timer_before: float = state["reload_timer"]
	var elapsed_before: float = state["reload_elapsed"]
	var ammo_before: int = state["pistol_ammo"]
	state["dive_active"] = true
	game._process_combat(0.5)
	assert(state["reload_phase"] == phase_before and is_equal_approx(state["reload_timer"], timer_before))
	assert(is_equal_approx(state["reload_elapsed"], elapsed_before) and state["pistol_ammo"] == ammo_before)
	state["dive_active"] = false
	game._advance_pistol_reload(state, 0.15)
	assert(state["pistol_ammo"] > ammo_before or state["reload_phase"] != phase_before)
	phase_before = state["reload_phase"]
	timer_before = state["reload_timer"]
	ammo_before = state["pistol_ammo"]
	state["dive_active"] = true
	game._advance_pistol_reload(state, 1.0)
	assert(state["reload_phase"] == phase_before and state["pistol_ammo"] == ammo_before and is_equal_approx(state["reload_timer"], timer_before))
	state["dive_active"] = false
	game._advance_pistol_reload(state, 10.0)
	assert(state["pistol_ammo"] == 6 and String(state["reload_phase"]).is_empty())
	# Bots never roll at a generic evade or fallback with no actual cover.
	seed(1234)
	var npc: Dictionary = game.player_states[1]
	npc["world_position"] = Vector2(2.15, 2.5)
	state["world_position"] = Vector2(3.7, 2.5)
	for index in range(game.player_joined.size()):
		game.player_joined[index] = index < 2
	var starts := 0
	for attempt in 30:
		npc["dive_active"] = false
		npc["dive_cooldown"] = 0.0
		npc["dive_was_pressed"] = false
		npc["dive_bot_reason"] = ""
		game.bot_brains[1] = {"tactical_mode": "evade", "move_direction": Vector2.ZERO, "target_index": 0}
		game.bot_inputs[1] = {"crouch": false}
		if game._advance_dive_roll(1, 0.01, false):
			starts += 1
	assert(starts == 0)
	game.world_barrels.append({"id": 100, "position": Vector2(2.75, 2.5), "projectile_radius": 0.12, "collision_radius": 0.12, "projectile_height": 0.7})
	var cover: Vector2 = game._bot_cover_point(Vector2(2.15, 2.5), Vector2(3.7, 2.5))
	assert(cover.is_finite())
	var cover_brain := {"tactical_mode": "reload_cover", "reload_cover_point": cover, "target_index": 0}
	assert(game._bot_dive_cover_goal(1, cover_brain).is_equal_approx(cover))
	for attempt in 30:
		npc["world_position"] = Vector2(2.15, 2.5)
		npc["dive_active"] = false
		npc["dive_cooldown"] = 0.0
		npc["dive_was_pressed"] = false
		npc["dive_bot_reason"] = ""
		game.bot_brains[1] = cover_brain.duplicate()
		if game._advance_dive_roll(1, 0.01, false):
			starts += 1
			assert(Vector2(npc["dive_cover_goal"]).is_equal_approx(cover))
			for tick in 65:
				game._advance_dive_roll(1, 1.0 / 60.0, false)
			assert(game._player_state_world_position(npc).distance_to(cover) < 0.04)
			assert(not game._bot_low_lane_clear(game._player_state_world_position(npc), Vector2(3.7, 2.5)))
	assert(starts > 0 and starts < 30)
	game.world_barrels.clear()
	# Frames 4–10 protect both humans and bots.
	for index in [0, 1]:
		var target: Dictionary = game.player_states[index]
		target["dive_active"] = true
		for frame in 13:
			target["dive_elapsed"] = (float(frame) + 0.5) / 12.0
			assert(game._dive_roll_invulnerable(target) == (frame >= 3 and frame <= 9))
		target["dive_elapsed"] = 0.5
		target["health"] = 10
		assert(not game._apply_projectile_hit(index, Vector2.RIGHT))
		assert(target["health"] == 10)
		target["dive_elapsed"] = 2.5 / 12.0
		assert(game._apply_projectile_hit(index, Vector2.RIGHT))
		target["dive_elapsed"] = 10.5 / 12.0
		assert(game._apply_projectile_hit(index, Vector2.RIGHT))
		assert(target["health"] == 8)
		target["dive_active"] = false
		assert(not game._dive_roll_invulnerable(target))
	# During protection, a projectile passes through instead of stopping at the body.
	for index in range(game.player_joined.size()):
		game.player_joined[index] = index < 2
	state["character_is_crouching"] = false
	state["world_position"] = Vector2(2.5, 2.5)
	state["dive_active"] = true
	state["dive_elapsed"] = 0.5
	var center: Vector2 = game._player_state_world_position(state)
	var ray_origin := center - Vector2.RIGHT
	assert(game._nearest_projectile_player_hit(1, ray_origin, Vector2.RIGHT, 2.0, false).is_empty())
	state["dive_elapsed"] = 10.5 / 12.0
	assert(not game._nearest_projectile_player_hit(1, ray_origin, Vector2.RIGHT, 2.0, false).is_empty())
	state["dive_active"] = true
	state["dive_elapsed"] = 0.5
	game.show_dive_roll_debug = true
	game._update_dive_debug_overlay(game.player_sprite, state)
	var overlay: Sprite2D = game.player_sprite.get_node("DiveRollDebug")
	assert(overlay.visible)
	assert((overlay.material as ShaderMaterial).get_shader_parameter("debug_color").g > 0.8)
	state["dive_elapsed"] = 0.1
	game._update_dive_debug_overlay(game.player_sprite, state)
	assert((overlay.material as ShaderMaterial).get_shader_parameter("debug_color").g < 0.2)
	game._set_debug_option(false, "dive_roll")
	game._update_dive_debug_overlay(game.player_sprite, state)
	assert(not overlay.visible)
	state["dive_active"] = false
	print("Dive roll movement, stance, fire lockout, NPC evasion and invincibility passed")
	game.queue_free()
	quit()
