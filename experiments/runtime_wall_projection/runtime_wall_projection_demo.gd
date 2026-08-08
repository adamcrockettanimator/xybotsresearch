extends Node2D

## A deliberately isolated runtime-wall-rendering experiment.
##
## It keeps the maze as the same kind of thin 2D grid-edge data used by the
## main project, but projects wall endpoints directly into Canvas space.
## The projection is yaw-only: vertical world lines always receive the same
## screen X at their top and bottom, so they cannot converge toward a third
## vanishing point.

const MAP_WIDTH := 7
const MAP_HEIGHT := 7
const WALL_HEIGHT := 1.0
const PLAYER_RADIUS := 0.13
const MOVE_SPEED := 2.15
const TURN_SPEED := 2.25
const VIEW_FOV_DEGREES := 82.0
const NEAR_DEPTH := 0.12
const MAX_DEPTH := 6.5
const RAY_COUNT := 121

const BASE_FOCAL_LENGTH := 104.0
const BASE_HORIZON_RATIO := 0.36
const CAMERA_HEIGHT := 0.58
const MAX_HOMOGRAPHY_WALLS := 64

var player_world := Vector2(3.5, 5.45)
var view_yaw := -PI * 0.5
var wall_edges: Dictionary = {}
var wall_texture: ImageTexture
var show_debug := true
var quantized_darkness := true
var use_homography := true
var focal_length := BASE_FOCAL_LENGTH
var horizon_ratio := BASE_HORIZON_RATIO
var wall_counter := 0

var _font: Font
var _last_viewport_size := Vector2.ZERO

@onready var homography_canvas: Polygon2D = $HomographyCanvas


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = ThemeDB.fallback_font
	wall_texture = _make_diagnostic_wall_texture()
	var homography_material := homography_canvas.material as ShaderMaterial
	homography_material.set_shader_parameter("wall_texture", wall_texture)
	_build_test_maze()
	queue_redraw()
	if "--capture-runtime-projection" in OS.get_cmdline_user_args():
		call_deferred("_capture_headless_frame")


func _process(delta: float) -> void:
	_update_continuous_input(delta)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F1:
			show_debug = not show_debug
		KEY_F2:
			quantized_darkness = not quantized_darkness
		KEY_F3:
			use_homography = not use_homography
		KEY_R:
			_build_test_maze()
		KEY_BRACKETLEFT:
			focal_length = maxf(48.0, focal_length - 6.0)
		KEY_BRACKETRIGHT:
			focal_length = minf(180.0, focal_length + 6.0)
		KEY_MINUS:
			horizon_ratio = maxf(0.18, horizon_ratio - 0.02)
		KEY_EQUAL:
			horizon_ratio = minf(0.62, horizon_ratio + 0.02)


func _update_continuous_input(delta: float) -> void:
	var keyboard_move := Input.get_vector("xybots_move_left", "xybots_move_right", "xybots_move_forward", "xybots_move_backward")
	var stick_move := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if stick_move.length() < 0.18:
		stick_move = Vector2.ZERO
	var move := keyboard_move if keyboard_move.length() >= stick_move.length() else stick_move
	if move.length() > 1.0:
		move = move.normalized()
	var forward := Vector2(cos(view_yaw), sin(view_yaw))
	var right := Vector2(-forward.y, forward.x)
	_try_move((right * move.x - forward * move.y) * MOVE_SPEED * delta)

	var keyboard_turn := Input.get_axis("xybots_turn_left", "xybots_turn_right")
	var stick_turn := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	if absf(stick_turn) < 0.18:
		stick_turn = 0.0
	var turn := keyboard_turn if absf(keyboard_turn) >= absf(stick_turn) else stick_turn
	view_yaw = wrapf(view_yaw + turn * TURN_SPEED * delta, -PI, PI)


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size != _last_viewport_size:
		_last_viewport_size = viewport_size
	var view_rect := _view_rect(viewport_size)
	_draw_backdrop(viewport_size, view_rect)
	_draw_floor_grid(view_rect)
	var visible_walls := _visible_walls()
	visible_walls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["depth"]) > float(b["depth"]))
	if use_homography:
		_update_homography_canvas(view_rect, visible_walls)
	else:
		homography_canvas.visible = false
		for wall in visible_walls:
			_draw_wall_quad(wall, view_rect)
	_draw_player_marker(view_rect)
	if show_debug:
		_draw_debug_overlay(view_rect, visible_walls)
	_draw_hud(view_rect, visible_walls.size())


func _view_rect(viewport_size: Vector2) -> Rect2:
	var desired_aspect := 4.0 / 3.0
	var available_aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	if available_aspect > desired_aspect:
		var height := viewport_size.y
		var width := height * desired_aspect
		return Rect2((viewport_size.x - width) * 0.5, 0.0, width, height)
	var width := viewport_size.x
	var height := width / desired_aspect
	return Rect2(0.0, (viewport_size.y - height) * 0.5, width, height)


func _draw_backdrop(viewport_size: Vector2, view_rect: Rect2) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("191b20"), true)
	draw_rect(view_rect, Color("080b10"), true)
	var horizon := _horizon_y(view_rect)
	draw_rect(Rect2(view_rect.position.x, horizon, view_rect.size.x, view_rect.end.y - horizon), Color("a96f3e"), true)
	draw_rect(Rect2(view_rect.position.x, horizon - 3.0, view_rect.size.x, 3.0), Color("332416"), true)


func _draw_floor_grid(view_rect: Rect2) -> void:
	var forward := _view_forward()
	var right := _view_right()
	var grid_color := Color("6e4930")
	for x in range(MAP_WIDTH + 1):
		var first := _project_world(Vector2(x, 0.0), 0.0, view_rect)
		var second := _project_world(Vector2(x, MAP_HEIGHT), 0.0, view_rect)
		if first.is_empty() or second.is_empty():
			continue
		var first_screen: Vector2 = first["screen"]
		var second_screen: Vector2 = second["screen"]
		draw_line(first_screen, second_screen, grid_color, 1.0)
	for y in range(MAP_HEIGHT + 1):
		var first := _project_world(Vector2(0.0, y), 0.0, view_rect)
		var second := _project_world(Vector2(MAP_WIDTH, y), 0.0, view_rect)
		if first.is_empty() or second.is_empty():
			continue
		var first_screen: Vector2 = first["screen"]
		var second_screen: Vector2 = second["screen"]
		draw_line(first_screen, second_screen, grid_color, 1.0)


func _draw_wall_quad(wall: Dictionary, view_rect: Rect2) -> void:
	var a_view: Vector2 = wall["a_view"]
	var b_view: Vector2 = wall["b_view"]
	var bottom_a_projection := _project_view(a_view, 0.0, view_rect)
	var bottom_b_projection := _project_view(b_view, 0.0, view_rect)
	var top_b_projection := _project_view(b_view, WALL_HEIGHT, view_rect)
	var top_a_projection := _project_view(a_view, WALL_HEIGHT, view_rect)
	if bottom_a_projection.is_empty() or bottom_b_projection.is_empty() or top_a_projection.is_empty() or top_b_projection.is_empty():
		return
	var bottom_a: Vector2 = bottom_a_projection["screen"]
	var bottom_b: Vector2 = bottom_b_projection["screen"]
	var top_b: Vector2 = top_b_projection["screen"]
	var top_a: Vector2 = top_a_projection["screen"]
	var shade := _distance_shade(float(wall["depth"]))
	var color := Color(shade, shade, shade, 1.0)
	# Two triangles intentionally use ordinary affine UV interpolation. Any seam
	# or perspective warp is part of the first arcade-style comparison.
	_draw_textured_triangle([bottom_a, bottom_b, top_b], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)], color)
	_draw_textured_triangle([bottom_a, top_b, top_a], [Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)], color)
	if show_debug:
		var outline := Color("42dff4")
		draw_line(bottom_a, bottom_b, outline, 1.0)
		draw_line(bottom_b, top_b, outline, 1.0)
		draw_line(top_b, top_a, outline, 1.0)
		draw_line(top_a, bottom_a, outline, 1.0)
		for point in [bottom_a, bottom_b, top_a, top_b]:
			draw_circle(point, 2.0, Color("e8ffff"))


func _draw_textured_triangle(points: Array[Vector2], uvs: Array[Vector2], color: Color) -> void:
	var packed_points := PackedVector2Array(points)
	var packed_uvs := PackedVector2Array(uvs)
	var packed_colors := PackedColorArray([color, color, color])
	draw_primitive(packed_points, packed_colors, packed_uvs, wall_texture)


func _draw_player_marker(view_rect: Rect2) -> void:
	var screen_ground := _project_world(player_world, 0.0, view_rect)
	var screen_head := _project_world(player_world, 0.72, view_rect)
	if screen_ground.is_empty() or screen_head.is_empty():
		return
	var ground: Vector2 = screen_ground["screen"]
	var head: Vector2 = screen_head["screen"]
	var body_height := absf(ground.y - head.y)
	var body_width := maxf(4.0, body_height * 0.28)
	draw_rect(Rect2(ground.x - body_width * 0.5, head.y, body_width, body_height), Color("d33b70"), true)
	draw_circle(Vector2(ground.x, head.y - body_width * 0.35), body_width * 0.42, Color("ffb779"))


func _draw_debug_overlay(view_rect: Rect2, visible_walls: Array) -> void:
	var horizon := _horizon_y(view_rect)
	draw_line(Vector2(view_rect.position.x, horizon), Vector2(view_rect.end.x, horizon), Color("ffe66d"), 1.0)
	var center := Vector2(view_rect.get_center().x, horizon)
	draw_line(center - Vector2(0, 8), center + Vector2(0, 8), Color("ffe66d"), 1.0)
	for wall in visible_walls:
		var a: Vector2 = wall["a_view"]
		var b: Vector2 = wall["b_view"]
		var mid := (a + b) * 0.5
		var label_projection := _project_view(mid, WALL_HEIGHT * 0.5, view_rect)
		if label_projection.is_empty():
			continue
		var label := "%s d%.2f" % [wall["name"], float(wall["depth"])]
		var label_screen: Vector2 = label_projection["screen"]
		draw_string(_font, label_screen + Vector2(3, -3), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color("ffffff"))


func _draw_hud(view_rect: Rect2, visible_count: int) -> void:
	var rows := [
		"RUNTIME WALL PROJECTION — affine Canvas quad experiment",
		"WASD / left stick: move   Q/E or right stick: continuous yaw   R: reset test maze",
		"F1: debug  F2: distance bands  F3: %s  [ ]: focal %.0f  -/=: horizon %.2f" % ["HOMOGRAPHY" if use_homography else "AFFINE", focal_length, horizon_ratio],
		"visible walls: %d   projection: yaw only / verticals parallel" % visible_count
	]
	for row_index in rows.size():
		draw_string(_font, view_rect.position + Vector2(10, 19 + row_index * 16), rows[row_index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color("f2f3f4"))


func _visible_walls() -> Array:
	var hits := {}
	var forward := _view_forward()
	var half_fov := deg_to_rad(VIEW_FOV_DEGREES) * 0.5
	for ray_index in range(RAY_COUNT):
		var blend := float(ray_index) / float(RAY_COUNT - 1)
		var direction := forward.rotated(lerpf(-half_fov, half_fov, blend))
		var nearest_distance := INF
		var nearest: Dictionary = {}
		for wall in _wall_list():
			var distance := _ray_segment_hit_distance(player_world, direction, wall["a"], wall["b"])
			if distance >= NEAR_DEPTH and distance < nearest_distance:
				nearest_distance = distance
				nearest = wall
		if not nearest.is_empty():
			hits[String(nearest["key"])] = nearest
	var visible := []
	for wall in hits.values():
		var clipped := _wall_in_view_space(wall)
		if not clipped.is_empty():
			visible.append(clipped)
	return visible


func _wall_in_view_space(wall: Dictionary) -> Dictionary:
	var a_relative: Vector2 = wall["a"] - player_world
	var b_relative: Vector2 = wall["b"] - player_world
	var right := _view_right()
	var forward := _view_forward()
	var a_view := Vector2(a_relative.dot(right), a_relative.dot(forward))
	var b_view := Vector2(b_relative.dot(right), b_relative.dot(forward))
	var clipped := _clip_view_segment_to_near_plane(a_view, b_view)
	if clipped.is_empty():
		return {}
	var clipped_a: Vector2 = clipped[0]
	var clipped_b: Vector2 = clipped[1]
	var depth := (clipped_a.y + clipped_b.y) * 0.5
	if depth > MAX_DEPTH:
		return {}
	return {"a_view": clipped_a, "b_view": clipped_b, "depth": depth, "name": wall["name"]}


func _clip_view_segment_to_near_plane(a: Vector2, b: Vector2) -> Array:
	if a.y < NEAR_DEPTH and b.y < NEAR_DEPTH:
		return []
	var clipped_a := a
	var clipped_b := b
	if clipped_a.y < NEAR_DEPTH:
		var blend := (NEAR_DEPTH - clipped_a.y) / (clipped_b.y - clipped_a.y)
		clipped_a = clipped_a.lerp(clipped_b, blend)
	if clipped_b.y < NEAR_DEPTH:
		var blend := (NEAR_DEPTH - clipped_b.y) / (clipped_a.y - clipped_b.y)
		clipped_b = clipped_b.lerp(clipped_a, blend)
	return [clipped_a, clipped_b]


func _project_world(world_position: Vector2, world_height: float, view_rect: Rect2) -> Dictionary:
	var relative := world_position - player_world
	var view := Vector2(relative.dot(_view_right()), relative.dot(_view_forward()))
	return _project_view(view, world_height, view_rect)


func _project_view(view: Vector2, world_height: float, view_rect: Rect2) -> Dictionary:
	if view.y < NEAR_DEPTH:
		return {}
	var screen := Vector2(
		view_rect.get_center().x + (view.x / view.y) * focal_length * view_rect.size.x / 320.0,
		_horizon_y(view_rect) + ((CAMERA_HEIGHT - world_height) / view.y) * focal_length * view_rect.size.x / 320.0
	)
	return {"screen": screen, "depth": view.y, "side": view.x}


func _horizon_y(view_rect: Rect2) -> float:
	return view_rect.position.y + view_rect.size.y * horizon_ratio


func _view_forward() -> Vector2:
	return Vector2(cos(view_yaw), sin(view_yaw))


func _view_right() -> Vector2:
	var forward := _view_forward()
	return Vector2(-forward.y, forward.x)


func _distance_shade(depth: float) -> float:
	var normalized := clampf((depth - NEAR_DEPTH) / (MAX_DEPTH - NEAR_DEPTH), 0.0, 1.0)
	if quantized_darkness:
		var band: int = min(3, int(floor(normalized * 4.0)))
		return [1.0, 0.76, 0.52, 0.30][band]
	return lerpf(1.0, 0.25, normalized)


func _update_homography_canvas(view_rect: Rect2, visible_walls: Array) -> void:
	homography_canvas.visible = true
	homography_canvas.polygon = PackedVector2Array([view_rect.position, Vector2(view_rect.end.x, view_rect.position.y), view_rect.end, Vector2(view_rect.position.x, view_rect.end.y)])
	var rows := PackedVector4Array()
	var view_segments := PackedVector4Array()
	var usable_count := 0
	for wall in visible_walls:
		if usable_count >= MAX_HOMOGRAPHY_WALLS:
			break
		var a_view: Vector2 = wall["a_view"]
		var b_view: Vector2 = wall["b_view"]
		var bottom_a_projection := _project_view(a_view, 0.0, view_rect)
		var bottom_b_projection := _project_view(b_view, 0.0, view_rect)
		var top_b_projection := _project_view(b_view, WALL_HEIGHT, view_rect)
		var top_a_projection := _project_view(a_view, WALL_HEIGHT, view_rect)
		if bottom_a_projection.is_empty() or bottom_b_projection.is_empty() or top_a_projection.is_empty() or top_b_projection.is_empty():
			continue
		var bottom_a: Vector2 = bottom_a_projection["screen"]
		var bottom_b: Vector2 = bottom_b_projection["screen"]
		var top_b: Vector2 = top_b_projection["screen"]
		var top_a: Vector2 = top_a_projection["screen"]
		var inverse_rows := _inverse_homography_rows(top_a, top_b, bottom_b, bottom_a)
		if inverse_rows.is_empty():
			continue
		var shade := _distance_shade(float(wall["depth"]))
		rows.append(Vector4(inverse_rows[0].x, inverse_rows[0].y, inverse_rows[0].z, shade))
		rows.append(Vector4(inverse_rows[1].x, inverse_rows[1].y, inverse_rows[1].z, 0.0))
		rows.append(Vector4(inverse_rows[2].x, inverse_rows[2].y, inverse_rows[2].z, 0.0))
		view_segments.append(Vector4(a_view.x, a_view.y, b_view.x, b_view.y))
		usable_count += 1
	var material := homography_canvas.material as ShaderMaterial
	material.set_shader_parameter("wall_count", usable_count)
	material.set_shader_parameter("inverse_homography_rows", rows)
	material.set_shader_parameter("wall_view_segments", view_segments)
	material.set_shader_parameter("projection_x", Vector2(view_rect.get_center().x, focal_length * view_rect.size.x / 320.0))


# Returns the inverse 3x3 transform that maps a screen pixel back to source
# wall UV. The supplied points correspond to source UV (0,0), (1,0), (1,1),
# and (0,1), respectively.
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


func _try_move(offset: Vector2) -> void:
	if offset.length_squared() <= 0.0:
		return
	var x_candidate := Vector2(player_world.x + offset.x, player_world.y)
	if _can_occupy(x_candidate):
		player_world.x = x_candidate.x
	var y_candidate := Vector2(player_world.x, player_world.y + offset.y)
	if _can_occupy(y_candidate):
		player_world.y = y_candidate.y


func _can_occupy(candidate: Vector2) -> bool:
	if candidate.x < PLAYER_RADIUS or candidate.x > MAP_WIDTH - PLAYER_RADIUS or candidate.y < PLAYER_RADIUS or candidate.y > MAP_HEIGHT - PLAYER_RADIUS:
		return false
	var probes := [Vector2(-PLAYER_RADIUS, -PLAYER_RADIUS), Vector2(PLAYER_RADIUS, -PLAYER_RADIUS), Vector2(-PLAYER_RADIUS, PLAYER_RADIUS), Vector2(PLAYER_RADIUS, PLAYER_RADIUS)]
	for probe in probes:
		var start_cell := Vector2i(floori((player_world + probe).x), floori((player_world + probe).y))
		var end_cell := Vector2i(floori((candidate + probe).x), floori((candidate + probe).y))
		if not _cells_connected(start_cell, end_cell):
			return false
	return true


func _cells_connected(start_cell: Vector2i, end_cell: Vector2i) -> bool:
	if start_cell == end_cell:
		return true
	if abs(end_cell.x - start_cell.x) + abs(end_cell.y - start_cell.y) != 1:
		return false
	var delta := end_cell - start_cell
	return not wall_edges.has(_edge_key_for_cell(start_cell, delta))


func _build_test_maze() -> void:
	wall_edges.clear()
	wall_counter = 0
	# Closed perimeter plus an intentionally sparse deterministic interior: this
	# makes direct, oblique, near, and far walls easy to inspect.
	for x in range(MAP_WIDTH):
		_add_wall(Vector2(x, 0), Vector2(x + 1, 0))
		_add_wall(Vector2(x, MAP_HEIGHT), Vector2(x + 1, MAP_HEIGHT))
	for y in range(MAP_HEIGHT):
		_add_wall(Vector2(0, y), Vector2(0, y + 1))
		_add_wall(Vector2(MAP_WIDTH, y), Vector2(MAP_WIDTH, y + 1))
	for segment in [
		[Vector2(1, 1), Vector2(5, 1)], [Vector2(1, 3), Vector2(4, 3)],
		[Vector2(2, 5), Vector2(6, 5)], [Vector2(1, 1), Vector2(1, 3)],
		[Vector2(5, 1), Vector2(5, 4)], [Vector2(3, 3), Vector2(3, 5)],
		[Vector2(6, 2), Vector2(6, 5)], [Vector2(1, 4), Vector2(2, 4)]
	]:
		_add_wall(segment[0], segment[1])
	player_world = Vector2(3.5, 5.45)
	view_yaw = -PI * 0.5


func _add_wall(a: Vector2, b: Vector2) -> void:
	var key := _edge_key(a, b)
	if wall_edges.has(key):
		return
	wall_counter += 1
	wall_edges[key] = {"a": a, "b": b, "key": key, "name": "W%02d" % wall_counter}


func _wall_list() -> Array:
	return wall_edges.values()


func _edge_key_for_cell(cell: Vector2i, delta: Vector2i) -> String:
	var a := Vector2(cell)
	if delta.x > 0:
		return _edge_key(a + Vector2(1, 0), a + Vector2(1, 1))
	if delta.x < 0:
		return _edge_key(a, a + Vector2(0, 1))
	if delta.y > 0:
		return _edge_key(a + Vector2(0, 1), a + Vector2(1, 1))
	return _edge_key(a, a + Vector2(1, 0))


func _edge_key(a: Vector2, b: Vector2) -> String:
	var first := a
	var second := b
	if first.x > second.x or (is_equal_approx(first.x, second.x) and first.y > second.y):
		first = b
		second = a
	return "%d,%d:%d,%d" % [roundi(first.x), roundi(first.y), roundi(second.x), roundi(second.y)]


func _ray_segment_hit_distance(origin: Vector2, ray_direction: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var denominator := _cross2(ray_direction, segment)
	if absf(denominator) < 0.0001:
		return -1.0
	var offset := a - origin
	var ray_distance := _cross2(offset, segment) / denominator
	var segment_fraction := _cross2(offset, ray_direction) / denominator
	if ray_distance < 0.0 or ray_distance > MAX_DEPTH or segment_fraction < 0.0 or segment_fraction > 1.0:
		return -1.0
	return ray_distance


func _cross2(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


func _make_diagnostic_wall_texture() -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var checker := (x / 16 + y / 16) % 2 == 0
			var grid_line := x % 16 == 0 or y % 16 == 0
			var color := Color("7998ad") if checker else Color("44596c")
			if grid_line:
				color = Color("e3edf3")
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


# Lets automated validation capture the diagnostic scene without opening a window.
func _capture_headless_frame() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "user://runtime_wall_projection_capture.png"
	image.save_png(path)
	print("RUNTIME_PROJECTION_CAPTURE=", ProjectSettings.globalize_path(path))
	get_tree().quit()
