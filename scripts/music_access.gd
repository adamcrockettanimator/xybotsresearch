extends RefCounted

# An editor that was already open when the autoload was added may not have
# reloaded project settings yet. Resolve it at runtime and create it if absent.
static func get_player(tree: SceneTree) -> AudioStreamPlayer:
	var existing := tree.root.get_node_or_null("GrudgeMusic") as AudioStreamPlayer
	if existing != null:
		return existing
	var script := load("res://scripts/adaptive_music.gd") as Script
	if script == null:
		return null
	var player := script.new() as AudioStreamPlayer
	player.name = "GrudgeMusic"
	tree.root.add_child(player)
	return player
