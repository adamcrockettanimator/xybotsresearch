extends Control

const CAGE := Color("#65e7f5")
const SIDING := Color("#ffc85b")
const TRIM := Color("#ff90bc")
const STRIPES := Color("#8ce997")
const DOOR := Color("#ff9961")
const WINDOW := Color("#a5c8ff")
const SHADOW := Color("#da9cff")

var _renderer: Node
var _style: Resource
var _walls: Array[Dictionary] = []
var _planes: Array[Dictionary] = []
var _origin := Vector2.ZERO
var _forward := Vector2.ZERO
var _right := Vector2.ZERO
var _logical_to_overlay := Transform2D.IDENTITY
var _show_cage := false
var _show_masks := false
var _broken_glass := false
var _line_width := 1.6
var _legend_font_size := 15


func _ready() -> void:
	name = "StorefrontDebugView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func update_view(renderer: Node, view: Node2D, content: Node2D, cage: bool, masks: bool) -> void:
	_renderer = renderer
	_style = renderer.controller.STOREFRONT_STYLE
	_show_cage = cage
	_show_masks = masks
	_broken_glass = renderer.controller.storefront_glass_broken
	var view_transform := view.get_global_transform_with_canvas()
	position = view_transform.origin
	size = renderer.VIEW_SIZE * view_transform.get_scale()
	_logical_to_overlay = Transform2D(0.0, -position) * content.get_global_transform_with_canvas()
	var viewport_size := get_viewport_rect().size
	var window_size := Vector2(get_window().size)
	var output_scale := maxf(1.0, minf(window_size.x / viewport_size.x, window_size.y / viewport_size.y))
	_line_width = 1.8 / output_scale
	_legend_font_size = maxi(9, roundi(16.0 / sqrt(output_scale)))
	_planes.clear()
	for plane: ColorRect in renderer.storefront_planes:
		var material := plane.material as ShaderMaterial
		var bounds: Vector4 = material.get_shader_parameter("bounds")
		_planes.append({
			"rect": Rect2(Vector2(bounds.x, bounds.y), Vector2(bounds.z - bounds.x, bounds.w - bounds.y)),
			"heights": material.get_shader_parameter("edge_heights"),
			"metal": material.get_shader_parameter("metal"),
			"ribs": material.get_shader_parameter("roof_rib_count"),
		})
	if not _planes.is_empty():
		var material: ShaderMaterial = renderer.storefront_planes[0].material
		_origin = material.get_shader_parameter("camera_origin")
		_forward = material.get_shader_parameter("camera_forward")
		_right = material.get_shader_parameter("camera_right")
	_walls.clear()
	for wall: Dictionary in renderer.last_wall_entries:
		if int(wall["storefront_paint"]) != 0:
			_walls.append(wall)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_renderer) or _planes.is_empty():
		return
	for plane in _planes:
		_draw_plane(plane)
	for wall in _walls:
		var top: Vector2 = wall["face_top"]
		var bottom: float = wall["face_bottom"]
		if _show_cage:
			var door: Vector2 = wall["storefront_doorway"]
			if door == Vector2.ZERO:
				_wall_outline(wall, Rect2(0.0, bottom, 1.0, top.x - bottom), CAGE, top.y)
			else:
				var upper: float = _style.DOOR_TOP
				var contour := PackedVector2Array([
					Vector2(0.0, bottom), Vector2(door.x, bottom), Vector2(door.x, upper),
					Vector2(door.y, upper), Vector2(door.y, bottom), Vector2(1.0, bottom),
					Vector2(1.0, top.y), Vector2(0.0, top.x), Vector2(0.0, bottom),
				])
				for index in range(contour.size() - 1):
					_wall_stroke(wall, contour[index], contour[index + 1], CAGE)
			var cap: Rect2 = wall["porch_cap"]
			if cap.has_area():
				_plane_outline(cap, Vector2.ONE * top.x, CAGE)
		if _show_masks:
			_draw_wall_masks(wall)
	_draw_legend()


func _draw_plane(plane: Dictionary) -> void:
	var rect: Rect2 = plane["rect"]
	var heights: Vector2 = plane["heights"]
	if _show_cage:
		_plane_outline(rect, heights, CAGE)
	if not _show_masks:
		return
	if plane["metal"]:
		var ribs: int = int(plane["ribs"])
		for index in ribs:
			for phase: float in [0.0, 0.5]:
				var x := lerpf(rect.position.x, rect.end.x, (index + phase) / ribs)
				var a := Vector3(x, rect.position.y, heights.x)
				var b := Vector3(x, rect.end.y, heights.y)
				_stroke(a, b, SHADOW if phase == 0.0 else STRIPES, _plane_detail((a + b) * 0.5, rect, heights))


func _plane_detail(point: Vector3, rect: Rect2, heights: Vector2) -> float:
	var delta := Vector2(point.x, point.y) - _origin
	var depth := delta.dot(_forward)
	if depth < 0.075:
		return 0.0
	var ray := delta / depth
	var slope := (heights.y - heights.x) / rect.size.y
	var eye: float = _renderer.VIRTUAL_CAMERA_HEIGHT
	var denominator := (eye - point.z) / depth + slope * ray.y
	var focal: float = _renderer.FOCAL_LENGTH
	var step_depth := Vector2(denominator + slope * _right.y / focal, denominator + 1.0 / focal)
	if minf(absf(step_depth.x), absf(step_depth.y)) < 0.0001:
		return 0.0
	var neighbor_x := (ray.x + _right.x / focal) * depth * denominator / step_depth.x
	var neighbor_y := ray.x * depth * denominator / step_depth.y
	var footprint := maxf(absf(neighbor_x - delta.x), absf(neighbor_y - delta.x)) * 16.0
	return (1.0 - smoothstep(2.0, 6.5, depth)) * (1.0 - smoothstep(0.29, 0.70, footprint))


func _draw_wall_masks(wall: Dictionary) -> void:
	var paint: int = wall["storefront_paint"]
	var top: Vector2 = wall["face_top"]
	var bottom: float = wall["face_bottom"]
	var a: Vector2 = wall["world_a"]
	var b: Vector2 = wall["world_b"]
	if paint == 3:
		var height := top.x - bottom
		for range_uv: Vector2 in [Vector2(0.10, 0.50), Vector2(0.60, 0.90)]:
			_wall_outline(wall, Rect2(0.14, top.x - range_uv.y * height, 0.72, (range_uv.y - range_uv.x) * height), DOOR)
		if not wall["storefront_open_leaf"]:
			var inset: float = _style.door_reveal_width
			var u := inset / a.distance_to(b)
			_wall_outline(wall, Rect2(u, bottom + inset, 1.0 - 2.0 * u, height - 2.0 * inset), SHADOW)
		return
	if paint != 1:
		return
	var front: float = _style.FOOTPRINT.position.y
	var facade := is_equal_approx(a.y, front) and is_equal_approx(b.y, front)
	var indoor: bool = _renderer.controller.town_has_roof(Vector2i(wall["facing_cell"]))
	var uses_interior_material: bool = indoor and _renderer.semantic_wall_material_enabled
	if not uses_interior_material or facade:
		var siding_base: float = _style.ROOF_FRONT if uses_interior_material else bottom
		var foundation: float = _style.porch_height + _style.FOUNDATION_BAND_HEIGHT
		_draw_courses(wall, maxf(siding_base, foundation))
		if foundation > siding_base and foundation < minf(top.x, top.y):
			_wall_stroke(wall, Vector2(0.0, foundation), Vector2(1.0, foundation), TRIM)
		var trim_depth: float = _style.WALL_TOP_TRIM_DEPTH
		if minf(top.x, top.y) - siding_base > trim_depth:
			_wall_stroke(wall, Vector2(0.0, top.x - trim_depth), Vector2(1.0, top.y - trim_depth), TRIM)
	_draw_corner_post_limits(wall)
	if uses_interior_material:
		_draw_interior_bands(wall)
	if facade and _origin.y < front and _style.awning_shadow > 0.0:
		var base: float = maxf(_style.porch_height, bottom)
		var cap: float = minf(_style.AWNING_BACK, minf(top.x, top.y))
		if cap > base:
			_wall_stroke(wall, Vector2(0, cap), Vector2(1, cap), SHADOW)
			_wall_stroke(wall, Vector2(0, base), Vector2(1, base), SHADOW, 0.55)
	var casing: Vector2 = wall["door_casing_ends"]
	var casing_width: float = _style.door_casing_width
	var door: Vector2 = wall["storefront_doorway"]
	if door != Vector2.ZERO:
		var width := casing_width / a.distance_to(b)
		var height: float = _style.DOOR_TOP + casing_width - _style.porch_height
		_wall_outline(wall, Rect2(door.x - width, _style.porch_height, width, height), DOOR)
		_wall_outline(wall, Rect2(door.y, _style.porch_height, width, height), DOOR)
		_wall_outline(wall, Rect2(door.x, _style.DOOR_TOP, door.y - door.x, casing_width), DOOR)
	elif casing == Vector2.ONE:
		_wall_outline(wall, Rect2(0, _style.DOOR_TOP, 1, casing_width), DOOR)
	elif casing != Vector2.ZERO:
		var width := casing_width / a.distance_to(b)
		_wall_outline(wall, Rect2(0.0 if casing.x > 0.0 else 1.0 - width, _style.porch_height, width, _style.DOOR_TOP + casing_width - _style.porch_height), DOOR)
	if wall["storefront_window"]:
		# Draw the original pane-local diagram on the window span of the wall.
		var span: Vector2 = wall["storefront_window_span"]
		var window := wall.duplicate()
		window["world_a"] = a.lerp(b, span.x)
		window["world_b"] = a.lerp(b, span.y)
		var aperture: Rect2 = _style.WINDOW_APERTURE
		_wall_outline(window, Rect2(0.13, 0.20, 0.74, 0.29), WINDOW)
		if _broken_glass:
			_wall_outline(window, aperture, WINDOW)
		else:
			var center := aperture.get_center()
			var half_size: Vector2 = _style.WINDOW_MULLION_HALF_SIZE
			var pane_size := aperture.size * 0.5 - half_size
			for horizontal in 2:
				for vertical in 2:
					var lower := Vector2(aperture.position.x if horizontal == 0 else center.x + half_size.x,
						aperture.position.y if vertical == 0 else center.y + half_size.y)
					_wall_outline(window, Rect2(lower, pane_size), WINDOW)
		if _origin.y < front and _style.ledge_shadow > 0.0:
			_wall_stroke(window, Vector2(0.12, 0.148), Vector2(0.88, 0.148), SHADOW, 0.55)


func _corner_distance(point: Vector2) -> float:
	var footprint := Rect2(_style.FOOTPRINT)
	var from_start := (point - footprint.position).abs()
	var from_end := (point - footprint.end).abs()
	return maxf(minf(from_start.x, from_end.x), minf(from_start.y, from_end.y))


func _draw_corner_post_limits(wall: Dictionary) -> void:
	var a: Vector2 = wall["world_a"]
	var b: Vector2 = wall["world_b"]
	var top: Vector2 = wall["face_top"]
	var width: float = _style.corner_post_width / a.distance_to(b)
	for end in 2:
		if _corner_distance(a if end == 0 else b) > 0.001:
			continue
		var rim := width if end == 0 else 1.0 - width
		_wall_stroke(wall, Vector2(rim, 0.0), Vector2(rim, lerpf(top.x, top.y, rim)), TRIM)


func _draw_interior_bands(wall: Dictionary) -> void:
	var texture: Texture2D = _renderer.wall_source_texture
	if texture == null:
		return
	var top: Vector2 = wall["face_top"]
	var bottom: float = wall["face_bottom"]
	for row: float in [8.0, 56.0, 62.0, 83.0]:
		var height: float = _style.porch_height + 0.6666667 * (1.0 - row / texture.get_height())
		if height > bottom and height < minf(top.x, top.y):
			var color := TRIM if row == 8.0 or row == 83.0 else SIDING
			_wall_stroke(wall, Vector2(0, height), Vector2(1, height), color, 0.8)


func _draw_courses(wall: Dictionary, minimum: float) -> void:
	var a: Vector2 = wall["world_a"]
	var b: Vector2 = wall["world_b"]
	var top: Vector2 = wall["face_top"]
	var origin: float = _style.porch_height + _style.FOUNDATION_BAND_HEIGHT
	var course_height: float = _style.siding_course_height()
	top -= Vector2.ONE * float(_style.WALL_TOP_TRIM_DEPTH)
	var first := ceili((minimum - origin) / course_height)
	var last := ceili((maxf(top.x, top.y) - origin) / course_height)
	for course in range(first, last):
		var lip := origin + course * course_height
		var u := Vector2(0.0, 1.0)
		if minf(top.x, top.y) < lip:
			var end := (lip - top.x) / (top.y - top.x)
			if top.x < lip:
				u.x = end
			else:
				u.y = end
		var depth := (a.lerp(b, (u.x + u.y) * 0.5) - _origin).dot(_forward)
		if depth > 0.075:
			var course_pixels := float(_renderer.FOCAL_LENGTH) * course_height / depth
			_wall_stroke(wall, Vector2(u.x, lip), Vector2(u.y, lip), SIDING, smoothstep(1.0, 2.5, course_pixels))


func _wall_outline(wall: Dictionary, rect: Rect2, color: Color, remaining_top := INF) -> void:
	var a := rect.position
	var b := Vector2(rect.end.x, a.y)
	var c := Vector2(b.x, rect.end.y if is_inf(remaining_top) else remaining_top)
	var d := Vector2(a.x, rect.end.y)
	_wall_stroke(wall, a, b, color)
	_wall_stroke(wall, b, c, color)
	_wall_stroke(wall, c, d, color)
	_wall_stroke(wall, d, a, color)


func _wall_stroke(wall: Dictionary, a: Vector2, b: Vector2, color: Color, opacity := 1.0) -> void:
	var start: Vector2 = wall["world_a"]
	var end: Vector2 = wall["world_b"]
	var first := start.lerp(end, a.x)
	var second := start.lerp(end, b.x)
	var surface := wall if color == SIDING or color == TRIM else {}
	_stroke(Vector3(first.x, first.y, a.y), Vector3(second.x, second.y, b.y), color, opacity, surface)


func _plane_outline(rect: Rect2, heights: Vector2, color: Color) -> void:
	var a := Vector3(rect.position.x, rect.position.y, heights.x)
	var b := Vector3(rect.end.x, rect.position.y, heights.x)
	var c := Vector3(rect.end.x, rect.end.y, heights.y)
	var d := Vector3(rect.position.x, rect.end.y, heights.y)
	_stroke(a, b, color)
	_stroke(b, c, color)
	_stroke(c, d, color)
	_stroke(d, a, color)


func _stroke(a: Vector3, b: Vector3, color: Color, opacity := 1.0, surface: Dictionary = {}) -> void:
	if opacity <= 0.04:
		return
	var first: Vector2 = _renderer._to_view(Vector2(a.x, a.y), _origin, _forward, _right)
	var second: Vector2 = _renderer._to_view(Vector2(b.x, b.y), _origin, _forward, _right)
	const near := 0.075
	if maxf(first.y, second.y) <= near:
		return
	if first.y < near:
		var cut := (near - first.y) / (second.y - first.y)
		first = first.lerp(second, cut)
		a = a.lerp(b, cut)
	if second.y < near:
		var cut := (near - second.y) / (first.y - second.y)
		second = second.lerp(first, cut)
		b = b.lerp(a, cut)
	var start: Vector2 = _renderer._project_view_point(first, a.z)
	var end: Vector2 = _renderer._project_view_point(second, b.z)
	var screen_a := _logical_to_overlay * start
	var screen_b := _logical_to_overlay * end
	var clipped := _clip_segment(screen_a, screen_b)
	if clipped.x >= clipped.y:
		return
	var steps := clampi(ceili(start.distance_to(end) * (clipped.y - clipped.x) / 2.0), 1, 96)
	var shown := Color(color, color.a * opacity)
	var run_start := -1.0
	for index in steps:
		var t := lerpf(clipped.x, clipped.y, (index + 0.5) / steps)
		var world_t := (t / second.y) / lerpf(1.0 / first.y, 1.0 / second.y, t)
		var point := a.lerp(b, world_t)
		var visible := (surface.is_empty() or _wall_band_visible(surface, point, color == SIDING)) and not _is_occluded(point)
		var boundary := lerpf(clipped.x, clipped.y, float(index) / steps)
		if visible and run_start < 0.0:
			run_start = boundary
		elif not visible and run_start >= 0.0:
			draw_line(screen_a.lerp(screen_b, run_start), screen_a.lerp(screen_b, boundary), shown, _line_width, true)
			run_start = -1.0
	if run_start >= 0.0:
		draw_line(screen_a.lerp(screen_b, run_start), screen_a.lerp(screen_b, clipped.y), shown, _line_width, true)


func _clip_segment(a: Vector2, b: Vector2) -> Vector2:
	var interval := Vector2(0.0, 1.0)
	var delta := b - a
	for axis in 2:
		if absf(delta[axis]) < 0.00001:
			if a[axis] < 0.0 or a[axis] > size[axis]:
				return Vector2.ZERO
			continue
		var first := -a[axis] / delta[axis]
		var last := (size[axis] - a[axis]) / delta[axis]
		interval.x = maxf(interval.x, minf(first, last))
		interval.y = minf(interval.y, maxf(first, last))
	return interval


func _wall_band_visible(wall: Dictionary, point: Vector3, siding: bool) -> bool:
	var start: Vector2 = wall["world_a"]
	var span: Vector2 = Vector2(wall["world_b"]) - start
	var u := (Vector2(point.x, point.y) - start).dot(span) / span.length_squared()
	var top: Vector2 = wall["face_top"]
	if siding and lerpf(top.x, top.y, u) - point.z < float(_style.WALL_TOP_TRIM_DEPTH):
		return false
	if _corner_distance(Vector2(point.x, point.y)) < _style.corner_post_width:
		return false
	var window_span: Vector2 = wall["storefront_window_span"]
	var window_u := inverse_lerp(window_span.x, window_span.y, u)
	if wall["storefront_window"] and window_u > 0.13 and window_u < 0.87 and point.z > 0.20 and point.z < 0.49:
		return false
	var casing: Vector2 = wall["door_casing_ends"]
	var door: Vector2 = wall["storefront_doorway"]
	if float(_style.porch_height) <= point.z and point.z <= float(_style.DOOR_TOP) + float(_style.door_casing_width):
		if door != Vector2.ZERO:
			if u > door.x and u < door.y:
				return false
			return minf(absf(u - door.x), absf(u - door.y)) * span.length() > float(_style.door_casing_width)
		if casing == Vector2.ONE:
			return false
		if casing != Vector2.ZERO:
			var from_jamb := u if casing.x > 0.0 else 1.0 - u
			return from_jamb * span.length() > float(_style.door_casing_width)
	return true


func _is_occluded(point: Vector3) -> bool:
	var ray := Vector2(point.x, point.y) - _origin
	var eye: float = _renderer.VIRTUAL_CAMERA_HEIGHT
	var rise := point.z - eye
	for wall in _walls:
		if wall["local_player_fan_contact"]:
			continue
		var a: Vector2 = wall["world_a"]
		var span: Vector2 = Vector2(wall["world_b"]) - a
		var denominator := ray.cross(span)
		if absf(denominator) < 0.000001:
			continue
		var offset := a - _origin
		var t := offset.cross(span) / denominator
		var u := offset.cross(ray) / denominator
		if t <= 0.0 or t >= 0.997 or u < 0.0 or u > 1.0:
			continue
		var height := eye + rise * t
		var top: Vector2 = wall["face_top"]
		if height >= float(wall["face_bottom"]) and height <= lerpf(top.x, top.y, u):
			if wall["storefront_paint"] == 1 and height < _style.apron_bottom() and _corner_distance(a + span * u) > _style.corner_post_width:
				continue
			var door: Vector2 = wall["storefront_doorway"]
			if u > door.x and u < door.y and height < _style.DOOR_TOP:
				continue
			var span_uv: Vector2 = wall["storefront_window_span"]
			var window_uv := Vector2(inverse_lerp(span_uv.x, span_uv.y, u), height)
			if wall["storefront_window"] and _style.window_has_opening(window_uv):
				var aperture: Rect2 = _style.WINDOW_APERTURE
				var cross: Vector2 = (window_uv - aperture.get_center()).abs()
				var mullion: Vector2 = _style.WINDOW_MULLION_HALF_SIZE
				if _broken_glass or (cross.x >= mullion.x and cross.y >= mullion.y):
					continue
			return true
	for plane in _planes:
		var rect: Rect2 = plane["rect"]
		var heights: Vector2 = plane["heights"]
		var slope := (heights.y - heights.x) / rect.size.y
		var denominator := rise - slope * ray.y
		if absf(denominator) < 0.000001:
			continue
		var t := (heights.x + slope * (_origin.y - rect.position.y) - eye) / denominator
		if t > 0.0 and t < 0.997 and rect.has_point(_origin + ray * t):
			return true
	return false


func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	var rows: Array[String] = []
	var colors: Array[Color] = []
	if _show_cage:
		rows.append("F9   Construction edges")
		colors.append(CAGE)
	if _show_masks:
		rows.append_array(["F10  Material masks", "Wall courses and chair rail", "Corner posts and wall trim", "Roof ribs", "Door casing and panels", "Window sash and opening", "Recess and cast shadow limits"])
		colors.append_array([Color.WHITE, SIDING, TRIM, STRIPES, DOOR, WINDOW, SHADOW])
	var row_height := _legend_font_size + 5
	var width := 0.0
	for row in rows:
		width = maxf(width, font.get_string_size(row, HORIZONTAL_ALIGNMENT_LEFT, -1, _legend_font_size).x)
	draw_rect(Rect2(Vector2(9, 9), Vector2(width + 20.0, rows.size() * row_height + 12.0)), Color(0.06, 0.045, 0.04, 0.90))
	for index in rows.size():
		draw_string(font, Vector2(19, 17 + _legend_font_size + index * row_height), rows[index], HORIZONTAL_ALIGNMENT_LEFT, -1, _legend_font_size, colors[index])
