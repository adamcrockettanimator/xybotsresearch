extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.player_bots[1] = true
	game.player_joined[0] = true
	game.player_joined[1] = true
	game.player_states[0] = game._make_player_state(0, Vector2i(2, 2), 0)
	game.player_states[0]["world_position"] = Vector2(2.5, 2.5)
	game.player_states[1] = game._make_player_state(1, Vector2i(3, 2), 0)
	game.player_states[1]["world_position"] = Vector2(3.5, 2.5)
	game.player_states[1]["voice_actor"] = "adam"
	game.player_states[1]["health"] = 2
	assert(game._apply_projectile_hit(1, Vector2.RIGHT, 0))
	assert(game.bot_damage_channels.has(1))
	var channel: Dictionary = game.bot_damage_channels[1]
	assert(channel["player"].playing)
	assert(channel["panner"].pan > 0.8)
	var hit_stream: AudioStream = channel["player"].stream
	assert(hit_stream.resource_path.begins_with("res://assets/Audio/Dialog/Barks/adam/"))
	assert(game._apply_projectile_hit(1, Vector2.RIGHT, 0))
	assert(game.player_states[1]["is_dying"] and channel["player"].playing)
	var death_stream: AudioStream = channel["player"].stream
	assert(death_stream.resource_path.begins_with("res://assets/Audio/Dialog/Barks/adam/"))
	assert(death_stream != hit_stream)
	assert(not game._apply_projectile_hit(1, Vector2.RIGHT, 0))
	assert(not game._request_bot_bark(0, "hit"))
	print("Assigned-actor injury and death reactions, spatialization and guards passed")
	game.queue_free()
	quit()
