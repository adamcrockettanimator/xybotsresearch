@tool
extends Node2D

## An editor-time sketchpad for the projected Canvas barrel's *art decisions*.
##
## This intentionally draws in the 2D editor rather than launching the game.
## It is a controlled authoring view: the real game still supplies the final
## camera projection and rasterises the result through semantic_projected_canvas_barrel.gd.

@export_category("View")
## Used by the runtime adapter to instance the actual Curved Lines hierarchy
## without also drawing this editor sketchpad's backdrop or generated fallback.
@export var runtime_asset_only := false
@export_range(2, 8, 1) var logical_pixel_scale := 5:
	set(value):
		logical_pixel_scale = value
		queue_redraw()
@export_range(0.35, 3.8, 0.05) var preview_distance := 1.0:
	set(value):
		preview_distance = value
		_rebuild_for_preview_change()
@export_range(-45.0, 45.0, 1.0, "degrees") var view_yaw_degrees := 0.0:
	set(value):
		view_yaw_degrees = value
		queue_redraw()
@export_enum("Smooth gradient", "Three colour steps") var body_shading := 0:
	set(value):
		body_shading = value
		_rebuild_for_preview_change()

@export_category("Semantic LOD")
## The source vector hierarchy is the close-up asset.  These bands decide
## when its visual job is handed to a simpler drawing that keeps the barrel's
## identity (round lid, wood body, and metal binding) readable in fewer pixels.
@export_enum("Automatic from preview distance", "Near — authored vectors", "Middle — lid body two hoops", "Far — lid body one hoop") var preview_lod := 0:
	set(value):
		preview_lod = value
		_rebuild_for_preview_change()
@export_range(0.45, 2.5, 0.05) var near_lod_max_distance := 1.20:
	set(value):
		near_lod_max_distance = value
		_rebuild_for_preview_change()
@export_range(1.0, 3.5, 0.05) var middle_lod_max_distance := 2.40:
	set(value):
		middle_lod_max_distance = value
		_rebuild_for_preview_change()

@export_category("Silhouette")
@export_range(16.0, 42.0, 1.0) var body_half_width := 29.0:
	set(value):
		body_half_width = value
		queue_redraw()
@export_range(28.0, 72.0, 1.0) var body_height := 52.0:
	set(value):
		body_height = value
		queue_redraw()
@export_range(0.0, 0.25, 0.01) var body_swell := 0.09:
	set(value):
		body_swell = value
		queue_redraw()
@export_range(0.12, 0.62, 0.01) var lid_depth := 0.36:
	set(value):
		lid_depth = value
		queue_redraw()
@export_range(3, 12, 1) var stave_count := 7:
	set(value):
		stave_count = value
		queue_redraw()
@export_range(0.20, 0.80, 0.01) var upper_hoop_height := 0.35:
	set(value):
		upper_hoop_height = value
		queue_redraw()
@export_range(0.20, 0.80, 0.01) var lower_hoop_height := 0.70:
	set(value):
		lower_hoop_height = value
		queue_redraw()
@export_range(1.0, 5.0, 0.25) var hoop_thickness := 2.0:
	set(value):
		hoop_thickness = value
		queue_redraw()

@export_category("Paint")
@export var wood_bottom := Color8(81, 53, 30):
	set(value):
		wood_bottom = value
		queue_redraw()
@export var wood_top := Color8(176, 118, 65):
	set(value):
		wood_top = value
		queue_redraw()
@export var wood_edge := Color8(53, 35, 20):
	set(value):
		wood_edge = value
		queue_redraw()
@export var lid_top := Color8(164, 108, 59):
	set(value):
		lid_top = value
		queue_redraw()
@export var metal_dark := Color8(52, 53, 49):
	set(value):
		metal_dark = value
		queue_redraw()
@export var metal_light := Color8(139, 143, 132):
	set(value):
		metal_light = value
		queue_redraw()
@export var shadow_colour := Color(0.05, 0.035, 0.02, 0.38):
	set(value):
		shadow_colour = value
		queue_redraw()

@export_category("Layer visibility")
@export var show_floor_shadow := true:
	set(value):
		show_floor_shadow = value
		queue_redraw()
@export var show_lid := true:
	set(value):
		show_lid = value
		queue_redraw()
@export var show_body_gradient := true:
	set(value):
		show_body_gradient = value
		queue_redraw()
@export var show_staves := true:
	set(value):
		show_staves = value
		queue_redraw()
@export var show_hoops := true:
	set(value):
		show_hoops = value
		queue_redraw()

const LOGICAL_SIZE := Vector2(160.0, 120.0)
const BACKDROP := Color8(35, 30, 25)
const GRID := Color8(52, 43, 35)

@export_tool_button("Rebuild Barrel Shapes", "Reload") var rebuild_barrel_shapes_action = Callable(self, "rebuild_barrel_shapes")
var _last_build_signature := 0


func _ready() -> void:
	_configure_authored_hoops_as_open_arcs()
	queue_redraw()
	# `Rectangle` is the artist-authored Curved Lines source.  It stays intact:
	# LOD only changes which representation is visible, never its points.
	call_deferred("rebuild_barrel_shapes")


## A Line2D gradient follows distance along its points, not screen X.  A closed
## oval therefore runs its metal ramp around the loop and doubles back on
## itself. Keep the two artist-authored hoop objects, but give each one a
## single, open front arc: side -> bright centre -> opposite side.
func _configure_authored_hoops_as_open_arcs() -> void:
	var metal_shader := Shader.new()
	metal_shader.code = """
shader_type canvas_item;

varying float hoop_local_x;

void vertex() {
	hoop_local_x = VERTEX.x;
}

void fragment() {
	float center_light = clamp(1.0 - abs((hoop_local_x + 1.25) / 50.0), 0.0, 1.0);
	vec3 edge_iron = vec3(0.11, 0.12, 0.11);
	vec3 center_iron = vec3(0.82, 0.84, 0.78);
	COLOR = vec4(mix(edge_iron, center_iron, center_light), 1.0);
}
"""
	var metal_material := ShaderMaterial.new()
	metal_material.shader = metal_shader
	for hoop_path in [NodePath("Rectangle/Ellipse2/Stroke"), NodePath("Rectangle/Ellipse3/Stroke")]:
		var hoop := get_node_or_null(hoop_path) as Line2D
		if hoop == null:
			continue
		var arc := PackedVector2Array()
		# The parent retains its authored horizontal scale; this local y radius is
		# already baked, so line width does not collapse at the arc's midpoint.
		for index in 25:
			var angle := PI * float(index) / 24.0
			arc.append(Vector2(-1.25 + cos(angle) * 50.0, 0.39 + sin(angle) * 14.0))
		hoop.points = arc
		hoop.closed = false
		hoop.width = 4.5
		hoop.gradient = null
		hoop.material = metal_material


func _process(_delta: float) -> void:
	# Inspector edits do not need a custom plugin: this detects a changed art
	# parameter and regenerates the ordinary child-node layer stack once.
	if Engine.is_editor_hint() and _last_build_signature != _build_signature():
		rebuild_barrel_shapes()


func _rebuild_for_preview_change() -> void:
	queue_redraw()
	if is_inside_tree():
		rebuild_barrel_shapes()


func _draw() -> void:
	if runtime_asset_only:
		return
	var scale_factor := float(logical_pixel_scale)
	draw_rect(Rect2(Vector2.ZERO, LOGICAL_SIZE * scale_factor), BACKDROP)
	for x in range(0, int(LOGICAL_SIZE.x) + 1, 16):
		draw_line(_p(Vector2(x, 0)), _p(Vector2(x, LOGICAL_SIZE.y)), GRID, 1.0)
	for y in range(0, int(LOGICAL_SIZE.y) + 1, 16):
		draw_line(_p(Vector2(0, y)), _p(Vector2(LOGICAL_SIZE.x, y)), GRID, 1.0)


## Build ordinary editor-selectable nodes for each visible barrel layer.
## The game retains its one-node Canvas raster; this hierarchy is authoring data.
func rebuild_barrel_shapes() -> void:
	if not is_inside_tree():
		return
	_last_build_signature = _build_signature()
	for child in get_children():
		if child.get_meta("semantic_barrel_generated", false):
			child.queue_free()
	var lod := _active_semantic_lod()
	_set_authored_vector_visible(lod == 1)
	if runtime_asset_only:
		return
	# The close barrel is exactly the artist's existing vector construction. It
	# is deliberately not regenerated from numbers, so its curves remain freely
	# editable in the Curved Lines dock.
	if lod == 1:
		return

	var distance_fraction := clampf((preview_distance - 0.35) / 3.45, 0.0, 1.0)
	var width := lerpf(body_half_width, body_half_width * 0.44, distance_fraction)
	var height := lerpf(body_height, body_height * 0.48, distance_fraction)
	var lid_squash := lerpf(lid_depth, lid_depth * 0.52, distance_fraction)
	var center := Vector2(80.0, 70.0)
	var top_center := center - Vector2(0.0, height * 0.45)
	var bottom_y := top_center.y + height
	var yaw_shift := sin(deg_to_rad(view_yaw_degrees)) * width * 0.22
	var edge_swell := width * (1.0 + body_swell)

	if show_floor_shadow:
		_add_polygon("Floor Shadow", PackedVector2Array([Vector2(center.x - edge_swell * 1.06, bottom_y + 1.0), Vector2(center.x + edge_swell * 1.06, bottom_y + 1.0), Vector2(center.x + edge_swell * 0.70, bottom_y + 5.0), Vector2(center.x - edge_swell * 0.70, bottom_y + 5.0)]), shadow_colour)
	var silhouette := PackedVector2Array([top_center + Vector2(-width, 0.0), top_center + Vector2(width, 0.0), Vector2(center.x + edge_swell, bottom_y), Vector2(center.x - edge_swell, bottom_y)])
	_add_polygon("Body Silhouette", silhouette, wood_bottom)

	# Middle range retains board rhythm; far range drops it before the silhouette
	# becomes too small for the seams to describe material rather than noise.
	var semantic_staves := stave_count if lod == 2 else 0
	for index in semantic_staves:
		var left_t := float(index) / float(stave_count)
		var right_t := float(index + 1) / float(stave_count)
		var left_x := lerpf(-width, width, left_t)
		var right_x := lerpf(-width, width, right_t)
		var panel := PackedVector2Array([Vector2(center.x + left_x / width * edge_swell, bottom_y), Vector2(center.x + right_x / width * edge_swell, bottom_y), top_center + Vector2(right_x + yaw_shift * right_t, 0.0), top_center + Vector2(left_x + yaw_shift * left_t, 0.0)])
		var middle := (left_t + right_t) * 0.5
		var round_light := 0.62 + sin(middle * PI) * 0.38
		var bottom_colour := wood_bottom.lerp(wood_top, 0.22 * round_light)
		var top_colour := wood_bottom.lerp(wood_top, 0.72 * round_light)
		if body_shading == 1:
			bottom_colour = _three_step(bottom_colour)
			top_colour = _three_step(top_colour)
		if show_body_gradient:
			_add_polygon("Stave %02d" % (index + 1), panel, bottom_colour, PackedColorArray([bottom_colour, bottom_colour, top_colour, top_colour]))
		if show_staves and index > 0:
			_add_line("Stave Seam %02d" % index, PackedVector2Array([panel[0], panel[3]]), Color(wood_edge, 0.62), 1.0)

	if show_hoops:
		_add_hoop("Upper Hoop", Vector2(center.x, lerpf(top_center.y, bottom_y, upper_hoop_height)), edge_swell, width * 0.13)
		if lod == 2:
			_add_hoop("Lower Hoop", Vector2(center.x, lerpf(top_center.y, bottom_y, lower_hoop_height)), edge_swell, width * 0.14)
	if show_lid:
		var lid_center := top_center + Vector2(yaw_shift, 0.0)
		_add_polygon("Lid Outer", _ellipse(lid_center, width, width * lid_squash, 16), lid_top)
		if lod == 2:
			_add_polygon("Lid Inset", _ellipse(lid_center, width * 0.72, width * lid_squash * 0.55, 16), wood_edge.lerp(lid_top, 0.28))
			for fraction in [-0.34, 0.0, 0.34]:
				_add_line("Lid Seam %s" % str(fraction), PackedVector2Array([lid_center + Vector2(width * fraction, -width * lid_squash * 0.50), lid_center + Vector2(width * fraction, width * lid_squash * 0.50)]), Color(wood_edge, 0.65), 1.0)


func _add_hoop(node_name: String, center: Vector2, radius_x: float, radius_y: float) -> void:
	var arc := PackedVector2Array()
	for index in 17:
		var angle := lerpf(PI, TAU, float(index) / 16.0)
		arc.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	_add_line(node_name, arc, metal_dark, hoop_thickness)
	_add_line("%s Highlight" % node_name, PackedVector2Array([arc[5], arc[6], arc[7], arc[8], arc[9], arc[10], arc[11]]), metal_light, maxf(1.0, hoop_thickness * 0.45))


func _add_polygon(node_name: String, logical_points: PackedVector2Array, colour: Color, vertex_colours := PackedColorArray()) -> void:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = _shape(logical_points)
	polygon.color = colour
	if not vertex_colours.is_empty():
		polygon.vertex_colors = vertex_colours
	_add_generated_node(polygon)


func _add_line(node_name: String, logical_points: PackedVector2Array, colour: Color, width: float) -> void:
	var line := Line2D.new()
	line.name = node_name
	line.points = _shape(logical_points)
	line.default_color = colour
	line.width = width * float(logical_pixel_scale)
	line.antialiased = false
	_add_generated_node(line)


func _add_generated_node(node: Node) -> void:
	node.set_meta("semantic_barrel_generated", true)
	node.set_meta("semantic_lod", _semantic_lod_name(_active_semantic_lod()))
	add_child(node, true)
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root


func _build_signature() -> int:
	return [logical_pixel_scale, preview_distance, view_yaw_degrees, body_shading, preview_lod, near_lod_max_distance, middle_lod_max_distance, body_half_width, body_height, body_swell, lid_depth, stave_count, upper_hoop_height, lower_hoop_height, hoop_thickness, wood_bottom, wood_top, wood_edge, lid_top, metal_dark, metal_light, shadow_colour, show_floor_shadow, show_lid, show_body_gradient, show_staves, show_hoops].hash()


## 1 = near authored curves, 2 = middle semantic construction, 3 = far icon.
## The cutoffs contain a deliberately broad middle band, preventing a close
## barrel from shedding its hoops abruptly as the camera wanders.
func _active_semantic_lod() -> int:
	if preview_lod > 0:
		return preview_lod
	if preview_distance <= near_lod_max_distance:
		return 1
	if preview_distance <= maxf(near_lod_max_distance, middle_lod_max_distance):
		return 2
	return 3


func _semantic_lod_name(lod: int) -> String:
	match lod:
		1: return "Near authored vectors"
		2: return "Middle semantic barrel"
		_: return "Far semantic barrel"


func _set_authored_vector_visible(is_visible: bool) -> void:
	var authored_vector := get_node_or_null("Rectangle") as CanvasItem
	if authored_vector != null:
		authored_vector.visible = is_visible


func _generated_shape_count() -> int:
	var count := 0
	for child in get_children():
		if child.get_meta("semantic_barrel_generated", false):
			count += 1
	return count


func _draw_barrel() -> void:
	var distance_fraction := clampf((preview_distance - 0.35) / 3.45, 0.0, 1.0)
	var width := lerpf(body_half_width, body_half_width * 0.44, distance_fraction)
	var height := lerpf(body_height, body_height * 0.48, distance_fraction)
	var lid_squash := lerpf(lid_depth, lid_depth * 0.52, distance_fraction)
	var center := Vector2(80.0, 70.0)
	var top_center := center - Vector2(0.0, height * 0.45)
	var bottom_y := top_center.y + height
	var yaw_shift := sin(deg_to_rad(view_yaw_degrees)) * width * 0.22
	var edge_swell := width * (1.0 + body_swell)
	var silhouette := PackedVector2Array([
		top_center + Vector2(-width, 0.0), top_center + Vector2(width, 0.0),
		Vector2(center.x + edge_swell, bottom_y), Vector2(center.x - edge_swell, bottom_y),
	])
	if show_floor_shadow:
		var shadow := PackedVector2Array([Vector2(center.x - edge_swell * 1.06, bottom_y + 1.0), Vector2(center.x + edge_swell * 1.06, bottom_y + 1.0), Vector2(center.x + edge_swell * 0.70, bottom_y + 5.0), Vector2(center.x - edge_swell * 0.70, bottom_y + 5.0)])
		draw_colored_polygon(_shape(shadow), shadow_colour)
	# The silhouette remains an editable, distinct layer beneath the board paint.
	draw_colored_polygon(_shape(silhouette), wood_bottom)
	_draw_panels(top_center, bottom_y, width, edge_swell, yaw_shift)
	if show_hoops:
		_draw_hoop(Vector2(center.x, lerpf(top_center.y, bottom_y, upper_hoop_height)), edge_swell, width * 0.13)
		_draw_hoop(Vector2(center.x, lerpf(top_center.y, bottom_y, lower_hoop_height)), edge_swell, width * 0.14)
	if show_lid:
		_draw_lid(top_center + Vector2(yaw_shift, 0.0), width, width * lid_squash)


func _draw_panels(top_center: Vector2, bottom_y: float, width: float, edge_swell: float, yaw_shift: float) -> void:
	for index in stave_count:
		var left_t := float(index) / float(stave_count)
		var right_t := float(index + 1) / float(stave_count)
		var left_x := lerpf(-width, width, left_t)
		var right_x := lerpf(-width, width, right_t)
		var panel := PackedVector2Array([
			Vector2(80.0 + left_x / width * edge_swell, bottom_y), Vector2(80.0 + right_x / width * edge_swell, bottom_y),
			top_center + Vector2(right_x + yaw_shift * right_t, 0.0), top_center + Vector2(left_x + yaw_shift * left_t, 0.0),
		])
		if show_body_gradient:
			var middle := (left_t + right_t) * 0.5
			var round_light := 0.62 + sin(middle * PI) * 0.38
			var bottom_colour := wood_bottom.lerp(wood_top, 0.22 * round_light)
			var top_colour := wood_bottom.lerp(wood_top, 0.72 * round_light)
			if body_shading == 1:
				bottom_colour = _three_step(bottom_colour)
				top_colour = _three_step(top_colour)
			draw_polygon(_shape(panel), PackedColorArray([bottom_colour, bottom_colour, top_colour, top_colour]))
		if show_staves and index > 0:
			draw_line(_p(panel[0]), _p(panel[3]), Color(wood_edge, 0.62), float(logical_pixel_scale), false)


func _draw_lid(center: Vector2, radius_x: float, radius_y: float) -> void:
	var outer := _ellipse(center, radius_x, radius_y, 16)
	var inner := _ellipse(center, radius_x * 0.72, radius_y * 0.55, 16)
	var colours := PackedColorArray()
	for point in outer:
		colours.append(lid_top.lerp(wood_edge, clampf((point.y - (center.y - radius_y)) / maxf(1.0, radius_y * 2.0), 0.0, 1.0) * 0.34))
	draw_polygon(_shape(outer), colours)
	draw_colored_polygon(_shape(inner), wood_edge.lerp(lid_top, 0.28))
	for fraction in [-0.34, 0.0, 0.34]:
		draw_line(_p(center + Vector2(radius_x * fraction, -radius_y * 0.50)), _p(center + Vector2(radius_x * fraction, radius_y * 0.50)), Color(wood_edge, 0.65), float(logical_pixel_scale), false)


func _draw_hoop(center: Vector2, radius_x: float, radius_y: float) -> void:
	var arc := PackedVector2Array()
	for index in 17:
		var angle := lerpf(PI, TAU, float(index) / 16.0)
		arc.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	for index in arc.size() - 1:
		var midpoint := (arc[index] + arc[index + 1]) * 0.5
		var highlight := sin(clampf((midpoint.x - (center.x - radius_x)) / (radius_x * 2.0), 0.0, 1.0) * PI)
		draw_line(_p(arc[index]), _p(arc[index + 1]), metal_dark.lerp(metal_light, highlight), hoop_thickness * float(logical_pixel_scale), false)


func _ellipse(center: Vector2, radius_x: float, radius_y: float, count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in count:
		var angle := TAU * float(index) / float(count)
		result.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return result


func _shape(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(_p(point))
	return result


func _p(logical_point: Vector2) -> Vector2:
	return logical_point * float(logical_pixel_scale)


func _three_step(colour: Color) -> Color:
	var brightness := (colour.r + colour.g + colour.b) / 3.0
	if brightness < 0.28:
		return wood_bottom
	if brightness < 0.48:
		return wood_bottom.lerp(wood_top, 0.42)
	return wood_top
