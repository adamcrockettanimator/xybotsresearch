extends Node

const STOOL_GRADIENT := preload("res://tests/calibration/town_direct_stool_gradient.gdshader")
const BARREL := "res://scripts/semantic_gpu_cage_barrel.gd"
const CRATE := "res://scripts/semantic_gpu_lattice_crate.gd"
const STOOL := "res://scripts/semantic_stool.gd"

var game: Node
var active := false
var converted: Dictionary = {}


func _ready() -> void:
	# Run after the game updates prop materials and crate overlay ordering.
	process_priority = 1000


func set_direct_enabled(enabled: bool) -> void:
	if active == enabled:
		return
	active = enabled
	if active:
		_scan_props()
	else:
		_restore_all()


func _process(_delta: float) -> void:
	if not active or not is_instance_valid(game):
		return
	_scan_props()
	for id in converted.keys():
		# A runtime mode switch can restore the collection during a frame.
		if not active or not converted.has(id):
			continue
		var info: Dictionary = converted[id]
		var prop: Node = info["prop"]
		if not is_instance_valid(prop):
			var orphan: SubViewport = info["viewport"]
			if is_instance_valid(orphan):
				orphan.queue_free()
			converted.erase(id)
			continue
		_update_layers(info)
		if info["kind"] == STOOL:
			var original: ShaderMaterial = prop.display.material
			var direct: ShaderMaterial = info["gradient"]
			# The old display shader replaces COLOR with its viewport texture,
			# so the outer stool modulate never reaches its paint. Cancel that
			# outer tint for the direct raster to preserve the same appearance.
			var tint: Color = prop.modulate
			var correction := Color(1.0 / maxf(tint.r, 0.001), 1.0 / maxf(tint.g, 0.001), 1.0 / maxf(tint.b, 0.001), 1.0 / maxf(tint.a, 0.001))
			if info["root"].modulate != correction:
				info["root"].modulate = correction
			for key in ["floor_logical_y", "top_logical_y", "floor_darkening_strength"]:
				var value: Variant = original.get_shader_parameter(key)
				if direct.get_shader_parameter(key) != value:
					direct.set_shader_parameter(key, value)


func _scan_props() -> void:
	for prop in game.semantic_lod_floor_outline_nodes.values():
		if not is_instance_valid(prop) or converted.has(prop.get_instance_id()):
			continue
		var script: Script = prop.get_script()
		if script == null or script.resource_path not in [BARREL, CRATE, STOOL]:
			continue
		_convert_prop(prop, script.resource_path)


func _convert_prop(prop: Node2D, kind: String) -> void:
	var viewport: SubViewport = prop.get("viewport")
	var root: Node2D = prop.get("logical_root" if kind == BARREL else "root" if kind == CRATE else "raster_root")
	var display: Sprite2D = prop.get("display")
	if not is_instance_valid(viewport) or not is_instance_valid(root) or not is_instance_valid(display):
		return
	var original_layers := {}
	var original_order := {}
	for child in root.get_children():
		if child is CanvasItem:
			original_layers[child.get_instance_id()] = child.z_index
		original_order[child.get_instance_id()] = child.get_index()
	root.reparent(prop, false)
	display.visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	prop.remove_child(viewport)
	var info := {"prop": prop, "kind": kind, "viewport": viewport, "root": root, "display": display, "layers": original_layers, "order": original_order, "root_modulate": root.modulate}
	if kind == STOOL:
		var gradient := ShaderMaterial.new()
		gradient.shader = STOOL_GRADIENT
		prop.raster_layer.material = gradient
		info["gradient"] = gradient
	converted[prop.get_instance_id()] = info
	_update_layers(info)


func _update_layers(info: Dictionary) -> void:
	var root: Node2D = info["root"]
	var layers: Dictionary = info["layers"]
	var children := root.get_children()
	var needs_sort := not root.has_meta("shared_layers_sorted")
	for child in children:
		if not child is CanvasItem:
			continue
		var id := child.get_instance_id()
		if not layers.has(id):
			layers[id] = child.z_index
			needs_sort = true
		elif child.z_index != 0:
			# Crates update their overlay z-index according to the raster mode.
			if info["kind"] == CRATE and child == info["prop"].logical_raster_overlay and layers[id] != child.z_index:
				layers[id] = child.z_index
				needs_sort = true
		if child.z_index != 0:
			child.z_index = 0
	if needs_sort:
		var order: Dictionary = info["order"]
		children.sort_custom(func(a: Node, b: Node) -> bool:
			var left := int(layers.get(a.get_instance_id(), 0))
			var right := int(layers.get(b.get_instance_id(), 0))
			return left < right if left != right else int(order.get(a.get_instance_id(), 0)) < int(order.get(b.get_instance_id(), 0))
		)
		for index in range(children.size()):
			root.move_child(children[index], index)
		root.set_meta("shared_layers_sorted", true)


func _restore_all() -> void:
	for info: Dictionary in converted.values():
		var prop: Node = info["prop"]
		var viewport: SubViewport = info["viewport"]
		if not is_instance_valid(prop):
			if is_instance_valid(viewport):
				viewport.queue_free()
			continue
		var root: Node2D = info["root"]
		for child in root.get_children():
			if child is CanvasItem:
				child.z_index = int(info["layers"].get(child.get_instance_id(), 0))
		var ordered := root.get_children()
		var original_order: Dictionary = info["order"]
		ordered.sort_custom(func(a: Node, b: Node) -> bool: return int(original_order.get(a.get_instance_id(), 0)) < int(original_order.get(b.get_instance_id(), 0)))
		for index in range(ordered.size()):
			root.move_child(ordered[index], index)
		root.remove_meta("shared_layers_sorted")
		if info["kind"] == STOOL:
			prop.raster_layer.material = null
			root.modulate = info["root_modulate"]
		prop.add_child(viewport)
		root.reparent(viewport, false)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		info["display"].visible = true
	converted.clear()


func _exit_tree() -> void:
	_restore_all()
