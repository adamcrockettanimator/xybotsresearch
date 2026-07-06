extends SceneTree


func _initialize() -> void:
	var source_dir := "res://assets/frames/session_2026-07-05_214147"
	var output_path := "res://assets/frames/session_2026-07-05_214147/capture_frames.tres"

	var dir := DirAccess.open(source_dir)
	if dir == null:
		push_error("Unable to open frame directory: %s" % source_dir)
		quit(1)
		return

	var file_names: PackedStringArray = []
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if file_name.to_lower().ends_with(".png"):
			file_names.append(file_name)
	dir.list_dir_end()

	file_names.sort()

	var frames := SpriteFrames.new()
	frames.add_animation("capture")
	frames.set_animation_loop("capture", true)
	frames.set_animation_speed("capture", 24.0)

	for file_name in file_names:
		var texture := load(source_dir.path_join(file_name))
		if texture is Texture2D:
			frames.add_frame("capture", texture)

	var result := ResourceSaver.save(frames, output_path)
	if result != OK:
		push_error("Failed to save SpriteFrames resource: %s (%s)" % [output_path, result])
		quit(1)
		return

	print("Saved SpriteFrames resource: %s with %d frames" % [output_path, frames.get_frame_count("capture")])
	quit(0)
