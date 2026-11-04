extends SceneTree

class TestController extends "res://scripts/xybots_character_controller.gd":
	func _runtime_camera_origin_for_visibility() -> Vector2:
		return Vector2.ZERO

	func _world_actor_draw_layer(_position: Vector2) -> int:
		return 200

	func _world_point_has_clear_camera_line(target: Vector2) -> bool:
		var distance := target.length()
		for edge in _all_physical_wall_edges():
			var hit := _ray_segment_hit_distance_limited(Vector2.ZERO, target / distance, edge["a"], edge["b"], distance - 0.001)
			if hit >= 0.0:
				return false
		return true

func _initialize() -> void:
	var game := TestController.new()
	game.physical_wall_edges_cache_dirty = false
	var circle := {"shape": game.OcclusionFootprintShape.CIRCLE, "position": Vector2(0, 4), "radius": 0.4}
	var rectangle := {"shape": game.OcclusionFootprintShape.RECTANGLE, "position": Vector2(0, 4), "half_width": 0.4, "half_depth": 0.3}
	game.physical_wall_edges_cache = [{"a": Vector2(-1, 2), "b": Vector2(0, 2)}, {"a": Vector2(0, 2), "b": Vector2(1, 2)}]
	assert(not game._world_footprint_has_visible_camera_span(circle), "joined walls must cover the circle")
	assert(not game._world_footprint_has_visible_camera_span(rectangle), "joined walls must cover the rectangle")
	game.physical_wall_edges_cache = [{"a": Vector2(-1, 2), "b": Vector2(0, 2)}]
	assert(game._world_footprint_has_visible_camera_span(circle), "partly exposed circle must remain visible")
	assert(game._world_footprint_has_visible_camera_span(rectangle), "partly exposed rectangle must remain visible")
	var renderer: Node = load("res://scripts/coordinate_frame_runtime_renderer.gd").new()
	game.coordinate_renderers.append(renderer)
	renderer.last_wall_entries.append({"world_a": Vector2(-1, 2), "world_b": Vector2(0, 2), "wall_draw_layer": 100})
	assert(game._world_footprint_draw_layer(circle) == 99, "wall in circle cone must paint later")
	assert(game._world_footprint_draw_layer(rectangle) == 99, "wall in rectangle cone must paint later")
	renderer.last_wall_entries.append({"world_a": Vector2(0, 2), "world_b": Vector2(1, 2), "wall_draw_layer": 80})
	assert(game._world_footprint_draw_layer(circle) == 79, "both joined walls must paint after the object")
	renderer.last_wall_entries.clear()
	renderer.last_wall_entries.append({"world_a": Vector2(1, 2), "world_b": Vector2(2, 2), "wall_draw_layer": 100})
	assert(game._world_footprint_draw_layer(circle) == game._world_footprint_near_draw_layer(circle), "wall outside cone must not change object layer")
	renderer.free()
	game._build_empty_grid_audit_wall_edges()
	game._set_wall_between(Vector2i(1, 1), Vector2i.RIGHT, true)
	game.player_states.clear()
	game.player_states.append({"grid_position": Vector2i(1, 1), "world_position": Vector2(1.95, 1.5)})
	game.player_states.append({"grid_position": Vector2i(2, 1), "world_position": Vector2(2.05, 1.5)})
	assert(not game._projectile_owner_has_clear_path_to_player(0, 1, false), "wall must block overlapping hit radii")
	game._set_wall_between(Vector2i(1, 1), Vector2i.RIGHT, false)
	game.physical_wall_edges_cache_dirty = true
	assert(game._projectile_owner_has_clear_path_to_player(0, 1, false), "open close-range path must remain clear")
	game.free()
	print("Footprint wall visibility passed")
	quit(0)
