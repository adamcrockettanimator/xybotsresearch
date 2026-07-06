extends SceneTree


func _initialize() -> void:
	var config_path := "res://assets/frames/renamed_trimmed_sequence/animation_sets.cfg"
	var config := ConfigFile.new()
	var err := config.load(config_path)
	if err != OK:
		push_error("Unable to load animation config: %s (%s)" % [config_path, err])
		quit(1)
		return

	var source_folder := str(config.get_value("meta", "source_folder", "res://assets/frames/renamed_trimmed_sequence"))
	var output_path := str(config.get_value("meta", "output_path", "res://assets/frames/renamed_trimmed_sequence/walk_sets.tres"))
	var default_fps := float(config.get_value("meta", "default_fps", 12.0))

	var source_files := _collect_pngs(source_folder)
	if source_files.is_empty():
		push_error("No PNG files found in: %s" % source_folder)
		quit(1)
		return

	var source_textures: Array[Texture2D] = []
	source_textures.resize(source_files.size())
	for i in source_files.size():
		var image_path := ProjectSettings.globalize_path(source_folder.path_join(source_files[i]))
		var image := Image.load_from_file(image_path)
		if image == null or image.is_empty():
			continue
		source_textures[i] = ImageTexture.create_from_image(image)

	var frames := SpriteFrames.new()
	for section in config.get_sections():
		if section == "meta":
			continue
		var frame_spec := str(config.get_value(section, "frames", "")).strip_edges()
		if frame_spec.is_empty():
			continue
		var loop := bool(config.get_value(section, "loop", true))
		var fps := float(config.get_value(section, "fps", default_fps))
		frames.add_animation(section)
		frames.set_animation_loop(section, loop)
		frames.set_animation_speed(section, fps)
		for index in _parse_frame_spec(frame_spec, source_textures.size()):
			var texture := source_textures[index]
			if texture != null:
				frames.add_frame(section, texture)

	var result := ResourceSaver.save(frames, output_path)
	if result != OK:
		push_error("Failed to save SpriteFrames resource: %s (%s)" % [output_path, result])
		quit(1)
		return

	print("Saved SpriteFrames resource: %s" % output_path)
	for animation in frames.get_animation_names():
		print("%s: %d frames" % [animation, frames.get_frame_count(animation)])
	quit(0)


func _collect_pngs(folder: String) -> PackedStringArray:
	var dir := DirAccess.open(folder)
	if dir == null:
		return PackedStringArray()
	var files: PackedStringArray = []
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if file_name.to_lower().ends_with(".png"):
			files.append(file_name)
	dir.list_dir_end()
	files.sort()
	return files


func _parse_frame_spec(spec: String, frame_count: int) -> PackedInt32Array:
	var indices: PackedInt32Array = []
	var seen := {}
	for token in spec.split(",", false):
		var part := token.strip_edges()
		if part.is_empty():
			continue
		if part.contains("-"):
			var bounds := part.split("-", false)
			if bounds.size() != 2:
				continue
			var start := int(bounds[0])
			var finish := int(bounds[1])
			var step := 1 if finish >= start else -1
			var i := start
			while true:
				if i >= 0 and i < frame_count and not seen.has(i):
					indices.append(i)
					seen[i] = true
				if i == finish:
					break
				i += step
		else:
			var index := int(part)
			if index >= 0 and index < frame_count and not seen.has(index):
				indices.append(index)
				seen[index] = true
	return indices
