extends SceneTree

class TestController extends "res://scripts/xybots_character_controller.gd":
	var test_forward := Vector2.DOWN
	func _runtime_camera_origin_for_visibility() -> Vector2:
		return Vector2(0.5, -1.0)
	func _view_forward_vector() -> Vector2:
		return test_forward

func _initialize() -> void:
	var game := TestController.new()
	var table := {"shape": game.OcclusionFootprintShape.RECTANGLE, "position": Vector2(0.5, 0.5), "half_width": 0.165, "half_depth": 0.125}
	var coin := {"shape": game.OcclusionFootprintShape.CIRCLE, "position": Vector2(0.5, 0.5), "radius": 0.045}
	assert(game._world_footprint_draw_layer(table) > game._world_footprint_draw_layer(coin), "larger footprint must paint over a centered pickup")
	game.test_forward = Vector2.RIGHT
	assert(game._world_footprint_draw_layer(table) > game._world_footprint_draw_layer(coin), "rectangle width must contribute from the side")
	game.test_forward = Vector2(1, 1).normalized()
	assert(game._world_footprint_draw_layer(table) > game._world_footprint_draw_layer(coin), "both rectangle axes must contribute diagonally")
	var behind := coin.duplicate()
	behind["position"] = Vector2(0.5, 0.8)
	game.test_forward = Vector2.DOWN
	assert(game._world_footprint_draw_layer(table) > game._world_footprint_draw_layer(behind), "nearer table must paint over a farther pickup")
	game.free()
	print("Footprint depth ordering passed")
	quit(0)
