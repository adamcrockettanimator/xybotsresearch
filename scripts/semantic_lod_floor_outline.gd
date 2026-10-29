## A live semantic floor footprint.
##
## This deliberately has no texture and no sprite anchor.  Its owner supplies
## four already-projected world corners each frame; CanvasItem then rasterizes
## the connecting one-pixel segments in the current logical viewport.
extends Node2D

const GPU_BRESENHAM_SHADER := preload("res://scripts/semantic_lod_floor_bresenham.gdshader")
const PROJECTIVE_LID_SHADER := preload("res://scripts/semantic_lod_projective_lid.gdshader")
const GROUND_CIRCLE_SHADER := preload("res://scripts/semantic_lod_ground_circle.gdshader")
const CYLINDER_SHADE_SHADER := preload("res://scripts/semantic_lod_cylinder_shade.gdshader")
const QUICK_CRATE_FACE_TEXTURE := preload("res://assets/Calibration/semantic_lod/quick_crate_face.png")
const LOGICAL_CANVAS_SIZE := Vector2(160.0, 120.0)

var projected_corners := PackedVector2Array()
var projected_edges: Array[Vector2i] = []
var line_color := Color.WHITE
var point_color := Color(1.0, 0.08, 0.08, 1.0)
var use_bresenham_reference := false
var use_gpu_bresenham := false
var use_low_resolution_vector := false
var gpu_bresenham_material: ShaderMaterial
var gpu_carrier_texture: ImageTexture
var low_resolution_viewport: SubViewport
var low_resolution_canvas: Node2D
var low_resolution_display: Sprite2D


func _ready() -> void:
	gpu_bresenham_material = ShaderMaterial.new()
	gpu_bresenham_material.shader = GPU_BRESENHAM_SHADER
	var carrier_image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	carrier_image.fill(Color.WHITE)
	gpu_carrier_texture = ImageTexture.create_from_image(carrier_image)


func _ensure_low_resolution_vector_viewport() -> void:
	if low_resolution_viewport != null:
		return
	# This is deliberately a real render target, rather than a Node2D merely
	# scaled to look low resolution. Godot rasterizes the vector strokes into
	# these 160x120 pixels before the resulting texture returns to the main view.
	low_resolution_viewport = SubViewport.new()
	low_resolution_viewport.name = "LogicalLineViewport"
	low_resolution_viewport.size = Vector2i(int(LOGICAL_CANVAS_SIZE.x), int(LOGICAL_CANVAS_SIZE.y))
	low_resolution_viewport.transparent_bg = true
	low_resolution_viewport.disable_3d = true
	low_resolution_viewport.gui_disable_input = true
	low_resolution_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(low_resolution_viewport)
	low_resolution_canvas = LogicalVectorLineCanvas.new()
	low_resolution_canvas.name = "LogicalVectorLineCanvas"
	low_resolution_viewport.add_child(low_resolution_canvas)
	low_resolution_display = Sprite2D.new()
	low_resolution_display.name = "LogicalLineTexture"
	low_resolution_display.centered = false
	low_resolution_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	low_resolution_display.texture = low_resolution_viewport.get_texture()
	add_child(low_resolution_display)


func set_projected_corners(corners: PackedVector2Array, bresenham_reference := false, gpu_bresenham := false, low_resolution_vector := false) -> void:
	set_projected_wireframe(corners, [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0)], bresenham_reference, gpu_bresenham, low_resolution_vector)


func set_projected_circle(points: PackedVector2Array) -> void:
	if low_resolution_canvas != null:
		low_resolution_canvas.circle_points = points
		low_resolution_canvas.queue_redraw()


func set_gpu_ground_circle(quad: PackedVector2Array) -> void:
	if low_resolution_canvas != null:
		low_resolution_canvas.set_gpu_ground_circle(quad)


func set_reference_barrel_style(enabled: bool) -> void:
	if low_resolution_canvas != null:
		low_resolution_canvas.reference_barrel_style = enabled
		if low_resolution_canvas.cylinder_fill != null:
			low_resolution_canvas.cylinder_fill.reference_barrel_style = enabled
			low_resolution_canvas.cylinder_fill.lid_canvas.reference_barrel_style = enabled


func set_barrel_staves(segments: PackedVector2Array) -> void:
	if low_resolution_canvas != null:
		low_resolution_canvas.barrel_staves = segments
		low_resolution_canvas.queue_redraw()


func set_reference_wood_marks(segments: PackedVector2Array) -> void:
	if low_resolution_canvas != null:
		low_resolution_canvas.wood_marks = segments
		low_resolution_canvas.queue_redraw()


func set_barrel_lid_recess(quads: Array) -> void:
	if low_resolution_canvas == null or low_resolution_canvas.cylinder_fill == null or quads.size() != 2:
		return
	var lip: PackedVector2Array = low_resolution_canvas.ring_from_quad(quads[0])
	var inset: PackedVector2Array = low_resolution_canvas.ring_from_quad(quads[1])
	low_resolution_canvas.cylinder_fill.lid_canvas.set_recess(lip, inset)


func set_barrel_lid_staves(segments: PackedVector2Array, camera_distance: float) -> void:
	if low_resolution_canvas != null and low_resolution_canvas.cylinder_fill != null:
		low_resolution_canvas.cylinder_fill.lid_canvas.set_staves(segments, camera_distance)


func set_vector_cylinder(bottom: PackedVector2Array, top: PackedVector2Array, sides: PackedVector2Array, camera_delta: Vector2, tangent_ratio: float, paths: Array, middle_quads: Array) -> void:
	if low_resolution_canvas != null:
		low_resolution_canvas.circle_points = bottom
		low_resolution_canvas.top_circle_points = top
		low_resolution_canvas.cylinder_sides = sides
		low_resolution_canvas.cylinder_view_direction = camera_delta.normalized()
		low_resolution_canvas.cylinder_tangent_ratio = tangent_ratio
		low_resolution_canvas.barrel_side_paths = paths
		low_resolution_canvas.set_cylinder_fill(bottom, top, middle_quads)
		low_resolution_canvas.queue_redraw()


func set_gpu_cylinder(bottom: PackedVector2Array, top: PackedVector2Array, sides: PackedVector2Array, camera_delta: Vector2, tangent_ratio: float, paths: Array, middle_quads: Array) -> void:
	if low_resolution_canvas != null:
		low_resolution_canvas.set_gpu_ground_circle(bottom)
		low_resolution_canvas.ground_circle.set_front_clip(camera_delta.normalized(), tangent_ratio)
		low_resolution_canvas.set_gpu_top_circle(top)
		low_resolution_canvas.top_circle.set_front_highlight(camera_delta.normalized(), tangent_ratio)
		# The final vector rim is layered above the inset and its shadows, just
		# as on the comparison barrel, to avoid losing pixels behind the recess.
		low_resolution_canvas.top_circle_points = low_resolution_canvas.ring_from_quad(top)
		low_resolution_canvas.cylinder_sides = sides
		low_resolution_canvas.cylinder_view_direction = camera_delta.normalized()
		low_resolution_canvas.cylinder_tangent_ratio = tangent_ratio
		low_resolution_canvas.barrel_side_paths = paths
		low_resolution_canvas.set_cylinder_fill(low_resolution_canvas.ring_from_quad(bottom), low_resolution_canvas.ring_from_quad(top), middle_quads)
		low_resolution_canvas.queue_redraw()


func set_projected_wireframe(corners: PackedVector2Array, edges: Array[Vector2i], bresenham_reference := false, gpu_bresenham := false, low_resolution_vector := false, flat_faces := false, camera_distance := INF, camera_delta := Vector2.ZERO) -> void:
	projected_corners = corners
	projected_edges = edges
	use_bresenham_reference = bresenham_reference
	use_gpu_bresenham = gpu_bresenham
	use_low_resolution_vector = low_resolution_vector
	if use_low_resolution_vector:
		_ensure_low_resolution_vector_viewport()
		var logical_corners := PackedVector2Array()
		for corner in projected_corners:
			logical_corners.append(corner.round())
		low_resolution_canvas.set_wireframe(logical_corners, projected_edges, line_color, point_color, QUICK_CRATE_FACE_TEXTURE, flat_faces, camera_distance, projected_corners, camera_delta)
		low_resolution_display.visible = true
		material = null
		queue_redraw()
		return
	if low_resolution_display != null:
		low_resolution_display.visible = false
	if use_gpu_bresenham:
		if gpu_bresenham_material == null:
			_ready()
		var logical_corners := PackedVector2Array()
		for corner in projected_corners:
			logical_corners.append(corner.round())
		material = gpu_bresenham_material
		gpu_bresenham_material.set_shader_parameter("logical_canvas_size", LOGICAL_CANVAS_SIZE)
		gpu_bresenham_material.set_shader_parameter("corner_a", logical_corners[0])
		gpu_bresenham_material.set_shader_parameter("corner_b", logical_corners[1])
		gpu_bresenham_material.set_shader_parameter("corner_c", logical_corners[2])
		gpu_bresenham_material.set_shader_parameter("corner_d", logical_corners[3])
		gpu_bresenham_material.set_shader_parameter("line_color", line_color)
		gpu_bresenham_material.set_shader_parameter("point_color", point_color)
	else:
		material = null
	queue_redraw()


func _draw() -> void:
	if projected_corners.is_empty() or projected_edges.is_empty():
		return
	if use_low_resolution_vector:
		return
	if use_gpu_bresenham:
		# One full logical-canvas textured primitive. The 1x1 carrier supplies
		# interpolated UVs; the fragment shader decides which pixels survive.
		draw_texture_rect(gpu_carrier_texture, Rect2(Vector2.ZERO, LOGICAL_CANVAS_SIZE), false, Color.WHITE)
		return
	# The world-corner projections remain continuous until this final drawing
	# step.  Snap each corner independently in the 160x120 logical canvas so a
	# line is always one authored game pixel wide, rather than a fractional
	# coverage strip whose apparent thickness changes with display scaling.
	var logical_corners := PackedVector2Array()
	for corner in projected_corners:
		logical_corners.append(corner.round())
	for edge in projected_edges:
		if edge.x < 0 or edge.y < 0 or edge.x >= logical_corners.size() or edge.y >= logical_corners.size():
			continue
		if use_bresenham_reference:
			_draw_logical_pixel_line(logical_corners[edge.x], logical_corners[edge.y], line_color)
		else:
			# Performance experiment: submit one hard-edged logical-pixel line for
			# each edge. CanvasItem passes four primitive strokes to the GPU;
			# unlike the reference, GDScript emits no per-covered-pixel commands.
			draw_line(logical_corners[edge.x], logical_corners[edge.y], line_color, 1.0, false)
	for corner in logical_corners:
		draw_rect(Rect2(corner, Vector2.ONE), point_color)


# The retained comparison/reference path. It is intentionally expensive so
# differences in the line primitive are visually attributable to rasterization,
# not changed projection, snapping, color, or layering.
func _draw_logical_pixel_line(from: Vector2, to: Vector2, color: Color) -> void:
	var x0 := roundi(from.x)
	var y0 := roundi(from.y)
	var x1 := roundi(to.x)
	var y1 := roundi(to.y)
	var delta_x: int = absi(x1 - x0)
	var step_x: int = 1 if x0 < x1 else -1
	var delta_y: int = -absi(y1 - y0)
	var step_y: int = 1 if y0 < y1 else -1
	var error: int = delta_x + delta_y
	while true:
		draw_rect(Rect2(Vector2(x0, y0), Vector2.ONE), color)
		if x0 == x1 and y0 == y1:
			break
		var doubled_error: int = error * 2
		if doubled_error >= delta_y:
			error += delta_y
			x0 += step_x
		if doubled_error <= delta_x:
			error += delta_x
			y0 += step_y


# A normal CanvasItem vector line, but inside the true 160x120 SubViewport
# created by the parent outline. It remains intentionally separate from the
# CPU Bresenham reference so the two rasterizers can be judged side by side.
class LogicalVectorLineCanvas extends Node2D:
	# Authored board colors from coordinate_frame_gpu_plane_homography.gdshader.
	const FLAT_TOP_COLOR := Color8(135, 108, 81)
	# Opposite sides share a world-axis tone, so the two adjoining visible
	# sides remain distinct without swapping colors as the camera moves.
	const FLAT_SIDE_X_COLOR := Color8(118, 94, 71)
	const FLAT_SIDE_Y_COLOR := Color8(101, 81, 60)
	# Semantic crate controls; distances are measured in world grid units.
	const SHOW_SEMANTIC_SILHOUETTE := false
	const SHOW_SEMANTIC_CORNER_MARKERS := false
	const INTERIOR_LINES_EXIT_DISTANCE := 1.15
	# At this distance the shared-edge color is at full strength; it fades
	# smoothly to the underlying face by INTERIOR_LINES_EXIT_DISTANCE.
	const INTERIOR_LINES_FULL_DISTANCE := 0.55
	const INTERIOR_LINE_BRIGHTENING := 0.2
	const FRAME_INSET := 0.19
	# Budget in 160x120 logical pixels, independently for each visible face.
	# Reserve the frame before spending any pixels on the recessed panel.
	const MIN_FRAME_PIXELS := 1.0
	const MIN_PANEL_SPAN_PIXELS := 1.5
	const MIN_SHADOW_PANEL_SPAN_PIXELS := 4.0
	# Blend opaque panel color toward the frame at a small projected size.
	# This is color contrast, not transparency or per-pixel dithering.
	const PANEL_INITIAL_CONTRAST := 0.18
	const PANEL_FULL_CONTRAST_SPAN := 6.0
	# Retain an enabled feature until it falls this far below its entry budget.
	const FEATURE_EXIT_MARGIN_PIXELS := 0.3
	const PANEL_SIDE_COLOR := Color8(101, 81, 60)
	const PANEL_DARK_SIDE_COLOR := Color8(82, 64, 47)
	const PANEL_TOP_COLOR := Color8(118, 94, 71)
	const PANEL_SHADOW_COLOR := Color8(78, 60, 44)
	# Set this false to use the two manual colors below. With it true, the
	# darkest/lightest opaque texels in quick_crate_face.png choose the colors.
	# Manual colors are the default so edits below take effect immediately.
	# Set true only when you specifically want darkest/lightest texture sampling.
	const USE_TEXTURE_DERIVED_LINE_COLORS := false
	const CUSTOM_SILHOUETTE_COLOR := Color(0.329, 0.239, 0.153, 1.0)
	const CUSTOM_INTERIOR_LINE_COLOR := Color(0.62, 0.541, 0.404, 1.0)
	const BARREL_OUTLINE_COLOR := Color8(67, 48, 33)
	const BARREL_HOOP_COLOR := Color8(75, 70, 61)
	const BARREL_HOOP_HIGHLIGHT_COLOR := Color8(170, 160, 140)
	const HOOP_HIGHLIGHT_FULL_DISTANCE := 0.55
	const HOOP_HIGHLIGHT_END_DISTANCE := 1.5
	const STAVE_FULL_DISTANCE := 1.0
	const STAVE_END_DISTANCE := 3.0
	const STAVE_COLOR := Color(0.24, 0.16, 0.10, 0.55)
	const STAVE_HIGHLIGHT_FULL_DISTANCE := 0.7
	const STAVE_HIGHLIGHT_END_DISTANCE := 2.0
	const STAVE_HIGHLIGHT_COLOR := Color(0.78, 0.66, 0.51, 0.50)
	var corners := PackedVector2Array()
	var circle_points := PackedVector2Array()
	var top_circle_points := PackedVector2Array()
	var cylinder_sides := PackedVector2Array()
	var barrel_side_paths: Array = []
	var barrel_hoops: Array = []
	var reference_barrel_style := false
	var barrel_staves := PackedVector2Array()
	var wood_marks := PackedVector2Array()
	var cylinder_view_direction := Vector2.ZERO
	var cylinder_tangent_ratio := 0.0
	var continuous_corners := PackedVector2Array()
	var edges: Array[Vector2i] = []
	var edge_color := Color.WHITE
	var corner_color := Color(1.0, 0.08, 0.08, 1.0)
	var face_texture: Texture2D
	var use_flat_faces := false
	var silhouette_color := CUSTOM_SILHOUETTE_COLOR
	var interior_line_color := CUSTOM_INTERIOR_LINE_COLOR
	var visible_interior_edges: Array[Vector2i] = []
	var semantic_edge_face_colors := {}
	var projective_lid: ProjectiveLidCanvas
	var ground_circle: GroundCircleCanvas
	var top_circle: GroundCircleCanvas
	var cylinder_fill: CylinderFillCanvas
	var semantic_panel_visible := {}
	var semantic_shadow_visible := {}
	# Optional live authoring overrides; the normal gallery keeps its defaults.
	var authoring_settings: Dictionary = {}
	var authoring_distance := INF
	var authoring_camera_delta := Vector2.ZERO

	func _ready() -> void:
		# The face texture is authored and sampled on the same 160x120 grid as
		# the line experiment; never let CanvasItem inherit linear filtering.
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		projective_lid = ProjectiveLidCanvas.new()
		projective_lid.name = "ProjectiveCrateLid"
		projective_lid.show_behind_parent = true
		add_child(projective_lid)
		cylinder_fill = CylinderFillCanvas.new()
		cylinder_fill.name = "CylinderShading"
		cylinder_fill.show_behind_parent = true
		add_child(cylinder_fill)
		ground_circle = GroundCircleCanvas.new()
		ground_circle.name = "GroundCircleShader"
		ground_circle.show_behind_parent = true
		ground_circle.visible = false
		add_child(ground_circle)
		top_circle = GroundCircleCanvas.new()
		top_circle.name = "TopCircleShader"
		top_circle.show_behind_parent = true
		top_circle.visible = false
		add_child(top_circle)

	func set_gpu_ground_circle(quad: PackedVector2Array) -> void:
		if ground_circle == null or projective_lid == null:
			return
		var uv := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
		var coefficients := projective_lid._screen_to_uv_coefficients(quad, uv)
		ground_circle.set_circle(quad, coefficients)

	func set_gpu_top_circle(quad: PackedVector2Array) -> void:
		if top_circle == null or projective_lid == null:
			return
		var uv := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
		top_circle.set_circle(quad, projective_lid._screen_to_uv_coefficients(quad, uv))
		# Draw the highlight only inside the same polygon used for the lid fill.
		# A full-viewport shader can otherwise shade pixels just outside the rim.
		top_circle.set_clip_polygon(ring_from_quad(quad))

	func set_cylinder_fill(bottom: PackedVector2Array, top: PackedVector2Array, middle_quads: Array = []) -> void:
		if cylinder_fill != null:
			var middle_points := PackedVector2Array()
			barrel_hoops.clear()
			for index in middle_quads.size():
				var ring := ring_from_quad(middle_quads[index])
				middle_points.append_array(ring)
				if index == 0 or index == 2:
					barrel_hoops.append(ring)
			cylinder_fill.set_rings(bottom, top, middle_points, barrel_side_paths)

	func ring_from_quad(quad: PackedVector2Array) -> PackedVector2Array:
		var result := PackedVector2Array()
		if projective_lid == null or quad.size() != 4:
			return result
		var uv := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
		var transform := projective_lid._screen_to_uv_coefficients(uv, quad)
		if transform.size() != 8:
			return result
		for index in 64:
			var angle := TAU * float(index) / 64.0
			var point := Vector2(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
			var denominator := transform[6] * point.x + transform[7] * point.y + 1.0
			if absf(denominator) < 0.000001:
				return PackedVector2Array()
			result.append(Vector2((transform[0] * point.x + transform[1] * point.y + transform[2]) / denominator, (transform[3] * point.x + transform[4] * point.y + transform[5]) / denominator))
		return result

	func set_wireframe(new_corners: PackedVector2Array, new_edges: Array[Vector2i], new_edge_color: Color, new_corner_color: Color, new_face_texture: Texture2D = null, new_flat_faces := false, camera_distance := INF, raw_corners := PackedVector2Array(), camera_delta := Vector2.ZERO) -> void:
		corners = new_corners
		continuous_corners = raw_corners if raw_corners.size() == new_corners.size() else new_corners
		edges = new_edges
		edge_color = new_edge_color
		corner_color = new_corner_color
		var texture_changed := face_texture != new_face_texture
		face_texture = new_face_texture
		use_flat_faces = new_flat_faces
		authoring_distance = camera_distance
		authoring_camera_delta = camera_delta
		# The constants are applied when this canvas is created. If automatic
		# palette sampling is enabled, read the image only when its resource
		# changes, not on every rendered frame.
		if texture_changed:
			_derive_line_colors_from_face_texture()
		if projective_lid != null:
			# Kept as an isolated prototype, but disabled: its full-canvas shader can
			# leak at far distances in the composited viewport. Use the stable
			# SubViewport polygon path below until a dedicated lid source exists.
			projective_lid.visible = false
		if ground_circle != null:
			ground_circle.visible = false
		if top_circle != null:
			top_circle.visible = false
		if cylinder_fill != null:
			cylinder_fill.visible = false
		top_circle_points.clear()
		cylinder_sides.clear()
		barrel_side_paths.clear()
		barrel_hoops.clear()
		barrel_staves.clear()
		wood_marks.clear()
		queue_redraw()

	func _draw() -> void:
		if corners.is_empty() or (edges.is_empty() and circle_points.is_empty() and cylinder_sides.is_empty()):
			return
		if corners.size() == 8 and face_texture != null:
			# Paint rear faces first, then nearer faces. Their opaque texels hide
			# any rear wire segments instead of letting the complete box wireframe
			# show through its own surfaces.  The only later outline is the convex
			# screen silhouette—never an internal or hidden edge.
			var silhouette := _draw_cube_face_test()
			if silhouette.size() >= 2 and (not use_flat_faces or SHOW_SEMANTIC_SILHOUETTE):
				var closed_silhouette := silhouette.duplicate()
				closed_silhouette.append(silhouette[0])
				draw_polyline(closed_silhouette, silhouette_color, 1.0, false)
			if not use_flat_faces or bool(authoring_settings.get("edge_enabled", true)):
				for edge in visible_interior_edges:
					var stroke := interior_line_color
					if use_flat_faces:
						var edge_key := "%d:%d" % [edge.x, edge.y]
						var adjacent: Array = semantic_edge_face_colors.get(edge_key, [])
						if adjacent.size() < 2:
							continue
						stroke = _semantic_edge_color(adjacent[0], adjacent[1], authoring_distance)
					draw_line(corners[edge.x], corners[edge.y], stroke, 1.0, false)
			if not use_flat_faces or SHOW_SEMANTIC_CORNER_MARKERS:
				for corner in silhouette:
					draw_rect(Rect2(corner, Vector2.ONE), corner_color)
			return
		for edge in edges:
			if edge.x < 0 or edge.y < 0 or edge.x >= corners.size() or edge.y >= corners.size():
				continue
			# Antialiasing stays explicitly off: the SubViewport determines the
			# final 160x120 pixel coverage before nearest-neighbor enlargement.
			draw_line(corners[edge.x], corners[edge.y], edge_color, 1.0, false)
		if circle_points.size() >= 3:
			# Keep projected vector positions continuous until the 160x120
			# SubViewport rasterizes the stroke. Rounding each vertex first makes
			# the many tiny segments jump independently as the camera moves.
			if cylinder_sides.size() == 4:
				for index in circle_points.size():
					var next := (index + 1) % circle_points.size()
					var angle_a := TAU * float(index) / float(circle_points.size())
					var angle_b := TAU * float(index + 1) / float(circle_points.size())
					var a := Vector2(cos(angle_a), sin(angle_a)).dot(cylinder_view_direction) - cylinder_tangent_ratio
					var b := Vector2(cos(angle_b), sin(angle_b)).dot(cylinder_view_direction) - cylinder_tangent_ratio
					if a < 0.0 and b < 0.0:
						continue
					var from := circle_points[index]
					var to := circle_points[next]
					if a < 0.0:
						from = from.lerp(to, -a / (b - a))
					elif b < 0.0:
						to = from.lerp(to, a / (a - b))
					draw_line(from, to, BARREL_OUTLINE_COLOR, 1.0, false)
			else:
				var logical_circle := circle_points.duplicate()
				logical_circle.append(logical_circle[0])
				draw_polyline(logical_circle, Color.BLACK, 1.0, false)
		if top_circle_points.size() >= 3:
			if cylinder_sides.size() == 4:
				# Draw the complete wooden rim after the recessed lid. At logical
				# resolution the inner shadow can otherwise occupy its same pixels.
				var rim := top_circle_points.duplicate()
				rim.append(rim[0])
				draw_polyline(rim, Color8(170, 126, 80) if reference_barrel_style else Color8(157, 129, 99), 1.0, false)
				for index in top_circle_points.size():
					var next := (index + 1) % top_circle_points.size()
					var angle_a := TAU * float(index) / float(top_circle_points.size())
					var angle_b := TAU * float(index + 1) / float(top_circle_points.size())
					var a := Vector2(cos(angle_a), sin(angle_a)).dot(cylinder_view_direction) - cylinder_tangent_ratio
					var b := Vector2(cos(angle_b), sin(angle_b)).dot(cylinder_view_direction) - cylinder_tangent_ratio
					if a < 0.0 and b < 0.0:
						continue
					var from := top_circle_points[index]
					var to := top_circle_points[next]
					if a < 0.0:
						from = from.lerp(to, -a / (b - a))
					elif b < 0.0:
						to = from.lerp(to, a / (a - b))
					draw_line(from, to, Color8(190, 162, 128), 1.0, false)
		var wood_strength := 1.0 - smoothstep(0.55, 1.5, authoring_distance)
		if wood_strength > 0.0:
			var wood_color := Color(0.36, 0.24, 0.15, 0.38 * wood_strength)
			for index in range(0, wood_marks.size() - 1, 2):
				draw_line(wood_marks[index], wood_marks[index + 1], wood_color, 1.0, false)
		var stave_strength := 1.0 - smoothstep(STAVE_FULL_DISTANCE, STAVE_END_DISTANCE, authoring_distance)
		if stave_strength > 0.0:
			var stave_color := STAVE_COLOR
			stave_color.a *= stave_strength
			var highlight_strength := 1.0 - smoothstep(STAVE_HIGHLIGHT_FULL_DISTANCE, STAVE_HIGHLIGHT_END_DISTANCE, authoring_distance)
			var stave_highlight := STAVE_HIGHLIGHT_COLOR
			stave_highlight.a *= highlight_strength
			for index in range(0, barrel_staves.size() - 1, 2):
				draw_line(barrel_staves[index], barrel_staves[index + 1], stave_color, 1.0, false)
				if highlight_strength > 0.0:
					draw_line(barrel_staves[index] + Vector2.RIGHT, barrel_staves[index + 1] + Vector2.RIGHT, stave_highlight, 1.0, false)
		# Render all shadows first so neighboring hoop segments cannot paint a
		# shadow over the metal. Clip the offset to the barrel's body silhouette.
		for hoop in barrel_hoops:
			for index in hoop.size():
				var next: int = (index + 1) % hoop.size()
				var angle_a := TAU * float(index) / float(hoop.size())
				var angle_b := TAU * float(index + 1) / float(hoop.size())
				var a := Vector2(cos(angle_a), sin(angle_a)).dot(cylinder_view_direction) - cylinder_tangent_ratio * 1.14
				var b := Vector2(cos(angle_b), sin(angle_b)).dot(cylinder_view_direction) - cylinder_tangent_ratio * 1.14
				if a < 0.0 and b < 0.0:
					continue
				var from: Vector2 = hoop[index]
				var to: Vector2 = hoop[next]
				if a < 0.0:
					from = from.lerp(to, -a / (b - a))
				elif b < 0.0:
					to = from.lerp(to, a / (a - b))
				if cylinder_fill != null and cylinder_fill.body.size() >= 3:
					var shadow_segment := PackedVector2Array([from + Vector2.DOWN, to + Vector2.DOWN])
					for clipped in Geometry2D.intersect_polyline_with_polygon(shadow_segment, cylinder_fill.body):
						if clipped.size() >= 2:
							draw_polyline(clipped, Color(0.19, 0.13, 0.09, 0.55), 1.0, false)
		for hoop in barrel_hoops:
			for index in hoop.size():
				var next: int = (index + 1) % hoop.size()
				var angle_a := TAU * float(index) / float(hoop.size())
				var angle_b := TAU * float(index + 1) / float(hoop.size())
				var a := Vector2(cos(angle_a), sin(angle_a)).dot(cylinder_view_direction) - cylinder_tangent_ratio * 1.14
				var b := Vector2(cos(angle_b), sin(angle_b)).dot(cylinder_view_direction) - cylinder_tangent_ratio * 1.14
				if a < 0.0 and b < 0.0:
					continue
				var from: Vector2 = hoop[index]
				var to: Vector2 = hoop[next]
				if a < 0.0:
					from = from.lerp(to, -a / (b - a))
				elif b < 0.0:
					to = from.lerp(to, a / (a - b))
				draw_line(from, to, BARREL_HOOP_COLOR, 1.0, false)
				var highlight_strength := 1.0 - smoothstep(HOOP_HIGHLIGHT_FULL_DISTANCE, HOOP_HIGHLIGHT_END_DISTANCE, authoring_distance)
				if highlight_strength > 0.0:
					var highlight := BARREL_HOOP_COLOR.lerp(BARREL_HOOP_HIGHLIGHT_COLOR, highlight_strength)
					draw_line(from + Vector2.UP, to + Vector2.UP, highlight, 1.0, false)
		if cylinder_sides.is_empty() and (ground_circle == null or not ground_circle.visible):
			for corner in corners:
				draw_rect(Rect2(corner, Vector2.ONE), corner_color)

	func _draw_cube_face_test() -> PackedVector2Array:
		var silhouette := PackedVector2Array()
		visible_interior_edges.clear()
		semantic_edge_face_colors.clear()
		if corners.size() != 8 or face_texture == null:
			return silhouette
		# The bottom face is the floor itself.  Sort only the four vertical faces
		# to choose the two nearest ones; the horizontal top is explicitly kept as
		# the lid regardless of camera heading.
		var side_faces: Array[PackedInt32Array] = [
			PackedInt32Array([0, 1, 5, 4]),
			PackedInt32Array([1, 2, 6, 5]),
			PackedInt32Array([2, 3, 7, 6]),
			PackedInt32Array([3, 0, 4, 7]),
		]
		var lid_face := PackedInt32Array([4, 5, 6, 7])
		var side_uvs := PackedVector2Array([
			Vector2.ZERO,
			Vector2(1.0, 0.0),
			Vector2.ONE,
			Vector2(0.0, 1.0),
		])
		# For this experiment, use the entire supplied crate image on the top
		# face too. Cropping only its upper band loses most of the crate pattern.
		var lid_uvs := PackedVector2Array([
			Vector2.ZERO,
			Vector2(1.0, 0.0),
			Vector2.ONE,
			Vector2(0.0, 1.0),
		])
		var face_colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
		# A closed box presents exactly three planes: its lid and the two nearest
		# sides.  Drawing these in that order guarantees a textured floor-parallel
		# quad before the two side panels overlap its near rim.
		var visible_faces: Array[PackedInt32Array] = [lid_face]
		var lid_winding := signf(_face_signed_area(lid_face))
		for side_face in side_faces:
			# Consistent outward winding means screen-space faces that point toward
			# the camera have the same winding as the visible lid.  This is robust
			# under turning, unlike sorting faces by vertical screen position.
			if absf(_face_signed_area(side_face)) > 0.01 and signf(_face_signed_area(side_face)) == lid_winding:
				visible_faces.append(side_face)
		if visible_faces.size() != 3:
			# Keep the test drawable at an exactly edge-on camera angle, where a
			# face has zero projected area and no winding to classify.
			side_faces.sort_custom(func(a: PackedInt32Array, b: PackedInt32Array) -> bool: return _face_average_y(a) < _face_average_y(b))
			visible_faces = [lid_face, side_faces[side_faces.size() - 2], side_faces[side_faces.size() - 1]]
		var visible_edge_counts := {}
		var visible_edge_values := {}
		for face in visible_faces:
			var polygon := PackedVector2Array([corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]]])
			var semantic_face_color := Color.WHITE
			# Both faces use the existing low-resolution texture path. A separate
			# top texture can be added later if a distinct lid design is desired.
			if use_flat_faces:
				var is_lid := face == lid_face
				var dark_side := not is_lid and face[0] % 2 == 1
				var face_color: Color = authoring_settings.get("top_color", FLAT_TOP_COLOR) if is_lid else (authoring_settings.get("side_y_color", FLAT_SIDE_Y_COLOR) if dark_side else authoring_settings.get("side_x_color", FLAT_SIDE_X_COLOR))
				if not is_lid:
					face_color = face_color.darkened(clampf(float(authoring_settings.get("lighting_shadow", 0.0)) * (1.0 if dark_side else 0.5), 0.0, 1.0))
				semantic_face_color = face_color
				draw_colored_polygon(polygon, face_color)
				var raw_polygon := PackedVector2Array([continuous_corners[face[0]], continuous_corners[face[1]], continuous_corners[face[2]], continuous_corners[face[3]]])
				_draw_semantic_panel(polygon, raw_polygon, is_lid, dark_side, 4 if is_lid else face[0], face_color)
			else:
				var uvs := lid_uvs if face == lid_face else side_uvs
				draw_polygon(polygon, face_colors, uvs, face_texture)
			for corner_index in face.size():
				var next_corner_index := (corner_index + 1) % face.size()
				var edge := Vector2i(mini(face[corner_index], face[next_corner_index]), maxi(face[corner_index], face[next_corner_index]))
				var edge_key := "%d:%d" % [edge.x, edge.y]
				visible_edge_counts[edge_key] = int(visible_edge_counts.get(edge_key, 0)) + 1
				visible_edge_values[edge_key] = edge
				if use_flat_faces:
					if not semantic_edge_face_colors.has(edge_key):
						semantic_edge_face_colors[edge_key] = []
					semantic_edge_face_colors[edge_key].append(semantic_face_color)
		# Edges shared by two selected faces are exactly the visible material
		# seams.  Their light color distinguishes form without reviving any rear
		# construction line.
		for edge_key in visible_edge_counts:
			if int(visible_edge_counts[edge_key]) >= 2:
				visible_interior_edges.append(visible_edge_values[edge_key])
		# A convex hull is the only line that can never reveal a far face through
		# an opaque cube.  It is still projected from the live eight world points,
		# but deliberately omits every internal construction edge.
		return Geometry2D.convex_hull(corners)

	func _semantic_edge_color(first: Color, second: Color, distance: float) -> Color:
		# Bias toward the darker or lighter face, independent of drawing order.
		var first_brightness := first.r * 0.2126 + first.g * 0.7152 + first.b * 0.0722
		var second_brightness := second.r * 0.2126 + second.g * 0.7152 + second.b * 0.0722
		var darker := first if first_brightness <= second_brightness else second
		var lighter := second if first_brightness <= second_brightness else first
		var balance := clampf(float(authoring_settings.get("edge_color_balance", 0.5)), 0.0, 1.0)
		var color: Color = darker.lerp(lighter, balance)
		color = color.lightened(clampf(float(authoring_settings.get("edge_brightening", INTERIOR_LINE_BRIGHTENING)), 0.0, 1.0))
		var exit_distance := maxf(0.01, float(authoring_settings.get("edge_fade_distance", INTERIOR_LINES_EXIT_DISTANCE)))
		var full_distance := clampf(float(authoring_settings.get("edge_full_distance", INTERIOR_LINES_FULL_DISTANCE)), 0.0, exit_distance - 0.01)
		color.a = clampf((exit_distance - distance) / (exit_distance - full_distance), 0.0, 1.0)
		return color

	# Map face-local points projectively, keeping the inset attached to the
	# same projected plane as the face, including the floor-parallel lid.
	func _face_point(quad: PackedVector2Array, u: float, v: float) -> Vector2:
		var p0 := quad[0]
		var p1 := quad[1]
		var p2 := quad[2]
		var p3 := quad[3]
		var d1 := p1 - p2
		var d2 := p3 - p2
		var d3 := p0 - p1 + p2 - p3
		var determinant := d1.x * d2.y - d2.x * d1.y
		var g := 0.0
		var h := 0.0
		if absf(determinant) > 0.0001:
			g = (d3.x * d2.y - d2.x * d3.y) / determinant
			h = (d1.x * d3.y - d3.x * d1.y) / determinant
		var denominator := 1.0 + g * u + h * v
		if absf(denominator) < 0.0001:
			return p0
		return ((p1 - p0 + g * p1) * u + (p3 - p0 + h * p3) * v + p0) / denominator

	func _draw_semantic_panel(quad: PackedVector2Array, raw_quad: PackedVector2Array, is_lid: bool, dark_side: bool, face_key: int, face_color: Color) -> void:
		# Geometry stays opaque and fixed. Unrounded projection drives the
		# contrast and budget, so snapped corners do not make the color jump.
		if not bool(authoring_settings.get("panel_enabled", true)):
			semantic_panel_visible[face_key] = false
			semantic_shadow_visible[face_key] = false
			return
		var inset := float(authoring_settings.get("frame_inset", FRAME_INSET))
		var panel := _semantic_inset_quad(quad, inset)
		var raw_panel := _semantic_inset_quad(raw_quad, inset)
		var panel_span := _minimum_quad_span(raw_panel)
		var was_visible := bool(semantic_panel_visible.get(face_key, false))
		var margin := FEATURE_EXIT_MARGIN_PIXELS if was_visible else 0.0
		var min_panel := float(authoring_settings.get("min_panel_pixels", MIN_PANEL_SPAN_PIXELS))
		var fits := _minimum_frame_width(raw_quad, raw_panel) >= MIN_FRAME_PIXELS - margin and panel_span >= min_panel - margin
		var max_distance := float(authoring_settings.get("panel_max_distance", 1000.0))
		fits = fits and authoring_distance <= max_distance + (0.1 if was_visible else 0.0)
		var max_edge := maxf(maxf(raw_quad[0].distance_to(raw_quad[1]), raw_quad[1].distance_to(raw_quad[2])), maxf(raw_quad[2].distance_to(raw_quad[3]), raw_quad[3].distance_to(raw_quad[0])))
		var face_ratio := _minimum_quad_span(raw_quad) / maxf(max_edge, 0.001)
		fits = fits and face_ratio >= maxf(0.0, float(authoring_settings.get("min_face_ratio", 0.0)) - (0.02 if was_visible else 0.0))
		semantic_panel_visible[face_key] = fits
		if not fits:
			semantic_shadow_visible[face_key] = false
			return
		var panel_color: Color = authoring_settings.get("panel_top_color", PANEL_TOP_COLOR) if is_lid else (authoring_settings.get("panel_dark_color", PANEL_DARK_SIDE_COLOR) if dark_side else authoring_settings.get("panel_color", PANEL_SIDE_COLOR))
		var visible_panel_color := face_color.lerp(panel_color, _panel_contrast(panel_span))
		draw_colored_polygon(panel, visible_panel_color)
		# Layers are contained within the inset. The upper shadow shares its
		# boundary with the frame instead of floating a pixel below it.
		var shadow_margin := FEATURE_EXIT_MARGIN_PIXELS if bool(semantic_shadow_visible.get(face_key, false)) else 0.0
		var shadow_fits := bool(authoring_settings.get("shadow_enabled", true)) and not is_lid and panel_span >= MIN_SHADOW_PANEL_SPAN_PIXELS - shadow_margin
		semantic_shadow_visible[face_key] = shadow_fits
		# Slats are a lower-priority detail: reserve multiple logical pixels per
		# division before drawing, and keep their ends inside the panel.
		if bool(authoring_settings.get("slats_enabled", true)) and _slats_view_allowed(is_lid, face_key, authoring_camera_delta, authoring_distance):
			var slat_count := clampi(int(authoring_settings.get("slat_count", 3)), 2, 8)
			var panel_width := minf(raw_panel[0].distance_to(raw_panel[1]), raw_panel[3].distance_to(raw_panel[2]))
			if panel_width >= float(slat_count) * 3.0 and panel_span >= 5.0:
				var slat_color: Color = authoring_settings.get("slat_color", PANEL_SHADOW_COLOR)
				var slat_strength := clampf((panel_width - float(slat_count) * 3.0) / 6.0, 0.0, 1.0)
				for slat in range(1, slat_count):
					var u := lerpf(inset, 1.0 - inset, float(slat) / float(slat_count))
					draw_line(_face_point(quad, u, inset), _face_point(quad, u, 1.0 - inset), visible_panel_color.lerp(slat_color, slat_strength), 1.0, false)
		var effective_shadow_color := visible_panel_color
		if shadow_fits:
			var shadow_strength := lerpf(PANEL_INITIAL_CONTRAST, 1.0, clampf((panel_span - MIN_SHADOW_PANEL_SPAN_PIXELS) / 4.0, 0.0, 1.0))
			var shadow_color: Color = authoring_settings.get("shadow_color", PANEL_SHADOW_COLOR)
			var shadow_depth := clampf(float(authoring_settings.get("shadow_depth", 0.07)), 0.01, 1.0 - 2.0 * inset)
			effective_shadow_color = visible_panel_color.lerp(shadow_color, shadow_strength)
			_draw_panel_rect(quad, inset, 1.0 - inset - shadow_depth, 1.0 - inset, 1.0 - inset, effective_shadow_color)
		# View-dependent inset occlusion: place a strip along the frame edge
		# opposite the camera's tangent direction, on top of the panel layers.
		if bool(authoring_settings.get("ao_enabled", true)) and panel_span >= 4.0 and authoring_camera_delta.length_squared() > 0.0001:
			var tangent: Vector2 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][face_key] if not is_lid else Vector2.RIGHT
			var side_view := authoring_camera_delta.normalized().dot(tangent)
			var ao_depth := clampf(float(authoring_settings.get("ao_depth", 0.08)), 0.0, 1.0 - 2.0 * inset) * absf(side_view)
			var ao_color: Color = authoring_settings.get("ao_color", PANEL_SHADOW_COLOR)
			var ao_strength := clampf(float(authoring_settings.get("ao_strength", 0.55)), 0.0, 1.0) * clampf((panel_span - 4.0) / 3.0, 0.0, 1.0)
			if ao_depth > 0.001 and ao_strength > 0.0:
				var left := inset if side_view > 0.0 else 1.0 - inset - ao_depth
				_draw_panel_rect(quad, left, inset, left + ao_depth, 1.0 - inset, visible_panel_color.lerp(ao_color, ao_strength))
			if is_lid and ao_strength > 0.0:
				var depth_view := authoring_camera_delta.normalized().y
				var depth_strip := clampf(float(authoring_settings.get("ao_depth", 0.08)), 0.0, 1.0 - 2.0 * inset) * absf(depth_view)
				if depth_strip > 0.001:
					var top := inset if depth_view > 0.0 else 1.0 - inset - depth_strip
					_draw_panel_rect(quad, inset, top, 1.0 - inset, top + depth_strip, visible_panel_color.lerp(ao_color, ao_strength))
		# Highlight the frame side of the inset, not the recessed panel itself.
		# The lid has no vertical "bottom" edge; this first pass is for sides.
		if not is_lid and bool(authoring_settings.get("inset_highlight_enabled", true)) and authoring_camera_delta.length_squared() > 0.0001:
			var tangent: Vector2 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][face_key]
			var side_view := clampf(authoring_camera_delta.normalized().dot(tangent), -1.0, 1.0)
			var weights := _inset_highlight_weights(side_view, authoring_distance)
			var highlight: Color = authoring_settings.get("inset_highlight_color", Color8(167, 141, 108))
			_draw_frame_highlight(quad, panel[0], panel[3], 0, 3, highlight, weights.x)
			_draw_frame_highlight(quad, panel[1], panel[2], 1, 2, highlight, weights.y)
			_draw_frame_highlight(quad, panel[0], panel[1], 0, 1, highlight, weights.z)
		# The upper frame edge is a bevel shadow, not a highlight. It is a
		# separate, lighter layer and never survives the underlying drop shadow.
		if shadow_fits and bool(authoring_settings.get("bevel_shadow_enabled", true)):
			var bevel_strength := _bevel_shadow_strength(authoring_distance)
			var bevel_color := effective_shadow_color.lerp(face_color, 0.5)
			_draw_frame_highlight(quad, panel[3], panel[2], 3, 2, bevel_color, bevel_strength)

	func _bevel_shadow_strength(distance: float) -> float:
		var fade_end := maxf(0.01, float(authoring_settings.get("bevel_shadow_fade_distance", 1.0)))
		var full := minf(0.4, fade_end * 0.5)
		return clampf((fade_end - distance) / (fade_end - full), 0.0, 1.0)

	# x/y are left/right frame highlights; z is the bottom frame highlight.
	func _inset_highlight_weights(side_view: float, distance: float) -> Vector3:
		var full := maxf(0.0, float(authoring_settings.get("inset_highlight_full_distance", 0.55)))
		var end := maxf(full + 0.01, float(authoring_settings.get("inset_highlight_fade_distance", 1.5)))
		var distance_strength := clampf((end - distance) / (end - full), 0.0, 1.0)
		var view := clampf(side_view, -1.0, 1.0)
		# A positive tangent points toward the right edge: that near edge fades.
		var left_strength := 1.0 - maxf(-view, 0.0)
		var right_strength := 1.0 - maxf(view, 0.0)
		# Bottom remains constant until the view approaches edge-on.
		var bottom_strength := 1.0 - clampf((absf(view) - 0.8) / 0.2, 0.0, 1.0)
		return Vector3(left_strength, right_strength, bottom_strength) * distance_strength

	func _draw_frame_highlight(quad: PackedVector2Array, a: Vector2, b: Vector2, outer_a: int, outer_b: int, color: Color, strength: float) -> void:
		if strength <= 0.001:
			return
		# Move the stroke half a logical pixel toward the surrounding frame so
		# it sits outside the inset and beside, rather than over, its shadow.
		var outward := ((quad[outer_a] + quad[outer_b]) * 0.5 - (a + b) * 0.5).normalized() * 0.5
		color.a *= strength
		draw_line(a + outward, b + outward, color, 1.0, false)

	func _draw_panel_rect(quad: PackedVector2Array, u0: float, v0: float, u1: float, v1: float, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array([_face_point(quad, u0, v0), _face_point(quad, u1, v0), _face_point(quad, u1, v1), _face_point(quad, u0, v1)]), color)

	func _slats_view_allowed(is_lid: bool, face_key: int, camera_delta: Vector2, distance: float) -> bool:
		if is_lid:
			# The top has its own distance control; heading never gates its slats.
			return distance <= float(authoring_settings.get("top_slats_max_distance", 1000.0))
		if camera_delta.length_squared() < 0.0001:
			return true
		var tangent: Vector2 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][face_key]
		# 0 degrees is face-on, 90 degrees is along the plane (edge-on).
		var angle := rad_to_deg(asin(clampf(absf(camera_delta.normalized().dot(tangent)), 0.0, 1.0)))
		return angle <= clampf(float(authoring_settings.get("side_slats_max_angle", 90.0)), 0.0, 90.0)

	func _panel_contrast(panel_span: float) -> float:
		var minimum := float(authoring_settings.get("min_panel_pixels", MIN_PANEL_SPAN_PIXELS))
		var full := maxf(minimum + 0.01, float(authoring_settings.get("full_contrast_pixels", PANEL_FULL_CONTRAST_SPAN)))
		var amount := clampf((panel_span - minimum) / (full - minimum), 0.0, 1.0)
		var steps := int(authoring_settings.get("fade_steps", 0))
		if steps > 1:
			amount = roundf(amount * float(steps - 1)) / float(steps - 1)
		return lerpf(PANEL_INITIAL_CONTRAST, 1.0, amount)

	func _semantic_inset_quad(quad: PackedVector2Array, inset: float) -> PackedVector2Array:
		return PackedVector2Array([
			_face_point(quad, inset, inset),
			_face_point(quad, 1.0 - inset, inset),
			_face_point(quad, 1.0 - inset, 1.0 - inset),
			_face_point(quad, inset, 1.0 - inset),
		])

	func _minimum_frame_width(outer: PackedVector2Array, inner: PackedVector2Array) -> float:
		var result := INF
		for index in 4:
			var next := (index + 1) % 4
			for point in [inner[index], inner[next]]:
				result = minf(result, point.distance_to(Geometry2D.get_closest_point_to_segment(point, outer[index], outer[next])))
		return result

	func _minimum_quad_span(quad: PackedVector2Array) -> float:
		var result := INF
		for index in 4:
			var next := (index + 1) % 4
			var opposite_midpoint := (quad[(index + 2) % 4] + quad[(index + 3) % 4]) * 0.5
			result = minf(result, opposite_midpoint.distance_to(Geometry2D.get_closest_point_to_segment(opposite_midpoint, quad[index], quad[next])))
		return result

	func _face_signed_area(face: PackedInt32Array) -> float:
		var area := 0.0
		for index in face.size():
			var next_index := (index + 1) % face.size()
			var point := corners[face[index]]
			var next_point := corners[face[next_index]]
			area += point.x * next_point.y - next_point.x * point.y
		return area * 0.5

	func _derive_line_colors_from_face_texture() -> void:
		if not USE_TEXTURE_DERIVED_LINE_COLORS:
			silhouette_color = CUSTOM_SILHOUETTE_COLOR
			interior_line_color = CUSTOM_INTERIOR_LINE_COLOR
			return
		if face_texture == null:
			return
		var image := face_texture.get_image()
		if image == null:
			return
		var darkest_luminance := INF
		var lightest_luminance := -INF
		for y in image.get_height():
			for x in image.get_width():
				var sample := image.get_pixel(x, y)
				if sample.a < 0.5:
					continue
				var luminance := sample.r * 0.2126 + sample.g * 0.7152 + sample.b * 0.0722
				if luminance < darkest_luminance:
					darkest_luminance = luminance
					silhouette_color = sample
				if luminance > lightest_luminance:
					lightest_luminance = luminance
					interior_line_color = sample

	func _face_average_y(face: PackedInt32Array) -> float:
		var total := 0.0
		for index in face:
			total += corners[index].y
		return total / float(face.size())


# This child covers the whole logical canvas but discards every fragment that
# is not inside the lid's projected UV rectangle. It sits behind its parent so
# the two visible side faces and all selected outline seams still draw over it.
class ProjectiveLidCanvas extends Node2D:
	const LID_UV_MIN := Vector2(0.34, 0.0)
	const LID_UV_MAX := Vector2(0.66, 0.32)
	const PROJECTIVE_LID_SHADER_RESOURCE := preload("res://scripts/semantic_lod_projective_lid.gdshader")

	var lid_material: ShaderMaterial

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lid_material = ShaderMaterial.new()
		lid_material.shader = PROJECTIVE_LID_SHADER_RESOURCE
		material = lid_material

	func set_lid(new_corners: PackedVector2Array, new_texture: Texture2D) -> void:
		if lid_material == null:
			_ready()
		if new_corners.size() != 8 or new_texture == null:
			visible = false
			return
		var lid_corners := PackedVector2Array([
			new_corners[4], new_corners[5], new_corners[6], new_corners[7],
		])
		var coefficients := _screen_to_uv_coefficients(lid_corners)
		if coefficients.size() != 8:
			visible = false
			return
		lid_material.set_shader_parameter("lid_texture", new_texture)
		lid_material.set_shader_parameter("uv_u_coefficients", Vector3(coefficients[0], coefficients[1], coefficients[2]))
		lid_material.set_shader_parameter("uv_v_coefficients", Vector3(coefficients[3], coefficients[4], coefficients[5]))
		lid_material.set_shader_parameter("uv_denominator_coefficients", Vector2(coefficients[6], coefficients[7]))
		lid_material.set_shader_parameter("uv_min", LID_UV_MIN)
		lid_material.set_shader_parameter("uv_max", LID_UV_MAX)
		lid_material.set_shader_parameter("logical_canvas_size", LOGICAL_CANVAS_SIZE)
		visible = true
		queue_redraw()

	func _draw() -> void:
		if visible:
			draw_rect(Rect2(Vector2.ZERO, LOGICAL_CANVAS_SIZE), Color.WHITE)

	# Solve the inverse homography directly: screen (x, y) -> crate UV (u, v).
	# Eight corner equations determine the eight free projective coefficients.
	func _screen_to_uv_coefficients(quad: PackedVector2Array, source_uvs := PackedVector2Array()) -> PackedFloat64Array:
		if quad.size() != 4:
			return PackedFloat64Array()
		if source_uvs.size() != 4:
			source_uvs = PackedVector2Array([
			LID_UV_MIN,
			Vector2(LID_UV_MAX.x, LID_UV_MIN.y),
			LID_UV_MAX,
			Vector2(LID_UV_MIN.x, LID_UV_MAX.y),
			])
		var rows: Array = []
		for index in 4:
			var screen := quad[index]
			var source_uv := source_uvs[index]
			rows.append(PackedFloat64Array([
				screen.x, screen.y, 1.0, 0.0, 0.0, 0.0,
				-source_uv.x * screen.x, -source_uv.x * screen.y, source_uv.x,
			]))
			rows.append(PackedFloat64Array([
				0.0, 0.0, 0.0, screen.x, screen.y, 1.0,
				-source_uv.y * screen.x, -source_uv.y * screen.y, source_uv.y,
			]))
		for column in 8:
			var pivot := column
			for candidate in range(column + 1, 8):
				if absf(rows[candidate][column]) > absf(rows[pivot][column]):
					pivot = candidate
			if absf(rows[pivot][column]) < 0.000001:
				return PackedFloat64Array()
			if pivot != column:
				var temporary: PackedFloat64Array = rows[column]
				rows[column] = rows[pivot]
				rows[pivot] = temporary
			var pivot_value: float = rows[column][column]
			for entry in 9:
				rows[column][entry] /= pivot_value
			for row in 8:
				if row == column:
					continue
				var factor: float = rows[row][column]
				for entry in 9:
					rows[row][entry] -= factor * rows[column][entry]
		var result := PackedFloat64Array()
		result.resize(8)
		for row in 8:
			result[row] = rows[row][8]
		return result


class CylinderFillCanvas extends Node2D:
	const BODY_COLOR := Color8(118, 94, 71)
	const TOP_COLOR := Color8(157, 129, 99)
	var body := PackedVector2Array()
	var lid := PackedVector2Array()
	var shade_material: ShaderMaterial
	var lid_canvas: CylinderLidCanvas
	var reference_barrel_style := false

	func _ready() -> void:
		shade_material = ShaderMaterial.new()
		shade_material.shader = CYLINDER_SHADE_SHADER
		material = shade_material
		lid_canvas = CylinderLidCanvas.new()
		lid_canvas.material = CanvasItemMaterial.new()
		add_child(lid_canvas)
		visible = false

	func set_rings(bottom: PackedVector2Array, top: PackedVector2Array, middle_points := PackedVector2Array(), paths: Array = []) -> void:
		if bottom.size() < 3 or top.size() < 3:
			visible = false
			return
		var points := bottom.duplicate()
		points.append_array(top)
		points.append_array(middle_points)
		body = Geometry2D.convex_hull(points)
		lid = Geometry2D.convex_hull(top)
		lid_canvas.set_lid(lid)
		var min_x := body[0].x
		var max_x := min_x
		for point in body:
			min_x = minf(min_x, point.x)
			max_x = maxf(max_x, point.x)
		shade_material.set_shader_parameter("left_x", min_x)
		shade_material.set_shader_parameter("right_x", max_x)
		if paths.size() == 2 and paths[0].size() == 5 and paths[1].size() == 5:
			shade_material.set_shader_parameter("side_a", paths[0])
			shade_material.set_shader_parameter("side_b", paths[1])
			shade_material.set_shader_parameter("use_profile", true)
		else:
			shade_material.set_shader_parameter("use_profile", false)
		visible = true
		queue_redraw()

	func _draw() -> void:
		if body.size() >= 3:
			draw_colored_polygon(body, Color8(132, 92, 57) if reference_barrel_style else BODY_COLOR)


class CylinderLidCanvas extends Node2D:
	var reference_barrel_style := false
	var points := PackedVector2Array()
	var inner_lip := PackedVector2Array()
	var inset := PackedVector2Array()
	var stave_segments := PackedVector2Array()
	var stave_distance := INF

	func set_lid(new_points: PackedVector2Array) -> void:
		points = new_points
		inner_lip.clear()
		inset.clear()
		stave_segments.clear()
		queue_redraw()

	func set_recess(lip_ring: PackedVector2Array, inset_ring: PackedVector2Array) -> void:
		inner_lip = Geometry2D.convex_hull(lip_ring) if lip_ring.size() >= 3 else PackedVector2Array()
		inset = Geometry2D.convex_hull(inset_ring) if inset_ring.size() >= 3 else PackedVector2Array()
		queue_redraw()

	func set_staves(segments: PackedVector2Array, distance: float) -> void:
		stave_segments = segments
		stave_distance = distance
		queue_redraw()

	func _draw() -> void:
		if points.size() >= 3:
			draw_colored_polygon(points, Color8(170, 126, 80) if reference_barrel_style else CylinderFillCanvas.TOP_COLOR)
		if points.size() >= 3 and inner_lip.size() >= 3:
			for lip in Geometry2D.intersect_polygons(points, inner_lip):
				if lip.size() >= 3:
					draw_colored_polygon(lip, Color8(89, 56, 31) if reference_barrel_style else Color8(92, 69, 49))
				if lip.size() >= 3 and inset.size() >= 3:
					for panel in Geometry2D.intersect_polygons(lip, inset):
						if panel.size() >= 3:
							draw_colored_polygon(panel, Color8(139, 98, 59) if reference_barrel_style else Color8(133, 106, 80))
							var strength := 1.0 - smoothstep(0.7, 2.0, stave_distance)
							var highlight_strength := 1.0 - smoothstep(0.9, 2.5, stave_distance)
							if strength > 0.0 or highlight_strength > 0.0:
								var seam_color := Color(0.24, 0.16, 0.10, 0.55 * strength)
								var highlight_color := Color(0.78, 0.66, 0.51, 0.50 * highlight_strength)
								for index in range(0, stave_segments.size() - 1, 2):
									var segment := PackedVector2Array([stave_segments[index], stave_segments[index + 1]])
									if strength > 0.0:
										for clipped in Geometry2D.intersect_polyline_with_polygon(segment, panel):
											if clipped.size() >= 2:
												draw_polyline(clipped, seam_color, 1.0, false)
									if highlight_strength > 0.0:
										var highlight_segment := PackedVector2Array([segment[0] + Vector2.RIGHT, segment[1] + Vector2.RIGHT])
										for clipped in Geometry2D.intersect_polyline_with_polygon(highlight_segment, panel):
											if clipped.size() >= 2:
												draw_polyline(clipped, highlight_color, 1.0, false)


class GroundCircleCanvas extends Node2D:
	var circle_material: ShaderMaterial
	var clip_polygon := PackedVector2Array()

	func _ready() -> void:
		circle_material = ShaderMaterial.new()
		circle_material.shader = GROUND_CIRCLE_SHADER
		material = circle_material

	func set_circle(quad: PackedVector2Array, coefficients: PackedFloat64Array) -> void:
		clip_polygon.clear()
		if coefficients.size() != 8 or quad.size() != 4:
			visible = false
			return
		if circle_material == null:
			_ready()
		var minimum := quad[0]
		var maximum := quad[0]
		for point in quad:
			minimum = minimum.min(point)
			maximum = maximum.max(point)
		circle_material.set_shader_parameter("bounds_min", minimum - Vector2.ONE * 2.0)
		circle_material.set_shader_parameter("bounds_max", maximum + Vector2.ONE * 2.0)
		circle_material.set_shader_parameter("uv_u_coefficients", Vector3(coefficients[0], coefficients[1], coefficients[2]))
		circle_material.set_shader_parameter("uv_v_coefficients", Vector3(coefficients[3], coefficients[4], coefficients[5]))
		circle_material.set_shader_parameter("uv_denominator_coefficients", Vector2(coefficients[6], coefficients[7]))
		circle_material.set_shader_parameter("clip_back", false)
		circle_material.set_shader_parameter("highlight_front", false)
		visible = true
		queue_redraw()

	func set_front_clip(view_direction: Vector2, tangent_ratio: float) -> void:
		circle_material.set_shader_parameter("clip_back", true)
		circle_material.set_shader_parameter("camera_direction", view_direction)
		circle_material.set_shader_parameter("tangent_ratio", tangent_ratio)

	func set_front_highlight(view_direction: Vector2, tangent_ratio: float) -> void:
		circle_material.set_shader_parameter("highlight_front", true)
		circle_material.set_shader_parameter("highlight_only", true)
		circle_material.set_shader_parameter("camera_direction", view_direction)
		circle_material.set_shader_parameter("tangent_ratio", tangent_ratio)

	func set_clip_polygon(ring: PackedVector2Array) -> void:
		clip_polygon = Geometry2D.convex_hull(ring) if ring.size() >= 3 else PackedVector2Array()
		if clip_polygon.size() < 3:
			visible = false
		queue_redraw()

	func _draw() -> void:
		if visible:
			if clip_polygon.size() >= 3:
				var uvs := PackedVector2Array()
				for point in clip_polygon:
					uvs.append(point / LOGICAL_CANVAS_SIZE)
				draw_polygon(clip_polygon, PackedColorArray([Color.WHITE]), uvs)
			else:
				draw_rect(Rect2(Vector2.ZERO, LOGICAL_CANVAS_SIZE), Color.WHITE)
