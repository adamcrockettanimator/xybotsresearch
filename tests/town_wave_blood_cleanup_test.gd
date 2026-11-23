extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load("res://outdoor_town.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var game: Node = scene.get_node("CoordinateFrameGame")
	game.set_process(false)
	game._set_town_waves_enabled(true)
	game.active_blood_splatters.assign([
		{"victim_player_index": 1, "persistent_killing_shot": true, "stuck": true, "timer": INF},
		{"victim_player_index": 2, "persistent_killing_shot": true, "stuck": false, "timer": 0.4},
		{"victim_player_index": 0, "persistent_killing_shot": true, "stuck": true, "timer": INF},
		{"victim_player_index": 1, "persistent_killing_shot": false, "stuck": true, "timer": 0.3},
	])
	assert(game._spawn_town_wave())
	var blood: Array = game.active_blood_splatters
	assert(not blood[0].persistent_killing_shot and blood[0].timer == game.BLOOD_SPLATTER_STUCK_LIFETIME)
	assert(not blood[1].persistent_killing_shot and blood[1].timer == 0.4)
	assert(blood[2].persistent_killing_shot and is_inf(blood[2].timer))
	assert(not blood[3].persistent_killing_shot and blood[3].timer == 0.3)
	print("Town wave blood lifecycle passed")
	scene.queue_free()
	quit()
