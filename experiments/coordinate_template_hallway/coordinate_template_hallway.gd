extends Node2D

## A fixed 160x120 authoring-template experiment. The red pixels in
## coordinates3.png are the source of all plane coordinates; no screen points
## are manually authored here.

const TEMPLATE_PATH := "res://experiments/coordinate_template_hallway/assets/coordinates3.png"
const GRID_PATH := "res://experiments/coordinate_template_hallway/assets/greyboxGrid.png"
const WALL_25_PATH := "res://assets/Environment/WallsStraight/Walls_Straight_25.png"
const RED_THRESHOLD := 200
const MAX_PLANES := 16

var detected_markers: Array[Vector2] = []
var depth_rings: Array[Dictionary] = []
var planes: Array[Dictionary] = []
var debug_visible := true
var template_visible := false
var mapped_planes_visible := true
var xybots_art_visible := false
var arcade_quantize_step := 2.0
var coverage_debug_enabled := false
var clean_edges_enabled := false

@onready var projective_planes: Polygon2D = $ProjectivePlanes
@onready var xybots_floor_ceiling: Sprite2D = $XybotsFloorCeiling
@onready var xybots_wall_planes: Polygon2D = $XybotsWallPlanes
@onready var template_overlay: Sprite2D = $TemplateOverlay
@onready var debug_overlay: Node2D = $DebugOverlay
@onready var status_label: Label = $StatusLabel
@onready var sampling_readout: Label = $SamplingReadout


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detect_template_points()
	_build_plane_definitions()
	_configure_projective_renderer()
	_rebuild_debug_overlay()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F1:
			debug_visible = not debug_visible
			debug_overlay.visible = debug_visible
		KEY_F2:
			template_visible = not template_visible
			template_overlay.visible = template_visible
		KEY_F3:
			mapped_planes_visible = not mapped_planes_visible
			_update_projective_plane_visibility()
		KEY_F4:
			xybots_art_visible = not xybots_art_visible
			xybots_floor_ceiling.visible = xybots_art_visible
			xybots_wall_planes.visible = xybots_art_visible
		KEY_F5:
			arcade_quantize_step = 1.0 if arcade_quantize_step >= 4.0 else arcade_quantize_step + 1.0
			_update_quantize_uniforms()
		KEY_F6:
			coverage_debug_enabled = not coverage_debug_enabled
			_update_coverage_debug()
		KEY_F7:
			clean_edges_enabled = not clean_edges_enabled
			_update_clean_edge_uniforms()
	_update_status_label()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 160, 120), Color.BLACK, true)


# Finds connected red pixel components, then uses their centers as markers.
func _detect_template_points() -> void:
	detected_markers.clear()
	var template_texture := load(TEMPLATE_PATH) as Texture2D
	var image := template_texture.get_image()
	var visited := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var seed := Vector2i(x, y)
			if visited.has(seed) or not _is_red_marker(image.get_pixelv(seed)):
				continue
			var component := _collect_red_component(image, seed, visited)
			var center := Vector2.ZERO
			for pixel in component:
				center += Vector2(pixel)
			center /= float(component.size())
			detected_markers.append(center)
	detected_markers.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y or (is_equal_approx(a.y, b.y) and a.x < b.x))
	print("COORDINATE_TEMPLATE size=%dx%d red_markers=%d" % [image.get_width(), image.get_height(), detected_markers.size()])
	for index in detected_markers.size():
		print("  marker_%02d = (%d, %d)" % [index, roundi(detected_markers[index].x), roundi(detected_markers[index].y)])


func _is_red_marker(color: Color) -> bool:
	return color.r8 >= RED_THRESHOLD and color.g8 <= 80 and color.b8 <= 80


func _collect_red_component(image: Image, seed: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [seed]
	var component: Array[Vector2i] = []
	visited[seed] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		component.append(current)
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = current + offset
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= image.get_width() or neighbor.y >= image.get_height() or visited.has(neighbor):
				continue
			if _is_red_marker(image.get_pixelv(neighbor)):
				visited[neighbor] = true
				queue.append(neighbor)
	return component


# Pairs the two red markers on each horizontal edge, then pairs same-width top
# and bottom edges into nested depth rings. The result is ordered outer -> back.
func _build_depth_rings() -> void:
	depth_rings.clear()
	var rows := {}
	for point in detected_markers:
		var y := roundi(point.y)
		if not rows.has(y):
			rows[y] = []
		rows[y].append(point)
	var horizontal_pairs := []
	for y in rows.keys():
		var row: Array = rows[y]
		row.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		if row.size() != 2:
			push_error("Coordinate template needs exactly two red markers on row %d." % y)
			return
		horizontal_pairs.append({"left": row[0], "right": row[1], "y": y, "width": absf(row[1].x - row[0].x)})
	var by_width := {}
	for pair in horizontal_pairs:
		var width := roundi(float(pair["width"]))
		if not by_width.has(width):
			by_width[width] = []
		by_width[width].append(pair)
	for width in by_width.keys():
		var pair_group: Array = by_width[width]
		pair_group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["y"]) < int(b["y"]))
		if pair_group.size() != 2:
			push_error("Coordinate template width %d needs top and bottom marker pairs." % width)
			return
		depth_rings.append({
			"top_left": pair_group[0]["left"], "top_right": pair_group[0]["right"],
			"bottom_left": pair_group[1]["left"], "bottom_right": pair_group[1]["right"],
			"width": width
		})
	depth_rings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["width"]) > int(b["width"]))
	if depth_rings.size() != 4:
		push_error("Expected four nested depth rings; found %d." % depth_rings.size())


func _build_plane_definitions() -> void:
	_build_depth_rings()
	planes.clear()
	if depth_rings.size() != 4:
		return
	# Each depth interval is a separately editable plane. The source grid maps in
	# full onto each quad, deliberately exposing the texture deformation band by band.
	for band in range(depth_rings.size() - 1):
		var outer: Dictionary = depth_rings[band]
		var inner: Dictionary = depth_rings[band + 1]
		_add_plane("ceiling_%d" % (band + 1), [outer["top_left"], outer["top_right"], inner["top_right"], inner["top_left"]], band)
		# Keep source U along the wall's top/bottom edges. The prior order ran U
		# vertically down the outside edge, rotating every right-wall texture 90°.
		_add_plane("right_wall_%d" % (band + 1), [outer["top_right"], inner["top_right"], inner["bottom_right"], outer["bottom_right"]], band)
		_add_plane("floor_%d" % (band + 1), [outer["bottom_left"], inner["bottom_left"], inner["bottom_right"], outer["bottom_right"]], band)
		_add_plane("left_wall_%d" % (band + 1), [outer["top_left"], inner["top_left"], inner["bottom_left"], outer["bottom_left"]], band)
	var back: Dictionary = depth_rings.back()
	_add_plane("back_wall", [back["top_left"], back["top_right"], back["bottom_right"], back["bottom_left"]], depth_rings.size() - 1)
	print("COORDINATE_TEMPLATE planes=%d" % planes.size())
	for plane in planes:
		print("  %s = %s" % [plane["name"], plane["points"]])


func _add_plane(plane_name: String, points: Array, depth_layer: int) -> void:
	planes.append({
		"name": plane_name,
		"points": points,
		"uvs": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
		"depth_layer": depth_layer,
		"enabled": true
	})


func _configure_projective_renderer() -> void:
	projective_planes.polygon = PackedVector2Array([Vector2(0, 0), Vector2(160, 0), Vector2(160, 120), Vector2(0, 120)])
	xybots_wall_planes.polygon = projective_planes.polygon
	var rows := PackedVector4Array()
	var xybots_wall_rows := PackedVector4Array()
	var grid_brightness := PackedFloat32Array()
	var xybots_wall_brightness := PackedFloat32Array()
	var enabled_count := 0
	var xybots_wall_count := 0
	for plane in planes:
		if not bool(plane["enabled"]) or enabled_count >= MAX_PLANES:
			continue
		var points: Array = plane["points"]
		var inverse_rows := _inverse_homography_rows(points[0], points[1], points[2], points[3])
		if inverse_rows.is_empty():
			push_error("Could not build homography for %s." % plane["name"])
			continue
		for row in inverse_rows:
			rows.append(Vector4(row.x, row.y, row.z, 0.0))
		grid_brightness.append(1.0)
		enabled_count += 1
		if _is_wall_plane(String(plane["name"])):
			for row in inverse_rows:
				xybots_wall_rows.append(Vector4(row.x, row.y, row.z, 0.0))
			xybots_wall_brightness.append(_brightness_for_depth(int(plane["depth_layer"])))
			xybots_wall_count += 1
	while grid_brightness.size() < MAX_PLANES:
		grid_brightness.append(1.0)
	while xybots_wall_brightness.size() < MAX_PLANES:
		xybots_wall_brightness.append(1.0)
	var material := projective_planes.material as ShaderMaterial
	material.set_shader_parameter("source_texture", load(GRID_PATH))
	material.set_shader_parameter("source_size", Vector2(160, 120))
	material.set_shader_parameter("plane_count", enabled_count)
	material.set_shader_parameter("inverse_homography_rows", rows)
	material.set_shader_parameter("plane_brightness", grid_brightness)
	var xybots_material := xybots_wall_planes.material as ShaderMaterial
	xybots_material.set_shader_parameter("source_texture", _wall_25_panel_texture())
	xybots_material.set_shader_parameter("source_size", Vector2(128, 88))
	xybots_material.set_shader_parameter("plane_count", xybots_wall_count)
	xybots_material.set_shader_parameter("inverse_homography_rows", xybots_wall_rows)
	xybots_material.set_shader_parameter("plane_brightness", xybots_wall_brightness)
	_update_quantize_uniforms()
	_update_coverage_debug()
	_update_clean_edge_uniforms()
	_update_status_label()


func _is_wall_plane(plane_name: String) -> bool:
	return plane_name.begins_with("left_wall") or plane_name.begins_with("right_wall") or plane_name == "back_wall"


func _brightness_for_depth(depth_layer: int) -> float:
	# Match the authored floor's stepped recession with intentionally discrete
	# arcade bands: outer/near, middle, far, then the back wall.
	match depth_layer:
		0:
			return 1.0
		1:
			return 0.78
		2:
			return 0.58
		_:
			return 0.42


# Walls_Straight_25 is an authored 160x120 transparent overlay. Its useful wall
# panel occupies (16,8)-(143,95); use that panel itself as the flat source so
# transparent margins are not stretched into every destination wall plane.
func _wall_25_panel_texture() -> ImageTexture:
	var overlay := load(WALL_25_PATH) as Texture2D
	var panel_image := overlay.get_image().get_region(Rect2i(16, 8, 128, 88))
	return ImageTexture.create_from_image(panel_image)


func _update_quantize_uniforms() -> void:
	var grid_material := projective_planes.material as ShaderMaterial
	var xybots_material := xybots_wall_planes.material as ShaderMaterial
	for material in [grid_material, xybots_material]:
		material.set_shader_parameter("arcade_pixel_step", arcade_quantize_step)
		material.set_shader_parameter("arcade_uv_step", arcade_quantize_step)


func _update_coverage_debug() -> void:
	var grid_material := projective_planes.material as ShaderMaterial
	var xybots_material := xybots_wall_planes.material as ShaderMaterial
	grid_material.set_shader_parameter("coverage_debug", coverage_debug_enabled)
	xybots_material.set_shader_parameter("coverage_debug", false)
	# Coverage colors must sit over the optional art layer to remain readable.
	projective_planes.z_index = 6 if coverage_debug_enabled else 0
	_update_projective_plane_visibility()


func _update_projective_plane_visibility() -> void:
	# F6 is a diagnostic view of the grid renderer, so it must remain visible
	# even when F3 has hidden its normal textured presentation.
	projective_planes.visible = mapped_planes_visible or coverage_debug_enabled


func _update_clean_edge_uniforms() -> void:
	var grid_material := projective_planes.material as ShaderMaterial
	var xybots_material := xybots_wall_planes.material as ShaderMaterial
	grid_material.set_shader_parameter("force_clean_edges", clean_edges_enabled)
	xybots_material.set_shader_parameter("force_clean_edges", clean_edges_enabled)


func _update_status_label() -> void:
	status_label.text = "PROJECTIVE HALLWAY\nF1 lines: %s F2 template: %s F3 grids: %s F4 Xybots: %s\nF5 sample  F6 coverage: %s  F7 seams: %s" % ["ON" if debug_visible else "OFF", "ON" if template_visible else "OFF", "ON" if mapped_planes_visible else "OFF", "ON" if xybots_art_visible else "OFF", "ON" if coverage_debug_enabled else "OFF", "CLEAN" if clean_edges_enabled else "RAW"]
	sampling_readout.text = "PIXEL / UV: %dx" % roundi(arcade_quantize_step)


# Inverse transform for screen pixel -> source UV. Points are UV (0,0),
# (1,0), (1,1), (0,1), matching the stored plane point order.
func _inverse_homography_rows(p00: Vector2, p10: Vector2, p11: Vector2, p01: Vector2) -> Array[Vector3]:
	var dx1 := p10.x - p11.x
	var dx2 := p01.x - p11.x
	var dx3 := p00.x - p10.x + p11.x - p01.x
	var dy1 := p10.y - p11.y
	var dy2 := p01.y - p11.y
	var dy3 := p00.y - p10.y + p11.y - p01.y
	var denominator := dx1 * dy2 - dx2 * dy1
	if absf(denominator) < 0.00001:
		return []
	var g := (dx3 * dy2 - dx2 * dy3) / denominator
	var h := (dx1 * dy3 - dx3 * dy1) / denominator
	var a := p10.x - p00.x + g * p10.x
	var b := p01.x - p00.x + h * p01.x
	var c := p00.x
	var d := p10.y - p00.y + g * p10.y
	var e := p01.y - p00.y + h * p01.y
	var f := p00.y
	var determinant := a * (e - f * h) - b * (d - f * g) + c * (d * h - e * g)
	if absf(determinant) < 0.00001:
		return []
	return [
		Vector3((e - f * h) / determinant, (c * h - b) / determinant, (b * f - c * e) / determinant),
		Vector3((f * g - d) / determinant, (a - c * g) / determinant, (c * d - a * f) / determinant),
		Vector3((d * h - e * g) / determinant, (b * g - a * h) / determinant, (a * e - b * d) / determinant)
	]


func _rebuild_debug_overlay() -> void:
	for child in debug_overlay.get_children():
		child.queue_free()
	var plane_colors := [Color("4cc9f0"), Color("f72585"), Color("b9fbc0"), Color("ffd166")]
	for plane_index in planes.size():
		var plane: Dictionary = planes[plane_index]
		var line := Line2D.new()
		var points := PackedVector2Array(plane["points"])
		points.append(points[0])
		line.points = points
		line.width = 1.0
		line.default_color = plane_colors[int(plane["depth_layer"]) % plane_colors.size()]
		line.antialiased = false
		debug_overlay.add_child(line)
		var center := Vector2.ZERO
		for point in plane["points"]:
			center += point
		center /= 4.0
		var plane_label := Label.new()
		plane_label.text = plane["name"]
		plane_label.position = center - Vector2(12, 3)
		plane_label.add_theme_font_size_override("font_size", 5)
		plane_label.add_theme_color_override("font_color", line.default_color)
		plane_label.add_theme_color_override("font_outline_color", Color.BLACK)
		plane_label.add_theme_constant_override("outline_size", 1)
		debug_overlay.add_child(plane_label)
	for marker_index in detected_markers.size():
		var marker := detected_markers[marker_index]
		var diamond := Polygon2D.new()
		diamond.polygon = PackedVector2Array([marker + Vector2(0, -2), marker + Vector2(2, 0), marker + Vector2(0, 2), marker + Vector2(-2, 0)])
		diamond.color = Color("ff3030")
		debug_overlay.add_child(diamond)
		var marker_label := Label.new()
		marker_label.text = "%02d" % marker_index
		marker_label.position = marker + Vector2(2, -6)
		marker_label.add_theme_font_size_override("font_size", 5)
		marker_label.add_theme_color_override("font_color", Color("ff8080"))
		marker_label.add_theme_color_override("font_outline_color", Color.BLACK)
		marker_label.add_theme_constant_override("outline_size", 1)
		debug_overlay.add_child(marker_label)
