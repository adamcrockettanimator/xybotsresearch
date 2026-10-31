## Minimal semantic stool: sparse authoring points become four post boxes plus
## one seat box. Debug construction belongs to the window; paint belongs only
## to this 160x120 logical SubViewport.
extends Node2D

const LOGICAL_SIZE := Vector2i(160, 120)
const STYLE_PATH := "res://resources/semantic_stool_style.tres"
const STYLE_SCRIPT := preload("res://scripts/semantic_stool_style.gd")
class StoolRasterLayer extends Node2D:
	# One logical-canvas node owns every semantic cube face.  Keeping the
	# inferred faces as 95 MeshInstance2D/ShaderMaterial descendants made the
	# Remote Inspector serialize a >160 MB resource tree before an artist could
	# inspect a single control.
	var layers: Array[Dictionary] = []

	func set_layers(new_layers: Array[Dictionary]) -> void:
		if layers == new_layers:
			return
		layers = new_layers
		queue_redraw()

	func _draw() -> void:
		for layer in layers:
			var points: PackedVector2Array = layer["points"]
			if points.size() >= 3:
				draw_colored_polygon(points, layer["colour"])

class StoolLogicalPixelGrid extends Node2D:
	var enabled := false
	var _last_window_size := Vector2.ZERO

	func set_enabled(value: bool) -> void:
		if enabled == value:
			return
		enabled = value
		visible = value
		if enabled:
			queue_redraw()

	func _process(_delta: float) -> void:
		# The grid is static while the game window is unchanged. Do not re-submit
		# its 322 boundaries just because the camera/debug construction moves.
		var current_size := get_viewport_rect().size
		if enabled and current_size != _last_window_size:
			queue_redraw()

	func _draw() -> void:
		if not enabled:
			return
		var window_size := get_viewport_rect().size
		_last_window_size = window_size
		var scale := minf(window_size.x / float(LOGICAL_SIZE.x), window_size.y / float(LOGICAL_SIZE.y))
		if scale < 2.0:
			return
		var offset := (window_size - Vector2(LOGICAL_SIZE) * scale) * 0.5
		var final_transform := get_viewport().get_final_transform()
		var final_scale := maxf(maxf(final_transform.x.length(), final_transform.y.length()), 0.0001)
		var segments := PackedVector2Array()
		for x in range(LOGICAL_SIZE.x + 1):
			var grid_x := offset.x + float(x) * scale
			segments.append(Vector2(grid_x, offset.y))
			segments.append(Vector2(grid_x, offset.y + float(LOGICAL_SIZE.y) * scale))
		for y in range(LOGICAL_SIZE.y + 1):
			var grid_y := offset.y + float(y) * scale
			segments.append(Vector2(offset.x, grid_y))
			segments.append(Vector2(offset.x + float(LOGICAL_SIZE.x) * scale, grid_y))
		draw_multiline(segments, Color(0.88, 0.92, 1.0, 0.34), 1.0 / final_scale, false)

class StoolDebugOverlay extends Node2D:
	var origin_point := Vector2.ZERO
	var footprint := PackedVector2Array()
	var leg_tops := PackedVector2Array()
	var base_squares: Array[PackedVector2Array] = []
	# These are the exact two camera-facing semantic masks per leg. They are
	# construction boundaries only; the colour still paints in the 160x120 view.
	var leg_face_rectangles: Array[Dictionary] = []
	var enabled := true
	var _next_redraw_msec := 0

	func set_geometry(new_origin: Vector2, new_footprint: PackedVector2Array, new_tops: PackedVector2Array, new_squares: Array[PackedVector2Array], new_leg_face_rectangles: Array[Dictionary], show: bool) -> void:
		var changed := origin_point != new_origin or footprint != new_footprint or leg_tops != new_tops or base_squares != new_squares or leg_face_rectangles != new_leg_face_rectangles or enabled != show
		if not changed:
			return
		origin_point = new_origin
		footprint = new_footprint
		leg_tops = new_tops
		base_squares = new_squares
		leg_face_rectangles = new_leg_face_rectangles
		enabled = show
		# This is an explanatory overlay, not gameplay paint. Its data remains
		# current every frame, but batching redraws prevents Remote Debugger from
		# accumulating hundreds of Canvas draw commands per second.
		if Time.get_ticks_msec() >= _next_redraw_msec:
			queue_redraw()
			_next_redraw_msec = Time.get_ticks_msec() + 66

	func _draw() -> void:
		if not enabled or footprint.size() != 4 or leg_tops.size() != 4:
			return
		var window_size := get_viewport_rect().size
		var scale := minf(window_size.x / float(LOGICAL_SIZE.x), window_size.y / float(LOGICAL_SIZE.y))
		var offset := (window_size - Vector2(LOGICAL_SIZE) * scale) * 0.5
		var map := func(point: Vector2) -> Vector2: return offset + point * scale
		# These construction marks live in the full window, so their dimensions
		# mean real display pixels rather than enlarged 160x120 logical cells.
		var final_transform := get_viewport().get_final_transform()
		var final_scale := maxf(maxf(final_transform.x.length(), final_transform.y.length()), 0.0001)
		var debug_line_width := 2.0 / final_scale
		var marker_radius := 2.5 / final_scale # Five-pixel diameter.
		var footprint_segments := PackedVector2Array()
		var leg_segments := PackedVector2Array()
		var base_square_segments := PackedVector2Array()
		var seat_segments := PackedVector2Array()
		# White: world anchor. Green: stretchable ground footprint. Cyan: legs.
		draw_circle(map.call(origin_point), marker_radius, Color.WHITE)
		for index in 4:
			var ground: Vector2 = map.call(footprint[index])
			var top: Vector2 = map.call(leg_tops[index])
			footprint_segments.append(ground)
			footprint_segments.append(map.call(footprint[(index + 1) % 4]))
			leg_segments.append(ground)
			leg_segments.append(top)
			draw_circle(ground, marker_radius, Color(0.25, 1.0, 0.42, 1.0))
			draw_circle(top, marker_radius, Color(1.0, 0.92, 0.20, 1.0))
			if index < base_squares.size() and base_squares[index].size() == 4:
				var square := base_squares[index]
				for corner in 4:
					base_square_segments.append(map.call(square[corner]))
					base_square_segments.append(map.call(square[(corner + 1) % 4]))
		# Yellow repeats the top-leg points: they are also the four seat-base points.
		for index in 4:
			seat_segments.append(map.call(leg_tops[index]))
			seat_segments.append(map.call(leg_tops[(index + 1) % 4]))
		draw_multiline(footprint_segments, Color(0.25, 1.0, 0.42, 1.0), debug_line_width, false)
		draw_multiline(leg_segments, Color(0.15, 0.92, 1.0, 1.0), debug_line_width, false)
		draw_multiline(base_square_segments, Color(1.0, 0.25, 0.80, 1.0), debug_line_width, false)
		draw_multiline(seat_segments, Color(1.0, 0.92, 0.20, 1.0), debug_line_width, false)
		# Each outline is the exact projected rectangle owned by one visible leg
		# side. Orange means X-facing material; violet means Z-facing material.
		for face in leg_face_rectangles:
			var rectangle: PackedVector2Array = face["points"]
			if rectangle.size() != 4:
				continue
			var colour: Color = face["colour"]
			for corner in 4:
				draw_line(map.call(rectangle[corner]), map.call(rectangle[(corner + 1) % 4]), colour, debug_line_width, false)

@export_category("Three-axis cube material")
@export var top_color := Color8(76, 229, 234)
@export var x_side_color := Color8(51, 166, 222)
@export var z_side_color := Color8(8, 111, 181)
@export var shadow_color := Color8(47, 55, 78, 128)
@export_category("Stool footprint")
@export_range(0.04, 0.50, 0.01) var footprint_x := 0.128
@export_range(0.04, 0.50, 0.01) var footprint_y := 0.141
@export_range(0.04, 0.50, 0.01) var leg_height := 0.205
@export_category("Logical-pixel box size")
@export_range(1, 16, 1) var maximum_leg_pixels := 5
@export_range(1, 16, 1) var maximum_seat_height_pixels := 5
@export_range(0.10, 12.0, 0.05) var maximum_pixels_distance := 0.60
@export_range(0.15, 30.0, 0.05) var one_pixel_distance := 3.00
@export_category("Full-window debug construction")
@export var show_debug_geometry := true
@export var show_logical_pixel_grid := false
@export_category("Read only")
@export var current_camera_distance_readout := 0.0
@export var current_leg_pixel_width_readout := 1
@export var current_seat_height_pixel_readout := 1

var viewport: SubViewport
var raster_root: Node2D
var display: Sprite2D
var raster_layer: StoolRasterLayer
var style: Resource
var _saved: Dictionary = {}
var _style_dirty := false
var debug_layer: CanvasLayer
var grid_overlay: StoolLogicalPixelGrid
var debug_overlay: StoolDebugOverlay

func _ready() -> void:
	_load_style()
	viewport = SubViewport.new()
	viewport.name = "SemanticStoolLogicalRaster_160x120"
	viewport.size = LOGICAL_SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	raster_root = Node2D.new()
	raster_root.name = "StoolRasterLayers_Shadow_Legs_Seat"
	viewport.add_child(raster_root)
	raster_layer = StoolRasterLayer.new()
	raster_layer.name = "StoolSemanticCubeFaces"
	raster_root.add_child(raster_layer)
	display = Sprite2D.new()
	display.name = "SemanticStoolPixels"
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.texture = viewport.get_texture()
	add_child(display)
	debug_layer = CanvasLayer.new()
	debug_layer.name = "SemanticStoolWindowDebug"
	debug_layer.layer = 80
	get_tree().root.add_child.call_deferred(debug_layer)
	grid_overlay = StoolLogicalPixelGrid.new()
	grid_overlay.name = "StoolLogicalPixelGrid_Static"
	debug_layer.add_child.call_deferred(grid_overlay)
	debug_overlay = StoolDebugOverlay.new()
	debug_overlay.name = "StoolConstructionPointsAndSquares"
	debug_layer.add_child.call_deferred(debug_overlay)

func _exit_tree() -> void:
	# Saving while the Remote Inspector is continuously sending slider updates
	# was the other large packet source. Persist the final authored values once,
	# on a normal scene stop, instead of serializing every intermediate drag.
	if style != null and _style_dirty:
		for key in _style_values():
			style.set(key, get(key))
		if ResourceSaver.save(style, STYLE_PATH) == OK:
			_saved = _style_values()
	if is_instance_valid(debug_layer):
		debug_layer.queue_free()

func _process(_delta: float) -> void:
	var values := _style_values()
	_style_dirty = style != null and values != _saved

func set_stool(center: Vector2, camera_origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> void:
	current_camera_distance_readout = center.distance_to(camera_origin)
	var seat_pixels := _logical_pixels(maximum_seat_height_pixels)
	# Leg width is deliberately angle-owned, not a changing projected cube
	# radius.  Each visible normal gets a stable integer rectangle width.
	current_leg_pixel_width_readout = maximum_leg_pixels
	current_seat_height_pixel_readout = seat_pixels
	# Keep live build data local. Remote Inspector exposes ordinary script
	# members, and rewriting these arrays every render frame made a single
	# slider drag accumulate an enormous debugger packet.
	var debug_leg_face_rectangles: Array[Dictionary] = []
	var raster_layers: Array[Dictionary] = []
	var depth := maxf((center - camera_origin).dot(forward), 0.05)
	# This converts an artist-selected logical width into a world-space radius
	# for this camera pose. The generated post itself changes size; its raster
	# remains the requested 1..N logical pixels wide.
	var world_per_pixel := depth / 128.0
	var leg_cube_world_width := world_per_pixel * float(maximum_leg_pixels)
	var seat_height := world_per_pixel * float(seat_pixels)
	var ground: Array[Vector3] = []
	for z_sign in [-1.0, 1.0]:
		for x_sign in [-1.0, 1.0]:
			ground.append(Vector3(x_sign * footprint_x * 0.5, 0.0, z_sign * footprint_y * 0.5))
	# Ordered winding: back-left, back-right, front-right, front-left.
	ground = [ground[0], ground[1], ground[3], ground[2]]
	# A camera has one global view direction for this small prop. Choose the
	# two normal-owned leg materials once here; individual corners must not pick
	# competing opposite sides simply because they lie across the stool centre.
	var stool_to_camera := Vector3(camera_origin.x - center.x, 0.5, camera_origin.y - center.y)
	var camera_x_normal := Vector3.RIGHT if stool_to_camera.x >= 0.0 else Vector3.LEFT
	var camera_z_normal := Vector3.BACK if stool_to_camera.z >= 0.0 else Vector3.FORWARD
	_draw_shadow(ground, center, camera_origin, forward, right, offset, raster_layers)
	var debug_ground := PackedVector2Array()
	var debug_tops := PackedVector2Array()
	var debug_squares: Array[PackedVector2Array] = []
	var cursor := 0
	for leg_index in ground.size():
		var point: Vector3 = ground[leg_index]
		var top := point + Vector3.UP * leg_height
		cursor = _draw_camera_facing_leg_rectangles(point, leg_height, leg_cube_world_width, camera_x_normal, camera_z_normal, cursor, center, camera_origin, forward, right, offset, raster_layers, debug_leg_face_rectangles)
		var base_projection := _project(point, center, camera_origin, forward, right, offset)
		var top_projection := _project(top, center, camera_origin, forward, right, offset)
		debug_ground.append(base_projection.pixel)
		debug_tops.append(top_projection.pixel)
		var square := PackedVector2Array()
		# This square shows the old world-space inferred-cube footprint only as a
		# source construction cue. The visible legs are the semantic rectangles.
		for corner in _post_base_corners(point, leg_cube_world_width):
			square.append(_project(corner, center, camera_origin, forward, right, offset).pixel)
		debug_squares.append(square)
	var seat_base: Array[Vector3] = []
	for point in ground:
		seat_base.append(point + Vector3.UP * leg_height)
	cursor = _draw_box(_slab_vertices(seat_base, seat_height), cursor, center, camera_origin, forward, right, offset, raster_layers)
	if is_instance_valid(raster_layer):
		raster_layers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["z"]) < int(b["z"]))
		raster_layer.set_layers(raster_layers)
	if is_instance_valid(debug_overlay):
		debug_overlay.set_geometry(_project(Vector3.ZERO, center, camera_origin, forward, right, offset).pixel, debug_ground, debug_tops, debug_squares, debug_leg_face_rectangles, show_debug_geometry)
	if is_instance_valid(grid_overlay):
		grid_overlay.set_enabled(show_logical_pixel_grid)

func _draw_camera_facing_leg_rectangles(footprint_corner: Vector3, height: float, cube_width: float, x_normal: Vector3, z_normal: Vector3, cursor: int, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2, raster_layers: Array[Dictionary], debug_leg_face_rectangles: Array[Dictionary]) -> int:
	# A footprint point is the outside corner of the physical post, but it is
	# not always the corner that faces the camera. Find the one corner where the
	# selected X and Z planes meet, then both semantic rectangles share it.
	var visible_base := _camera_facing_post_corner(footprint_corner, cube_width, x_normal, z_normal)
	var visible_top := visible_base + Vector3.UP * height
	# The X face runs away from its shared edge along -Z normal; the Z face runs
	# away along -X normal. This is true for every leg, including the far pair.
	cursor = _draw_leg_face_rectangle(visible_base, visible_top, -z_normal, x_normal, cursor, center, origin, forward, right, offset, Color(1.0, 0.28, 0.04, 0.96), raster_layers, debug_leg_face_rectangles)
	cursor = _draw_leg_face_rectangle(visible_base, visible_top, -x_normal, z_normal, cursor, center, origin, forward, right, offset, Color(0.95, 0.25, 1.0, 0.96), raster_layers, debug_leg_face_rectangles)
	return cursor

func _camera_facing_post_corner(footprint_corner: Vector3, cube_width: float, x_normal: Vector3, z_normal: Vector3) -> Vector3:
	var best_corner := footprint_corner
	var best_score := -INF
	for corner in _post_base_corners(footprint_corner, cube_width):
		var score := corner.dot(x_normal + z_normal)
		if score > best_score:
			best_corner = corner
			best_score = score
	return best_corner

func _draw_leg_face_rectangle(base: Vector3, top: Vector3, inward_world: Vector3, face_normal: Vector3, cursor: int, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2, debug_colour: Color, raster_layers: Array[Dictionary], debug_leg_face_rectangles: Array[Dictionary]) -> int:
	cursor += 1
	var base_projection := _project(base, center, origin, forward, right, offset)
	var top_projection := _project(top, center, origin, forward, right, offset)
	var base_direction_projection := _project(base + inward_world * 0.05, center, origin, forward, right, offset)
	var top_direction_projection := _project(top + inward_world * 0.05, center, origin, forward, right, offset)
	if not bool(base_projection.visible) or not bool(top_projection.visible) or not bool(base_direction_projection.visible) or not bool(top_direction_projection.visible):
		return cursor
	var width_pixels := _leg_face_width_from_view_angle(face_normal, center, origin)
	if width_pixels <= 0:
		return cursor
	var base_screen_direction: Vector2 = base_direction_projection.pixel - base_projection.pixel
	var top_screen_direction: Vector2 = top_direction_projection.pixel - top_projection.pixel
	if absf(base_screen_direction.x) <= 0.0001 or absf(top_screen_direction.x) <= 0.0001:
		return cursor
	# The long edges are the important semantic edges. Lock both to logical-cell
	# boundaries, then put the opposite edge exactly N columns away. This keeps
	# a two-pixel face two cells wide instead of letting an arbitrary projected
	# float gain or lose a column while the camera barely moves.
	var shared_edge_x := float(roundi(base_projection.pixel.x))
	var horizontal_sign := signf(base_screen_direction.x)
	var opposite_edge_x := shared_edge_x + horizontal_sign * float(width_pixels)
	# Only X is quantized. Each far-edge endpoint retains the perspective Y
	# offset produced by its own projected 3D point, so the top/bottom edges do
	# not become artificial horizontal bands.
	var base_y_offset := base_screen_direction.y * float(width_pixels) / absf(base_screen_direction.x)
	var top_y_offset := top_screen_direction.y * float(width_pixels) / absf(top_screen_direction.x)
	var rectangle := PackedVector2Array([
		Vector2(shared_edge_x, base_projection.pixel.y),
		Vector2(shared_edge_x, top_projection.pixel.y),
		Vector2(opposite_edge_x, top_projection.pixel.y + top_y_offset),
		Vector2(opposite_edge_x, base_projection.pixel.y + base_y_offset),
	])
	var face_z := clampi(-int((float(base_projection.depth) + float(top_projection.depth)) * 500.0), -4000, -1)
	raster_layers.append({"points": rectangle, "colour": _axis_color(face_normal), "z": face_z})
	debug_leg_face_rectangles.append({"points": rectangle, "colour": debug_colour, "width_pixels": width_pixels})
	return cursor

func _leg_face_width_from_view_angle(face_normal: Vector3, center: Vector2, origin: Vector2) -> int:
	# Width is also camera-owned: all matching leg faces use the same integer
	# plateau until the *camera* crosses the next angular threshold.
	var to_camera := Vector3(origin.x - center.x, 0.5, origin.y - center.y)
	if to_camera.length_squared() <= 0.0001:
		return maximum_leg_pixels
	var facing := clampf(face_normal.normalized().dot(to_camera.normalized()), 0.0, 1.0)
	var degrees := rad_to_deg(acos(facing))
	# 0..45 is a fixed, intentional broad face.  45..90 divides the remaining
	# angle into integer plateaus: max=3 gives 3, then 2, 1, 0 by edge-on.
	if degrees <= 45.0:
		return maximum_leg_pixels
	var remaining := clampf((90.0 - degrees) / 45.0, 0.0, 1.0)
	return clampi(ceili(float(maximum_leg_pixels) * remaining), 0, maximum_leg_pixels)

func _logical_pixels(maximum: int) -> int:
	var close := minf(maximum_pixels_distance, one_pixel_distance - 0.01)
	var far := maxf(one_pixel_distance, close + 0.01)
	if current_camera_distance_readout <= close:
		return maximum
	if current_camera_distance_readout >= far:
		return 1
	return clampi(roundi(lerpf(1.0, float(maximum), inverse_lerp(far, close, current_camera_distance_readout))), 1, maximum)

func _post_base_corners(outer_corner: Vector3, width: float) -> Array[Vector3]:
	# The footprint point is the post's outside corner, shared exactly with the
	# shadow and seat slab. Each post grows inward toward the stool's centre,
	# never equally around the source point.
	var inward_x := -signf(outer_corner.x) * width
	var inward_z := -signf(outer_corner.z) * width
	return [outer_corner, outer_corner + Vector3(inward_x, 0.0, 0.0), outer_corner + Vector3(inward_x, 0.0, inward_z), outer_corner + Vector3(0.0, 0.0, inward_z)]

func _post_vertices(base_outer_corner: Vector3, top_outer_corner: Vector3, width: float) -> Array[Vector3]:
	var result := _post_base_corners(base_outer_corner, width)
	for corner in _post_base_corners(top_outer_corner, width):
		result.append(corner)
	return result

func _slab_vertices(base: Array[Vector3], height: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point in base:
		result.append(point)
	for point in base:
		result.append(point + Vector3.UP * height)
	return result

func _draw_shadow(points: Array[Vector3], center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2, raster_layers: Array[Dictionary]) -> void:
	var projected := PackedVector2Array()
	for point in points:
		var value := _project(point, center, origin, forward, right, offset)
		if not value.visible:
			return
		projected.append(value.pixel)
	raster_layers.append({"points": projected, "colour": shadow_color, "z": -4096})

func _draw_box(vertices: Array[Vector3], cursor: int, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2, raster_layers: Array[Dictionary]) -> int:
	var box_center := Vector3.ZERO
	for point in vertices:
		box_center += point
	box_center /= vertices.size()
	var faces: Array = [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	for ids in faces:
		cursor += 1
		var points: Array[Vector3] = []
		for id in ids:
			points.append(vertices[int(id)])
		var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
		var local_center := Vector3.ZERO
		for point in points:
			local_center += point
		local_center /= points.size()
		if normal.dot(local_center - box_center) < 0.0:
			normal = -normal
			points.reverse()
		var visible := _face_visible(normal, local_center, center, origin)
		var pixels := PackedVector2Array()
		var average_depth := 0.0
		for point in points:
			var projected := _project(point, center, origin, forward, right, offset)
			visible = visible and bool(projected.visible)
			pixels.append(projected.pixel)
			average_depth += float(projected.depth)
		if visible:
			# The top plane receives the final face slot at a shared cell so it
			# cannot be cut by a side plane at the seat's upper rim.
			var face_z := clampi(-int(average_depth / pixels.size() * 1000.0), -4000, 0)
			if normal.y > 0.5:
				face_z += 2
			raster_layers.append({"points": pixels, "colour": _axis_color(normal), "z": face_z})
	return cursor

func _face_visible(normal: Vector3, face_center: Vector3, center: Vector2, origin: Vector2) -> bool:
	var camera := Vector3(origin.x - center.x, 0.5, origin.y - center.y)
	return normal.dot(camera - face_center) > 0.0

func _axis_color(normal: Vector3) -> Color:
	var unit := normal.normalized()
	if absf(unit.y) >= maxf(absf(unit.x), absf(unit.z)):
		return top_color
	if absf(unit.x) >= absf(unit.z):
		return x_side_color
	return z_side_color

func _project(point: Vector3, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> Dictionary:
	var relative := center + Vector2(point.x, point.z) - origin
	var depth := relative.dot(forward)
	if depth <= 0.01:
		return {"visible": false, "pixel": Vector2.ZERO, "depth": depth}
	return {"visible": true, "pixel": Vector2(80.0 + relative.dot(right) / depth * 128.0, 31.5 + (0.5 - point.y) / depth * 128.0) + offset, "depth": depth}

func _load_style() -> void:
	style = load(STYLE_PATH)
	if style == null:
		style = STYLE_SCRIPT.new()
		ResourceSaver.save(style, STYLE_PATH)
	for key in _style_values():
		set(key, style.get(key))
	_saved = _style_values()

func _style_values() -> Dictionary:
	return {"top_color": top_color, "x_side_color": x_side_color, "z_side_color": z_side_color, "shadow_color": shadow_color, "footprint_x": footprint_x, "footprint_y": footprint_y, "leg_height": leg_height, "maximum_leg_pixels": maximum_leg_pixels, "maximum_seat_height_pixels": maximum_seat_height_pixels, "maximum_pixels_distance": maximum_pixels_distance, "one_pixel_distance": one_pixel_distance, "show_debug_geometry": show_debug_geometry, "show_logical_pixel_grid": show_logical_pixel_grid}
