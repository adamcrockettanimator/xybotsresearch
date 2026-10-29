extends SceneTree


func _initialize() -> void:
	var game: Node = load("res://scripts/xybots_character_controller.gd").new()
	game.semantic_lod_floor_footprints.append({"id": "crate_semantic_flat_box", "position": Vector2(2.0, 2.0), "side_length": 0.2, "depth": 0.1, "height": 0.2})
	game.semantic_lod_floor_footprints.append({"id": "barrel_ground_gpu_circle", "position": Vector2(3.0, 3.0), "side_length": 0.16, "height": 0.2})
	game._setup_semantic_stress_props()
	assert(game.world_barrels.size() > 10)
	var crate: Dictionary = game.world_barrels[0]
	var hit: Dictionary = game._nearest_projectile_barrel_hit(Vector2(1.5, 2.0), Vector2.RIGHT, 1.0, 0.5)
	assert(int(hit.get("id", -1)) == int(crate["id"]))
	assert(game._nearest_projectile_barrel_hit(Vector2(1.5, 2.0), Vector2.RIGHT, 0.6, 0.8).is_empty())
	var collision: Dictionary = game._barrel_sweep_hit(Vector2(1.5, 2.0), Vector2(0.5, 0.0))
	assert(not collision.is_empty())
	assert(Vector2(collision["normal"]).x < -0.9)
	var count: int = game.world_barrels.size()
	game._damage_barrel(int(crate["id"]), Vector2.RIGHT, Vector2(1.9, 2.0), 0.5)
	game._damage_barrel(int(crate["id"]), Vector2.RIGHT, Vector2(1.9, 2.0), 0.5)
	assert(game.world_barrels.size() == count)
	game._damage_barrel(int(crate["id"]), Vector2.RIGHT, Vector2(1.9, 2.0), 0.5)
	assert(game.world_barrels.size() == count - 1)
	assert(bool(game.semantic_lod_floor_footprints[0].get("destroyed", false)))
	game._setup_semantic_stress_props()
	assert(game.world_barrels.size() == count)
	assert(not bool(game.semantic_lod_floor_footprints[0].get("destroyed", false)))
	print("Semantic prop registration, box hits, cover height, player sweep, destruction, and reset passed")
	game.free()
	quit()
