extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var game: Node = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game._build_empty_grid_audit_wall_edges()
	game.world_barrels.clear()
	for i in range(game.player_joined.size()):
		game.player_joined[i] = i < 2
	game.player_two_joined = true
	var state: Dictionary = game.player_states[0]
	state["world_position"] = Vector2(2, 2)
	game.player_states[1]["world_position"] = Vector2(4, 2.2)
	var origin := Vector2(2, 2)
	var aim := Vector2.RIGHT
	var assisted: Vector2 = game._assisted_shot_direction(0, origin, aim, false)
	assert(absf(aim.angle_to(assisted)) <= deg_to_rad(2.0))
	assert(not game._nearest_projectile_player_hit(0, origin, assisted, 20.0, false).is_empty())
	game.player_states[1]["world_position"] = Vector2(4, 3.5)
	assert(game._assisted_shot_direction(0, origin, aim, false).is_equal_approx(aim))
	state["dive_active"] = true
	state["dive_elapsed"] = 1.0
	state["reload_phase"] = ""
	state["pistol_ammo"] = 6
	game.held_keycodes[KEY_F] = true
	var before: int = game.active_projectiles.size()
	game._process_combat(0.001)
	assert(game.active_projectiles.size() == before + 1)
	game._process_combat(0.001)
	assert(game.active_projectiles.size() == before + 1)
	game.held_keycodes[KEY_F] = false
	game._process_combat(0.001)
	game.held_keycodes[KEY_F] = true
	game._process_combat(0.001)
	assert(game.active_projectiles.size() == before + 2)
	print("Semi-auto, late-roll firing and aim assist passed")
	quit()

