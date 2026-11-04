## An eight-corner crate: the mesh is made once, while the GPU projects and
## shades it every frame from the current camera and prop transform.
extends Node2D

const CRATE_SHADER := preload("res://scripts/semantic_gpu_lattice_crate.gdshader")
const STYLE_PATH := "res://resources/gpu_cage_crate_style.tres"
const STYLE_SCRIPT := preload("res://scripts/semantic_gpu_lattice_crate_style.gd")
const LOGICAL_VIEW_SIZE := Vector2i(160, 120)

class CrateLatticeOverlay extends Node2D:
	var faces: Array[PackedVector2Array] = []
	# Each dictionary is one *paint mask boundary* used by the crate shader.
	# They are lines only: this overlay never creates or draws a second crate.
	var semantic_strokes: Array[Dictionary] = []

	func set_faces(new_faces: Array[PackedVector2Array], new_semantic_strokes: Array[Dictionary]) -> void:
		faces = new_faces
		semantic_strokes = new_semantic_strokes
		queue_redraw()

	func _draw() -> void:
		var canvas_transform := get_global_transform_with_canvas()
		var scale_factor := maxf(canvas_transform.x.length(), 1.0)
		var width := 1.0 / scale_factor
		# The diagnostic is full-resolution, but it is still pixel art: convert
		# endpoints to actual framebuffer pixel centres before rasterizing a
		# one-pixel, non-antialiased Bresenham-style stroke.
		var snap_to_pixel := func(point: Vector2) -> Vector2:
			var canvas_point := canvas_transform * point
			return canvas_transform.affine_inverse() * (canvas_point.floor() + Vector2(0.5, 0.5))
		var draw_aliased := func(from: Vector2, to: Vector2, colour: Color) -> void:
			draw_line.call(snap_to_pixel.call(from), snap_to_pixel.call(to), colour, width, false)
		# The construction basis is only the cube's twelve physical edges.
		for face in faces:
			if face.size() != 4:
				continue
			for index in 4:
				draw_aliased.call(face[index], face[(index + 1) % 4], Color(0.05, 1.0, 0.92, 0.96))
		# Semantic geometry is separate from the cyan eight-corner construction
		# cage. The colour-coded strokes are the actual shader-mask boundaries:
		# orange frame, amber inset, purple inset shadows, yellow inset/edge
		# highlights, magenta slats, blue brace, and navy contact-shadow footprint.
		# Empty entries are deliberately omitted for culled/back-facing faces.
		for stroke in semantic_strokes:
			var points: PackedVector2Array = stroke.get("points", PackedVector2Array())
			if points.size() < 2:
				continue
			var colour: Color = stroke.get("colour", Color.WHITE)
			var closed: bool = stroke.get("closed", false)
			for index in range(points.size() - 1):
				draw_aliased.call(points[index], points[index + 1], colour)
			if closed:
				draw_aliased.call(points[points.size() - 1], points[0], colour)

class CrateLogicalRasterOverlay extends Node2D:
	# These are not freehand Canvas lines. Each segment is expanded into exact
	# cells in the same 160x120 target that holds the crate pixels.
	var strokes: Array[Dictionary] = []

	func set_strokes(new_strokes: Array[Dictionary]) -> void:
		strokes = new_strokes
		queue_redraw()

	func _draw() -> void:
		for stroke in strokes:
			var from: Vector2 = stroke.get("from", Vector2.ZERO).floor()
			var to: Vector2 = stroke.get("to", Vector2.ZERO).floor()
			var colour: Color = stroke.get("colour", Color.WHITE)
			var x0 := int(from.x)
			var y0 := int(from.y)
			var x1 := int(to.x)
			var y1 := int(to.y)
			var dx := absi(x1 - x0)
			var dy := -absi(y1 - y0)
			var sx := 1 if x0 < x1 else -1
			var sy := 1 if y0 < y1 else -1
			var error := dx + dy
			var cell_count := maxi(dx, -dy)
			var cell_index := 0
			var fade_start := int(stroke.get("fade_start_cells", 0))
			var fade_end := int(stroke.get("fade_end_cells", 0))
			while true:
				var alpha_scale := 1.0
				if fade_start > 0:
					alpha_scale = minf(alpha_scale, float(cell_index) / float(fade_start))
				if fade_end > 0:
					alpha_scale = minf(alpha_scale, float(cell_count - cell_index) / float(fade_end))
				var cell_colour := colour
				cell_colour.a *= clampf(alpha_scale, 0.0, 1.0)
				if cell_colour.a > 0.001:
					draw_rect(Rect2(Vector2(x0, y0), Vector2.ONE), cell_colour, true)
				if x0 == x1 and y0 == y1:
					break
				var doubled_error := error * 2
				if doubled_error >= dy:
					error += dy
					x0 += sx
				if doubled_error <= dx:
					error += dx
					y0 += sy
				cell_index += 1

@export_category("GPU cage crate")
@export var show_gpu_lattice_wireframe := false
@export var show_gpu_semantic_geometry_debug := false
## Comparison backend: the legacy crate emits effect cells through CPU Bresenham;
## the fragment path tests each logical pixel independently in the GPU shader.
@export_enum("CPU Bresenham reference", "GPU fragment raster") var line_raster_backend := 0
## -1 uses distance LOD; 0..4 force concept stages A..E for the authoring strip.
@export_range(-1, 4, 1) var authoring_lod_stage := -1
## Kept only to read an older F6 preset. New tuning belongs in the Remote
## Inspector fields below, exactly like the GPU cage barrel.
@export_storage var authoring_settings: Dictionary = {}

@export_category("Paint - form by axis")
@export var top_color := Color8(185, 128, 65)
@export var side_x_color := Color8(151, 94, 44)
@export var side_y_color := Color8(126, 72, 34)
## Shared bottom-to-top lighting for both side planes and their semantic parts.
@export_range(0.0, 2.0, 0.05) var side_bottom_light := 0.65
@export_range(0.0, 2.0, 0.05) var side_top_light := 1.10
@export var panel_top_color := Color8(163, 105, 50)
@export var panel_color := Color8(136, 77, 35)
@export var panel_dark_color := Color8(114, 61, 29)
@export var frame_color := Color8(207, 142, 68)
@export var inset_shadow_color := Color8(77, 42, 21)
@export var slat_color := Color8(91, 48, 23)
@export var edge_highlight_color := Color8(244, 186, 94)
@export var floor_shadow_color := Color(0.08, 0.05, 0.025, 0.45)

@export_category("Semantic pieces")
@export var lid_enabled := true
@export var panel_enabled := true
@export var slats_enabled := true
@export var diagonal_enabled := true
@export var floor_shadow_enabled := true
@export var edge_highlight_enabled := true
@export_range(0.06, 0.28, 0.01) var frame_inset := 0.14
@export_range(0.10, 12.0, 0.05) var panel_full_distance := 4.0
@export_range(0.15, 16.0, 0.05) var panel_hidden_distance := 6.0
@export_range(0.10, 12.0, 0.05) var inset_full_distance := 2.0
@export_range(0.15, 16.0, 0.05) var inset_hidden_distance := 3.5
@export_range(2, 8, 1) var slat_count := 4
@export_range(1.0, 6.0, 1.0) var diagonal_width_logical_pixels := 3.0
## Directional recess depth for the lid only; side insets use one-pixel bands.
@export_range(0.0, 0.20, 0.005) var inset_shadow_depth := 0.035
@export_range(0.0, 1.0, 0.05) var inset_shadow_strength := 0.55
@export_range(0.0, 1.0, 0.05) var floor_shadow_opacity := 0.45

@export_category("Detail distance LOD")
@export_range(0.10, 12.0, 0.05) var detail_full_distance := 2.0
@export_range(0.15, 16.0, 0.05) var detail_hidden_distance := 4.5
@export_range(0.10, 12.0, 0.05) var diagonal_full_distance := 2.5
@export_range(0.15, 16.0, 0.05) var diagonal_hidden_distance := 5.0
## Distance fade for the diagonal brace highlight, independent of the brace.
@export_range(0.10, 12.0, 0.05) var diagonal_highlight_full_distance := 1.5
@export_range(0.15, 16.0, 0.05) var diagonal_highlight_hidden_distance := 3.0
@export_range(0.5, 3.0, 0.25) var edge_highlight_width_logical_pixels := 1.0
## 0 hides the lid arms at their corner; 1 reveals them to the far frame edge.
@export_range(0.0, 1.0, 0.01) var edge_highlight_end_fade := 0.30
## Larger values soften the handoff as a face approaches the silhouette.
@export_range(0.02, 0.75, 0.01) var edge_highlight_angle_fade := 0.28
@export_range(0.10, 12.0, 0.05) var edge_highlight_full_distance := 1.5
@export_range(0.15, 16.0, 0.05) var edge_highlight_hidden_distance := 3.0
## Side-inset highlights only appear within this close camera range.
@export_range(0.10, 4.0, 0.05) var inset_side_highlight_full_distance := 0.60
@export_range(0.15, 6.0, 0.05) var inset_side_highlight_hidden_distance := 1.20
## Suppress detailed inset paint on a face approaching its silhouette.
@export_range(0.0, 1.0, 0.01) var minimum_face_ratio := 0.10
@export_range(0.25, 12.0, 0.05) var panel_max_distance := 8.0

@export_category("Live distance capture")
## Live camera-to-crate distance in the exact world units used by this crate's LOD fades.
## This is a runtime readout only; it is never saved into the crate style resource.
@export var current_camera_distance_readout := 0.0

var viewport: SubViewport
var root: Node2D
var display: Sprite2D
var materials: Array[ShaderMaterial] = []
var wireframe_overlay: CrateLatticeOverlay
var logical_raster_overlay: CrateLogicalRasterOverlay
var floor_shadow_piece: MeshInstance2D
var crate_style: Resource
var _last_saved_style_values: Dictionary = {}
const LATTICE_COLUMNS := 2
const LATTICE_ROWS := 2

func _ready() -> void:
	_load_or_create_style()
	viewport = SubViewport.new()
	viewport.name = "GpuCageCrateLogicalViewport_160x120"
	viewport.size = LOGICAL_VIEW_SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	root = Node2D.new()
	root.name = "GpuCageCrateEightCorners"
	viewport.add_child(root)
	# The crate is the literal eight-corner cube: one quad per face, repainted
	# as separate frame/panel/slat/brace strips by the shader.
	for face in range(5):
		# Layer 5 is an otherwise-transparent GPU carrier for the fragment-raster
		# Y highlight. The CPU reference mode makes it discard every fragment.
		for layer in range(6):
			var material := ShaderMaterial.new()
			material.shader = CRATE_SHADER
			material.set_meta("crate_face_index", face)
			material.set_shader_parameter("face_index", face)
			material.set_shader_parameter("surface_layer", layer)
			var piece := MeshInstance2D.new()
			piece.name = ["North", "East", "South", "West", "Lid"][face] + ["_BasePlanes", "_FrameStrips", "_InsetBoards", "_SlatStrips", "_DiagonalBrace", "_FragmentRasterCarrier"][layer]
			piece.mesh = _make_face_lattice_mesh(face, material)
			piece.material = material
			piece.z_index = 7 if layer == 4 else layer + 1
			root.add_child(piece)
			materials.append(material)
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = CRATE_SHADER
	shadow_material.set_meta("crate_face_index", 5)
	shadow_material.set_shader_parameter("face_index", 5)
	shadow_material.set_shader_parameter("surface_layer", 5)
	floor_shadow_piece = MeshInstance2D.new()
	floor_shadow_piece.name = "FloorShadow"
	floor_shadow_piece.mesh = _make_face_lattice_mesh(5, shadow_material)
	floor_shadow_piece.material = shadow_material
	floor_shadow_piece.z_index = -1
	# The contact line is drawn by the deterministic logical raster overlay.
	# Keep this old GPU carrier hidden so it cannot leave a second broken copy.
	floor_shadow_piece.visible = false
	root.add_child(floor_shadow_piece)
	materials.append(shadow_material)
	logical_raster_overlay = CrateLogicalRasterOverlay.new()
	logical_raster_overlay.name = "CrateLogicalRasterLines"
	logical_raster_overlay.z_index = 10
	root.add_child(logical_raster_overlay)
	display = Sprite2D.new()
	display.name = "GpuCageCratePixels_160x120"
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.texture = viewport.get_texture()
	add_child(display)
	wireframe_overlay = CrateLatticeOverlay.new()
	wireframe_overlay.name = "GpuCageCrateWireframe"
	wireframe_overlay.z_index = 50
	wireframe_overlay.visible = false
	add_child(wireframe_overlay)


## The Remote Inspector remains the convenient tuning surface.  Store only the
## artist controls, so its changes survive stopping and restarting the game.
func _process(_delta: float) -> void:
	if crate_style == null:
		_load_or_create_style()
	var current_values := _style_values_from_inspector()
	if current_values == _last_saved_style_values:
		return
	for key in current_values:
		crate_style.set(key, current_values[key])
	crate_style.emit_changed()
	var error := ResourceSaver.save(crate_style, STYLE_PATH)
	if error != OK:
		push_error("Could not save GPU cage crate style (%s)." % error)
		return
	_last_saved_style_values = current_values


func _load_or_create_style() -> void:
	var inspector_values := _style_values_from_inspector()
	var style_exists := ResourceLoader.exists(STYLE_PATH)
	crate_style = load(STYLE_PATH) if style_exists else STYLE_SCRIPT.new()
	if crate_style == null:
		crate_style = STYLE_SCRIPT.new()
	if not style_exists or (_style_is_pristine(crate_style) and inspector_values != _default_style_values()):
		for key in inspector_values:
			crate_style.set(key, inspector_values[key])
		crate_style.emit_changed()
		var error := ResourceSaver.save(crate_style, STYLE_PATH)
		if error != OK:
			push_error("Could not create GPU cage crate style (%s)." % error)
		_last_saved_style_values = inspector_values
		return
	for key in inspector_values:
		set(key, crate_style.get(key))
	_last_saved_style_values = _style_values_from_inspector()


func _default_style_values() -> Dictionary:
	var defaults: Resource = STYLE_SCRIPT.new()
	var values: Dictionary = {}
	for key in _style_values_from_inspector():
		values[key] = defaults.get(key)
	return values


func _style_is_pristine(style: Resource) -> bool:
	for key in _default_style_values():
		if style.get(key) != _default_style_values()[key]:
			return false
	return true


func _style_values_from_inspector() -> Dictionary:
	return {
		"top_color": top_color, "side_x_color": side_x_color, "side_y_color": side_y_color,
		"side_bottom_light": side_bottom_light, "side_top_light": side_top_light,
		"panel_top_color": panel_top_color, "panel_color": panel_color, "panel_dark_color": panel_dark_color,
		"frame_color": frame_color, "inset_shadow_color": inset_shadow_color,
		"slat_color": slat_color, "edge_highlight_color": edge_highlight_color,
		"floor_shadow_color": floor_shadow_color, "lid_enabled": lid_enabled, "panel_enabled": panel_enabled,
		"slats_enabled": slats_enabled, "diagonal_enabled": diagonal_enabled, "floor_shadow_enabled": floor_shadow_enabled,
		"edge_highlight_enabled": edge_highlight_enabled,
		"frame_inset": frame_inset, "panel_full_distance": panel_full_distance, "panel_hidden_distance": panel_hidden_distance,
		"inset_full_distance": inset_full_distance, "inset_hidden_distance": inset_hidden_distance,
		"slat_count": slat_count, "diagonal_width_logical_pixels": diagonal_width_logical_pixels,
		"inset_shadow_depth": inset_shadow_depth, "inset_shadow_strength": inset_shadow_strength,
		"floor_shadow_opacity": floor_shadow_opacity, "detail_full_distance": detail_full_distance,
		"detail_hidden_distance": detail_hidden_distance, "diagonal_full_distance": diagonal_full_distance,
		"diagonal_hidden_distance": diagonal_hidden_distance,
		"diagonal_highlight_full_distance": diagonal_highlight_full_distance,
		"diagonal_highlight_hidden_distance": diagonal_highlight_hidden_distance,
		"edge_highlight_width_logical_pixels": edge_highlight_width_logical_pixels,
		"edge_highlight_end_fade": edge_highlight_end_fade,
		"edge_highlight_angle_fade": edge_highlight_angle_fade,
		"edge_highlight_full_distance": edge_highlight_full_distance,
		"edge_highlight_hidden_distance": edge_highlight_hidden_distance,
		"inset_side_highlight_full_distance": inset_side_highlight_full_distance,
		"inset_side_highlight_hidden_distance": inset_side_highlight_hidden_distance,
		"minimum_face_ratio": minimum_face_ratio,
		"panel_max_distance": panel_max_distance,
	}

func set_crate(center: Vector2, width: float, depth: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> void:
	if materials.is_empty():
		return
	# Keep the Remote Inspector's value aligned with the shader's `length(...)`
	# camera-distance calculation, which drives every crate LOD fade.
	current_camera_distance_readout = center.distance_to(camera_origin)
	var use_fragment_raster := line_raster_backend == 1
	if logical_raster_overlay != null:
		# GPU mode retains one deterministic final overlay: the three-segment
		# front-edge Y. It is intentionally above every face carrier.
		# CPU panel strokes also sit beneath the diagonal; the GPU-only Y stays on top.
		logical_raster_overlay.z_index = 10 if use_fragment_raster else 6
		logical_raster_overlay.visible = not use_fragment_raster or edge_highlight_enabled
		if use_fragment_raster:
			logical_raster_overlay.set_strokes([])
	if floor_shadow_piece != null:
		# GPU raster mode paints contact directly on the crate's bottom silhouette
		# cells through the final carrier.  The floor-plane carrier remains unused
		# so it cannot leave a second, detached or spotty outline.
		floor_shadow_piece.visible = false
	var values := _settings_with_defaults()
	var inset := clampf(frame_inset, 0.06, 0.28)
	# The diagonal's lit edge is based on which projected side of the crate owns
	# the brace: left panels expose their upper brace edge; right panels expose
	# their lower edge. This remains meaningful as the camera orbits.
	var crate_center_pixel := _project_face_uv_exact(5, 0.5, 0.5, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
	for material in materials:
		material.set_shader_parameter("fragment_raster_lines_enabled", use_fragment_raster)
		material.set_shader_parameter("final_edge_overlay_enabled", use_fragment_raster)
		material.set_shader_parameter("authoring_lod_stage", authoring_lod_stage)
		material.set_shader_parameter("camera_origin", camera_origin)
		material.set_shader_parameter("camera_forward", camera_forward)
		material.set_shader_parameter("camera_right", camera_right)
		material.set_shader_parameter("projection_offset", projection_offset)
		material.set_shader_parameter("crate_center", center)
		material.set_shader_parameter("crate_half_size", Vector2(width, depth) * 0.5)
		material.set_shader_parameter("crate_height", height)
		material.set_shader_parameter("crate_center_pixel", crate_center_pixel)
		for key in values:
			material.set_shader_parameter(key, values[key])
		var face_index := int(material.get_meta("crate_face_index", -1))
		if face_index < 0:
			continue
		var outer_bl := _project_face_uv_exact(face_index, 0.0, 0.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var outer_br := _project_face_uv_exact(face_index, 1.0, 0.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var outer_tr := _project_face_uv_exact(face_index, 1.0, 1.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var outer_tl := _project_face_uv_exact(face_index, 0.0, 1.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		material.set_shader_parameter("face_bl_pixel", outer_bl)
		material.set_shader_parameter("face_br_pixel", outer_br)
		material.set_shader_parameter("face_tr_pixel", outer_tr)
		material.set_shader_parameter("face_tl_pixel", outer_tl)
		if face_index >= 5:
			continue
		var panel_bl := _project_face_uv_exact(face_index, inset, inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var panel_br := _project_face_uv_exact(face_index, 1.0 - inset, inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var panel_tr := _project_face_uv_exact(face_index, 1.0 - inset, 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var panel_tl := _project_face_uv_exact(face_index, inset, 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var near_u_axis := camera_origin.y if face_index == 1 or face_index == 3 else camera_origin.x
		var center_u_axis := center.y if face_index == 1 or face_index == 3 else center.x
		var near_u := 1.0 if near_u_axis >= center_u_axis else 0.0
		material.set_shader_parameter("panel_bl_pixel", panel_bl)
		material.set_shader_parameter("panel_br_pixel", panel_br)
		material.set_shader_parameter("panel_tr_pixel", panel_tr)
		material.set_shader_parameter("panel_tl_pixel", panel_tl)
		# Brace orientation is deliberately canonical across every side panel:
		# local lower-left to local upper-right.  The projected slope may differ by
		# face, but the support itself is never independently flipped.
		material.set_shader_parameter("diagonal_start_pixel", panel_bl)
		material.set_shader_parameter("diagonal_end_pixel", panel_tr)
		for seam in range(8):
			var fraction := float(seam + 1) / float(slat_count + 1)
			var slat_start := _project_face_uv_exact(face_index, lerpf(inset, 1.0 - inset, fraction), inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
			var slat_end := _project_face_uv_exact(face_index, lerpf(inset, 1.0 - inset, fraction), 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
			if face_index == 4:
				slat_start = _project_face_uv_exact(face_index, inset, lerpf(inset, 1.0 - inset, fraction), center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
				slat_end = _project_face_uv_exact(face_index, 1.0 - inset, lerpf(inset, 1.0 - inset, fraction), center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
			material.set_shader_parameter("slat_start_%d" % seam, slat_start)
			material.set_shader_parameter("slat_end_%d" % seam, slat_end)
		# A side face's local U follows the horizontal world axis that lies in
		# that face: Z for east/west faces, X for north/south. Using X for all
		# faces left the foreground Y highlight stranded on the back edge after
		# walking around an east/west side.
		var near_v := 1.0 if camera_origin.y >= center.y else 0.0
		var arm_reveal := clampf(edge_highlight_end_fade, 0.0, 1.0)
		var arm_u := clampf(near_u + (arm_reveal if near_u < 0.5 else -arm_reveal), 0.0, 1.0)
		var arm_v := clampf(near_v + (arm_reveal if near_v < 0.5 else -arm_reveal), 0.0, 1.0)
		material.set_shader_parameter("edge_y_start_pixel", _project_face_uv_exact(face_index, near_u, near_v, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset))
		material.set_shader_parameter("edge_y_u_end_pixel", _project_face_uv_exact(face_index, arm_u, near_v, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset))
		material.set_shader_parameter("edge_y_v_end_pixel", _project_face_uv_exact(face_index, near_u, arm_v, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset))
		material.set_shader_parameter("edge_y_vertical_start_pixel", _project_face_uv_exact(face_index, near_u, 0.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset))
		material.set_shader_parameter("edge_y_vertical_end_pixel", _project_face_uv_exact(face_index, near_u, 1.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset))
	_update_logical_raster_lines(center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset, inset, use_fragment_raster)
	# Unlike the SubViewport source nodes, this is an intentional in-game
	# diagnostic drawn above the nearest-enlarged result.
	wireframe_overlay.visible = show_gpu_lattice_wireframe or show_gpu_semantic_geometry_debug
	if wireframe_overlay.visible:
		var faces := _project_visible_faces(center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var debug_edges: Array[PackedVector2Array] = []
		var debug_strokes: Array[Dictionary] = []
		if show_gpu_lattice_wireframe:
			# The cyan cage obeys the same Remote-tree visibility as its face pieces.
			# A hidden face has no diagnostic construction lines left behind.
			for face_index in range(faces.size()):
				debug_edges.append(faces[face_index] if _face_has_visible_piece(face_index) else PackedVector2Array())
		if show_gpu_semantic_geometry_debug:
			debug_strokes = _project_semantic_geometry(faces, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		wireframe_overlay.set_faces(debug_edges, debug_strokes)
	visible = true

func _update_logical_raster_lines(center: Vector2, width: float, depth: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2, inset: float, y_only: bool = false) -> void:
	if logical_raster_overlay == null:
		return
	var strokes: Array[Dictionary] = []
	var distance := center.distance_to(camera_origin)
	var inset_alpha := _line_detail_fade(distance, inset_full_distance, inset_hidden_distance)
	var edge_alpha := _line_detail_fade(distance, edge_highlight_full_distance, edge_highlight_hidden_distance)
	var edge_colour := edge_highlight_color
	var inset_highlight_colour := edge_colour
	inset_highlight_colour.a *= inset_alpha
	var edge_highlight_colour := edge_colour
	edge_highlight_colour.a *= edge_alpha
	var inset_shadow_colour := inset_shadow_color
	inset_shadow_colour.a *= inset_alpha
	var append_stroke := func(from: Vector2, to: Vector2, colour: Color) -> void:
		if colour.a > 0.001:
			strokes.append({"from": from, "to": to, "colour": colour})
	var append_faded_stroke := func(from: Vector2, to: Vector2, colour: Color, fade_start_cells: int, fade_end_cells: int) -> void:
		if colour.a > 0.001:
			strokes.append({"from": from, "to": to, "colour": colour, "fade_start_cells": fade_start_cells, "fade_end_cells": fade_end_cells})
	if y_only:
		if !edge_highlight_enabled or edge_alpha <= 0.0 or (authoring_lod_stage >= 0 and authoring_lod_stage < 4):
			logical_raster_overlay.set_strokes(strokes)
			return
		var camera_direction := (camera_origin - center).normalized()
		# Blend over a broad angular interval instead of choosing one nearest
		# corner by sign.  At an axis crossing, the outgoing Y fades while its
		# neighbouring incoming Y appears, matching the panel-shadow behavior.
		var x_positive_weight := smoothstep(-0.28, 0.28, camera_direction.x)
		var z_positive_weight := smoothstep(-0.28, 0.28, camera_direction.y)
		var y_reveal := clampf(edge_highlight_end_fade, 0.0, 1.0)
		var arm_fade_cells := maxi(1, roundi(1.0 + edge_highlight_end_fade * 3.0))
		for x_corner in [0.0, 1.0]:
			var x_weight := x_positive_weight if x_corner > 0.5 else 1.0 - x_positive_weight
			for z_corner in [0.0, 1.0]:
				var z_weight := z_positive_weight if z_corner > 0.5 else 1.0 - z_positive_weight
				var corner_weight := x_weight * z_weight
				if corner_weight <= 0.01:
					continue
				var candidate_colour := edge_highlight_colour
				candidate_colour.a *= corner_weight
				var lid_join := _project_face_uv_exact(4, x_corner, z_corner, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
				append_faded_stroke.call(lid_join, _project_face_uv_exact(4, clampf(x_corner + (y_reveal if x_corner < 0.5 else -y_reveal), 0.0, 1.0), z_corner, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset), candidate_colour, 0, arm_fade_cells)
				append_faded_stroke.call(lid_join, _project_face_uv_exact(4, x_corner, clampf(z_corner + (y_reveal if z_corner < 0.5 else -y_reveal), 0.0, 1.0), center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset), candidate_colour, 0, arm_fade_cells)
				# Either adjacent face describes the same vertical edge. Choose the
				# X-facing face consistently for this candidate corner.
				var vertical_face := 1 if x_corner > 0.5 else 3
				var vertical_bottom := _project_face_uv_exact(vertical_face, z_corner, 0.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
				var vertical_top := _project_face_uv_exact(vertical_face, z_corner, 1.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
				var vertical_direction := (vertical_top - vertical_bottom).normalized()
				append_faded_stroke.call(vertical_bottom + vertical_direction, vertical_top - vertical_direction, candidate_colour, 0, 2)
		logical_raster_overlay.set_strokes(strokes)
		return
	# Floor contact is the actual lower cube footprint, not the expanded old
	# carrier. It is painted last in the logical viewport, one cell at a time.
	if floor_shadow_enabled and inset_alpha > 0.0:
		var floor_bl := _project_face_uv_exact(5, 0.0, 0.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var floor_br := _project_face_uv_exact(5, 1.0, 0.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var floor_tr := _project_face_uv_exact(5, 1.0, 1.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var floor_tl := _project_face_uv_exact(5, 0.0, 1.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var floor_colour := floor_shadow_color
		floor_colour.a *= floor_shadow_opacity * inset_alpha
		append_stroke.call(floor_br if camera_origin.x >= center.x else floor_bl, floor_tr if camera_origin.x >= center.x else floor_tl, floor_colour)
		append_stroke.call(floor_tl if camera_origin.y >= center.y else floor_bl, floor_tr if camera_origin.y >= center.y else floor_br, floor_colour)
	if !edge_highlight_enabled:
		logical_raster_overlay.set_strokes(strokes)
		return
	if authoring_lod_stage >= 0 and authoring_lod_stage < 4:
		logical_raster_overlay.set_strokes(strokes)
		return
	var camera_direction := (camera_origin - center).normalized()
	for face_index in range(5):
		if face_index < 4:
			var normals := [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0)]
			if normals[face_index].dot(camera_direction) <= 0.001:
				continue
		var panel_bl := _project_face_uv_exact(face_index, inset, inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var panel_br := _project_face_uv_exact(face_index, 1.0 - inset, inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var panel_tr := _project_face_uv_exact(face_index, 1.0 - inset, 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var panel_tl := _project_face_uv_exact(face_index, inset, 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		var panel_near_u_axis := camera_origin.y if face_index == 1 or face_index == 3 else camera_origin.x
		var panel_center_u_axis := center.y if face_index == 1 or face_index == 3 else center.x
		var panel_near_u := 1.0 if panel_near_u_axis >= panel_center_u_axis else 0.0
		if face_index == 4:
			if inset_alpha > 0.0:
				append_stroke.call(panel_bl if camera_direction.x >= 0.0 else panel_br, panel_tl if camera_direction.x >= 0.0 else panel_tr, inset_highlight_colour)
				append_stroke.call(panel_bl if camera_direction.y >= 0.0 else panel_tl, panel_br if camera_direction.y >= 0.0 else panel_tr, inset_highlight_colour)
		else:
			if inset_alpha > 0.0:
				append_stroke.call(panel_bl, panel_br, inset_highlight_colour)
				# The top ledge is a recessed-panel drop shadow. Like every other
				# one-pixel effect it is drawn by the logical Bresenham pass.
				append_stroke.call(panel_tl, panel_tr, inset_shadow_colour)
				# The extrusion shadow belongs on the panel edge farthest from the
				# viewer. `near_u` is the local panel edge facing the camera, so the
				# opposite U edge is the only eligible side-shadow carrier.
				var side_view := camera_direction.y if face_index == 1 or face_index == 3 else camera_direction.x
				var side_shadow_colour := inset_shadow_colour
				side_shadow_colour.a *= clampf(absf(side_view), 0.0, 1.0)
				if panel_near_u < 0.5:
					append_stroke.call(panel_br, panel_tr, side_shadow_colour)
				else:
					append_stroke.call(panel_bl, panel_tl, side_shadow_colour)
		if edge_alpha <= 0.0:
			continue
		var near_u_axis := camera_origin.y if face_index == 1 or face_index == 3 else camera_origin.x
		var center_u_axis := center.y if face_index == 1 or face_index == 3 else center.x
		var near_u := 1.0 if near_u_axis >= center_u_axis else 0.0
		var near_v := 1.0 if camera_origin.y >= center.y else 0.0
		var reveal := clampf(edge_highlight_end_fade, 0.0, 1.0)
		var arm_u := clampf(near_u + (reveal if near_u < 0.5 else -reveal), 0.0, 1.0)
		var arm_v := clampf(near_v + (reveal if near_v < 0.5 else -reveal), 0.0, 1.0)
		var y_start := _project_face_uv_exact(face_index, near_u, near_v, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		if face_index == 4:
			# The lid arms fade only toward their outer ends; the shared Y join
			# stays solid where it meets the vertical highlight.
			var arm_fade_cells := maxi(1, roundi(1.0 + edge_highlight_end_fade * 3.0))
			append_faded_stroke.call(y_start, _project_face_uv_exact(face_index, arm_u, near_v, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset), edge_highlight_colour, 0, arm_fade_cells)
			append_faded_stroke.call(y_start, _project_face_uv_exact(face_index, near_u, arm_v, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset), edge_highlight_colour, 0, arm_fade_cells)
		else:
			# Keep the vertical arm inside both caps: the lower endpoint stops above
			# the floor-contact stroke, while the upper endpoint fades before it can
			# hang over the lid silhouette.
			var vertical_bottom := _project_face_uv_exact(face_index, near_u, 0.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
			var vertical_top := _project_face_uv_exact(face_index, near_u, 1.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
			var vertical_direction := (vertical_top - vertical_bottom).normalized()
			var safe_bottom := vertical_bottom + vertical_direction
			var safe_top := vertical_top - vertical_direction
			append_faded_stroke.call(safe_bottom, safe_top, edge_highlight_colour, 0, 2)
	logical_raster_overlay.set_strokes(strokes)

func _line_detail_fade(distance: float, full_distance: float, hidden_distance: float) -> float:
	var near_distance := minf(full_distance, hidden_distance - 0.01)
	var far_distance := maxf(hidden_distance, full_distance + 0.01)
	return 1.0 - clampf((distance - near_distance) / (far_distance - near_distance), 0.0, 1.0)

func _piece_visible(face_index: int, suffix: String) -> bool:
	if root == null:
		return false
	var face_names := ["North", "East", "South", "West", "Lid"]
	if face_index < 0 or face_index >= face_names.size():
		return false
	var piece := root.get_node_or_null("%s_%s" % [face_names[face_index], suffix]) as CanvasItem
	return piece != null and piece.is_visible_in_tree()

func _face_has_visible_piece(face_index: int) -> bool:
	for suffix in ["FrameStrips", "InsetBoards", "SlatStrips", "DiagonalBrace"]:
		if _piece_visible(face_index, suffix):
			return true
	return false

func _floor_shadow_visible() -> bool:
	var piece := logical_raster_overlay as CanvasItem
	return piece != null and piece.is_visible_in_tree()

func _project_visible_faces(center: Vector2, width: float, depth: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var cube_faces := [
		[Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
		[Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)],
		[Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(-1, 1, 1), Vector3(1, 1, 1)],
		[Vector3(-1, 0, 1), Vector3(-1, 0, -1), Vector3(-1, 1, -1), Vector3(-1, 1, 1)],
		[Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
	]
	for face_values in cube_faces:
		var projected := PackedVector2Array()
		for corner_value in face_values:
			var corner: Vector3 = corner_value
			var relative := center + Vector2(corner.x * width * 0.5, corner.z * depth * 0.5) - camera_origin
			var distance := maxf(relative.dot(camera_forward), 0.02)
			projected.append(Vector2(80.0 + relative.dot(camera_right) / distance * 128.0, 31.5 + (0.5 - corner.y * height) / distance * 128.0) + projection_offset)
		# The diagnostic is intentionally front-face only.  The shader also culls
		# side faces against the camera, so drawing their reverse side here would
		# make the assembly view claim that invisible paint is being emitted.
		var face_index := result.size()
		var side_normals: Array[Vector2] = [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0)]
		var normal: Vector2 = Vector2.ZERO if face_index == 4 else side_normals[face_index]
		if face_index == 4 or normal.dot(camera_origin - center) > 0.001:
			result.append(projected)
		else:
			result.append(PackedVector2Array())
	return result

func _project_semantic_geometry(faces: Array[PackedVector2Array], center: Vector2, width: float, depth: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> Array[Dictionary]:
	# This is a map of the shader's actual semantic masks, not a second mesh.
	# Every point follows the same perspective-correct face UV reconstruction as
	# the one-quad shader, so diagnostics remain authoritative after camera moves.
	var strokes: Array[Dictionary] = []
	var inset := clampf(float(_settings_with_defaults().get("frame_inset", 0.14)), 0.06, 0.28)
	var camera_direction := (camera_origin - center).normalized()
	for face_index in range(faces.size()):
		var face := faces[face_index]
		if face.size() != 4:
			continue
		var outer := PackedVector2Array([face[0], face[1], face[2], face[3]])
		var inner := _project_face_rect_exact(face_index, inset, inset, 1.0 - inset, 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
		# Orange/amber = the FrameStrips mesh mask. Hide its node and both
		# boundaries disappear, exactly as the authored frame does.
		if _piece_visible(face_index, "FrameStrips"):
			_add_debug_stroke(strokes, outer, Color(1.0, 0.36, 0.06, 0.95), true)
			_add_debug_stroke(strokes, inner, Color(1.0, 0.67, 0.10, 0.96), true)
		# The lid preserves its directional recess outline. Side panels show only
		# their far-edge extrusion band (purple shadow or close yellow highlight).
		if _piece_visible(face_index, "InsetBoards"):
			if face_index == 4:
				var inner_span := 1.0 - inset * 2.0
				var shifted_inner := _project_face_rect_exact(face_index, inset - camera_direction.x * inner_span * inset_shadow_depth, inset - camera_direction.y * inner_span * inset_shadow_depth, 1.0 - inset - camera_direction.x * inner_span * inset_shadow_depth, 1.0 - inset - camera_direction.y * inner_span * inset_shadow_depth, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
				_add_debug_stroke(strokes, shifted_inner, Color(0.83, 0.22, 1.0, 0.90), true)
			else:
				var top_shadow := PackedVector2Array([
					_project_face_uv_exact(face_index, inset, 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
					_project_face_uv_exact(face_index, 1.0 - inset, 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
				])
				var bottom_highlight := PackedVector2Array([
					_project_face_uv_exact(face_index, inset, inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
					_project_face_uv_exact(face_index, 1.0 - inset, inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
				])
				_add_debug_stroke(strokes, top_shadow, Color(0.83, 0.22, 1.0, 0.90), false)
				_add_debug_stroke(strokes, bottom_highlight, Color(1.0, 0.88, 0.10, 0.96), false)
				var side_view := camera_direction.y if face_index == 1 or face_index == 3 else camera_direction.x
				var left_weight := maxf(side_view, 0.0)
				var right_weight := maxf(-side_view, 0.0)
				var left_shadow := PackedVector2Array([
					_project_face_uv_exact(face_index, inset, inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
					_project_face_uv_exact(face_index, inset, 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
				])
				var right_shadow := PackedVector2Array([
					_project_face_uv_exact(face_index, 1.0 - inset, inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
					_project_face_uv_exact(face_index, 1.0 - inset, 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
				])
				if left_weight > 0.01:
					_add_debug_stroke(strokes, left_shadow, Color(0.83, 0.22, 1.0, left_weight * 0.90), false)
				if right_weight > 0.01:
					_add_debug_stroke(strokes, right_shadow, Color(0.83, 0.22, 1.0, right_weight * 0.90), false)
		# Magenta = one stroke for each internal panel seam.  `slat_count` makes
		# that many seams, dividing the inset panel (not the cube face) into equal
		# board gaps. Side seams run upright; lid seams run across the lid.
		if slats_enabled and _piece_visible(face_index, "SlatStrips"):
			var seam_count: int = maxi(2, slat_count)
			for seam in range(seam_count):
				var fraction := float(seam + 1) / float(seam_count + 1)
				var seam_points := PackedVector2Array()
				if face_index == 4:
					seam_points.append(_project_face_uv_exact(face_index, inset, lerpf(inset, 1.0 - inset, fraction), center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset))
					seam_points.append(_project_face_uv_exact(face_index, 1.0 - inset, lerpf(inset, 1.0 - inset, fraction), center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset))
				else:
					seam_points.append(_project_face_uv_exact(face_index, lerpf(inset, 1.0 - inset, fraction), inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset))
					seam_points.append(_project_face_uv_exact(face_index, lerpf(inset, 1.0 - inset, fraction), 1.0 - inset, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset))
				_add_debug_stroke(strokes, seam_points, Color(1.0, 0.08, 0.62, 0.96), false)
		# Blue = the single optional diagonal brace.  The shader deliberately omits
		# it from the lid so the top stays readable as parallel boards.
		if diagonal_enabled and face_index != 4 and _piece_visible(face_index, "DiagonalBrace"):
			_add_debug_stroke(strokes, PackedVector2Array([inner[0], inner[2]]), Color(0.15, 0.68, 1.0, 0.96), false)
		# Yellow = the interior-edge Y mask: nearest shared vertical edge plus the
		# two lid edges leaving its closest corner.
		if edge_highlight_enabled and _piece_visible(face_index, "FrameStrips"):
			var reveal := edge_highlight_end_fade
			if face_index == 4:
				var near_x := 1.0 if camera_direction.x >= 0.0 else 0.0
				var near_z := 1.0 if camera_direction.y >= 0.0 else 0.0
				var end_x := clampf(near_x + (reveal if near_x < 0.5 else -reveal), 0.0, 1.0)
				var end_z := clampf(near_z + (reveal if near_z < 0.5 else -reveal), 0.0, 1.0)
				var corner := _project_face_uv_exact(face_index, near_x, near_z, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)
				_add_debug_stroke(strokes, PackedVector2Array([corner, _project_face_uv_exact(face_index, end_x, near_z, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)]), Color(1.0, 0.94, 0.18, 0.96), false)
				_add_debug_stroke(strokes, PackedVector2Array([corner, _project_face_uv_exact(face_index, near_x, end_z, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)]), Color(1.0, 0.94, 0.18, 0.96), false)
			else:
				if face_index == 1 or face_index == 3:
					var near_u := 1.0 if camera_direction.y >= 0.0 else 0.0
					_add_debug_stroke(strokes, PackedVector2Array([_project_face_uv_exact(face_index, near_u, 0.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset), _project_face_uv_exact(face_index, near_u, 1.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset)]), Color(1.0, 0.94, 0.18, 0.96), false)
	# Navy = the two camera-facing edges of the hard one-pixel floor-contact
	# stroke. The other two floor-patch borders are intentionally absent.
	if floor_shadow_enabled and _floor_shadow_visible():
		var near_u := 1.0 if camera_direction.x >= 0.0 else 0.0
		var near_v := 1.0 if camera_direction.y >= 0.0 else 0.0
		_add_debug_stroke(strokes, PackedVector2Array([
			_project_face_uv_exact(5, near_u, 0.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
			_project_face_uv_exact(5, near_u, 1.0, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
		]), Color(0.08, 0.28, 0.52, 0.96), false)
		_add_debug_stroke(strokes, PackedVector2Array([
			_project_face_uv_exact(5, 0.0, near_v, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
			_project_face_uv_exact(5, 1.0, near_v, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
		]), Color(0.08, 0.28, 0.52, 0.96), false)
	return strokes

func _project_face_rect_exact(face_index: int, left: float, bottom: float, right: float, top: float, center: Vector2, width: float, depth: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		_project_face_uv_exact(face_index, left, bottom, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
		_project_face_uv_exact(face_index, right, bottom, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
		_project_face_uv_exact(face_index, right, top, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
		_project_face_uv_exact(face_index, left, top, center, width, depth, height, camera_origin, camera_forward, camera_right, projection_offset),
	])

func _project_face_uv_exact(face_index: int, u: float, v: float, center: Vector2, width: float, depth: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> Vector2:
	var local := Vector3.ZERO
	var x := lerpf(-1.0, 1.0, u)
	var z := lerpf(-1.0, 1.0, u)
	match face_index:
		0: local = Vector3(x, v, -1.0)
		1: local = Vector3(1.0, v, z)
		2: local = Vector3(x, v, 1.0)
		3: local = Vector3(-1.0, v, z)
		4: local = Vector3(x, 1.0, lerpf(-1.0, 1.0, v))
		# Face 5 supplies the authored floor-contact endpoints. Its mesh carrier is
		# enlarged separately in the shader so this must remain the true cube
		# footprint; using an expanded CPU projection made the shadow float away.
		5: local = Vector3(x, 0.0, lerpf(-1.0, 1.0, v))
	var relative := center + Vector2(local.x * width * 0.5, local.z * depth * 0.5) - camera_origin
	var distance := maxf(relative.dot(camera_forward), 0.02)
	return Vector2(80.0 + relative.dot(camera_right) / distance * 128.0, 31.5 + (0.5 - local.y * height) / distance * 128.0) + projection_offset

func _add_debug_stroke(strokes: Array[Dictionary], points: PackedVector2Array, colour: Color, closed: bool) -> void:
	strokes.append({"points": points, "colour": colour, "closed": closed})

func _settings_with_defaults() -> Dictionary:
	# The actual crate artist controls.  No screen-space points or generated
	# polygons are saved here: only the semantic paint and LOD intent.
	return {
		"top_color": top_color, "side_x_color": side_x_color, "side_y_color": side_y_color,
		"side_bottom_light": side_bottom_light, "side_top_light": side_top_light,
		"panel_top_color": panel_top_color, "panel_color": panel_color, "panel_dark_color": panel_dark_color,
		"shadow_color": inset_shadow_color, "inset_shadow_color": inset_shadow_color,
		"slat_color": slat_color,
		"frame_color": frame_color, "edge_highlight_color": edge_highlight_color,
		"floor_shadow_color": floor_shadow_color, "panel_enabled": panel_enabled, "lid_enabled": lid_enabled,
		"slats_enabled": slats_enabled, "diagonal_enabled": diagonal_enabled, "floor_shadow_enabled": floor_shadow_enabled,
		"edge_highlight_enabled": edge_highlight_enabled,
		"frame_inset": frame_inset, "panel_full_distance": panel_full_distance, "panel_hidden_distance": panel_hidden_distance,
		"inset_full_distance": inset_full_distance, "inset_hidden_distance": inset_hidden_distance,
		"slat_count": slat_count,
		"diagonal_width": diagonal_width_logical_pixels, "inset_shadow_depth": inset_shadow_depth,
		"inset_shadow_strength": inset_shadow_strength, "floor_shadow_opacity": floor_shadow_opacity,
		"detail_full_distance": detail_full_distance, "detail_hidden_distance": detail_hidden_distance,
		"diagonal_full_distance": diagonal_full_distance, "diagonal_hidden_distance": diagonal_hidden_distance,
		"diagonal_highlight_full_distance": diagonal_highlight_full_distance,
		"diagonal_highlight_hidden_distance": diagonal_highlight_hidden_distance,
		"edge_highlight_width_logical_pixels": edge_highlight_width_logical_pixels,
		"edge_highlight_end_fade": edge_highlight_end_fade,
		"edge_highlight_angle_fade": edge_highlight_angle_fade,
		"edge_highlight_full_distance": edge_highlight_full_distance,
		"edge_highlight_hidden_distance": edge_highlight_hidden_distance,
		"inset_side_highlight_full_distance": inset_side_highlight_full_distance,
		"inset_side_highlight_hidden_distance": inset_side_highlight_hidden_distance,
		"minimum_face_ratio": minimum_face_ratio, "panel_max_distance": panel_max_distance,
		"ground_lift": 0.0,
	}

func _make_face_lattice_mesh(face: int, material: Material) -> ArrayMesh:
	# Static semantic topology only.  There is deliberately no texture/UV array:
	# VERTEX carries the lattice's two local axes and the shader projects them.
	# Give Godot a concrete typed value before the match.  This avoids the
	# editor treating the later corner arrays as an untyped Variant on reload.
	var corners: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	match face:
		0: corners = [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1)]
		1: corners = [Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]
		2: corners = [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(-1, 1, 1), Vector3(1, 1, 1)]
		3: corners = [Vector3(-1, 0, 1), Vector3(-1, 0, -1), Vector3(-1, 1, -1), Vector3(-1, 1, 1)]
		4: corners = [Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
		_: corners = [Vector3(-1.15, 0, -1.15), Vector3(1.15, 0, -1.15), Vector3(1.15, 0, 1.15), Vector3(-1.15, 0, 1.15)]
	var vertices := PackedVector2Array()
	for row in range(LATTICE_ROWS):
		var v := float(row) / float(LATTICE_ROWS - 1)
		for column in range(LATTICE_COLUMNS):
			var u := float(column) / float(LATTICE_COLUMNS - 1)
			var corner: Vector3 = corners[0].lerp(corners[1], u).lerp(corners[3].lerp(corners[2], u), v)
			if face == 0 or face == 2:
				vertices.append(Vector2(corner.x, corner.y))
			elif face == 1 or face == 3:
				vertices.append(Vector2(corner.z, corner.y))
			else:
				vertices.append(Vector2(corner.x, corner.z))
	var indices := PackedInt32Array()
	for row in range(LATTICE_ROWS - 1):
		for column in range(LATTICE_COLUMNS - 1):
			var a := row * LATTICE_COLUMNS + column
			var b := a + 1
			var d := (row + 1) * LATTICE_COLUMNS + column
			indices.append_array(PackedInt32Array([a, b, d + 1, a, d + 1, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh
