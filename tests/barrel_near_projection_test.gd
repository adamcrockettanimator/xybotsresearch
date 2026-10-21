extends SceneTree


class TestRenderer extends "res://scripts/coordinate_frame_runtime_renderer.gd":
	func _runtime_camera_origin(_forward: Vector2, _right: Vector2) -> Vector2:
		return Vector2.ZERO

	func _overscan_projection_offset() -> Vector2:
		return Vector2.ZERO


class TestController extends "res://scripts/xybots_character_controller.gd":
	var test_sprites: Dictionary = {}

	func _view_forward_vector() -> Vector2:
		return Vector2.DOWN

	func _view_right_vector() -> Vector2:
		return Vector2.RIGHT

	func _world_actor_overlaps_current_camera_fan(_target_world: Vector2, _side_margin: float) -> bool:
		return true

	func _world_point_has_clear_camera_line(_target_world: Vector2) -> bool:
		return true

	func _world_actor_draw_layer(_world_position: Vector2) -> int:
		return 0

	func _combat_sprite(key: String) -> Sprite2D:
		if not test_sprites.has(key):
			test_sprites[key] = Sprite2D.new()
		return test_sprites[key]

	func _apply_runtime_world_prop_style(_sprite: Sprite2D, _world_view_depth: float, _floor_pixel: Vector2) -> void:
		pass


func _initialize() -> void:
	var game := TestController.new()
	var renderer := TestRenderer.new()
	renderer.controller = game
	game.coordinate_renderers.append(renderer)
	var previous_scale := 0.0
	var expected_scale_depth_product := -1.0
	var failures: Array[String] = []
	# Include both sides of the old near cap and the point where the barrel's top
	# naturally leaves the bottom edge of the 160x120 view.
	for depth in [1.0, 0.8, 0.7, 0.6, 0.5, 0.45, 0.4, 0.35]:
		var point := Vector2(0.0, depth)
		var projection := renderer.runtime_project_world_effect_point_for_current_pose(point)
		var used := {}
		game._render_world_barrel("test_barrel", point, used)
		var sprite: Sprite2D = game.test_sprites.get("test_barrel")
		if sprite == null or not used.has("test_barrel"):
			failures.append("Barrel was not rendered at depth %s" % depth)
			continue
		var scale_value := sprite.scale.x
		var scale_depth_product := scale_value * float(depth)
		if expected_scale_depth_product < 0.0:
			expected_scale_depth_product = scale_depth_product
		if scale_value <= previous_scale or not is_equal_approx(scale_depth_product, expected_scale_depth_product):
			failures.append("Scale did not follow inverse depth at %s: %s" % [depth, scale_value])
		var expected_y := roundf(roundf(float(projection["feet_y"])) - game.BARREL_ART_HEIGHT * scale_value * 0.5)
		if not is_equal_approx(sprite.position.y, expected_y):
			failures.append("Ground anchor diverged at depth %s" % depth)
		print("depth=%.2f scale=%.4f feet=%.2f top=%.2f" % [depth, scale_value, projection["feet_y"], sprite.position.y - game.BARREL_ART_HEIGHT * scale_value * 0.5])
		previous_scale = scale_value
	for sprite in game.test_sprites.values():
		sprite.free()
	renderer.free()
	game.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Barrel near projection test passed")
	quit(0)
