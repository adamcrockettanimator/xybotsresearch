@tool
## GPU cage barrel: semantic pieces are real, fixed mesh ribbons/panels.
##
## At runtime the CPU supplies only the barrel transform and camera basis. The
## 8 x 5 cage is static GPU geometry; it is rasterized in the shared 160 x 120
## viewport before nearest-neighbour enlargement. The optional wireframe is an
## authoring-only CPU projection drawn over the full-resolution game view.
extends Node2D

const CAGE_SHADER := preload("res://scripts/semantic_gpu_cage_barrel.gdshader")
const STYLE_PATH := "res://resources/gpu_cage_barrel_style.tres"
const STYLE_SCRIPT := preload("res://scripts/semantic_gpu_cage_barrel_style.gd")
const SIDES := 8
var cage_rows := [0.0, 0.25, 0.50, 0.75, 1.0]
const LOGICAL_VIEW_SIZE := Vector2i(160, 120)


class FullResolutionLatticeOverlay extends Node2D:
	var rows: Array[PackedVector2Array] = []
	var semantic_outlines: Array[Dictionary] = []
	const COLOUR := Color(0.10, 1.0, 0.90, 0.96)

	func set_lattice(new_rows: Array[PackedVector2Array]) -> void:
		rows = new_rows
		queue_redraw()

	func set_semantic_outlines(new_outlines: Array[Dictionary]) -> void:
		semantic_outlines = new_outlines
		queue_redraw()

	func _draw_outline(points: PackedVector2Array, colour: Color, width: float, closed := true) -> void:
		for index in points.size() - 1:
			draw_line(points[index], points[index + 1], colour, width, false)
		if closed and points.size() > 2:
			draw_line(points[points.size() - 1], points[0], colour, width, false)

	func _draw() -> void:
		if rows.is_empty() and semantic_outlines.is_empty():
			return
		var scale := maxf(get_global_transform().x.length(), get_global_transform().y.length())
		var width := 1.0 / maxf(scale, 1.0)
		if not rows.is_empty():
			for row in rows:
				for side in row.size():
					draw_line(row[side], row[(side + 1) % row.size()], COLOUR, width, false)
			for side in SIDES:
				for row in rows.size() - 1:
					draw_line(rows[row][side], rows[row + 1][side], COLOUR, width, false)
			for row in rows:
				for point in row:
					draw_line(point - Vector2(width * 2.0, 0.0), point + Vector2(width * 2.0, 0.0), Color.WHITE, width, false)
					draw_line(point - Vector2(0.0, width * 2.0), point + Vector2(0.0, width * 2.0), Color.WHITE, width, false)
		for outline in semantic_outlines:
			_draw_outline(outline.get("points", PackedVector2Array()), outline.get("colour", Color.WHITE), width, bool(outline.get("closed", true)))


@export_category("GPU cage barrel")
@export var show_gpu_lattice_wireframe := false
@export var show_gpu_semantic_geometry_debug := false # Full-resolution authoring overlay; never rendered into the 160x120 game target.
@export var wood_edge := Color8(54, 30, 12)
@export var wood_centre := Color8(142, 86, 42)
@export var interior_colour := Color8(42, 20, 8)
@export var interior_shadow_colour := Color8(12, 5, 2)
@export var interior_highlight_colour := Color8(112, 62, 27)
@export_range(0.75, 1.0, 0.01) var interior_radius_fraction := 1.0
@export var lid_colour := Color8(157, 95, 47)
## A fraction of the barrel's outer radius. Keeping this below 1 exposes the rim.
@export_range(0.10, 1.0, 0.01) var lid_radius_fraction := 0.78
## Vertical position within the barrel: 1.0 is level with the top rim.
@export_range(0.0, 1.0, 0.01) var lid_height_fraction := 0.94
@export var lid_stave_colour := Color8(91, 50, 22)
@export var lid_stave_highlight_colour := Color8(216, 153, 83)
@export_range(0, 4, 1) var lid_stave_width_logical_pixels := 1
@export var rim_colour := Color8(196, 135, 72)
@export var rim_highlight_colour := Color8(241, 193, 119)
@export var metal_dark := Color8(57, 59, 54)
@export var metal_light := Color8(181, 188, 176)
@export var hoop_shadow_colour := Color8(35, 38, 34)
@export var hoop_highlight_colour := Color8(220, 226, 215)
@export var stave_shadow_colour := Color8(56, 28, 10)
@export var stave_highlight_colour := Color8(216, 153, 83)
@export var floor_shadow_colour := Color(0.10, 0.06, 0.025, 0.34)

@export_category("GPU cage style")
@export_range(0.0, 0.40, 0.01) var barrel_swell := 0.20
@export_range(0.05, 0.95, 0.01) var lower_hoop_height_from_floor := 0.30
@export_range(0.05, 0.95, 0.01) var upper_hoop_height_from_floor := 0.70
@export_range(1, 8, 1) var hoop_width_logical_pixels := 2
@export_range(1, 4, 1) var rim_highlight_width_logical_pixels := 1
@export_range(1, 16, 1) var interior_rim_width_logical_pixels := 4
@export_range(0, 4, 1) var stave_shadow_width_logical_pixels := 1
@export_range(0, 4, 1) var stave_highlight_width_logical_pixels := 1
## Higher values pull stave seams farther in from the barrel's side silhouette.
@export_range(0.0, 0.90, 0.01) var stave_silhouette_cutoff := 0.32
## Retained in saved styles from the former ground-fan shadow. The new bottom
## rim accent is always one logical pixel, so this is intentionally hidden.
@export_storage var floor_shadow_radius := 1.30
@export_range(0.0, 1.0, 0.05) var floor_shadow_opacity := 0.55
@export_range(0.0, 2.0, 0.05) var stave_bottom_light := 0.65
@export_range(0.0, 2.0, 0.05) var stave_top_light := 1.10

@export_category("Interior opening LOD")
## The interior is full-strength once the opening is at least this many logical pixels tall.
@export_range(0.0, 16.0, 0.25) var interior_full_opening_logical_pixels := 4.0
## The interior is omitted once the apparent opening is this thin or thinner.
@export_range(0.0, 16.0, 0.25) var interior_hidden_opening_logical_pixels := 1.0

@export_category("Per-detail distance LOD")
## Each pair is a hold distance followed by a fully-hidden distance. The gap is the fade length.
@export_range(0.10, 12.0, 0.05) var stave_detail_full_distance := 2.50
@export_range(0.15, 16.0, 0.05) var stave_detail_hidden_distance := 4.50
@export_range(0.10, 12.0, 0.05) var hoop_accent_full_distance := 2.50
@export_range(0.15, 16.0, 0.05) var hoop_accent_hidden_distance := 4.50
## Bright outer hoop edge: hold distance, then fade-out endpoint.
@export_range(0.10, 12.0, 0.05) var hoop_highlight_full_distance := 2.50
@export_range(0.15, 16.0, 0.05) var hoop_highlight_hidden_distance := 3.20
## Dark inner hoop contact edge: hold distance, then fade-out endpoint.
@export_range(0.10, 12.0, 0.05) var hoop_shadow_full_distance := 3.90
@export_range(0.15, 16.0, 0.05) var hoop_shadow_hidden_distance := 4.50
@export_range(0.10, 12.0, 0.05) var rim_highlight_full_distance := 2.00
@export_range(0.15, 16.0, 0.05) var rim_highlight_hidden_distance := 3.50
## The structural wood rim remains at its selected width through this distance.
@export_range(0.10, 12.0, 0.05) var rim_width_full_distance := 2.00
## The structural wood rim smoothly narrows to exactly one logical pixel by this distance.
@export_range(0.15, 20.0, 0.05) var rim_one_pixel_distance := 4.50
@export_range(0.10, 12.0, 0.05) var floor_shadow_full_distance := 2.50
@export_range(0.15, 16.0, 0.05) var floor_shadow_hidden_distance := 4.50

@export_category("Live distance capture")
## Live camera-to-barrel view depth, in the exact world units used by all LOD tests.
## This is a readout, not a style value, and is never saved into the .tres.
@export var current_camera_distance_readout := 0.0
@export_enum("Staves and lid seams", "Hoop metal width", "Hoop highlight", "Hoop shadow", "Rim highlight", "Rim width", "Floor shadow", "All details") var distance_capture_target := "Staves and lid seams"
# Tool-button exports take a callable method reference. Creating a Callable
# from `self` here happens before this Node has been initialized and produced
# the `null::null` callback seen in the editor.
@export_tool_button("Capture current distance as FULL", "Save") var capture_distance_as_full_action = capture_current_distance_as_full
@export_tool_button("Capture current distance as HIDDEN", "Save") var capture_distance_as_hidden_action = capture_current_distance_as_hidden

var viewport: SubViewport
var logical_root: Node2D
var display: Sprite2D
var wireframe: FullResolutionLatticeOverlay
var materials: Array[ShaderMaterial] = []
var barrel_style: Resource
var _last_saved_style_values: Dictionary = {}


func _ready() -> void:
	_load_or_create_style()
	_normalise_distance_ranges()
	_build_static_cage()


## Remote Inspector adjustments are copied into a real .tres resource once per
## changed value set. The runtime node remains the convenient control surface,
## but its look now survives stopping and restarting the game.
func _process(_delta: float) -> void:
	if barrel_style == null:
		_load_or_create_style()
	_normalise_distance_ranges()
	var current_values := _style_values_from_inspector()
	if current_values == _last_saved_style_values:
		return
	for key in current_values:
		barrel_style.set(key, current_values[key])
	barrel_style.emit_changed()
	var error := ResourceSaver.save(barrel_style, STYLE_PATH)
	if error != OK:
		push_error("Could not save GPU cage barrel style (%s)." % error)
		return
	_last_saved_style_values = current_values


func _normalise_distance_ranges() -> void:
	# A fade must run from near to far. The earlier saved hoop values had this
	# backwards (1.50 full / 0.65 hidden), which collapsed the transition into a
	# pop once the shader guarded against reversed smoothstep arguments.
	# Keep a useful minimum range so the three hoop phases can be seen.
	hoop_accent_hidden_distance = maxf(hoop_accent_hidden_distance, hoop_accent_full_distance + 1.0)
	hoop_highlight_hidden_distance = maxf(hoop_highlight_hidden_distance, hoop_highlight_full_distance + 0.01)
	hoop_shadow_hidden_distance = maxf(hoop_shadow_hidden_distance, hoop_shadow_full_distance + 0.01)
	# Preserve an already-authored one-pixel endpoint when this newer "full
	# width" control first appears in an old saved style. Move the start of the
	# transition back instead of silently changing the artist's endpoint.
	if rim_one_pixel_distance <= rim_width_full_distance:
		rim_width_full_distance = maxf(0.10, rim_one_pixel_distance - 1.0)


func _load_or_create_style() -> void:
	var inspector_values := _style_values_from_inspector()
	var style_exists := ResourceLoader.exists(STYLE_PATH)
	barrel_style = load(STYLE_PATH) if style_exists else STYLE_SCRIPT.new()
	if barrel_style == null:
		barrel_style = STYLE_SCRIPT.new()
	# A newly introduced, all-default resource must not erase adjustments that
	# are still alive on the running Remote node. Adopt those values once, then
	# future launches correctly treat the resource as the source of truth.
	if not style_exists or (_style_is_pristine(barrel_style) and inspector_values != _default_style_values()):
		for key in inspector_values:
			barrel_style.set(key, inspector_values[key])
		barrel_style.emit_changed()
		var error := ResourceSaver.save(barrel_style, STYLE_PATH)
		if error != OK:
			push_error("Could not create GPU cage barrel style (%s)." % error)
		_last_saved_style_values = inspector_values
		return
	for key in inspector_values:
		set(key, barrel_style.get(key))
	_last_saved_style_values = _style_values_from_inspector()


func _default_style_values() -> Dictionary:
	var defaults: Resource = STYLE_SCRIPT.new()
	var values: Dictionary = {}
	for key in _style_values_from_inspector():
		values[key] = defaults.get(key)
	return values


func _style_is_pristine(style: Resource) -> bool:
	var defaults := _default_style_values()
	for key in defaults:
		if style.get(key) != defaults[key]:
			return false
	return true


func _style_values_from_inspector() -> Dictionary:
	return {
		"wood_edge": wood_edge, "wood_centre": wood_centre,
		"interior_colour": interior_colour, "interior_shadow_colour": interior_shadow_colour,
		"interior_highlight_colour": interior_highlight_colour, "interior_radius_fraction": interior_radius_fraction,
		"lid_colour": lid_colour, "lid_radius_fraction": lid_radius_fraction,
		"lid_height_fraction": lid_height_fraction, "lid_stave_colour": lid_stave_colour,
		"lid_stave_highlight_colour": lid_stave_highlight_colour,
		"lid_stave_width_logical_pixels": lid_stave_width_logical_pixels,
		"rim_colour": rim_colour, "rim_highlight_colour": rim_highlight_colour,
		"metal_dark": metal_dark, "metal_light": metal_light,
		"hoop_shadow_colour": hoop_shadow_colour, "hoop_highlight_colour": hoop_highlight_colour,
		"stave_shadow_colour": stave_shadow_colour, "stave_highlight_colour": stave_highlight_colour,
		"floor_shadow_colour": floor_shadow_colour, "barrel_swell": barrel_swell,
		"lower_hoop_height_from_floor": lower_hoop_height_from_floor,
		"upper_hoop_height_from_floor": upper_hoop_height_from_floor,
		"hoop_width_logical_pixels": hoop_width_logical_pixels,
		"rim_highlight_width_logical_pixels": rim_highlight_width_logical_pixels,
		"interior_rim_width_logical_pixels": interior_rim_width_logical_pixels,
		"stave_shadow_width_logical_pixels": stave_shadow_width_logical_pixels,
		"stave_highlight_width_logical_pixels": stave_highlight_width_logical_pixels,
		"stave_silhouette_cutoff": stave_silhouette_cutoff,
		"floor_shadow_radius": floor_shadow_radius, "floor_shadow_opacity": floor_shadow_opacity,
		"stave_bottom_light": stave_bottom_light, "stave_top_light": stave_top_light,
		"interior_full_opening_logical_pixels": interior_full_opening_logical_pixels,
		"interior_hidden_opening_logical_pixels": interior_hidden_opening_logical_pixels,
		"stave_detail_full_distance": stave_detail_full_distance,
		"stave_detail_hidden_distance": stave_detail_hidden_distance,
		"hoop_accent_full_distance": hoop_accent_full_distance,
		"hoop_accent_hidden_distance": hoop_accent_hidden_distance,
		"hoop_highlight_full_distance": hoop_highlight_full_distance,
		"hoop_highlight_hidden_distance": hoop_highlight_hidden_distance,
		"hoop_shadow_full_distance": hoop_shadow_full_distance,
		"hoop_shadow_hidden_distance": hoop_shadow_hidden_distance,
		"rim_highlight_full_distance": rim_highlight_full_distance,
		"rim_highlight_hidden_distance": rim_highlight_hidden_distance,
		"rim_width_full_distance": rim_width_full_distance,
		"rim_one_pixel_distance": rim_one_pixel_distance,
		"floor_shadow_full_distance": floor_shadow_full_distance,
		"floor_shadow_hidden_distance": floor_shadow_hidden_distance,
	}


func set_barrel(center: Vector2, radius: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> void:
	var camera_distance := maxf((center - camera_origin).dot(camera_forward), 0.02)
	current_camera_distance_readout = camera_distance
	for material in materials:
		material.set_shader_parameter("camera_origin", camera_origin)
		material.set_shader_parameter("camera_forward", camera_forward)
		material.set_shader_parameter("camera_right", camera_right)
		material.set_shader_parameter("projection_offset", projection_offset)
		material.set_shader_parameter("barrel_center", center)
		material.set_shader_parameter("barrel_radius", radius)
		material.set_shader_parameter("barrel_height", height)
		material.set_shader_parameter("barrel_swell", barrel_swell)
		material.set_shader_parameter("interior_radius_fraction", interior_radius_fraction)
		material.set_shader_parameter("lower_hoop_height", lower_hoop_height_from_floor)
		material.set_shader_parameter("upper_hoop_height", upper_hoop_height_from_floor)
		material.set_shader_parameter("hoop_width_pixels", float(hoop_width_logical_pixels))
		material.set_shader_parameter("rim_highlight_width_pixels", float(rim_highlight_width_logical_pixels))
		material.set_shader_parameter("interior_rim_width_pixels", float(interior_rim_width_logical_pixels))
		material.set_shader_parameter("stave_shadow_width_pixels", float(stave_shadow_width_logical_pixels))
		material.set_shader_parameter("stave_highlight_width_pixels", float(stave_highlight_width_logical_pixels))
		material.set_shader_parameter("stave_silhouette_cutoff", stave_silhouette_cutoff)
		material.set_shader_parameter("floor_shadow_radius", floor_shadow_radius)
		material.set_shader_parameter("floor_shadow_opacity", floor_shadow_opacity)
		material.set_shader_parameter("camera_distance", camera_distance)
		material.set_shader_parameter("interior_full_opening_pixels", interior_full_opening_logical_pixels)
		material.set_shader_parameter("interior_hidden_opening_pixels", minf(interior_hidden_opening_logical_pixels, interior_full_opening_logical_pixels))
		material.set_shader_parameter("wood_edge", wood_edge)
		material.set_shader_parameter("wood_centre", wood_centre)
		material.set_shader_parameter("interior_colour", interior_colour)
		material.set_shader_parameter("interior_shadow_colour", interior_shadow_colour)
		material.set_shader_parameter("interior_highlight_colour", interior_highlight_colour)
		material.set_shader_parameter("lid_colour", lid_colour)
		material.set_shader_parameter("lid_radius_fraction", lid_radius_fraction)
		material.set_shader_parameter("lid_height_fraction", lid_height_fraction)
		material.set_shader_parameter("lid_stave_colour", lid_stave_colour)
		material.set_shader_parameter("lid_stave_highlight_colour", lid_stave_highlight_colour)
		material.set_shader_parameter("lid_stave_width_pixels", float(lid_stave_width_logical_pixels))
		material.set_shader_parameter("rim_colour", rim_colour)
		material.set_shader_parameter("rim_highlight_colour", rim_highlight_colour)
		material.set_shader_parameter("metal_dark", metal_dark)
		material.set_shader_parameter("metal_light", metal_light)
		material.set_shader_parameter("hoop_shadow_colour", hoop_shadow_colour)
		material.set_shader_parameter("hoop_highlight_colour", hoop_highlight_colour)
		material.set_shader_parameter("stave_shadow_colour", stave_shadow_colour)
		material.set_shader_parameter("stave_highlight_colour", stave_highlight_colour)
		material.set_shader_parameter("floor_shadow_colour", floor_shadow_colour)
		material.set_shader_parameter("stave_bottom_light", stave_bottom_light)
		material.set_shader_parameter("stave_top_light", stave_top_light)
		material.set_shader_parameter("stave_detail_full_distance", stave_detail_full_distance)
		material.set_shader_parameter("stave_detail_hidden_distance", maxf(stave_detail_hidden_distance, stave_detail_full_distance + 0.01))
		material.set_shader_parameter("hoop_accent_full_distance", hoop_accent_full_distance)
		material.set_shader_parameter("hoop_accent_hidden_distance", maxf(hoop_accent_hidden_distance, hoop_accent_full_distance + 0.01))
		material.set_shader_parameter("hoop_highlight_full_distance", hoop_highlight_full_distance)
		material.set_shader_parameter("hoop_highlight_hidden_distance", maxf(hoop_highlight_hidden_distance, hoop_highlight_full_distance + 0.01))
		material.set_shader_parameter("hoop_shadow_full_distance", hoop_shadow_full_distance)
		material.set_shader_parameter("hoop_shadow_hidden_distance", maxf(hoop_shadow_hidden_distance, hoop_shadow_full_distance + 0.01))
		material.set_shader_parameter("rim_highlight_full_distance", rim_highlight_full_distance)
		material.set_shader_parameter("rim_highlight_hidden_distance", maxf(rim_highlight_hidden_distance, rim_highlight_full_distance + 0.01))
		material.set_shader_parameter("rim_width_full_distance", rim_width_full_distance)
		material.set_shader_parameter("rim_one_pixel_distance", rim_one_pixel_distance)
		material.set_shader_parameter("floor_shadow_full_distance", floor_shadow_full_distance)
		material.set_shader_parameter("floor_shadow_hidden_distance", maxf(floor_shadow_hidden_distance, floor_shadow_full_distance + 0.01))
	wireframe.visible = show_gpu_lattice_wireframe or show_gpu_semantic_geometry_debug
	var lattice_rows: Array[PackedVector2Array] = []
	var semantic_outlines: Array[Dictionary] = []
	if show_gpu_lattice_wireframe:
		lattice_rows = _project_debug_lattice(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset)
	if show_gpu_semantic_geometry_debug:
		semantic_outlines = _project_debug_semantic_geometry(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset)
	wireframe.set_lattice(lattice_rows)
	wireframe.set_semantic_outlines(semantic_outlines)
	visible = true


func capture_current_distance_as_full() -> void:
	_capture_current_distance(true)


func capture_current_distance_as_hidden() -> void:
	_capture_current_distance(false)


func _capture_current_distance(capturing_full_distance: bool) -> void:
	var captured_distance := maxf(current_camera_distance_readout, 0.02)
	match distance_capture_target:
		"Staves and lid seams":
			if capturing_full_distance:
				stave_detail_full_distance = captured_distance
			else:
				stave_detail_hidden_distance = captured_distance
		"Hoop metal width":
			if capturing_full_distance:
				hoop_accent_full_distance = captured_distance
			else:
				hoop_accent_hidden_distance = captured_distance
		"Hoop highlight":
			if capturing_full_distance:
				hoop_highlight_full_distance = captured_distance
			else:
				hoop_highlight_hidden_distance = captured_distance
		"Hoop shadow":
			if capturing_full_distance:
				hoop_shadow_full_distance = captured_distance
			else:
				hoop_shadow_hidden_distance = captured_distance
		"Rim highlight":
			if capturing_full_distance:
				rim_highlight_full_distance = captured_distance
			else:
				rim_highlight_hidden_distance = captured_distance
		"Rim width":
			if capturing_full_distance:
				rim_width_full_distance = captured_distance
			else:
				rim_one_pixel_distance = captured_distance
		"Floor shadow":
			if capturing_full_distance:
				floor_shadow_full_distance = captured_distance
			else:
				floor_shadow_hidden_distance = captured_distance
		"All details":
			if capturing_full_distance:
				stave_detail_full_distance = captured_distance
				hoop_accent_full_distance = captured_distance
				hoop_highlight_full_distance = captured_distance
				hoop_shadow_full_distance = captured_distance
				rim_highlight_full_distance = captured_distance
				floor_shadow_full_distance = captured_distance
			else:
				stave_detail_hidden_distance = captured_distance
				hoop_accent_hidden_distance = captured_distance
				hoop_highlight_hidden_distance = captured_distance
				hoop_shadow_hidden_distance = captured_distance
				rim_highlight_hidden_distance = captured_distance
				floor_shadow_hidden_distance = captured_distance
				rim_highlight_hidden_distance = captured_distance
				floor_shadow_hidden_distance = captured_distance
	notify_property_list_changed()


func _build_static_cage() -> void:
	viewport = SubViewport.new()
	viewport.name = "GpuCageLogicalViewport_160x120"
	viewport.size = LOGICAL_VIEW_SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	logical_root = Node2D.new()
	logical_root.name = "GpuCageSemanticPieces"
	viewport.add_child(logical_root)
	display = Sprite2D.new()
	display.name = "GpuCagePixels_160x120"
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.texture = viewport.get_texture()
	add_child(display)
	wireframe = FullResolutionLatticeOverlay.new()
	wireframe.name = "FullResolutionLatticeWireframe_AuthoringOnly"
	wireframe.z_index = 50
	wireframe.visible = false
	add_child(wireframe)

	# The former floor fan made a sideways ground blob. This is instead a
	# one-logical-pixel dark accent anchored to the bottom cage ring, mirroring
	# the top rim highlight and preserving the barrel's silhouette.
	_add_piece("01 Bottom rim shadow_8", _make_band_mesh(), 2, 1)
	# This uses the *same full cage* as the exterior. Its normal/culling rule is
	# reversed in the shader, so it is the other half of the barrel—not a lid,
	# cap, shortened wall, or a new set of points.
	_add_piece("02 Barrel interior wall_8x5", _make_body_mesh(), 1, -4)
	_add_piece("05 Outside wood panels_8x5", _make_body_mesh(), 0, 0)
	# A centred groove is the authoritative seam; the two bevel marks extend
	# from it toward their near/far panels. This prevents the low-res target
	# from exposing body colour between independently rasterized bevel halves.
	_add_piece("06 Outside stave groove cores_8x5", _make_stave_mesh(), 13, 1)
	_add_piece("06 Outside stave shadows_8x5", _make_stave_mesh(), 3, 2)
	_add_piece("06 Outside stave highlights_8x5", _make_stave_mesh(), 4, 3)
	_add_piece("07 Lower hoop shadow_8", _make_band_mesh(), 5, 4)
	_add_piece("07 Lower hoop metal_8", _make_band_mesh(), 6, 5)
	_add_piece("07 Lower hoop highlight_8", _make_band_mesh(), 7, 6)
	_add_piece("08 Upper hoop shadow_8", _make_band_mesh(), 8, 7)
	_add_piece("08 Upper hoop metal_8", _make_band_mesh(), 9, 8)
	_add_piece("08 Upper hoop highlight_8", _make_band_mesh(), 10, 9)
	# The real rim is an annulus on the top plane. Its inner edge moves toward
	# the projected centre by a clamped logical-pixel distance, never outward.
	_add_piece("10 Inner wood rim ribbon_8", _make_top_rim_mesh(), 12, 10)
	# Both rim layers now share the same top-plane annulus. The outermost slice
	# is the highlight, so it can never drift away from or warp against the rim.
	_add_piece("10 Wood rim highlight_8", _make_top_rim_mesh(), 11, 11)
	# The lid belongs immediately in front of the interior wall, but behind all
	# exterior wood, stave grooves, hoops, and rim layers. That lets it read only
	# through the opening rather than as a coloured disk pasted across the front.
	_add_piece("09 Lid_8", _make_top_lid_mesh(), 14, -3)
	_add_piece("09 Lid stave bevels_2", _make_lid_stave_mesh(), 15, -2)


func _add_piece(piece_name: String, mesh: ArrayMesh, component: int, z_order: int) -> void:
	var instance := MeshInstance2D.new()
	instance.name = piece_name
	var material := ShaderMaterial.new()
	material.shader = CAGE_SHADER
	material.set_shader_parameter("component", component)
	mesh.surface_set_material(0, material)
	instance.mesh = mesh
	instance.material = material
	instance.z_index = z_order
	logical_root.add_child(instance)
	materials.append(material)


func _project_debug_lattice(center: Vector2, radius: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array] = []
	for row_height in cage_rows:
		var row := PackedVector2Array()
		for side in SIDES:
			var radial := Vector2(cos(TAU * float(side) / float(SIDES)), sin(TAU * float(side) / float(SIDES)))
			var world := center + radial * radius * (1.0 + barrel_swell * sin(PI * row_height))
			var relative := world - camera_origin
			var depth := maxf(relative.dot(camera_forward), 0.02)
			row.append(Vector2(80.0 + relative.dot(camera_right) / depth * 128.0, 31.5 + (0.5 - height * row_height) / depth * 128.0) + projection_offset)
		output.append(row)
	return output


func _debug_project_point(center: Vector2, radius: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2, side: int, height_fraction: float, radius_scale := 1.0) -> Dictionary:
	var radial := Vector2(cos(TAU * float(side) / float(SIDES)), sin(TAU * float(side) / float(SIDES)))
	var world := center + radial * radius * (1.0 + barrel_swell * sin(PI * height_fraction)) * radius_scale
	var relative := world - camera_origin
	var depth := maxf(relative.dot(camera_forward), 0.02)
	return {"point": Vector2(80.0 + relative.dot(camera_right) / depth * 128.0, 31.5 + (0.5 - height * height_fraction) / depth * 128.0) + projection_offset, "depth": depth, "facing": radial.dot((camera_origin - center).normalized())}


func _project_debug_semantic_geometry(center: Vector2, radius: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> Array[Dictionary]:
	# This intentionally mirrors the GPU only while debugging. It outlines the
	# extra semantic pieces at full display resolution and skips their backfaces.
	var outlines: Array[Dictionary] = []
	var inner_colour := Color(0.76, 0.28, 1.0, 0.95)
	for row_index in cage_rows.size() - 1:
		for side in SIDES:
			var a: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, side, cage_rows[row_index], interior_radius_fraction)
			var b: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, (side + 1) % SIDES, cage_rows[row_index], interior_radius_fraction)
			var c: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, (side + 1) % SIDES, cage_rows[row_index + 1], interior_radius_fraction)
			var d: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, side, cage_rows[row_index + 1], interior_radius_fraction)
			if (float(a.facing) + float(b.facing) + float(c.facing) + float(d.facing)) * 0.25 <= 0.05:
				outlines.append({"points": PackedVector2Array([a.point, b.point, c.point, d.point]), "colour": inner_colour})
	# The stave pieces are three separate curved ribbon meshes attached to a
	# shared cage column: a central groove, then its near and far bevels. Show
	# their complete front-facing outlines, rather than inventing new guide lines.
	for side in SIDES:
		var stave_facing: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, side, 0.5)
		if float(stave_facing.facing) < 0.32:
			continue
		var core_left := PackedVector2Array()
		var core_right := PackedVector2Array()
		var shadow_near := PackedVector2Array()
		var shadow_far := PackedVector2Array()
		var highlight_near := PackedVector2Array()
		var highlight_far := PackedVector2Array()
		for row_height in cage_rows:
			var point_data: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, side, row_height)
			var neighbour_a: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, (side + SIDES - 1) % SIDES, row_height)
			var neighbour_b: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, (side + 1) % SIDES, row_height)
			var point := Vector2(point_data.point)
			var near_neighbour := Vector2(neighbour_a.point) if float(neighbour_a.depth) < float(neighbour_b.depth) else Vector2(neighbour_b.point)
			var near_direction := (near_neighbour - point).normalized()
			core_left.append(point - near_direction * 0.5)
			core_right.append(point + near_direction * 0.5)
			shadow_near.append(point + near_direction * 0.15)
			shadow_far.append(point + near_direction * (float(stave_shadow_width_logical_pixels) + 0.15))
			highlight_near.append(point - near_direction * 0.15)
			highlight_far.append(point - near_direction * (float(stave_highlight_width_logical_pixels) + 0.15))
		var groove_outline := PackedVector2Array(core_left)
		for index in range(core_right.size() - 1, -1, -1):
			groove_outline.push_back(core_right[index])
		var shadow_outline := PackedVector2Array(shadow_near)
		for index in range(shadow_far.size() - 1, -1, -1):
			shadow_outline.push_back(shadow_far[index])
		var highlight_outline := PackedVector2Array(highlight_near)
		for index in range(highlight_far.size() - 1, -1, -1):
			highlight_outline.push_back(highlight_far[index])
		outlines.append({"points": groove_outline, "colour": Color(1.0, 0.24, 0.24, 0.95)})
		if stave_shadow_width_logical_pixels > 0:
			outlines.append({"points": shadow_outline, "colour": Color(0.20, 0.55, 1.0, 0.95)})
		if stave_highlight_width_logical_pixels > 0:
			outlines.append({"points": highlight_outline, "colour": Color(1.0, 0.95, 0.25, 0.95)})
	# Outline the three actual ribbon layers per hoop, front half only.
	for hoop_height in [lower_hoop_height_from_floor, upper_hoop_height_from_floor]:
		for offset_and_colour in [[1.0, Color(0.25, 0.40, 1.0, 0.95)], [0.0, Color(1.0, 0.75, 0.15, 0.95)], [-1.0, Color(1.0, 1.0, 0.45, 0.95)]]:
			for side in SIDES:
				var start: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, side, hoop_height)
				var finish: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, (side + 1) % SIDES, hoop_height)
				if (float(start.facing) + float(finish.facing)) * 0.5 < -0.12:
					continue
				var half_width := float(hoop_width_logical_pixels) * 0.5
				var y_offset := float(offset_and_colour[0])
				outlines.append({"points": PackedVector2Array([Vector2(start.point.x, start.point.y - half_width + y_offset), Vector2(finish.point.x, finish.point.y - half_width + y_offset), Vector2(finish.point.x, finish.point.y + half_width + y_offset), Vector2(start.point.x, start.point.y + half_width + y_offset)]), "colour": offset_and_colour[1]})
	# The old exterior rim ribbon is a front-facing one-pixel seam, separate
	# from the annulus below. It is shown in pale orange.
	for side in SIDES:
		var rim_start: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, side, 1.0)
		var rim_finish: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, (side + 1) % SIDES, 1.0)
		if (float(rim_start.facing) + float(rim_finish.facing)) * 0.5 < -0.12:
			continue
		var rim_half_width := float(rim_highlight_width_logical_pixels) * 0.5
		outlines.append({"points": PackedVector2Array([Vector2(rim_start.point.x, rim_start.point.y - rim_half_width), Vector2(rim_finish.point.x, rim_finish.point.y - rim_half_width), Vector2(rim_finish.point.x, rim_finish.point.y + rim_half_width), Vector2(rim_start.point.x, rim_start.point.y + rim_half_width)]), "colour": Color(1.0, 0.88, 0.42, 0.95)})
	# The top rim is a full annulus; its inner ring is clamped toward top centre.
	var outer_ring := PackedVector2Array()
	var inner_ring := PackedVector2Array()
	var top_centre: Dictionary = _debug_project_point(center, 0.0, height, camera_origin, camera_forward, camera_right, projection_offset, 0, 1.0)
	for side in SIDES:
		var top_point: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, side, 1.0)
		outer_ring.append(top_point.point)
		var inward := Vector2(top_centre.point) - Vector2(top_point.point)
		inner_ring.append(Vector2(top_point.point) + _debug_top_rim_inset(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, side))
	outlines.append({"points": outer_ring, "colour": Color(1.0, 0.62, 0.12, 0.95)})
	outlines.append({"points": inner_ring, "colour": Color(1.0, 0.62, 0.12, 0.95)})
	var lid_ring := PackedVector2Array()
	for side in SIDES:
		lid_ring.append(_debug_project_point(center, radius * lid_radius_fraction, height, camera_origin, camera_forward, camera_right, projection_offset, side, lid_height_fraction).point)
	outlines.append({"points": lid_ring, "colour": Color(0.94, 0.30, 0.96, 0.95)})
	# The bottom accent shares the same projected lower cage ring as the body.
	var shadow_ring := PackedVector2Array()
	for side in SIDES:
		shadow_ring.append(_debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, side, 0.0).point)
	outlines.append({"points": shadow_ring, "colour": Color(0.95, 0.25, 0.25, 0.90)})
	return outlines


func _debug_top_rim_inset(center: Vector2, radius: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2, side: int) -> Vector2:
	# Intersect the two inward-offset projected edges. This is the debug-side
	# equivalent of the shader's parallel polygon offset, not a radial pull.
	var current: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, side, 1.0)
	var previous: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, (side + SIDES - 1) % SIDES, 1.0)
	var next: Dictionary = _debug_project_point(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset, (side + 1) % SIDES, 1.0)
	var point := Vector2(current.point)
	var projected_centre: Dictionary = _debug_project_point(center, 0.0, height, camera_origin, camera_forward, camera_right, projection_offset, 0, 1.0)
	var toward_centre := (Vector2(projected_centre.point) - point).normalized()
	var previous_edge := (point - Vector2(previous.point)).normalized()
	var next_edge := (Vector2(next.point) - point).normalized()
	var normal_a := Vector2(-previous_edge.y, previous_edge.x)
	var normal_b := Vector2(-next_edge.y, next_edge.x)
	if normal_a.dot(toward_centre) < 0.0:
		normal_a = -normal_a
	if normal_b.dot(toward_centre) < 0.0:
		normal_b = -normal_b
	var bisector := (normal_a + normal_b).normalized()
	var corner_scale := float(interior_rim_width_logical_pixels) / maxf(bisector.dot(normal_a), 0.10)
	return bisector * minf(corner_scale, (Vector2(projected_centre.point) - point).length() * 0.98)


func _new_mesh(vertices: PackedVector2Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_body_mesh() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	for row_height in cage_rows:
		for side in SIDES:
			vertices.append(Vector2(float(side), row_height))
			uvs.append(Vector2(0.5, 1.0))
	var indices := PackedInt32Array()
	for row in cage_rows.size() - 1:
		for side in SIDES:
			var next_side := (side + 1) % SIDES
			var a := row * SIDES + side
			var b := row * SIDES + next_side
			var c := (row + 1) * SIDES + next_side
			var d := (row + 1) * SIDES + side
			indices.append_array(PackedInt32Array([a, b, c, a, c, d]))
	return _new_mesh(vertices, uvs, indices)


func _make_fan_mesh() -> ArrayMesh:
	# UV.y marks centre (0) vs rim (1); no per-frame coordinates are created.
	var vertices := PackedVector2Array([Vector2(0.0, 1.0)])
	var uvs := PackedVector2Array([Vector2(0.5, 0.0)])
	for side in SIDES:
		vertices.append(Vector2(float(side), 1.0))
		uvs.append(Vector2(0.5, 1.0))
	var indices := PackedInt32Array()
	for side in SIDES:
		indices.append_array(PackedInt32Array([0, side + 1, (side + 1) % SIDES + 1]))
	return _new_mesh(vertices, uvs, indices)


func _make_stave_mesh() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for side in SIDES:
		# A stroke attached to this exact cage column. The two vertices at every
		# shared row are reused by both neighboring stroke segments, which gives
		# us the panel's projected bend without the former row-join cracks.
		var base := vertices.size()
		for row_height in cage_rows:
			vertices.append(Vector2(float(side), row_height))
			uvs.append(Vector2(0.0, 1.0))
			vertices.append(Vector2(float(side), row_height))
			uvs.append(Vector2(1.0, 1.0))
		for row in cage_rows.size() - 1:
			var left_bottom := base + row * 2
			var right_bottom := left_bottom + 1
			var left_top := left_bottom + 2
			var right_top := left_bottom + 3
			indices.append_array(PackedInt32Array([left_bottom, right_bottom, right_top, left_bottom, right_top, left_top]))
	return _new_mesh(vertices, uvs, indices)


func _make_band_mesh() -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for side in SIDES:
		var next_side := (side + 1) % SIDES
		var base := vertices.size()
		for endpoint in [side, next_side]:
			vertices.append(Vector2(float(endpoint), 0.0))
			uvs.append(Vector2(0.0, 1.0))
			vertices.append(Vector2(float(endpoint), 0.0))
			uvs.append(Vector2(1.0, 1.0))
		indices.append_array(PackedInt32Array([base, base + 1, base + 3, base, base + 3, base + 2]))
	return _new_mesh(vertices, uvs, indices)


func _make_top_rim_mesh() -> ArrayMesh:
	# Every segment has an outer top-ring point and an inner point. The shader
	# moves only the inner point toward the top centre by the requested number
	# of logical pixels, clamped at that centre.
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for side in SIDES:
		var next_side := (side + 1) % SIDES
		var base := vertices.size()
		for endpoint in [side, next_side]:
			vertices.append(Vector2(float(endpoint), 1.0))
			uvs.append(Vector2(0.0, 1.0)) # Outer edge.
			vertices.append(Vector2(float(endpoint), 1.0))
			uvs.append(Vector2(1.0, 1.0)) # Inset edge.
		indices.append_array(PackedInt32Array([base, base + 1, base + 3, base, base + 3, base + 2]))
	return _new_mesh(vertices, uvs, indices)


func _make_top_lid_mesh() -> ArrayMesh:
	# Reuse the same eight top-ring vertices as the rim. Unlike the floor fan,
	# its centre uses UV.y to collapse to the barrel centre at the top plane.
	var vertices := PackedVector2Array([Vector2(0.0, 1.0)])
	var uvs := PackedVector2Array([Vector2(0.5, 0.0)])
	for side in SIDES:
		vertices.append(Vector2(float(side), 1.0))
		uvs.append(Vector2(0.5, 1.0))
	var indices := PackedInt32Array()
	for side in SIDES:
		indices.append_array(PackedInt32Array([0, side + 1, (side + 1) % SIDES + 1]))
	return _new_mesh(vertices, uvs, indices)


func _make_lid_stave_mesh() -> ArrayMesh:
	# Two parallel chord seams divide the lid into three boards. They are local
	# top-plane vectors—not radial spokes—so they never form a cross or pizza.
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for line_offset in [-0.37, 0.37]:
		var base := vertices.size()
		var x := float(line_offset)
		var half_length := sqrt(maxf(0.0, 1.0 - x * x)) * 0.88
		for y in [-half_length, half_length]:
			vertices.append(Vector2(x, y))
			uvs.append(Vector2(0.0, 0.0))
			vertices.append(Vector2(x, y))
			uvs.append(Vector2(1.0, 0.0))
		indices.append_array(PackedInt32Array([base, base + 1, base + 3, base, base + 3, base + 2]))
	return _new_mesh(vertices, uvs, indices)
