extends SceneTree


const LOD_SIZES := [32, 28, 24, 21, 18, 15, 12, 9, 6, 4]
const LOD_01_DIRECTORY := "res://assets/Props/Barrel_LOD_01/Render_2026-10-23_09-02-59"
const GENERATED_DIRECTORY_TEMPLATE := "res://assets/Props/Barrel_LOD_%02d/Generated_Godot_Static_10_LOD"


func _initialize() -> void:
	var failures: Array[String] = []
	for lod_index in range(2, LOD_SIZES.size()):
		var destination_directory := GENERATED_DIRECTORY_TEMPLATE % lod_index
		var make_directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination_directory))
		if make_directory_error != OK:
			failures.append("Could not create %s (error %d)" % [destination_directory, make_directory_error])
			continue
		for frame_index in range(16):
			var source_path := "%s/barrel_LOD_01_%03d.png" % [LOD_01_DIRECTORY, frame_index]
			var source_texture := load(source_path) as Texture2D
			var source_image := source_texture.get_image() if source_texture != null else null
			if source_image == null or source_image.is_empty():
				failures.append("Could not load %s" % source_path)
				continue
			var output_image := source_image.duplicate()
			output_image.resize(LOD_SIZES[lod_index], LOD_SIZES[lod_index], Image.INTERPOLATE_NEAREST)
			var output_path := "%s/barrel_LOD_%02d_%03d.png" % [destination_directory, lod_index, frame_index]
			var save_error: int = output_image.save_png(output_path)
			if save_error != OK:
				failures.append("Could not write %s (error %d)" % [output_path, save_error])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Generated static barrel LOD 02 through LOD 09 from the authored LOD 01 frames.")
	quit(0)
