extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var old_music := root.get_node("GrudgeMusic")
	root.remove_child(old_music)
	var scene: Node = load("res://grudge_title_menu.tscn").instantiate()
	root.add_child(scene)
	var fallback := root.get_node_or_null("GrudgeMusic")
	assert(fallback != null and fallback.playing and fallback.current_mode == "menu")
	assert(load("res://scripts/music_access.gd").get_player(self) == fallback)
	print("Music fallback loads title without an autoload global")
	scene.queue_free()
	fallback.queue_free()
	old_music.queue_free()
	quit()
