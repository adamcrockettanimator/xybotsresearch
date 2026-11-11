extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _filter_for_bus(name: String) -> AudioEffectLowPassFilter:
	var bus := AudioServer.get_bus_index(name)
	for index in AudioServer.get_bus_effect_count(bus):
		var effect := AudioServer.get_bus_effect(bus, index)
		if effect is AudioEffectLowPassFilter:
			return effect
	return null

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var master := AudioServer.get_bus_index("Master")
	var music := AudioServer.get_bus_index("Music")
	var master_effects := AudioServer.get_bus_effect_count(master)
	var music_effects := AudioServer.get_bus_effect_count(music)
	game._build_empty_grid_audit_wall_edges()
	for index in range(game.player_joined.size()):
		game.player_joined[index] = index < 2
	game.player_states[0]["world_position"] = Vector2(1.5, 1.5)
	game.player_states[0]["continuous_camera_yaw"] = 0.0
	game.player_states[1]["world_position"] = Vector2(2.5, 1.5)
	var clear: Dictionary = game._world_sound_spatial_info(1)
	assert(not clear.blocked and clear.pan > 0.5)
	game._advance_world_sound_occlusion(0.01)
	game._play_pickup_sound(game.coin_pickup_player, 1)
	var pickup: AudioStreamPlayer = game.get_child(game.get_child_count() - 1)
	var clear_db := pickup.volume_db
	assert(pickup.bus == "Actor World 1")
	var filter := _filter_for_bus(pickup.bus)
	assert(filter != null and filter.cutoff_hz > 20000.0)
	assert(game._request_bot_bark(1, "hearing"))
	assert(game.bot_bark_player.bus == "NPC Voice")
	assert(AudioServer.get_bus_send(AudioServer.get_bus_index("NPC Voice Reverb")) == "NPC Voice")
	var voice_filter := _filter_for_bus("NPC Voice")
	assert(voice_filter != null and voice_filter.cutoff_hz > 20000.0)
	game._set_wall_between(Vector2i(1, 1), Vector2i.RIGHT, true)
	var blocked: Dictionary = game._world_sound_spatial_info(1)
	assert(blocked.blocked and is_equal_approx(blocked.distance, clear.distance))
	game._play_pickup_sound(game.coin_pickup_player, 1)
	pickup = game.get_child(game.get_child_count() - 1)
	assert(is_equal_approx(pickup.volume_db, clear_db))
	assert(filter.cutoff_hz > 20000.0)
	game._advance_world_sound_occlusion(0.3)
	var actor_bus := AudioServer.get_bus_index(pickup.bus)
	assert(is_equal_approx(float(game.world_sound_occlusion[1]), 0.5))
	assert(filter.cutoff_hz > 1400.0 and filter.cutoff_hz < 3200.0)
	assert(game._update_bot_bark_spatial())
	assert(voice_filter.cutoff_hz > 1400.0 and voice_filter.cutoff_hz < 3200.0)
	assert(is_equal_approx(AudioServer.get_bus_volume_db(actor_bus), -2.5))
	game._advance_world_sound_occlusion(0.3)
	assert(is_equal_approx(filter.cutoff_hz, 1400.0))
	assert(is_equal_approx(AudioServer.get_bus_volume_db(actor_bus), -5.0))
	assert(game._update_bot_bark_spatial())
	assert(is_equal_approx(voice_filter.cutoff_hz, 1400.0))
	game._reload_sound("Turn", 1)
	var reload: AudioStreamPlayer = game.get_child(game.get_child_count() - 1)
	assert(reload.bus == pickup.bus and is_equal_approx(reload.volume_db + AudioServer.get_bus_volume_db(actor_bus), -16.0))
	assert(game._play_wood_actor_sound(1, "Run"))
	var footsteps: AudioStreamPlayer = game._footstep_channel(1)["player"]
	assert(is_equal_approx(footsteps.volume_db + AudioServer.get_bus_volume_db(AudioServer.get_bus_index(footsteps.bus)), -20.0))
	assert(is_equal_approx(_filter_for_bus(footsteps.bus).cutoff_hz, 1400.0))
	game._play_world_gunshot(1)
	var shot: AudioStreamPlayer = game.get_child(game.get_child_count() - 1)
	assert(shot.bus == "Actor World 1" and shot.bus == pickup.bus and shot.volume_db < 0.0)
	assert(AudioServer.get_bus_effect_count(master) == master_effects)
	assert(AudioServer.get_bus_effect_count(music) == music_effects)
	assert(game.music_player.bus == "Music")
	game._update_world_audio_bus("Master", blocked)
	game._update_world_audio_bus("Music", blocked)
	assert(AudioServer.get_bus_effect_count(master) == master_effects)
	assert(AudioServer.get_bus_effect_count(music) == music_effects)
	# Local player cues must stay unobstructed, and opening the wall restores
	# the remote actor's full-frequency bus on the next sound.
	assert(not game._world_sound_spatial_info(0).blocked)
	game._set_wall_between(Vector2i(1, 1), Vector2i.RIGHT, false)
	game._play_pickup_sound(game.coin_pickup_player, 1)
	assert(is_equal_approx(filter.cutoff_hz, 1400.0))
	game._advance_world_sound_occlusion(0.3)
	assert(filter.cutoff_hz > 1400.0 and filter.cutoff_hz < 20000.0)
	assert(is_equal_approx(AudioServer.get_bus_volume_db(actor_bus), -2.5))
	game._advance_world_sound_occlusion(0.3)
	assert(filter.cutoff_hz > 20000.0)
	assert(is_zero_approx(AudioServer.get_bus_volume_db(actor_bus)))
	assert(game._update_bot_bark_spatial())
	assert(voice_filter.cutoff_hz > 20000.0)
	print("World sound occlusion, distance, stereo and clear-path restoration passed")
	game.queue_free()
	quit()
