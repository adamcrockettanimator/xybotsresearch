@tool
extends Node3D

## The actual 3D "mini studio" used by SemanticMeshInstance2DBarrel.
## Keep it as a scene so its camera, lights, models, and shared material can
## be authored directly in Godot's 3D editor.  At runtime the parent script
## places this scene inside a transparent SubViewport.

@export var toon_material: Material:
	set(value):
		toon_material = value
		_apply_toon_material()

@export_enum("LOD 00 — near", "LOD 01 — far") var editor_preview_lod := 0:
	set(value):
		editor_preview_lod = value
		_set_editor_preview_lod()


func _ready() -> void:
	call_deferred("_apply_toon_material")
	call_deferred("_set_editor_preview_lod")


func _apply_toon_material() -> void:
	if toon_material == null:
		return
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = toon_material


func _set_editor_preview_lod() -> void:
	# The runtime parent switches these nodes from live game depth. In the 3D
	# editor, show exactly one authored LOD so their similar shells never stack.
	if not Engine.is_editor_hint():
		return
	var lod_00 := get_node_or_null("Barrel_LOD_00_3D") as Node3D
	var lod_01 := get_node_or_null("Barrel_LOD_01_3D") as Node3D
	_set_lod_preview_visible(lod_00, editor_preview_lod == 0)
	_set_lod_preview_visible(lod_01, editor_preview_lod == 1)


func _set_lod_preview_visible(lod_root: Node3D, should_show: bool) -> void:
	if lod_root == null:
		return
	# The FBX scene owns its MeshInstance3D with an independent imported state.
	# Toggle the instance root *and* the actual mesh descendants so the inactive
	# LOD cannot remain visible as a second, offset barrel in the editor.
	lod_root.visible = should_show
	for child in lod_root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := child as GeometryInstance3D
		if geometry != null:
			geometry.visible = should_show
