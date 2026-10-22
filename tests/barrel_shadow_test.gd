extends SceneTree


class TestRenderer extends "res://scripts/coordinate_frame_runtime_renderer.gd":
	func _runtime_camera_origin(_forward: Vector2, _right: Vector2) -> Vector2:
		return Vector2.ZERO

	func _overscan_projection_offset() -> Vector2:
		return Vector2.ZERO


class TestController extends "res://scripts/xybots_character_controller.gd":
	var test_sprites: Dictionary = {}
	var clear_barrel_samples: Array[Vector2] = []
	var force_barrel_line_samples := false

	func _view_forward_vector() -> Vector2:
		return Vector2.DOWN

	func _view_right_vector() -> Vector2:
		return Vector2.RIGHT

	func _world_actor_overlaps_current_camera_fan(_target_world: Vector2, _side_margin: float) -> bool:
		return true

	func _world_point_has_clear_camera_line(_target_world: Vector2) -> bool:
		if not force_barrel_line_samples:
			return true
		for sample in clear_barrel_samples:
			if _target_world.is_equal_approx(sample):
				return true
		return false

	func _world_actor_draw_layer(_world_position: Vector2) -> int:
		return 0

	func _combat_sprite(key: String) -> Sprite2D:
		if not test_sprites.has(key):
			test_sprites[key] = Sprite2D.new()
		return test_sprites[key]

func _initialize() -> void:
	var game := TestController.new()
	var renderer := TestRenderer.new()
	renderer.controller = game
	game.coordinate_renderers.append(renderer)
	var failures: Array[String] = []
	for depth in [2.5, 1.0, 0.8, 0.5, 0.35]:
		var used := {}
		game._render_world_barrel("test_barrel", Vector2(0.0, depth), used)
		var barrel: Sprite2D = game.test_sprites.get("test_barrel")
		var shadow: Sprite2D = game.test_sprites.get("test_barrel_shadow")
		if barrel == null or shadow == null:
			failures.append("Missing barrel or shadow at depth %s" % depth)
			continue
		var material := shadow.material as ShaderMaterial
		if shadow.texture != barrel.texture:
			failures.append("Shadow did not reuse the directional barrel texture at depth %s" % depth)
		if not shadow.centered or shadow.scale != barrel.scale or shadow.position != barrel.position + Vector2.DOWN:
			failures.append("Shadow is not an identical copy shifted down one pixel at depth %s" % depth)
		if shadow.z_index >= barrel.z_index or material == null or material.shader != game.BARREL_CONTACT_SHADOW_SHADER:
			failures.append("Shadow layering or mask shader is incorrect at depth %s" % depth)
		if barrel.z_index != 0 or shadow.z_index != -1:
			failures.append("Barrel no longer uses the shared actor layer at depth %s" % depth)
		var barrel_material := barrel.material as ShaderMaterial
		if material == null or barrel_material == null or material.get_shader_parameter("sprite_scale") != barrel_material.get_shader_parameter("sprite_scale") or material.get_shader_parameter("grid_origin") != barrel_material.get_shader_parameter("grid_origin"):
			failures.append("Shadow sampling differs from barrel sampling at depth %s" % depth)
		print("depth=%.2f barrel_scale=%.3f" % [depth, barrel.scale.x])
	# A center ray is deliberately irrelevant. One of the two true visual-circle
	# tangents can be exposed at a wall end, and the generic footprint rule must
	# retain the barrel in that case; with both tangent edges blocked it vanishes.
	var occlusion_probe := Vector2(4.0, 4.0)
	var probe_radius := game.barrel_visual_radius
	var probe_distance := occlusion_probe.length()
	var probe_direction := occlusion_probe / probe_distance
	var probe_perpendicular := Vector2(-probe_direction.y, probe_direction.x)
	var probe_base := probe_direction * (probe_radius * probe_radius / probe_distance)
	var probe_offset := probe_perpendicular * (probe_radius * sqrt(probe_distance * probe_distance - probe_radius * probe_radius) / probe_distance)
	game.force_barrel_line_samples = true
	game.clear_barrel_samples = [probe_base + probe_offset]
	if not game._world_barrel_has_visible_camera_span(occlusion_probe):
		failures.append("Barrel tangent edge was hidden despite a visible rim")
	game.clear_barrel_samples.clear()
	if game._world_barrel_has_visible_camera_span(occlusion_probe):
		failures.append("Fully wall-occluded barrel remained visible")
	game.force_barrel_line_samples = false
	for sprite in game.test_sprites.values():
		sprite.free()
	renderer.free()
	game.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Barrel shadow test passed")
	quit(0)
