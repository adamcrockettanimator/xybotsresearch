@tool
extends EditorPlugin

const MuzzleAnchorDock := preload("res://addons/muzzle_anchor_editor/muzzle_anchor_dock.gd")

var dock: Control


func _enter_tree() -> void:
	dock = MuzzleAnchorDock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
