extends SceneTree

class TestRenderer extends "res://scripts/coordinate_frame_runtime_renderer.gd":
	func _runtime_camera_origin(_forward: Vector2, _right: Vector2) -> Vector2:
		return Vector2.ZERO
	func _overscan_projection_offset() -> Vector2:
		return Vector2.ZERO

class TestController extends "res://scripts/xybots_character_controller.gd":
	var test_sprites: Dictionary = {}
	var test_layer: Node2D
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
			var sprite := Sprite2D.new()
			test_layer.add_child(sprite)
			test_sprites[key] = sprite
		return test_sprites[key]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var layer := Node2D.new()
	layer.scale = Vector2.ONE * 6.0
	viewport.add_child(layer)
	var game := TestController.new()
	game.test_layer = layer
	var renderer := TestRenderer.new()
	renderer.controller = game
	game.coordinate_renderers.append(renderer)
	var failures: Array[String] = []
	for depth in [0.8, 1.15, 1.29, 1.3, 1.31, 1.6, 2.1, 2.8]:
		var used := {}
		game._render_world_barrel("barrel", Vector2(0.0, depth), used)
		var sprite: Sprite2D = game.test_sprites["barrel"]
		var shadow: Sprite2D = game.test_sprites["barrel_shadow"]
		shadow.visible = false
		var material := sprite.material as ShaderMaterial
		var shadow_material := shadow.material as ShaderMaterial
		if material.get_shader_parameter("sprite_scale") != shadow_material.get_shader_parameter("sprite_scale") or material.get_shader_parameter("grid_origin") != shadow_material.get_shader_parameter("grid_origin"):
			failures.append("Shadow sampling does not match at depth %s" % depth)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		# Ignore the outer silhouette, which can end part-way through a pixel;
		# every fully interior logical cell must have one consistent sample.
		var size := Vector2(sprite.texture.get_size()) * sprite.scale
		var top_left := sprite.position - size * 0.5
		var tested := 0
		var mixed := 0
		for y in range(ceili(top_left.y) + 1, floori(top_left.y + size.y) - 1):
			for x in range(ceili(top_left.x) + 1, floori(top_left.x + size.x) - 1):
				if x < 0 or y < 0 or x >= 160 or y >= 120:
					continue
				var first := image.get_pixel(x * 6, y * 6)
				var matches := true
				for py in range(6):
					for px in range(6):
						if image.get_pixel(x * 6 + px, y * 6 + py) != first:
							matches = false
				tested += 1
				if not matches:
					mixed += 1
		print("depth=%.2f scale=%.3f interior cells=%d mixed=%d" % [depth, sprite.scale.x, tested, mixed])
		if tested == 0 or mixed > 0:
			failures.append("Logical cells contain subpixel detail at depth %s" % depth)
	viewport.queue_free()
	renderer.free()
	game.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
	else:
		print("Barrel playfield-pixel grid render test passed")
		quit(0)
