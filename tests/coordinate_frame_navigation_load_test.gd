extends SceneTree


# Keep the F5 coordinate-frame entry point parser-checked independently of the
# normal-match tests, which instantiate main.tscn directly.
func _initialize() -> void:
	var navigation_scene := load("res://coordinate_frame_navigation.tscn") as PackedScene
	assert(navigation_scene != null)
	print("Coordinate-frame navigation scene loads")
	quit()
