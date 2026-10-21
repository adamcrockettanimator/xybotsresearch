extends SceneTree

class TestController extends "res://scripts/xybots_character_controller.gd":
	var test_wall_y := -INF
	func _view_forward_vector_for_state(_state: Dictionary) -> Vector2:
		return Vector2.UP
	func _advance_combat_round(_delta: float) -> void:
		pass
	func _collect_combat_pickups(_delta: float) -> void:
		pass
	func _update_combat_hud() -> void:
		pass
	func _is_player_fire_pressed_for(_player_index: int) -> bool:
		return false
	func _nearest_projectile_wall_distance(origin: Vector2, direction: Vector2, maximum_distance: float) -> float:
		if is_inf(test_wall_y) or direction.y >= 0.0:
			return maximum_distance + 1.0
		var distance := (test_wall_y - origin.y) / direction.y
		return distance if distance >= 0.0 and distance <= maximum_distance else maximum_distance + 1.0
	func _nearest_projectile_wall_edge_key(_origin: Vector2, _direction: Vector2, _maximum_distance: float) -> String:
		return "test_wall"
	func _nearest_projectile_player_hit(_owner: int, _origin: Vector2, _direction: Vector2, _maximum_distance: float, _shot_crouched: bool) -> Dictionary:
		return {}

func _initialize() -> void:
	var game := TestController.new()
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = (load(game.IDLE_FRAMES) as SpriteFrames).duplicate(true)
	game._add_crouch_walk_animations(sprite.sprite_frames)
	game.player_views.append({"player_sprite": sprite})
	game.player_joined[0] = true
	game.player_states.append({"world_position": Vector2(3, 3), "character_is_crouching": false, "machine_gun_ammo": 0, "fire_cooldown": 0.0})
	var failures: Array[String] = []
	sprite.animation = &"IdleN"
	game._spawn_pistol_shot(0)
	var standing: Dictionary = game.active_projectiles[0]
	var standing_height := float(standing["height"])
	game.active_projectiles.clear()
	sprite.animation = &"CrouchWalkN"
	game.player_states[0]["character_is_crouching"] = true
	var muzzle: Dictionary = game._world_muzzle_anchor(0, Vector2(3, 3), Vector2.UP, &"right")
	game.world_barrels.append({"id": 77, "position": Vector2(Vector2(muzzle["position"]).x, 2.0)})
	game._spawn_pistol_shot(0)
	var crouched: Dictionary = game.active_projectiles[0]
	if float(crouched["height"]) >= standing_height:
		failures.append("Crouched muzzle did not produce a lower projectile")
	if float(crouched["height"]) * 0.36 >= (2.0 / 3.0) * (1.0 - 62.0 / 88.0):
		failures.append("Crouched projectile is not below the wall's trim rail")
	if not is_equal_approx(float(crouched["muzzle_height"]), float(muzzle["height"])):
		failures.append("Crouch adjustment moved the authored muzzle smoke anchor")
	if not is_equal_approx(float(standing["height"]), float(standing["muzzle_height"])):
		failures.append("Standing shot height changed")
	if Vector2(crouched["visual_target_position"]).distance_to(game.world_barrels[0]["position"]) > game.BARREL_PROJECTILE_RADIUS + 0.001:
		failures.append("Crouched visual endpoint missed the barrel")
	game._process_combat(0.16)
	if not game.active_projectiles.is_empty() or game.active_wall_bullet_holes.is_empty() or not bool(game.active_wall_bullet_holes.back().get("barrel_hit", false)):
		failures.append("Crouched shot did not stop at the barrel with an impact")
	game.active_wall_bullet_holes.clear()
	sprite.animation = &"IdleN"
	game.player_states[0]["character_is_crouching"] = false
	game._spawn_pistol_shot(0)
	game._process_combat(0.16)
	if game.active_projectiles.is_empty() or not game.active_wall_bullet_holes.is_empty():
		failures.append("Standing shot did not pass over the barrel")
	game.active_projectiles.clear()
	sprite.animation = &"CrouchWalkN"
	game.player_states[0]["character_is_crouching"] = true
	game.test_wall_y = 2.35
	game._spawn_pistol_shot(0)
	game._process_combat(0.16)
	if game.active_wall_bullet_holes.is_empty() or bool(game.active_wall_bullet_holes.back().get("barrel_hit", false)):
		failures.append("Wall in front of barrel did not win collision")
	game.test_wall_y = -INF
	game.active_projectiles.clear()
	game.active_wall_bullet_holes.clear()
	game.world_barrels[0]["position"] = Vector2(Vector2(muzzle["position"]).x, 2.8)
	game._spawn_pistol_shot(0)
	game._process_combat(0.04)
	if not game.active_projectiles.is_empty() or game.active_wall_bullet_holes.is_empty() or not bool(game.active_wall_bullet_holes.back().get("barrel_hit", false)):
		failures.append("Close barrel was skipped when spawning the shot")
	var projection := {"screen_x": 5.0, "feet_y": 100.0, "continuous_actor_height": 50.0}
	var standing_y := game._projectile_screen_position_continuous(projection, standing_height).y
	var crouching_y := game._projectile_screen_position_continuous(projection, float(crouched["height"])).y
	if crouching_y <= standing_y:
		failures.append("Projectile tracer projection did not use the lowered height")
	game.world_barrels.clear()
	for animation in [&"CrouchWalkN", &"CrouchWalkRightN", &"CrouchWalkLeftN", &"CrouchIdleN"]:
		sprite.animation = animation
		for frame_index in sprite.sprite_frames.get_frame_count(animation):
			sprite.frame = frame_index
			game.active_projectiles.clear()
			game._spawn_pistol_shot(0)
			var frame_shot: Dictionary = game.active_projectiles.back()
			if float(frame_shot["height"]) * 0.36 >= (2.0 / 3.0) * (1.0 - 63.0 / 88.0):
				failures.append("Crouched shot is too close to the rail in %s frame %d" % [animation, frame_index])
	print("standing height=%.3f crouched height=%.3f barrel top=%.3f" % [standing_height, float(crouched["height"]), game.BARREL_PROJECTILE_HEIGHT])
	sprite.free()
	game.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("Crouch and barrel projectile checks passed")
		quit(0)
