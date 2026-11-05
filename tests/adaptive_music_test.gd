extends SceneTree

func _initialize() -> void:
	call_deferred("_test")

func _test() -> void:
	var music: AudioStreamPlayer = root.get_node("GrudgeMusic")
	assert(music.stream is AudioStreamMP3 and music.stream.loop)
	var music_bus := AudioServer.get_bus_index("Music")
	assert(music.bus == "Music" and music_bus >= 0)
	assert(AudioServer.get_bus_effect_count(music_bus) == 1)
	assert(AudioServer.get_bus_effect(music_bus, 0) is AudioEffectCompressor)
	music.call("_setup_music_bus")
	assert(AudioServer.get_bus_effect_count(music_bus) == 1)
	music.stop()
	music.call("set_music_mode", "menu")
	assert(music.playing)
	music.seek(12.0)
	music.call("set_music_mode", "combat")
	assert(music.get_playback_position() >= 11.9)
	music.call("set_music_mode", "win", true)
	assert(music.get_playback_position() >= 11.9)
	music.stop()
	music.call("set_music_mode", "menu")
	assert(music.playing and music.get_playback_position() < 1.0)
	print("Full fast music track loops without mode changes interrupting playback")
	quit()
