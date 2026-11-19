extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var config := ConfigFile.new()
	assert(config.load("res://export_presets.cfg") == OK)
	var files: PackedStringArray = config.get_value("preset.0", "export_files")
	var barks := {}
	for path in files:
		if path.begins_with("res://assets/Audio/Dialog/Barks/"):
			assert(path.ends_with(".ogg"))
			var stream := load(path) as AudioStreamOggVorbis
			assert(stream != null and stream.get_length() > 0.0)
			barks[path] = true
	var bank: JSON = load("res://assets/Audio/Dialog/bark_bank.json")
	for voice in bank.data.values():
		for lines in voice.values():
			for line in lines:
				assert(barks.has(line["path"]))
	assert(barks.size() == 1294)
	print("Verified ", barks.size(), " exported dialogue streams and every bank reference")
	quit()
