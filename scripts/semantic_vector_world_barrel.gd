## World-anchored vector-barrel prototype.
##
## The controller supplies already-projected points from a real barrel centre,
## radius and height.  This node only owns vector presentation: no ray-march,
## no baked sprite, and no per-pixel colour bands.
extends Node2D


const LOGICAL_VIEW_SIZE := Vector2i(160, 120)
const STYLE_PATH := "res://resources/vector_barrel_style.tres"
const STYLE_SCRIPT := preload("res://scripts/vector_barrel_style.gd")

@export_category("Vector Barrel - Outside wood")
@export var wood_edge := Color8(41, 18, 5)
@export var wood_centre := Color8(173, 79, 19)
@export_range(0.25, 1.75, 0.05) var wood_bottom_light := 0.76
@export_range(0.25, 1.75, 0.05) var wood_top_light := 1.14

@export_category("Vector Barrel - Interior and lid")
@export var barrel_interior_colour := Color8(46, 19, 5)
@export var lid_colour := Color8(156, 69, 15)

@export_category("Vector Barrel - Gradient treatment")
@export_enum("Linear", "Radial") var body_gradient_mode := 0
@export_enum("Linear", "Radial") var lid_gradient_mode := 0
@export_range(0, 8, 1) var gradient_steps := 0
@export_range(0.0, 1.0, 0.05) var gradient_dither := 0.0

@export_category("Vector Barrel - Rim and hoops")
@export var rim_colour := Color8(212, 142, 67)
@export_range(0.5, 8.0, 0.5) var rim_width := 2.0
@export var hoop_edge := Color8(35, 37, 34)
@export var hoop_centre := Color8(201, 207, 194)
@export var hoop_shadow_colour := Color(0.03, 0.025, 0.02, 0.56)
@export var hoop_highlight_colour := Color(1.0, 1.0, 1.0, 0.48)
@export_range(0.5, 8.0, 0.5) var hoop_width := 3.0

@export_category("Vector Barrel - Staves")
@export var side_stave_colour := Color(0.13, 0.055, 0.012, 0.64)
@export var side_stave_highlight_colour := Color(1.0, 0.72, 0.36, 0.30)
@export var lid_stave_colour := Color(0.08, 0.035, 0.01, 0.72)
@export var lid_stave_highlight_colour := Color(1.0, 0.74, 0.36, 0.38)
@export_range(0.5, 6.0, 0.5) var stave_width := 1.0

@export_category("Vector Barrel - Shadow")
@export var floor_shadow_colour := Color(0.10, 0.06, 0.025, 0.34)

@export_category("Vector Barrel - Debug")
## Draw the CPU's projected construction geometry above the finished barrel.
## This is diagnostic-only and is off by default.
@export var show_vector_skeleton := false
@export_range(2.0, 8.0, 1.0) var skeleton_cross_display_pixels := 4.0

var vector_viewport: SubViewport
var vector_root: Node2D
var vector_display: Sprite2D
var vector_skeleton_overlay: FullResolutionSkeletonOverlay
var barrels: Dictionary = {}
var barrel_style: Resource
var _last_saved_style_values: Dictionary = {}


func _ready() -> void:
	_load_or_create_style()
	vector_viewport = SubViewport.new()
	vector_viewport.name = "SemanticVectorWorldBarrelViewport"
	vector_viewport.size = LOGICAL_VIEW_SIZE
	vector_viewport.transparent_bg = true
	vector_viewport.disable_3d = true
	vector_viewport.gui_disable_input = true
	vector_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(vector_viewport)
	vector_root = Node2D.new()
	vector_root.name = "SemanticVectorWorldBarrelRoot"
	vector_viewport.add_child(vector_root)
	vector_display = Sprite2D.new()
	vector_display.name = "SemanticVectorWorldBarrelPixels"
	vector_display.centered = false
	vector_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vector_display.texture = vector_viewport.get_texture()
	add_child(vector_display)
	vector_skeleton_overlay = FullResolutionSkeletonOverlay.new()
	vector_skeleton_overlay.name = "VectorBarrelSkeletonOverlay"
	vector_skeleton_overlay.z_index = 100
	add_child(vector_skeleton_overlay)


## Remote Inspector values are the friendly art controls.  This light check
## copies a changed value into a real .tres resource once, rather than writing
## a file every frame.  It also means a live tweak survives stopping the game.
func _process(_delta: float) -> void:
	# Script hot-reload does not call _ready on an already-running prototype.
	# Initialize here too, so an artist can keep a current Remote Inspector
	# session and have its next tweak become the first saved style resource.
	if barrel_style == null:
		_load_or_create_style()
	var current_values := _style_values_from_inspector()
	if current_values == _last_saved_style_values:
		return
	_copy_values_to_style(current_values)
	_save_style()
	_last_saved_style_values = current_values


func _load_or_create_style() -> void:
	if ResourceLoader.exists(STYLE_PATH):
		barrel_style = load(STYLE_PATH)
		_migrate_style(barrel_style)
		_apply_style_values(barrel_style)
	else:
		barrel_style = STYLE_SCRIPT.new()
		_copy_values_to_style(_style_values_from_inspector())
		_save_style()
	_last_saved_style_values = _style_values_from_inspector()


func _style_values_from_inspector() -> Dictionary:
	return {
		"wood_edge": wood_edge, "wood_centre": wood_centre,
		"wood_bottom_light": wood_bottom_light, "wood_top_light": wood_top_light,
		"barrel_interior_colour": barrel_interior_colour, "lid_colour": lid_colour,
		"body_gradient_mode": body_gradient_mode, "lid_gradient_mode": lid_gradient_mode,
		"gradient_steps": gradient_steps, "gradient_dither": gradient_dither,
		"rim_colour": rim_colour, "rim_width": rim_width,
		"hoop_edge": hoop_edge, "hoop_centre": hoop_centre,
		"hoop_shadow_colour": hoop_shadow_colour, "hoop_highlight_colour": hoop_highlight_colour, "hoop_width": hoop_width,
		"side_stave_colour": side_stave_colour, "side_stave_highlight_colour": side_stave_highlight_colour,
		"lid_stave_colour": lid_stave_colour, "lid_stave_highlight_colour": lid_stave_highlight_colour, "stave_width": stave_width,
		"floor_shadow_colour": floor_shadow_colour,
	}


func _migrate_style(style: Resource) -> void:
	if style == null or int(style.get("style_version")) >= 2:
		return
	style.set("barrel_interior_colour", style.get("lid_dark"))
	style.set("lid_colour", style.get("lid_light"))
	style.set("side_stave_colour", style.get("stave_colour"))
	style.set("style_version", 2)
	_save_style()


func _apply_style_values(style: Resource) -> void:
	if style == null:
		return
	for key in _style_values_from_inspector():
		set(key, style.get(key))


func _copy_values_to_style(values: Dictionary) -> void:
	if barrel_style == null:
		return
	for key in values:
		barrel_style.set(key, values[key])


func _save_style() -> void:
	var directory := ProjectSettings.globalize_path(STYLE_PATH.get_base_dir())
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var error := ResourceSaver.save(barrel_style, STYLE_PATH)
	if error != OK:
		push_error("Could not save vector barrel style (%s)." % error)


## Matches the projected-Canvas barrel handoff, but retains actual Polygon2D
## and Line2D vector objects for the prototype rather than drawing colour bands.
func set_projected_barrel(
	barrel_id: String,
	body_silhouette: PackedVector2Array,
	body_panels: Array,
	lid_ring: PackedVector2Array,
	lid_inset: PackedVector2Array,
	lower_hoop: PackedVector2Array,
	upper_hoop: PackedVector2Array,
	floor_shadow: PackedVector2Array,
	stave_segments: PackedVector2Array,
	_lid_seam_segments: PackedVector2Array,
	_camera_distance: float,
	draw_layer: int,
	_body_style: String,
) -> void:
	if body_silhouette.size() < 3 or lid_ring.size() < 3:
		visible = false
		return
	var barrel: VectorBarrel = barrels.get(barrel_id, null)
	if barrel == null or not is_instance_valid(barrel):
		barrel = VectorBarrel.new()
		barrel.name = "VectorBarrel_%s" % barrel_id
		vector_root.add_child(barrel)
		barrels[barrel_id] = barrel
	barrel.z_index = draw_layer
	barrel.set_style_resource(barrel_style, self)
	# Capture a Remote Inspector adjustment before procedural styling redraws it.
	barrel.capture_manual_child_edits()
	barrel.apply_style(self)
	barrel.update_geometry(body_silhouette, body_panels, lid_ring, lid_inset, lower_hoop, upper_hoop, floor_shadow, stave_segments, _lid_seam_segments)
	barrel.apply_saved_child_edits()
	# Keep diagnostic geometry out of the low-res texture.  The overlay maps the
	# exact same CPU points through the displayed texture's transform and draws
	# at full game-canvas resolution.
	barrel.set_skeleton_visible(false, 1.0, 1.0)
	_update_full_resolution_skeleton(barrel)
	visible = true


func _skeleton_local_pixel_width() -> float:
	# The vector viewport is enlarged for the pixel-art game view. Convert a
	# one-display-pixel diagnostic stroke back into the viewport's coordinates.
	if vector_display == null:
		return 1.0
	var transform := vector_display.get_global_transform()
	var display_scale := maxf(transform.x.length(), transform.y.length())
	return 1.0 / maxf(display_scale, 1.0)


func _update_full_resolution_skeleton(barrel: Node) -> void:
	if vector_skeleton_overlay == null:
		return
	vector_skeleton_overlay.visible = show_vector_skeleton
	if not show_vector_skeleton:
		return
	var canvas_transform := get_global_transform()
	var canvas_scale := maxf(canvas_transform.x.length(), canvas_transform.y.length())
	vector_skeleton_overlay.set_geometry(
		barrel.get_skeleton_shapes(),
		vector_display.transform,
		1.0 / maxf(canvas_scale, 1.0),
		skeleton_cross_display_pixels / maxf(canvas_scale, 1.0),
	)


class VectorBarrel extends Node2D:
	# These parents make the live Remote tree read as the barrel's paint order.
	# Their child nodes remain ordinary Polygon2D/Line2D pieces for close inspection.
	var floor_shadow_layer := Node2D.new()
	var interior_layer := Node2D.new()
	var lid_layer := Node2D.new()
	var lid_detail_layer := Node2D.new()
	var outside_wood_layer := Node2D.new()
	var outside_detail_layer := Node2D.new()
	var hoop_shadow_layer := Node2D.new()
	var hoop_metal_layer := Node2D.new()
	var hoop_highlight_layer := Node2D.new()
	var rim_layer := Node2D.new()
	var skeleton_layer := Node2D.new()
	var skeleton := SkeletonOverlay.new()
	var shadow := Polygon2D.new()
	var inside_body := Polygon2D.new()
	var lid := Polygon2D.new()
	var outside_panels: Array[Polygon2D] = []
	var lid_seam_shadows: Array[Line2D] = []
	var lid_seam_highlights: Array[Line2D] = []
	var rim := Line2D.new()
	var upper_hoop_shadow := Line2D.new()
	var lower_hoop_shadow := Line2D.new()
	var upper_hoop := Line2D.new()
	var lower_hoop := Line2D.new()
	var upper_hoop_highlight := Line2D.new()
	var lower_hoop_highlight := Line2D.new()
	var stave_lines: Array[Line2D] = []
	var stave_highlights: Array[Line2D] = []
	var inside_material := ShaderMaterial.new()
	var outside_material := ShaderMaterial.new()
	var lid_material := ShaderMaterial.new()
	var style_resource: Resource
	var style_owner: Node
	var _last_child_art_values: Dictionary = {}

	func _ready() -> void:
		_add_layer(floor_shadow_layer, "01 Floor shadow", 0)
		_add_layer(interior_layer, "02 Interior opening", 1)
		_add_layer(lid_layer, "03 Lid surface", 2)
		_add_layer(lid_detail_layer, "04 Lid stave details", 3)
		_add_layer(outside_wood_layer, "05 Outside wood", 4)
		_add_layer(outside_detail_layer, "06 Outside stave details", 5)
		_add_layer(hoop_shadow_layer, "07 Hoop shadows", 6)
		_add_layer(hoop_metal_layer, "08 Hoop metal", 7)
		_add_layer(hoop_highlight_layer, "09 Hoop highlights", 8)
		_add_layer(rim_layer, "10 Wood rim", 9)
		_add_layer(skeleton_layer, "Debug — CPU skeleton", 50)
		skeleton.name = "ProjectedPointsAndWireframes"
		skeleton_layer.add_child(skeleton)
		shadow.name = "FloorShadow"
		shadow.color = Color(0.10, 0.06, 0.025, 0.34)
		floor_shadow_layer.add_child(shadow)
		inside_body.name = "InteriorOpening"
		inside_body.material = inside_material
		interior_layer.add_child(inside_body)
		lid.name = "LidSurface"
		lid.material = lid_material
		lid_layer.add_child(lid)
		_configure_gradient_materials()
		_configure_hoop_shadow(upper_hoop_shadow, "UpperHoopShadow", hoop_shadow_layer)
		_configure_hoop_shadow(lower_hoop_shadow, "LowerHoopShadow", hoop_shadow_layer)
		_configure_hoop_highlight(upper_hoop_highlight, "UpperHoopHighlight", hoop_highlight_layer)
		_configure_hoop_highlight(lower_hoop_highlight, "LowerHoopHighlight", hoop_highlight_layer)
		_configure_line(rim, Color8(212, 142, 67), 2.0, true)
		rim.name = "WoodRim"
		rim_layer.add_child(rim)
		_configure_hoop(upper_hoop, "UpperHoop", hoop_metal_layer)
		_configure_hoop(lower_hoop, "LowerHoop", hoop_metal_layer)

	func _add_layer(layer: Node2D, layer_name: String, order: int) -> void:
		layer.name = layer_name
		layer.z_index = order
		add_child(layer)

	func set_style_resource(new_style_resource: Resource, new_style_owner: Node) -> void:
		style_resource = new_style_resource
		style_owner = new_style_owner

	func capture_manual_child_edits() -> void:
		if style_resource == null or _last_child_art_values.is_empty():
			return
		var changed := false
		var barrel_overrides: Dictionary = style_resource.get("child_visual_overrides").get(name, {}).duplicate(true)
		for node in _art_nodes():
			var current := _child_art_values(node)
			var previous: Dictionary = _last_child_art_values.get(str(node.get_path()), {})
			if current == previous:
				continue
			barrel_overrides[node.name] = current
			changed = true
		if not changed:
			return
		var all_overrides: Dictionary = style_resource.get("child_visual_overrides").duplicate(true)
		all_overrides[name] = barrel_overrides
		style_resource.set("child_visual_overrides", all_overrides)
		style_resource.emit_changed()
		if style_owner != null and style_owner.has_method("_save_style"):
			style_owner.call("_save_style")

	func apply_saved_child_edits() -> void:
		if style_resource == null:
			_remember_child_art_values()
			return
		var barrel_overrides: Dictionary = style_resource.get("child_visual_overrides").get(name, {})
		for node in _art_nodes():
			var values: Dictionary = barrel_overrides.get(node.name, {})
			if not values.is_empty():
				_apply_child_art_values(node, values)
		_remember_child_art_values()

	func _art_nodes() -> Array[Node2D]:
		var result: Array[Node2D] = []
		for layer in get_children():
			for node in layer.get_children():
				if node is Polygon2D or node is Line2D:
					result.append(node)
		return result

	func _child_art_values(node: Node2D) -> Dictionary:
		var values := {
			"visible": node.visible,
			"position": node.position,
			"rotation": node.rotation,
			"scale": node.scale,
		}
		if node is Polygon2D:
			values["colour"] = node.color
		elif node is Line2D:
			values["colour"] = node.default_color
			values["width"] = node.width
			if node.gradient != null:
				values["gradient_colours"] = node.gradient.colors
				values["gradient_offsets"] = node.gradient.offsets
		return values

	func _apply_child_art_values(node: Node2D, values: Dictionary) -> void:
		node.visible = values.get("visible", node.visible)
		node.position = values.get("position", node.position)
		node.rotation = values.get("rotation", node.rotation)
		node.scale = values.get("scale", node.scale)
		if node is Polygon2D:
			node.color = values.get("colour", node.color)
		elif node is Line2D:
			node.default_color = values.get("colour", node.default_color)
			node.width = values.get("width", node.width)
			if values.has("gradient_colours"):
				var gradient: Gradient = node.gradient if node.gradient != null else Gradient.new()
				gradient.colors = values["gradient_colours"]
				gradient.offsets = values.get("gradient_offsets", gradient.offsets)
				node.gradient = gradient

	func _remember_child_art_values() -> void:
		_last_child_art_values.clear()
		for node in _art_nodes():
			_last_child_art_values[str(node.get_path())] = _child_art_values(node)

	func _configure_gradient_materials() -> void:
		var body_shader := Shader.new()
		body_shader.code = """
shader_type canvas_item;
uniform float center_x = 80.0;
uniform float half_width = 20.0;
uniform float top_y = 30.0;
uniform float bottom_y = 90.0;
uniform vec4 edge_wood : source_color;
uniform vec4 centre_wood : source_color;
uniform float bottom_light = 0.76;
uniform float top_light = 1.14;
uniform int gradient_mode = 0;
uniform int gradient_steps = 0;
uniform float gradient_dither = 0.0;
varying vec2 vector_point;
void vertex() { vector_point = VERTEX; }
float bayer4(vec2 pixel) {
	vec2 p = mod(pixel, 4.0);
	float row = p.y;
	float column = p.x;
	if (row < 1.0) return (column < 1.0 ? 0.0 : column < 2.0 ? 8.0 : column < 3.0 ? 2.0 : 10.0) / 15.0;
	if (row < 2.0) return (column < 1.0 ? 12.0 : column < 2.0 ? 4.0 : column < 3.0 ? 14.0 : 6.0) / 15.0;
	if (row < 3.0) return (column < 1.0 ? 3.0 : column < 2.0 ? 11.0 : column < 3.0 ? 1.0 : 9.0) / 15.0;
	return (column < 1.0 ? 15.0 : column < 2.0 ? 7.0 : column < 3.0 ? 13.0 : 5.0) / 15.0;
}
float treat_gradient(float value) {
	if (gradient_steps < 2) return value;
	float jitter = (bayer4(floor(vector_point)) - 0.5) * gradient_dither / float(gradient_steps - 1);
	return floor(clamp(value + jitter, 0.0, 1.0) * float(gradient_steps - 1) + 0.5) / float(gradient_steps - 1);
}
void fragment() {
	float linear_light = clamp(1.0 - abs((vector_point.x - center_x) / max(half_width, 1.0)), 0.0, 1.0);
	float radial_light = clamp(1.0 - length(vec2((vector_point.x - center_x) / max(half_width, 1.0), (vector_point.y - (top_y + bottom_y) * 0.5) / max((bottom_y - top_y) * 0.5, 1.0))), 0.0, 1.0);
	float round_light = treat_gradient(gradient_mode == 1 ? radial_light : linear_light);
	float height_light = clamp(1.0 - (vector_point.y - top_y) / max(bottom_y - top_y, 1.0), 0.0, 1.0);
	vec3 colour = mix(edge_wood.rgb, centre_wood.rgb, 0.25 + round_light * 0.75);
	colour *= mix(bottom_light, top_light, height_light);
	COLOR = vec4(colour, 1.0);
}
"""
		inside_material.shader = body_shader
		outside_material.shader = body_shader
		var lid_shader := Shader.new()
		lid_shader.code = """
shader_type canvas_item;
uniform float center_y = 35.0;
uniform float center_x = 80.0;
uniform float half_width = 20.0;
uniform float half_height = 8.0;
uniform vec4 dark_wood : source_color;
uniform vec4 light_wood : source_color;
uniform int gradient_mode = 0;
uniform int gradient_steps = 0;
uniform float gradient_dither = 0.0;
varying vec2 vector_point;
void vertex() { vector_point = VERTEX; }
float bayer4(vec2 pixel) {
	vec2 p = mod(pixel, 4.0);
	float row = p.y;
	float column = p.x;
	if (row < 1.0) return (column < 1.0 ? 0.0 : column < 2.0 ? 8.0 : column < 3.0 ? 2.0 : 10.0) / 15.0;
	if (row < 2.0) return (column < 1.0 ? 12.0 : column < 2.0 ? 4.0 : column < 3.0 ? 14.0 : 6.0) / 15.0;
	if (row < 3.0) return (column < 1.0 ? 3.0 : column < 2.0 ? 11.0 : column < 3.0 ? 1.0 : 9.0) / 15.0;
	return (column < 1.0 ? 15.0 : column < 2.0 ? 7.0 : column < 3.0 ? 13.0 : 5.0) / 15.0;
}
float treat_gradient(float value) {
	if (gradient_steps < 2) return value;
	float jitter = (bayer4(floor(vector_point)) - 0.5) * gradient_dither / float(gradient_steps - 1);
	return floor(clamp(value + jitter, 0.0, 1.0) * float(gradient_steps - 1) + 0.5) / float(gradient_steps - 1);
}
void fragment() {
	float linear_light = clamp((vector_point.y - center_y) / max(half_height * 2.0, 1.0) + 0.5, 0.0, 1.0);
	float radial_light = clamp(1.0 - length(vec2((vector_point.x - center_x) / max(half_width, 1.0), (vector_point.y - center_y) / max(half_height, 1.0))), 0.0, 1.0);
	float lid_light = treat_gradient(gradient_mode == 1 ? radial_light : linear_light);
	COLOR = vec4(mix(dark_wood.rgb, light_wood.rgb, lid_light), 1.0);
}
"""
		lid_material.shader = lid_shader

	func _configure_line(line: Line2D, colour: Color, width: float, closed: bool) -> void:
		line.default_color = colour
		line.width = width
		line.closed = closed
		line.antialiased = false

	func _configure_hoop(hoop: Line2D, node_name: String, parent: Node) -> void:
		hoop.name = node_name
		hoop.width = 3.0
		hoop.closed = false
		hoop.antialiased = false
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		ramp.colors = PackedColorArray([Color8(35, 37, 34), Color8(201, 207, 194), Color8(35, 37, 34)])
		hoop.gradient = ramp
		parent.add_child(hoop)

	func _configure_hoop_shadow(hoop_shadow: Line2D, node_name: String, parent: Node) -> void:
		_configure_line(hoop_shadow, Color(0.03, 0.025, 0.02, 0.56), 4.5, false)
		hoop_shadow.name = node_name
		parent.add_child(hoop_shadow)

	func _configure_hoop_highlight(hoop_highlight: Line2D, node_name: String, parent: Node) -> void:
		_configure_line(hoop_highlight, Color(1.0, 1.0, 1.0, 0.48), 0.75, false)
		hoop_highlight.name = node_name
		parent.add_child(hoop_highlight)

	func apply_style(style: Node) -> void:
		shadow.color = style.get("floor_shadow_colour")
		rim.default_color = style.get("rim_colour")
		rim.width = float(style.get("rim_width"))
		upper_hoop.width = float(style.get("hoop_width"))
		lower_hoop.width = float(style.get("hoop_width"))
		for hoop in [upper_hoop, lower_hoop]:
			var ramp := Gradient.new()
			ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			ramp.colors = PackedColorArray([style.get("hoop_edge"), style.get("hoop_centre"), style.get("hoop_edge")])
			hoop.gradient = ramp
		var inside_wood: Color = style.get("barrel_interior_colour")
		inside_material.set_shader_parameter("edge_wood", inside_wood)
		inside_material.set_shader_parameter("centre_wood", inside_wood.lightened(0.08))
		inside_material.set_shader_parameter("bottom_light", 0.58)
		inside_material.set_shader_parameter("top_light", 0.82)
		inside_material.set_shader_parameter("gradient_mode", int(style.get("body_gradient_mode")))
		inside_material.set_shader_parameter("gradient_steps", int(style.get("gradient_steps")))
		inside_material.set_shader_parameter("gradient_dither", float(style.get("gradient_dither")))
		outside_material.set_shader_parameter("edge_wood", style.get("wood_edge"))
		outside_material.set_shader_parameter("centre_wood", style.get("wood_centre"))
		outside_material.set_shader_parameter("bottom_light", float(style.get("wood_bottom_light")))
		outside_material.set_shader_parameter("top_light", float(style.get("wood_top_light")))
		outside_material.set_shader_parameter("gradient_mode", int(style.get("body_gradient_mode")))
		outside_material.set_shader_parameter("gradient_steps", int(style.get("gradient_steps")))
		outside_material.set_shader_parameter("gradient_dither", float(style.get("gradient_dither")))
		var lid_wood: Color = style.get("lid_colour")
		lid_material.set_shader_parameter("dark_wood", lid_wood.darkened(0.34))
		lid_material.set_shader_parameter("light_wood", lid_wood)
		lid_material.set_shader_parameter("gradient_mode", int(style.get("lid_gradient_mode")))
		lid_material.set_shader_parameter("gradient_steps", int(style.get("gradient_steps")))
		lid_material.set_shader_parameter("gradient_dither", float(style.get("gradient_dither")))
		for stave in stave_lines:
			stave.default_color = style.get("side_stave_colour")
			stave.width = float(style.get("stave_width"))
		for highlight in stave_highlights:
			highlight.default_color = style.get("side_stave_highlight_colour")
			highlight.width = maxf(0.5, float(style.get("stave_width")) * 0.5)
		for seam_shadow in lid_seam_shadows:
			seam_shadow.default_color = style.get("lid_stave_colour")
			seam_shadow.width = float(style.get("stave_width"))
		for seam_highlight in lid_seam_highlights:
			seam_highlight.default_color = style.get("lid_stave_highlight_colour")
			seam_highlight.width = maxf(0.5, float(style.get("stave_width")) * 0.5)
		for hoop_shadow in [upper_hoop_shadow, lower_hoop_shadow]:
			hoop_shadow.default_color = style.get("hoop_shadow_colour")
			hoop_shadow.width = float(style.get("hoop_width")) + 1.5
		for hoop_highlight in [upper_hoop_highlight, lower_hoop_highlight]:
			hoop_highlight.default_color = style.get("hoop_highlight_colour")
			hoop_highlight.width = maxf(0.5, float(style.get("hoop_width")) * 0.22)

	func update_geometry(
		new_body: PackedVector2Array,
		panels: Array,
		new_lid: PackedVector2Array,
		inset: PackedVector2Array,
		new_lower_hoop: PackedVector2Array,
		new_upper_hoop: PackedVector2Array,
		new_shadow: PackedVector2Array,
		staves: PackedVector2Array,
		lid_seams: PackedVector2Array,
	) -> void:
		# The rear layer only fills the opening beneath the lid; using the complete
		# silhouette made it leak through the sides and bottom of the front staves.
		inside_body.polygon = inset if inset.size() >= 3 else new_lid
		lid.polygon = inset if inset.size() >= 3 else new_lid
		shadow.polygon = new_shadow
		rim.points = new_lid
		_update_panels(panels)
		_set_hoop_points(new_upper_hoop, upper_hoop_shadow, upper_hoop, upper_hoop_highlight)
		_set_hoop_points(new_lower_hoop, lower_hoop_shadow, lower_hoop, lower_hoop_highlight)
		var bounds := _bounds_for(new_body)
		for material in [inside_material, outside_material]:
			material.set_shader_parameter("center_x", bounds.get_center().x)
			material.set_shader_parameter("half_width", maxf(2.0, bounds.size.x * 0.5))
			material.set_shader_parameter("top_y", bounds.position.y)
			material.set_shader_parameter("bottom_y", bounds.end.y)
		var lid_bounds := _bounds_for(new_lid)
		lid_material.set_shader_parameter("center_x", lid_bounds.get_center().x)
		lid_material.set_shader_parameter("center_y", lid_bounds.get_center().y)
		lid_material.set_shader_parameter("half_width", maxf(2.0, lid_bounds.size.x * 0.5))
		lid_material.set_shader_parameter("half_height", maxf(1.0, lid_bounds.size.y * 0.5))
		_update_staves(staves)
		_update_lid_staves(lid_seams)
		skeleton.set_geometry(new_body, panels, new_lid, inset, new_lower_hoop, new_upper_hoop, new_shadow, staves, lid_seams)

	func set_skeleton_visible(enabled: bool, display_pixel_width: float, cross_display_pixels: float) -> void:
		skeleton.visible = enabled
		skeleton.stroke_width = display_pixel_width
		skeleton.cross_span = display_pixel_width * cross_display_pixels
		skeleton.queue_redraw()

	func get_skeleton_shapes() -> Array[Dictionary]:
		return skeleton.shapes

	func _update_panels(panels: Array) -> void:
		while outside_panels.size() < panels.size():
			var panel := Polygon2D.new()
			panel.name = "OutsideStave_%02d" % (outside_panels.size() + 1)
			panel.material = outside_material
			outside_wood_layer.add_child(panel)
			outside_panels.append(panel)
		for index in outside_panels.size():
			var panel := outside_panels[index]
			panel.visible = index < panels.size()
			if index < panels.size():
				panel.polygon = panels[index].get("points", PackedVector2Array())

	func _set_hoop_points(points: PackedVector2Array, hoop_shadow: Line2D, hoop_metal: Line2D, hoop_highlight: Line2D) -> void:
		hoop_shadow.points = _offset_points(points, Vector2.DOWN * 0.8)
		hoop_metal.points = points
		hoop_highlight.points = _offset_points(points, Vector2.UP * 0.55)

	func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
		var shifted := PackedVector2Array()
		for point in points:
			shifted.append(point + offset)
		return shifted

	func _update_staves(points: PackedVector2Array) -> void:
		var needed := points.size() / 2
		while stave_lines.size() < needed:
			var stave := Line2D.new()
			stave.name = "OutsideStaveShadow_%02d" % (stave_lines.size() + 1)
			_configure_line(stave, Color(0.13, 0.055, 0.012, 0.64), 1.0, false)
			outside_detail_layer.add_child(stave)
			stave_lines.append(stave)
			var highlight := Line2D.new()
			highlight.name = "OutsideStaveHighlight_%02d" % (stave_highlights.size() + 1)
			_configure_line(highlight, Color(1.0, 0.72, 0.36, 0.30), 0.5, false)
			outside_detail_layer.add_child(highlight)
			stave_highlights.append(highlight)
		for index in stave_lines.size():
			var stave := stave_lines[index]
			stave.visible = index < needed
			var highlight := stave_highlights[index]
			highlight.visible = index < needed
			if index < needed:
				stave.points = PackedVector2Array([points[index * 2], points[index * 2 + 1]])
				highlight.points = _offset_points(stave.points, Vector2.RIGHT * 0.55)

	func _update_lid_staves(points: PackedVector2Array) -> void:
		var needed := points.size() / 2
		while lid_seam_shadows.size() < needed:
			var seam_shadow := Line2D.new()
			seam_shadow.name = "LidStaveShadow_%02d" % (lid_seam_shadows.size() + 1)
			_configure_line(seam_shadow, Color(0.08, 0.035, 0.01, 0.72), 1.0, false)
			lid_detail_layer.add_child(seam_shadow)
			lid_seam_shadows.append(seam_shadow)
			var seam_highlight := Line2D.new()
			seam_highlight.name = "LidStaveHighlight_%02d" % (lid_seam_highlights.size() + 1)
			_configure_line(seam_highlight, Color(1.0, 0.74, 0.36, 0.38), 0.5, false)
			lid_detail_layer.add_child(seam_highlight)
			lid_seam_highlights.append(seam_highlight)
		for index in lid_seam_shadows.size():
			var seam_shadow := lid_seam_shadows[index]
			var seam_highlight := lid_seam_highlights[index]
			seam_shadow.visible = index < needed
			seam_highlight.visible = index < needed
			if index < needed:
				seam_shadow.points = PackedVector2Array([points[index * 2], points[index * 2 + 1]])
				seam_highlight.points = _offset_points(seam_shadow.points, Vector2.RIGHT * 0.5)

	func _bounds_for(points: PackedVector2Array) -> Rect2:
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		return bounds


	class SkeletonOverlay extends Node2D:
		var shapes: Array[Dictionary] = []
		var stroke_width := 1.0
		var cross_span := 4.0

		func set_geometry(
			body: PackedVector2Array,
			panels: Array,
			lid_ring: PackedVector2Array,
			lid_inset: PackedVector2Array,
			lower_hoop: PackedVector2Array,
			upper_hoop: PackedVector2Array,
			floor_shadow: PackedVector2Array,
			staves: PackedVector2Array,
			lid_seams: PackedVector2Array,
		) -> void:
			shapes.clear()
			_add_shape(body, Color("40d9ff"), true)
			_add_shape(floor_shadow, Color("ff9c3d"), true)
			_add_shape(lid_ring, Color("ff4db8"), true)
			_add_shape(lid_inset, Color("ff784d"), true)
			_add_shape(lower_hoop, Color("77ff91"), false)
			_add_shape(upper_hoop, Color("77ff91"), false)
			for panel_data in panels:
				_add_shape(panel_data.get("points", PackedVector2Array()), Color("6ca0ff"), true)
			_add_segment_pairs(staves, Color("ffe34d"))
			_add_segment_pairs(lid_seams, Color("eaa4ff"))
			if visible:
				queue_redraw()

		func _add_shape(points: PackedVector2Array, colour: Color, closed: bool) -> void:
			if points.size() >= 2:
				shapes.append({"points": points, "colour": colour, "closed": closed})

		func _add_segment_pairs(points: PackedVector2Array, colour: Color) -> void:
			for index in range(0, points.size() - 1, 2):
				_add_shape(PackedVector2Array([points[index], points[index + 1]]), colour, false)

		func _draw() -> void:
			for shape in shapes:
				var points: PackedVector2Array = shape["points"]
				var colour: Color = shape["colour"]
				var wire := points.duplicate()
				if bool(shape["closed"]):
					wire.append(points[0])
				draw_polyline(wire, colour, stroke_width, false)
				for point in points:
					draw_line(point - Vector2(cross_span, 0.0), point + Vector2(cross_span, 0.0), colour, stroke_width, false)
					draw_line(point - Vector2(0.0, cross_span), point + Vector2(0.0, cross_span), colour, stroke_width, false)


class FullResolutionSkeletonOverlay extends Node2D:
	var source_shapes: Array[Dictionary] = []
	var logical_to_local := Transform2D.IDENTITY
	var stroke_width := 1.0
	var cross_span := 3.0

	func set_geometry(
		new_shapes: Array[Dictionary],
		new_logical_to_local: Transform2D,
		new_stroke_width: float,
		new_cross_span: float,
	) -> void:
		source_shapes = new_shapes
		logical_to_local = new_logical_to_local
		stroke_width = new_stroke_width
		cross_span = new_cross_span
		queue_redraw()

	func _draw() -> void:
		var crossed_points := {}
		for shape in source_shapes:
			var points: PackedVector2Array = shape["points"]
			if points.size() < 2:
				continue
			var wire := PackedVector2Array()
			for point in points:
				wire.append(logical_to_local * point)
			if bool(shape["closed"]):
				wire.append(wire[0])
			var colour: Color = shape["colour"]
			colour.a = 0.72
			draw_polyline(wire, colour, stroke_width, true)
			for point in wire:
				var key := Vector2i(roundi(point.x), roundi(point.y))
				if crossed_points.has(key):
					continue
				crossed_points[key] = true
				var cross_colour := Color(1.0, 1.0, 1.0, 0.9)
				draw_line(point - Vector2(cross_span, 0.0), point + Vector2(cross_span, 0.0), cross_colour, stroke_width, true)
				draw_line(point - Vector2(0.0, cross_span), point + Vector2(0.0, cross_span), cross_colour, stroke_width, true)
