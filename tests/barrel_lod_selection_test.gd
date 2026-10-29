extends SceneTree


class TestController extends "res://scripts/xybots_character_controller.gd":
	func _view_forward_vector() -> Vector2:
		return Vector2.DOWN


func _initialize() -> void:
	var game := TestController.new()
	var failures: Array[String] = []
	var lod_00_texture := game._barrel_texture_for_current_camera(game.BARREL_LOD_01_MIN_VIEW_DEPTH)
	var lod_01_texture := game._barrel_texture_for_current_camera(game.BARREL_LOD_01_MIN_VIEW_DEPTH + 0.001)
	if game._barrel_art_height_for_view_depth(game.BARREL_LOD_01_MIN_VIEW_DEPTH) != game.BARREL_ART_HEIGHT:
		failures.append("LOD 00 did not remain active at the LOD 01 threshold")
	if game._barrel_art_height_for_view_depth(game.BARREL_LOD_01_MIN_VIEW_DEPTH + 0.001) != game.BARREL_LOD_01_ART_HEIGHT:
		failures.append("LOD 01 did not activate beyond its threshold")
	if lod_00_texture.get_width() != 32 or lod_00_texture.get_height() != 32:
		failures.append("LOD 00 texture is not the expected 32x32 source")
	if lod_01_texture.get_width() != 28 or lod_01_texture.get_height() != 28:
		failures.append("LOD 01 texture is not the expected 28x28 source")
	for lod_index in range(game.BARREL_LOD_ART_HEIGHTS.size()):
		var entered_depth := float(game.BARREL_LOD_MIN_VIEW_DEPTHS[lod_index]) + 0.001
		var texture := game._barrel_texture_for_current_camera(entered_depth)
		var expected_size := int(game.BARREL_LOD_ART_HEIGHTS[lod_index])
		if game._barrel_lod_index_for_view_depth(entered_depth) != lod_index:
			failures.append("LOD %02d was not selected at depth %.3f" % [lod_index, entered_depth])
		if texture.get_width() != expected_size or texture.get_height() != expected_size:
			failures.append("LOD %02d texture is not the expected %dx%d source" % [lod_index, expected_size, expected_size])
	game.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Barrel LOD selection test passed")
	quit(0)
