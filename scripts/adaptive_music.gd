extends AudioStreamPlayer

const TRACK := "res://assets/Audio/Music/Faster_Version-2024-02-19_-_Swamp_Showdown_-_www.FesliyanStudios.com.mp3"

# Keep the requested state available to callers, without interrupting the track.
var current_mode := ""

func _ready() -> void:
	_setup_music_bus()
	stream = load(TRACK)
	if stream == null:
		push_error("Music track is missing: " + TRACK)
		return
	if stream is AudioStreamMP3:
		stream = stream.duplicate()
		stream.loop = true

func set_music_mode(mode: String, _restart := false) -> void:
	current_mode = "menu" if mode == "explore" else mode
	if stream != null and not playing:
		play()

# Compress only the music so loud sections do not overwhelm the rest of the mix.
func _setup_music_bus() -> void:
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus < 0:
		AudioServer.add_bus()
		music_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(music_bus, "Music")
		AudioServer.set_bus_send(music_bus, "Master")
		if not OS.has_feature("web"):
			var compressor := AudioEffectCompressor.new()
			compressor.threshold = -24.0
			compressor.ratio = 4.0
			compressor.attack_us = 1000.0
			compressor.release_ms = 350.0
			AudioServer.add_bus_effect(music_bus, compressor)
	if OS.has_feature("web"):
		AudioServer.set_bus_volume_db(music_bus, -10.0)
	bus = "Music"
