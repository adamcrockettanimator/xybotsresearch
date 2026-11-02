## Minimal semantic stool: sparse authoring points become four post boxes plus
## one seat box. Debug construction belongs to the window; paint belongs only
## to this 160x120 logical SubViewport.
extends Node2D

const LOGICAL_SIZE := Vector2i(160, 120)
const STYLE_PATH := "res://resources/semantic_stool_style.tres"
const STYLE_SCRIPT := preload("res://scripts/semantic_stool_style.gd")
const FLOOR_GRADIENT_SHADER := preload("res://scripts/semantic_stool_floor_gradient.gdshader")
# Stable ordered coverage for whole-pixel leg LOD. The retained face pixels
# remain opaque; only an outer pixel strip fades during its staggered cull.
const LEG_LOD_DITHER_THRESHOLDS := [0.125, 0.375, 0.625, 0.875]
const LEG_LOD_DITHER_FADE_COVERAGE := 0.25
class StoolRasterLayer extends Node2D:
	# One logical-canvas node owns every semantic cube face.  Keeping the
	# inferred faces as 95 MeshInstance2D/ShaderMaterial descendants made the
	# Remote Inspector serialize a >160 MB resource tree before an artist could
	# inspect a single control.
	var layers: Array[Dictionary] = []
	# Final logical-pixel accents, drawn after semantic face fills.
	var raster_strokes: Array[Dictionary] = []

	func set_layers(new_layers: Array[Dictionary], new_raster_strokes: Array[Dictionary] = []) -> void:
		if layers == new_layers and raster_strokes == new_raster_strokes:
			return
		layers = new_layers
		raster_strokes = new_raster_strokes
		queue_redraw()

	func _draw() -> void:
		for layer in layers:
			if bool(layer.get("raster_stroke", false)):
				_draw_raster_stroke(layer)
				continue
			var points: PackedVector2Array = layer["points"]
			if points.size() >= 3:
				var under_table_strength := float(layer.get("under_table_leg_darkening", 0.0))
				var exterior_brightening := float(layer.get("exterior_corner_brightening", 0.0))
				if under_table_strength > 0.001:
					_draw_under_table_leg_gradient(points, layer["colour"], under_table_strength)
				elif exterior_brightening > 0.001:
					_draw_exterior_corner_brightening(points, layer["colour"], exterior_brightening, float(layer.get("brightening_center_x", 80.0)), float(layer.get("brightening_fade_pixels", 24.0)))
				else:
					draw_colored_polygon(points, layer["colour"])
		for stroke in raster_strokes:
			_draw_raster_stroke(stroke)

	func _draw_under_table_leg_gradient(points: PackedVector2Array, colour: Color, strength: float) -> void:
		# Rasterize only this leg face. The multiplier falls from its top (the
		# underside of the seat) to its foot, so it never brightens either axis.
		var top_y := INF
		var bottom_y := -INF
		var min_x := INF
		var max_x := -INF
		for point in points:
			top_y = minf(top_y, point.y)
			bottom_y = maxf(bottom_y, point.y)
			min_x = minf(min_x, point.x)
			max_x = maxf(max_x, point.x)
		var span := maxf(bottom_y - top_y, 0.001)
		for y in range(maxi(0, floori(top_y)), mini(LOGICAL_SIZE.y, ceili(bottom_y) + 1)):
			var height_fraction := clampf((float(y) + 0.5 - top_y) / span, 0.0, 1.0)
			var multiplier := clampf(1.0 - strength * (1.0 - height_fraction), 0.0, 1.0)
			var row_colour := Color(colour.r * multiplier, colour.g * multiplier, colour.b * multiplier, colour.a)
			for x in range(maxi(0, floori(min_x)), mini(LOGICAL_SIZE.x, ceili(max_x) + 1)):
				if Geometry2D.is_point_in_polygon(Vector2(float(x) + 0.5, float(y) + 0.5), points):
					draw_rect(Rect2(Vector2(x, y), Vector2.ONE), row_colour, true)

	func _draw_exterior_corner_brightening(points: PackedVector2Array, colour: Color, strength: float, center_x: float, fade_pixels: float) -> void:
		# Exterior-only light grows from the camera-near corner and never applies
		# a multiplier below one, so this pass cannot darken a material.
		var min_x := INF
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		for point in points:
			min_x = minf(min_x, point.x)
			max_x = maxf(max_x, point.x)
			min_y = minf(min_y, point.y)
			max_y = maxf(max_y, point.y)
		var safe_fade := maxf(fade_pixels, 0.001)
		for y in range(maxi(0, floori(min_y)), mini(LOGICAL_SIZE.y, ceili(max_y) + 1)):
			for x in range(maxi(0, floori(min_x)), mini(LOGICAL_SIZE.x, ceili(max_x) + 1)):
				var cell_center := Vector2(float(x) + 0.5, float(y) + 0.5)
				if not Geometry2D.is_point_in_polygon(cell_center, points):
					continue
				var fade := 1.0 - clampf(absf(cell_center.x - center_x) / safe_fade, 0.0, 1.0)
				var multiplier := 1.0 + strength * fade
				var cell_colour := Color(minf(colour.r * multiplier, 1.0), minf(colour.g * multiplier, 1.0), minf(colour.b * multiplier, 1.0), colour.a)
				draw_rect(Rect2(Vector2(x, y), Vector2.ONE), cell_colour, true)

	func _draw_raster_stroke(stroke: Dictionary) -> void:
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
		var fade_end := int(stroke.get("fade_end_cells", 0))
		while true:
			var cell_colour := colour
			if fade_end > 0:
				cell_colour.a *= clampf(float(cell_count - cell_index) / float(fade_end), 0.0, 1.0)
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
@export_file("*.tres") var style_path := STYLE_PATH
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
@export_category("Near edge highlight")
@export var near_edge_highlight_color := Color8(244, 186, 94)
@export_range(0.0, 1.0, 0.01) var near_edge_highlight_end_fade := 0.30
@export_range(0.02, 0.75, 0.01) var near_edge_highlight_angle_fade := 0.28
@export_range(0.10, 12.0, 0.05) var near_edge_highlight_full_distance := 1.50
@export_range(0.15, 16.0, 0.05) var near_edge_highlight_hidden_distance := 3.00
@export_category("Seat slats")
@export_range(1, 8, 1) var seat_slat_count := 1
@export var seat_slat_shadow_color := Color8(87, 65, 47)
@export var seat_slat_highlight_color := Color8(220, 180, 122)
@export_range(0.10, 12.0, 0.05) var seat_slat_shadow_full_distance := 2.50
@export_range(0.15, 16.0, 0.05) var seat_slat_shadow_hidden_distance := 4.50
@export_range(0.10, 12.0, 0.05) var seat_slat_highlight_full_distance := 1.25
@export_range(0.15, 16.0, 0.05) var seat_slat_highlight_hidden_distance := 2.50
@export_category("Floor darkening")
@export_range(0.0, 1.0, 0.01) var floor_darkening_strength := 0.32
@export_category("Underside pixel shadow")
@export var underside_shadow_color := Color8(48, 35, 27, 180)
# Multiplies the authored shadow colour alpha. Zero removes the semantic
# bottom-edge strokes; one preserves the colour's full authored opacity.
@export_range(0.0, 1.0, 0.01) var underside_shadow_fade := 0.72
@export_category("Under-table leg darkening")
# Applied only to the leg face pixels. It is darkest directly beneath the
# tabletop/seat and fades to the authored axis colour at the floor.
@export_range(0.0, 1.0, 0.01) var under_table_leg_darkening_strength := 0.42
@export_category("Exterior corner brightening")
# Brightens only exterior leg/table-side pixels from the camera-near highlighted
# corner outward; it never participates in the under-table face pass.
@export_range(0.0, 1.0, 0.01) var exterior_corner_brightening_strength := 0.22
@export_range(1.0, 120.0, 1.0) var exterior_corner_brightening_fade_pixels := 28.0
@export_category("Edge-on face fade")
# A semantic side face has no meaningful horizontal identity once its physical
# projection becomes this narrow. Its fade prevents the fixed logical-width
# construction from extrapolating an almost-vertical 3D direction.
@export_range(0.05, 8.0, 0.05) var face_horizontal_span_hidden_pixels := 0.75
@export_range(0.10, 8.0, 0.05) var face_horizontal_span_full_pixels := 1.50
@export_category("Full-window debug construction")
@export var show_debug_geometry := true
@export var show_logical_pixel_grid := false
@export_category("Read only")
@export var current_camera_distance_readout := 0.0
@export var current_leg_pixel_width_readout := 1.0
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
	var floor_gradient_material := ShaderMaterial.new()
	floor_gradient_material.shader = FLOOR_GRADIENT_SHADER
	display.material = floor_gradient_material
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
		if ResourceSaver.save(style, style_path) == OK:
			_saved = _style_values()
	if is_instance_valid(debug_layer):
		debug_layer.queue_free()

func _process(_delta: float) -> void:
	var values := _style_values()
	_style_dirty = style != null and values != _saved

func set_stool(center: Vector2, camera_origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> void:
	current_camera_distance_readout = center.distance_to(camera_origin)
	var leg_lod := _logical_pixel_lod(maximum_leg_pixels)
	var leg_narrow_pixels: int = leg_lod["narrow_pixels"]
	var leg_wide_pixels: int = leg_lod["wide_pixels"]
	var leg_wide_coverage: float = leg_lod["wide_coverage"]
	var seat_pixels := _logical_pixels(maximum_seat_height_pixels)
	# Leg width is deliberately angle-owned, not a changing projected cube
	# radius.  Each visible normal gets a stable integer rectangle width.
	current_leg_pixel_width_readout = leg_lod["continuous_pixels"]
	current_seat_height_pixel_readout = seat_pixels
	# Keep live build data local. Remote Inspector exposes ordinary script
	# members, and rewriting these arrays every render frame made a single
	# slider drag accumulate an enormous debugger packet.
	var debug_leg_face_rectangles: Array[Dictionary] = []
	var raster_layers: Array[Dictionary] = []
	var near_edge_highlight_strokes: Array[Dictionary] = []
	var depth := maxf((center - camera_origin).dot(forward), 0.05)
	# This converts an artist-selected logical width into a world-space radius
	# for this camera pose. The generated post itself changes size; its raster
	# remains the requested 1..N logical pixels wide.
	var world_per_pixel := depth / 128.0
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
	var near_x := 1.0 if stool_to_camera.x >= 0.0 else -1.0
	var near_z := 1.0 if stool_to_camera.z >= 0.0 else -1.0
	# Unlike the discrete highlighted corner, the exterior-light origin follows
	# the camera direction continuously along the near perimeter. This prevents
	# the horizontal gradient from popping when a camera axis changes sign.
	var camera_horizontal := Vector2(stool_to_camera.x, stool_to_camera.z).normalized()
	var exterior_light_origin := Vector3(camera_horizontal.x * footprint_x * 0.5, leg_height, camera_horizontal.y * footprint_y * 0.5)
	var nearest_corner_x: float = float(_project(exterior_light_origin, center, camera_origin, forward, right, offset).pixel.x)
	var near_edge_highlight_alpha := _line_detail_fade(current_camera_distance_readout, near_edge_highlight_full_distance, near_edge_highlight_hidden_distance)
	var near_edge_highlight_colour := near_edge_highlight_color
	near_edge_highlight_colour.a *= near_edge_highlight_alpha
	_draw_shadow(ground, center, camera_origin, forward, right, offset, raster_layers)
	var debug_ground := PackedVector2Array()
	var debug_tops := PackedVector2Array()
	var debug_squares: Array[PackedVector2Array] = []
	# Assign the LOD stagger by camera depth, not the arbitrary footprint order:
	# closest gets the lowest threshold and farthest gets the highest. Thus the
	# far legs disappear first when receding, while near legs return first.
	var depth_sorted_leg_indices := [0, 1, 2, 3]
	depth_sorted_leg_indices.sort_custom(func(a: int, b: int) -> bool:
		var a_depth := (center + Vector2(ground[a].x, ground[a].z) - camera_origin).dot(forward)
		var b_depth := (center + Vector2(ground[b].x, ground[b].z) - camera_origin).dot(forward)
		return a_depth < b_depth
	)
	var cursor := 0
	for leg_index in ground.size():
		var point: Vector3 = ground[leg_index]
		var top := point + Vector3.UP * leg_height
		var leg_cube_world_width := world_per_pixel * float(leg_wide_pixels)
		# The narrow part is never faded: it is the pixel row that survives this
		# distance LOD transition.
		var leg_depth_rank := depth_sorted_leg_indices.find(leg_index)
		var leg_dither_threshold: float = LEG_LOD_DITHER_THRESHOLDS[leg_depth_rank]
		var leg_transition_coverage := _leg_transition_coverage(leg_wide_coverage, leg_dither_threshold)
		var secondary_face_opacity := 1.0
		var strip_opacity := leg_transition_coverage
		if leg_narrow_pixels == 1 and leg_wide_pixels == 2:
			# Reserve equal global halves for the two visual states. All legs first
			# settle at one pixel per side; only in the second half do outer strips
			# expand the faces to two pixels. Each phase is still dither-staggered.
			secondary_face_opacity = _leg_transition_coverage(minf(leg_wide_coverage * 2.0, 1.0), leg_dither_threshold)
			strip_opacity = _leg_transition_coverage(maxf((leg_wide_coverage - 0.5) * 2.0, 0.0), leg_dither_threshold)
		cursor = _draw_camera_facing_leg_rectangles(point, leg_height, leg_cube_world_width, leg_wide_pixels, 0, leg_narrow_pixels, 1.0, secondary_face_opacity, camera_x_normal, camera_z_normal, exterior_corner_brightening_strength, nearest_corner_x, exterior_corner_brightening_fade_pixels, cursor, center, camera_origin, forward, right, offset, raster_layers, debug_leg_face_rectangles)
		if leg_wide_pixels != leg_narrow_pixels:
			if strip_opacity > 0.001:
				cursor = _draw_camera_facing_leg_rectangles(point, leg_height, leg_cube_world_width, leg_wide_pixels, leg_narrow_pixels, leg_wide_pixels - leg_narrow_pixels, strip_opacity, secondary_face_opacity, camera_x_normal, camera_z_normal, exterior_corner_brightening_strength, nearest_corner_x, exterior_corner_brightening_fade_pixels, cursor, center, camera_origin, forward, right, offset, raster_layers, debug_leg_face_rectangles)
		# Every post contributes angle-weighted candidate edges. The outgoing
		# corner fades as a new camera-facing corner fades in at side crossings.
		_append_camera_facing_leg_highlights(raster_layers, point, leg_cube_world_width, leg_height, near_edge_highlight_colour, center, camera_origin, forward, right, offset)
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
	var underside_colour := underside_shadow_color
	underside_colour.a *= underside_shadow_fade
	cursor = _draw_box(_slab_vertices(seat_base, seat_height), cursor, center, camera_origin, forward, right, offset, raster_layers, underside_colour, world_per_pixel * float(leg_narrow_pixels), exterior_corner_brightening_strength, nearest_corner_x, exterior_corner_brightening_fade_pixels)
	_update_floor_gradient(center, camera_origin, forward, right, offset, ground, leg_height + seat_height)
	# The nearest seat corner receives a crate-like raster Y: vertical join plus
	# two top arms that remain solid at the join and fade toward their side ends.
	var seat_top_corner := Vector3(near_x * footprint_x * 0.5, leg_height + seat_height, near_z * footprint_y * 0.5)
	var seat_bottom_corner := seat_top_corner - Vector3.UP * seat_height
	var arm_fraction := clampf(near_edge_highlight_end_fade, 0.0, 1.0)
	var arm_fade_cells := maxi(1, roundi(1.0 + arm_fraction * 3.0))
	# Foot shadows belong to the same depth layer as their semantic leg faces.
	_append_leg_foot_shadow_layers(raster_layers, debug_leg_face_rectangles, underside_colour)
	_append_seat_slat_strokes(near_edge_highlight_strokes, leg_height + seat_height, stool_to_camera, center, camera_origin, forward, right, offset)
	_append_near_edge_highlight(near_edge_highlight_strokes, seat_bottom_corner, seat_top_corner, near_edge_highlight_colour, 1, false, center, camera_origin, forward, right, offset)
	_append_near_edge_highlight(near_edge_highlight_strokes, seat_top_corner, seat_top_corner + Vector3(-near_x * footprint_x * arm_fraction, 0.0, 0.0), near_edge_highlight_colour, arm_fade_cells, false, center, camera_origin, forward, right, offset)
	_append_near_edge_highlight(near_edge_highlight_strokes, seat_top_corner, seat_top_corner + Vector3(0.0, 0.0, -near_z * footprint_y * arm_fraction), near_edge_highlight_colour, arm_fade_cells, false, center, camera_origin, forward, right, offset)
	if is_instance_valid(raster_layer):
		raster_layers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["z"]) < int(b["z"]))
		raster_layer.set_layers(raster_layers, near_edge_highlight_strokes)
	if is_instance_valid(debug_overlay):
		debug_overlay.set_geometry(_project(Vector3.ZERO, center, camera_origin, forward, right, offset).pixel, debug_ground, debug_tops, debug_squares, debug_leg_face_rectangles, show_debug_geometry)
	if is_instance_valid(grid_overlay):
		grid_overlay.set_enabled(show_logical_pixel_grid)

func _draw_camera_facing_leg_rectangles(footprint_corner: Vector3, height: float, cube_width: float, angle_width: int, logical_start: int, logical_width: int, opacity: float, secondary_face_opacity: float, x_normal: Vector3, z_normal: Vector3, exterior_brightening: float, brightening_center_x: float, brightening_fade_pixels: float, cursor: int, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2, raster_layers: Array[Dictionary], debug_leg_face_rectangles: Array[Dictionary]) -> int:
	# A footprint point is the outside corner of the physical post, but it is
	# not always the corner that faces the camera. Find the one corner where the
	# selected X and Z planes meet, then both semantic rectangles share it.
	var visible_base := _camera_facing_post_corner(footprint_corner, cube_width, x_normal, z_normal)
	var visible_top := visible_base + Vector3.UP * height
	# The X face runs away from its shared edge along -Z normal; the Z face runs
	# away along -X normal. This is true for every leg, including the far pair.
	var camera_direction := Vector3(origin.x - center.x, 0.5, origin.y - center.y).normalized()
	var x_is_primary := x_normal.dot(camera_direction) >= z_normal.dot(camera_direction)
	# A face is under the table only when its normal points from this corner
	# back toward the footprint centre. Outside planes remain unshadowed.
	var corner_from_center := Vector3(footprint_corner.x, 0.0, footprint_corner.z)
	var x_is_under_table := x_normal.dot(corner_from_center) < 0.0
	var z_is_under_table := z_normal.dot(corner_from_center) < 0.0
	if x_is_primary:
		cursor = _draw_leg_face_rectangle(visible_base, visible_top, -z_normal, x_normal, x_is_under_table, exterior_brightening if not x_is_under_table else 0.0, brightening_center_x, brightening_fade_pixels, cube_width, angle_width, logical_start, logical_width, opacity, cursor, center, origin, forward, right, offset, Color(1.0, 0.28, 0.04, 0.96), raster_layers, debug_leg_face_rectangles)
		if angle_width > 1 and secondary_face_opacity > 0.001:
			cursor = _draw_leg_face_rectangle(visible_base, visible_top, -x_normal, z_normal, z_is_under_table, exterior_brightening if not z_is_under_table else 0.0, brightening_center_x, brightening_fade_pixels, cube_width, angle_width, logical_start, logical_width, opacity * secondary_face_opacity, cursor, center, origin, forward, right, offset, Color(0.95, 0.25, 1.0, 0.96), raster_layers, debug_leg_face_rectangles)
	else:
		cursor = _draw_leg_face_rectangle(visible_base, visible_top, -x_normal, z_normal, z_is_under_table, exterior_brightening if not z_is_under_table else 0.0, brightening_center_x, brightening_fade_pixels, cube_width, angle_width, logical_start, logical_width, opacity, cursor, center, origin, forward, right, offset, Color(0.95, 0.25, 1.0, 0.96), raster_layers, debug_leg_face_rectangles)
		if angle_width > 1 and secondary_face_opacity > 0.001:
			cursor = _draw_leg_face_rectangle(visible_base, visible_top, -z_normal, x_normal, x_is_under_table, exterior_brightening if not x_is_under_table else 0.0, brightening_center_x, brightening_fade_pixels, cube_width, angle_width, logical_start, logical_width, opacity * secondary_face_opacity, cursor, center, origin, forward, right, offset, Color(1.0, 0.28, 0.04, 0.96), raster_layers, debug_leg_face_rectangles)
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

func _draw_leg_face_rectangle(base: Vector3, top: Vector3, inward_world: Vector3, face_normal: Vector3, is_under_table: bool, exterior_brightening: float, brightening_center_x: float, brightening_fade_pixels: float, cube_width: float, angle_width: int, logical_start: int, logical_width: int, opacity: float, cursor: int, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2, debug_colour: Color, raster_layers: Array[Dictionary], debug_leg_face_rectangles: Array[Dictionary]) -> int:
	cursor += 1
	var base_projection := _project(base, center, origin, forward, right, offset)
	var top_projection := _project(top, center, origin, forward, right, offset)
	var base_direction_projection := _project(base + inward_world * 0.05, center, origin, forward, right, offset)
	var top_direction_projection := _project(top + inward_world * 0.05, center, origin, forward, right, offset)
	if not bool(base_projection.visible) or not bool(top_projection.visible) or not bool(base_direction_projection.visible) or not bool(top_direction_projection.visible):
		return cursor
	var visible_width := _leg_face_width_from_view_angle(face_normal, center, origin, angle_width)
	if visible_width <= logical_start:
		return cursor
	var width_pixels := mini(logical_width, visible_width - logical_start)
	# Measure the physical post face, rather than the tiny direction probe used
	# for its slope. As this span approaches zero at an edge-on camera angle,
	# fading prevents the fixed-width semantic rectangle from being extrapolated
	# many rows high by its dy / dx construction.
	var base_face_projection := _project(base + inward_world * cube_width, center, origin, forward, right, offset)
	var top_face_projection := _project(top + inward_world * cube_width, center, origin, forward, right, offset)
	if not bool(base_face_projection.visible) or not bool(top_face_projection.visible):
		return cursor
	var horizontal_span := minf(absf(base_face_projection.pixel.x - base_projection.pixel.x), absf(top_face_projection.pixel.x - top_projection.pixel.x))
	var fade_hidden := minf(face_horizontal_span_hidden_pixels, face_horizontal_span_full_pixels - 0.01)
	var fade_full := maxf(face_horizontal_span_full_pixels, fade_hidden + 0.01)
	var face_fade := smoothstep(fade_hidden, fade_full, horizontal_span)
	if face_fade <= 0.001:
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
	var start_x := shared_edge_x + horizontal_sign * float(logical_start)
	var opposite_edge_x := start_x + horizontal_sign * float(width_pixels)
	# Only X is quantized. Each far-edge endpoint retains the perspective Y
	# offset produced by its own projected 3D point, so the top/bottom edges do
	# not become artificial horizontal bands.
	var base_start_y_offset := base_screen_direction.y * float(logical_start) / absf(base_screen_direction.x)
	var top_start_y_offset := top_screen_direction.y * float(logical_start) / absf(top_screen_direction.x)
	var base_y_offset := base_screen_direction.y * float(logical_start + width_pixels) / absf(base_screen_direction.x)
	var top_y_offset := top_screen_direction.y * float(logical_start + width_pixels) / absf(top_screen_direction.x)
	var rectangle := PackedVector2Array([
		Vector2(start_x, base_projection.pixel.y + base_start_y_offset),
		Vector2(start_x, top_projection.pixel.y + top_start_y_offset),
		Vector2(opposite_edge_x, top_projection.pixel.y + top_y_offset),
		Vector2(opposite_edge_x, base_projection.pixel.y + base_y_offset),
	])
	var face_z := clampi(-int((float(base_projection.depth) + float(top_projection.depth)) * 500.0), -4000, -1)
	var face_colour := _axis_color(face_normal)
	face_colour.a *= face_fade * opacity
	debug_colour.a *= face_fade * opacity
	raster_layers.append({"points": rectangle, "colour": face_colour, "z": face_z, "under_table_leg_darkening": under_table_leg_darkening_strength if is_under_table else 0.0, "exterior_corner_brightening": exterior_brightening, "brightening_center_x": brightening_center_x, "brightening_fade_pixels": brightening_fade_pixels})
	debug_leg_face_rectangles.append({"points": rectangle, "colour": debug_colour, "width_pixels": width_pixels, "z": face_z})
	return cursor

func _leg_face_width_from_view_angle(face_normal: Vector3, center: Vector2, origin: Vector2, logical_width: int) -> int:
	# Width is also camera-owned: all matching leg faces use the same integer
	# plateau until the *camera* crosses the next angular threshold.
	var to_camera := Vector3(origin.x - center.x, 0.5, origin.y - center.y)
	if to_camera.length_squared() <= 0.0001:
		return logical_width
	var facing := clampf(face_normal.normalized().dot(to_camera.normalized()), 0.0, 1.0)
	var degrees := rad_to_deg(acos(facing))
	# 0..45 is a fixed, intentional broad face.  45..90 divides the remaining
	# angle into integer plateaus: max=3 gives 3, then 2, 1, 0 by edge-on.
	if degrees <= 45.0:
		return logical_width
	var remaining := clampf((90.0 - degrees) / 45.0, 0.0, 1.0)
	return clampi(ceili(float(logical_width) * remaining), 0, logical_width)

func _logical_pixels(maximum: int) -> int:
	var close := minf(maximum_pixels_distance, one_pixel_distance - 0.01)
	var far := maxf(one_pixel_distance, close + 0.01)
	if current_camera_distance_readout <= close:
		return maximum
	if current_camera_distance_readout >= far:
		return 1
	return clampi(roundi(lerpf(1.0, float(maximum), inverse_lerp(far, close, current_camera_distance_readout))), 1, maximum)

func _logical_pixel_lod(maximum: int) -> Dictionary:
	var close := minf(maximum_pixels_distance, one_pixel_distance - 0.01)
	var far := maxf(one_pixel_distance, close + 0.01)
	var continuous_pixels := clampf(lerpf(1.0, float(maximum), inverse_lerp(far, close, current_camera_distance_readout)), 1.0, float(maximum))
	var narrow_pixels := clampi(floori(continuous_pixels), 1, maximum)
	var wide_pixels := clampi(ceili(continuous_pixels), 1, maximum)
	if narrow_pixels == wide_pixels:
		return {"continuous_pixels": continuous_pixels, "narrow_pixels": narrow_pixels, "wide_pixels": wide_pixels, "wide_coverage": 0.0}
	return {"continuous_pixels": continuous_pixels, "narrow_pixels": narrow_pixels, "wide_pixels": wide_pixels, "wide_coverage": continuous_pixels - float(narrow_pixels)}

func _leg_transition_coverage(wide_coverage: float, threshold: float) -> float:
	return smoothstep(threshold, minf(1.0, threshold + LEG_LOD_DITHER_FADE_COVERAGE), wide_coverage)

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

func _update_floor_gradient(center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2, ground: Array[Vector3], top_height: float) -> void:
	if display == null or not (display.material is ShaderMaterial):
		return
	var floor_y := -INF
	var top_y := INF
	for point in ground:
		floor_y = maxf(floor_y, _project(point, center, origin, forward, right, offset).pixel.y)
		var top_point := point + Vector3.UP * top_height
		top_y = minf(top_y, _project(top_point, center, origin, forward, right, offset).pixel.y)
	var material := display.material as ShaderMaterial
	material.set_shader_parameter("floor_logical_y", floor_y)
	material.set_shader_parameter("top_logical_y", minf(top_y, floor_y - 0.001))
	material.set_shader_parameter("floor_darkening_strength", floor_darkening_strength)

func _append_leg_foot_shadow_layers(raster_layers: Array[Dictionary], leg_face_rectangles: Array[Dictionary], colour: Color) -> void:
	if colour.a <= 0.001:
		return
	for rectangle in leg_face_rectangles:
		var polygon: PackedVector2Array = rectangle["points"]
		if polygon.size() == 4:
			raster_layers.append({"raster_stroke": true, "from": polygon[3], "to": polygon[0], "colour": colour, "fade_end_cells": 0, "z": int(rectangle["z"]) + 1})

func _append_seat_slat_strokes(strokes: Array[Dictionary], top_height: float, stool_to_camera: Vector3, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> void:
	var shadow_colour := seat_slat_shadow_color
	shadow_colour.a *= _line_detail_fade(current_camera_distance_readout, seat_slat_shadow_full_distance, seat_slat_shadow_hidden_distance)
	var highlight_colour := seat_slat_highlight_color
	highlight_colour.a *= _line_detail_fade(current_camera_distance_readout, seat_slat_highlight_full_distance, seat_slat_highlight_hidden_distance)
	if shadow_colour.a <= 0.001 and highlight_colour.a <= 0.001:
		return
	# A bench grows along its longer authored dimension. Slats follow that grain,
	# while their seam positions stay evenly distributed across the shorter span.
	var run_along_x := footprint_x >= footprint_y
	for slat_index in seat_slat_count:
		var seam_fraction := float(slat_index + 1) / float(seat_slat_count + 1)
		var from: Vector3
		var to: Vector3
		var side_sample: Vector3
		if run_along_x:
			var z := lerpf(-footprint_y * 0.5, footprint_y * 0.5, seam_fraction)
			from = Vector3(-footprint_x * 0.5, top_height, z)
			to = Vector3(footprint_x * 0.5, top_height, z)
			side_sample = Vector3(0.0, top_height, z + signf(stool_to_camera.z) * 0.01)
		else:
			var x := lerpf(-footprint_x * 0.5, footprint_x * 0.5, seam_fraction)
			from = Vector3(x, top_height, -footprint_y * 0.5)
			to = Vector3(x, top_height, footprint_y * 0.5)
			side_sample = Vector3(x + signf(stool_to_camera.x) * 0.01, top_height, 0.0)
		var from_projection := _project(from, center, origin, forward, right, offset)
		var to_projection := _project(to, center, origin, forward, right, offset)
		var side_projection := _project(side_sample, center, origin, forward, right, offset)
		if not bool(from_projection.visible) or not bool(to_projection.visible) or not bool(side_projection.visible):
			continue
		if shadow_colour.a > 0.001:
			strokes.append({"from": from_projection.pixel, "to": to_projection.pixel, "colour": shadow_colour, "fade_end_cells": 1})
		if highlight_colour.a > 0.001:
			var midpoint: Vector2 = (from_projection.pixel + to_projection.pixel) * 0.5
			var line_direction: Vector2 = to_projection.pixel - from_projection.pixel
			if line_direction.length_squared() > 0.0001:
				line_direction = line_direction.normalized()
				var highlight_normal := Vector2(-line_direction.y, line_direction.x)
				# Select the camera-near side, then quantize one offset once. The
				# highlight is an integer-cell translation of the shadow's exact
				# Bresenham line, so both paths have the same stepping pattern.
				if highlight_normal.dot(side_projection.pixel - midpoint) < 0.0:
					highlight_normal = -highlight_normal
				var highlight_offset := Vector2(float(roundi(highlight_normal.x)), float(roundi(highlight_normal.y)))
				strokes.append({"from": from_projection.pixel + highlight_offset, "to": to_projection.pixel + highlight_offset, "colour": highlight_colour, "fade_end_cells": 1})

func _append_near_edge_highlight(strokes: Array[Dictionary], from: Vector3, to: Vector3, colour: Color, fade_end_cells: int, inset_endpoints: bool, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> void:
	if colour.a <= 0.001:
		return
	var from_projection := _project(from, center, origin, forward, right, offset)
	var to_projection := _project(to, center, origin, forward, right, offset)
	if not bool(from_projection.visible) or not bool(to_projection.visible):
		return
	var from_pixel: Vector2 = from_projection.pixel
	var to_pixel: Vector2 = to_projection.pixel
	if inset_endpoints and from_pixel.distance_to(to_pixel) > 2.0:
		var direction := (to_pixel - from_pixel).normalized()
		from_pixel += direction
		to_pixel -= direction
	strokes.append({"from": from_pixel, "to": to_pixel, "colour": colour, "fade_end_cells": fade_end_cells})

func _append_leg_edge_highlight(raster_layers: Array[Dictionary], from: Vector3, to: Vector3, colour: Color, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> void:
	if colour.a <= 0.001:
		return
	var from_projection := _project(from, center, origin, forward, right, offset)
	var to_projection := _project(to, center, origin, forward, right, offset)
	if not bool(from_projection.visible) or not bool(to_projection.visible):
		return
	var stroke_z := clampi(-int((float(from_projection.depth) + float(to_projection.depth)) * 500.0) + 1, -4000, 0)
	raster_layers.append({"raster_stroke": true, "from": from_projection.pixel, "to": to_projection.pixel, "colour": colour, "fade_end_cells": 1, "z": stroke_z})

func _append_camera_facing_leg_highlights(raster_layers: Array[Dictionary], footprint_corner: Vector3, cube_width: float, height: float, colour: Color, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> void:
	var corners := _post_base_corners(footprint_corner, cube_width)
	var post_center := Vector3.ZERO
	for corner in corners:
		post_center += corner
	post_center /= float(corners.size())
	var camera_horizontal := Vector2(origin.x - center.x, origin.y - center.y)
	if camera_horizontal.length_squared() <= 0.0001:
		return
	camera_horizontal = camera_horizontal.normalized()
	for corner in corners:
		var local := corner - post_center
		var x_weight := smoothstep(-near_edge_highlight_angle_fade, near_edge_highlight_angle_fade, signf(local.x) * camera_horizontal.x)
		var z_weight := smoothstep(-near_edge_highlight_angle_fade, near_edge_highlight_angle_fade, signf(local.z) * camera_horizontal.y)
		var corner_weight := x_weight * z_weight
		if corner_weight <= 0.001:
			continue
		var candidate_colour := colour
		candidate_colour.a *= corner_weight
		_append_leg_edge_highlight(raster_layers, corner, corner + Vector3.UP * height, candidate_colour, center, origin, forward, right, offset)

func _draw_box(vertices: Array[Vector3], cursor: int, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2, raster_layers: Array[Dictionary], lower_edge_shadow: Color = Color.TRANSPARENT, leg_inset_world: float = 0.0, exterior_brightening: float = 0.0, brightening_center_x: float = 80.0, brightening_fade_pixels: float = 24.0) -> int:
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
			# The seat is a cap over all posts. Keep every seat face after the leg
			# layers so a rear post/highlight cannot show through its top at an
			# oblique camera angle. Its top plane still wins its shared rim cell.
			var face_z := clampi(-int(average_depth / pixels.size() * 1000.0), -4000, 0)
			face_z += 4096
			if normal.y > 0.5:
				face_z += 2
			var box_layer := {"points": pixels, "colour": _axis_color(normal), "z": face_z}
			if absf(normal.y) < 0.5:
				box_layer["exterior_corner_brightening"] = exterior_brightening
				box_layer["brightening_center_x"] = brightening_center_x
				box_layer["brightening_fade_pixels"] = brightening_fade_pixels
			raster_layers.append(box_layer)
			if absf(normal.y) < 0.5 and lower_edge_shadow.a > 0.001:
				# This is the literal bottom edge of this visible table side. Shrink
				# its world endpoints by the leg width, then leave one logical cell
				# clear before the rendered leg begins.
				var lowest_y := INF
				for point in points:
					lowest_y = minf(lowest_y, point.y)
				var lower_points: Array[Vector3] = []
				for point in points:
					if is_equal_approx(point.y, lowest_y):
						lower_points.append(point)
				if lower_points.size() == 2:
					var shadow_from := lower_points[0]
					var shadow_to := lower_points[1]
					var world_edge := shadow_to - shadow_from
					if world_edge.length() > leg_inset_world * 2.0:
						var world_direction := world_edge.normalized()
						shadow_from += world_direction * leg_inset_world
						shadow_to -= world_direction * leg_inset_world
					var shadow_from_projection := _project(shadow_from, center, origin, forward, right, offset)
					var shadow_to_projection := _project(shadow_to, center, origin, forward, right, offset)
					if bool(shadow_from_projection.visible) and bool(shadow_to_projection.visible):
						var shadow_from_pixel: Vector2 = shadow_from_projection.pixel
						var shadow_to_pixel: Vector2 = shadow_to_projection.pixel
						if shadow_from_pixel.distance_to(shadow_to_pixel) > 2.0:
							var pixel_direction := (shadow_to_pixel - shadow_from_pixel).normalized()
							shadow_from_pixel += pixel_direction
							shadow_to_pixel -= pixel_direction
							raster_layers.append({"raster_stroke": true, "from": shadow_from_pixel, "to": shadow_to_pixel, "colour": lower_edge_shadow, "fade_end_cells": 0, "z": face_z + 1})
	return cursor

func _face_visible(normal: Vector3, face_center: Vector3, center: Vector2, origin: Vector2) -> bool:
	var camera := Vector3(origin.x - center.x, 0.5, origin.y - center.y)
	return normal.dot(camera - face_center) > 0.0

func _line_detail_fade(distance: float, full_distance: float, hidden_distance: float) -> float:
	var full := minf(full_distance, hidden_distance - 0.01)
	var hidden := maxf(hidden_distance, full + 0.01)
	return 1.0 - smoothstep(full, hidden, distance)

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
	style = load(style_path)
	if style == null:
		style = STYLE_SCRIPT.new()
		ResourceSaver.save(style, style_path)
	for key in _style_values():
		set(key, style.get(key))
	_saved = _style_values()

func _style_values() -> Dictionary:
	return {"top_color": top_color, "x_side_color": x_side_color, "z_side_color": z_side_color, "shadow_color": shadow_color, "footprint_x": footprint_x, "footprint_y": footprint_y, "leg_height": leg_height, "maximum_leg_pixels": maximum_leg_pixels, "maximum_seat_height_pixels": maximum_seat_height_pixels, "maximum_pixels_distance": maximum_pixels_distance, "one_pixel_distance": one_pixel_distance, "near_edge_highlight_color": near_edge_highlight_color, "near_edge_highlight_end_fade": near_edge_highlight_end_fade, "near_edge_highlight_angle_fade": near_edge_highlight_angle_fade, "near_edge_highlight_full_distance": near_edge_highlight_full_distance, "near_edge_highlight_hidden_distance": near_edge_highlight_hidden_distance, "seat_slat_count": seat_slat_count, "seat_slat_shadow_color": seat_slat_shadow_color, "seat_slat_highlight_color": seat_slat_highlight_color, "seat_slat_shadow_full_distance": seat_slat_shadow_full_distance, "seat_slat_shadow_hidden_distance": seat_slat_shadow_hidden_distance, "seat_slat_highlight_full_distance": seat_slat_highlight_full_distance, "seat_slat_highlight_hidden_distance": seat_slat_highlight_hidden_distance, "floor_darkening_strength": floor_darkening_strength, "underside_shadow_color": underside_shadow_color, "underside_shadow_fade": underside_shadow_fade, "under_table_leg_darkening_strength": under_table_leg_darkening_strength, "exterior_corner_brightening_strength": exterior_corner_brightening_strength, "exterior_corner_brightening_fade_pixels": exterior_corner_brightening_fade_pixels, "face_horizontal_span_hidden_pixels": face_horizontal_span_hidden_pixels, "face_horizontal_span_full_pixels": face_horizontal_span_full_pixels, "show_debug_geometry": show_debug_geometry, "show_logical_pixel_grid": show_logical_pixel_grid}
