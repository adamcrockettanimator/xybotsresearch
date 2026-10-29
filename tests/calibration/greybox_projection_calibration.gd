@tool
extends Node2D

## Interactive projection diagnostic.  It intentionally has no dependency on
## gameplay nodes: the geometry and camera contract are shared with Blender via
## assets/Calibration/xybots_projection_contract.json.

const CONTRACT_PATH := "res://assets/Calibration/xybots_projection_contract.json"
const CAPTURE_DIRECTORY := "res://assets/Calibration/captures"
const DISPLAY_SCALE := 6.0
const NEAR_CLIP := 0.02

var contract: Dictionary
var logical_size := Vector2(160.0, 120.0)
var focal_length := 128.0
var horizon_y := 31.5
var camera_height := 0.5
var player_foot := Vector2(80.0, 112.0)
var yaw_radians := 0.0
var capture_mode := false
var flat_geometry_pass := false
var is_capture_renderer := false
var capture_viewport: SubViewport
var capture_renderer: Node2D


func _ready() -> void:
	contract = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	if contract.is_empty():
		push_error("Could not load the Xybots greybox projection contract.")
		return
	logical_size = Vector2(contract.logical_canvas.width, contract.logical_canvas.height)
	focal_length = float(contract.projection.focal_length_pixels)
	horizon_y = float(contract.projection.horizon_y_from_top)
	camera_height = float(contract.projection.camera_height_godot_units)
	player_foot = Vector2(contract.projection.player_foot_screen[0], contract.projection.player_foot_screen[1])
	if is_capture_renderer:
		scale = Vector2.ONE
		capture_mode = true
	else:
		scale = Vector2.ONE * DISPLAY_SCALE
		_create_native_capture_viewport()
		call_deferred("_capture_reference_views")
	queue_redraw()


func _create_native_capture_viewport() -> void:
	capture_viewport = SubViewport.new()
	capture_viewport.name = "Native160CaptureViewport"
	capture_viewport.size = Vector2i(int(logical_size.x), int(logical_size.y))
	capture_viewport.transparent_bg = false
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	capture_viewport.gui_disable_input = true
	add_child(capture_viewport)
	var renderer := get_script().new() as Node2D
	renderer.name = "ProjectionRenderer"
	renderer.set("is_capture_renderer", true)
	capture_viewport.add_child(renderer)
	capture_renderer = renderer


func _set_calibration_yaw(value: float) -> void:
	yaw_radians = value
	queue_redraw()
	if not is_capture_renderer and is_instance_valid(capture_renderer):
		capture_renderer.set("yaw_radians", value)
		capture_renderer.queue_redraw()


func _set_flat_geometry_pass(value: bool) -> void:
	flat_geometry_pass = value
	queue_redraw()
	if not is_capture_renderer and is_instance_valid(capture_renderer):
		capture_renderer.set("flat_geometry_pass", value)
		capture_renderer.queue_redraw()


func _capture_reference_views() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))
	capture_mode = true
	for flat_pass in [false, true]:
		_set_flat_geometry_pass(flat_pass)
		var prefix := "godot_flat" if flat_pass else "godot"
		for view_variant in contract["calibration_views"]:
			var view: Dictionary = view_variant
			var view_id := String(view["id"])
			_set_calibration_yaw(deg_to_rad(float(view["yaw_degrees"])))
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var capture := capture_viewport.get_texture().get_image()
			var godot_path := "%s/%s_%s.png" % [CAPTURE_DIRECTORY, prefix, view_id]
			capture.save_png(ProjectSettings.globalize_path(godot_path))
			_write_projection_comparison(view_id, godot_path, flat_pass)
	_set_calibration_yaw(0.0)
	_set_flat_geometry_pass(false)
	capture_mode = false
	queue_redraw()
	print("Wrote lit and flat native Godot calibration captures and comparisons to ", CAPTURE_DIRECTORY)


func _write_projection_comparison(view_id: String, godot_path: String, flat_pass: bool) -> void:
	var prefix := "flat_" if flat_pass else ""
	var blender_prefix := "blender_flat" if flat_pass else "blender"
	var blender_path := "%s/%s_%s.png" % [CAPTURE_DIRECTORY, blender_prefix, view_id]
	var blender_image := Image.load_from_file(ProjectSettings.globalize_path(blender_path))
	if blender_image == null or blender_image.is_empty():
		return
	var godot_image := Image.load_from_file(ProjectSettings.globalize_path(godot_path))
	if godot_image == null or godot_image.is_empty():
		return
	blender_image.resize(int(logical_size.x), int(logical_size.y), Image.INTERPOLATE_NEAREST)
	godot_image.resize(int(logical_size.x), int(logical_size.y), Image.INTERPOLATE_NEAREST)
	var overlay := Image.create(int(logical_size.x), int(logical_size.y), false, Image.FORMAT_RGBA8)
	var difference := Image.create(int(logical_size.x), int(logical_size.y), false, Image.FORMAT_RGBA8)
	for y in range(int(logical_size.y)):
		for x in range(int(logical_size.x)):
			var blender_luma: float = blender_image.get_pixel(x, y).get_luminance()
			var godot_luma: float = godot_image.get_pixel(x, y).get_luminance()
			overlay.set_pixel(x, y, Color(godot_luma, blender_luma, blender_luma, 1.0))
			var delta: float = absf(godot_luma - blender_luma)
			difference.set_pixel(x, y, Color(delta, delta, delta, 1.0))
	overlay.save_png(ProjectSettings.globalize_path("%s/%soverlay_%s.png" % [CAPTURE_DIRECTORY, prefix, view_id]))
	difference.save_png(ProjectSettings.globalize_path("%s/%sdifference_%s.png" % [CAPTURE_DIRECTORY, prefix, view_id]))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_1:
			_set_calibration_yaw(0.0)
		KEY_2:
			_set_calibration_yaw(PI * 0.25)
		KEY_3:
			_set_calibration_yaw(PI * 0.5)
		KEY_R:
			_set_calibration_yaw(0.0)
		_:
			return


func _draw() -> void:
	if contract.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, logical_size), Color("20242a"), true)
	_draw_ground_grid()
	_draw_room()
	_draw_primitives()
	if not capture_mode:
		_draw_hud()


func _camera_basis() -> Dictionary:
	# X is screen-right and positive world-forward is Y.  This mirrors the
	# runtime's side/depth camera basis without any crop translation.
	var forward := Vector2(0.0, 1.0).rotated(-yaw_radians).normalized()
	var right := Vector2(forward.y, -forward.x).normalized()
	var target_depth := camera_height * focal_length / (player_foot.y - horizon_y)
	return {
		"forward": forward,
		"right": right,
		"origin": -forward * target_depth,
	}


func _project(point: Vector3) -> Vector2:
	var basis: Dictionary = _camera_basis()
	var origin: Vector2 = basis["origin"]
	var forward: Vector2 = basis["forward"]
	var right: Vector2 = basis["right"]
	var relative: Vector2 = Vector2(point.x, point.y) - origin
	var depth: float = relative.dot(forward)
	if depth <= NEAR_CLIP:
		return Vector2.INF
	var side: float = relative.dot(right)
	return Vector2(
		logical_size.x * 0.5 + side / depth * focal_length,
		horizon_y + (camera_height - point.z) / depth * focal_length
	)


func _draw_ground_grid() -> void:
	var minor := float(contract.greybox_grid.minor_interval_godot_units)
	var major := float(contract.greybox_grid.major_interval_godot_units)
	# The diagnostic floor field is deliberately screen-space.  Its job is to
	# establish the shared 50% grey base; the grid drawn below carries the
	# perspective measurement.  This avoids a giant near-plane polygon hiding
	# the rest of the test on CanvasItem.
	draw_rect(Rect2(Vector2(0.0, horizon_y), Vector2(logical_size.x, logical_size.y - horizon_y)), Color("808080"), true)
	for i in range(-12, 13):
		var coordinate := float(i) * minor
		var major_line := is_zero_approx(fmod(absf(coordinate), major))
		var color := Color("b8b8b8") if major_line else Color("575b61")
		var width := 0.9 if major_line else 0.35
		_draw_ground_segment(Vector3(coordinate, -3.0, 0.0), Vector3(coordinate, 3.0, 0.0), color, width)
		_draw_ground_segment(Vector3(-3.0, coordinate, 0.0), Vector3(3.0, coordinate, 0.0), color, width)


func _draw_floor_surface() -> void:
	var floor: Array[Vector3] = [Vector3(-3.0, -3.0, 0.0), Vector3(3.0, -3.0, 0.0), Vector3(3.0, 3.0, 0.0), Vector3(-3.0, 3.0, 0.0)]
	var clipped := _clip_polygon_to_near_plane(floor)
	if clipped.size() < 3:
		return
	var points := PackedVector2Array()
	for vertex in clipped:
		points.append(_project(vertex))
	draw_colored_polygon(points, Color("808080"))


func _clip_polygon_to_near_plane(vertices: Array[Vector3]) -> Array[Vector3]:
	var basis: Dictionary = _camera_basis()
	var origin: Vector2 = basis["origin"]
	var forward: Vector2 = basis["forward"]
	var output: Array[Vector3] = []
	var previous: Vector3 = vertices[vertices.size() - 1]
	var previous_depth: float = (Vector2(previous.x, previous.y) - origin).dot(forward)
	for current in vertices:
		var current_depth: float = (Vector2(current.x, current.y) - origin).dot(forward)
		var previous_visible: bool = previous_depth > NEAR_CLIP
		var current_visible: bool = current_depth > NEAR_CLIP
		if previous_visible != current_visible:
			output.append(previous.lerp(current, (NEAR_CLIP - previous_depth) / (current_depth - previous_depth)))
		if current_visible:
			output.append(current)
		previous = current
		previous_depth = current_depth
	return output


func _draw_room() -> void:
	var h := float(contract.projection.wall_height_godot_units)
	var back_color := Color("808080") if flat_geometry_pass else Color("6c7076")
	var side_color := Color("808080") if flat_geometry_pass else Color("686c72")
	_draw_quad_grid(Vector3(-3.0, 3.0, 0.0), Vector3(3.0, 3.0, 0.0), Vector3(3.0, 3.0, h), Vector3(-3.0, 3.0, h), back_color)
	_draw_quad_grid(Vector3(-3.0, -3.0, 0.0), Vector3(-3.0, 3.0, 0.0), Vector3(-3.0, 3.0, h), Vector3(-3.0, -3.0, h), side_color)
	_draw_quad_grid(Vector3(3.0, 3.0, 0.0), Vector3(3.0, -3.0, 0.0), Vector3(3.0, -3.0, h), Vector3(3.0, 3.0, h), side_color)


func _draw_primitives() -> void:
	var faces: Array[Dictionary] = []
	for spec_variant in contract.primitives:
		var spec: Dictionary = spec_variant
		faces.append_array(_primitive_faces(spec))
	faces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _face_depth(a.vertices) > _face_depth(b.vertices)
	)
	for face in faces:
		_draw_face(face.vertices, face.color)


func _primitive_faces(spec: Dictionary) -> Array[Dictionary]:
	var dimensions: Array = spec.dimensions
	var position: Array = spec.position
	var center := Vector3(float(position[0]), float(position[1]), 0.0)
	match String(spec.type):
		"box", "beveled_box":
			return _box_faces(center, Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2])), String(spec.type) == "beveled_box")
		"sphere":
			return _sphere_faces(center, Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2])))
		"cone":
			return _cone_faces(center, Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2])))
		"pyramid":
			return _pyramid_faces(center, Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2])))
		"cylinder":
			return _cylinder_faces(center, Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2])), false)
		"sideways_cylinder":
			return _cylinder_faces(center, Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2])), true)
		"stepped_block":
			var result := _box_faces(center, Vector3(float(dimensions[0]), float(dimensions[1]), float(dimensions[2])), false)
			result.append_array(_box_faces(center + Vector3(0.0, float(dimensions[1]) * 0.12, float(dimensions[2]) * 0.38), Vector3(float(dimensions[0]) * 0.58, float(dimensions[1]) * 0.58, float(dimensions[2]) * 0.28), false))
			return result
	return []


func _box_faces(center: Vector3, size: Vector3, _beveled: bool) -> Array[Dictionary]:
	var half := size * 0.5
	var z_center := center.z + half.z
	var v: Array[Vector3] = [
		Vector3(center.x - half.x, center.y - half.y, z_center - half.z), Vector3(center.x + half.x, center.y - half.y, z_center - half.z),
		Vector3(center.x + half.x, center.y + half.y, z_center - half.z), Vector3(center.x - half.x, center.y + half.y, z_center - half.z),
		Vector3(center.x - half.x, center.y - half.y, z_center + half.z), Vector3(center.x + half.x, center.y - half.y, z_center + half.z),
		Vector3(center.x + half.x, center.y + half.y, z_center + half.z), Vector3(center.x - half.x, center.y + half.y, z_center + half.z),
	]
	return _faces_from_indices(v, [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]])


func _pyramid_faces(center: Vector3, size: Vector3) -> Array[Dictionary]:
	var half := size * 0.5
	var z := center.z
	var v: Array[Vector3] = [Vector3(center.x - half.x, center.y - half.y, z), Vector3(center.x + half.x, center.y - half.y, z), Vector3(center.x + half.x, center.y + half.y, z), Vector3(center.x - half.x, center.y + half.y, z), Vector3(center.x, center.y, z + size.z)]
	return _faces_from_indices(v, [[0, 1, 2, 3], [0, 4, 1], [1, 4, 2], [2, 4, 3], [3, 4, 0]])


func _cone_faces(center: Vector3, size: Vector3) -> Array[Dictionary]:
	var sides := 12
	var vertices: Array[Vector3] = []
	for i in range(sides):
		var angle := TAU * float(i) / float(sides)
		vertices.append(Vector3(center.x + cos(angle) * size.x * 0.5, center.y + sin(angle) * size.y * 0.5, center.z))
	vertices.append(Vector3(center.x, center.y, center.z + size.z))
	var faces: Array[Array] = [range(sides)]
	for i in range(sides):
		faces.append([i, sides, (i + 1) % sides])
	return _faces_from_indices(vertices, faces)


func _cylinder_faces(center: Vector3, size: Vector3, sideways: bool) -> Array[Dictionary]:
	var sides := 12
	var vertices: Array[Vector3] = []
	for end in [-1.0, 1.0]:
		for i in range(sides):
			var angle := TAU * float(i) / float(sides)
			if sideways:
				vertices.append(Vector3(center.x + end * size.x * 0.5, center.y + cos(angle) * size.y * 0.5, center.z + size.z * 0.5 + sin(angle) * size.z * 0.5))
			else:
				vertices.append(Vector3(center.x + cos(angle) * size.x * 0.5, center.y + sin(angle) * size.y * 0.5, center.z + (end + 1.0) * size.z * 0.5))
	var faces: Array[Array] = [range(sides), range(sides, sides * 2)]
	for i in range(sides):
		faces.append([i, (i + 1) % sides, (i + 1) % sides + sides, i + sides])
	return _faces_from_indices(vertices, faces)


func _sphere_faces(center: Vector3, size: Vector3) -> Array[Dictionary]:
	var rings := 6
	var sides := 12
	var vertices: Array[Vector3] = []
	for ring in range(rings + 1):
		var phi := PI * float(ring) / float(rings)
		for side in range(sides):
			var theta := TAU * float(side) / float(sides)
			vertices.append(center + Vector3(cos(theta) * sin(phi) * size.x * 0.5, sin(theta) * sin(phi) * size.y * 0.5, (1.0 - cos(phi)) * size.z * 0.5))
	var faces: Array[Array] = []
	for ring in range(rings):
		for side in range(sides):
			var next := (side + 1) % sides
			faces.append([ring * sides + side, ring * sides + next, (ring + 1) * sides + next, (ring + 1) * sides + side])
	return _faces_from_indices(vertices, faces)


func _faces_from_indices(vertices: Array[Vector3], indices: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for face_indices in indices:
		var face_vertices: Array[Vector3] = []
		for index in face_indices:
			face_vertices.append(vertices[int(index)])
		result.append({"vertices": face_vertices, "color": _face_color(face_vertices)})
	return result


func _face_color(vertices: Array[Vector3]) -> Color:
	if flat_geometry_pass:
		return Color("808080")
	if vertices.size() < 3:
		return Color("808080")
	var normal := (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).normalized()
	var light := maxf(normal.dot(Vector3(-0.4, -0.5, 0.75).normalized()), 0.0)
	var value := lerpf(0.34, 0.58, light)
	return Color(value, value, value)


func _face_depth(vertices: Array[Vector3]) -> float:
	var basis := _camera_basis()
	var total := 0.0
	for vertex in vertices:
		total += (Vector2(vertex.x, vertex.y) - basis.origin).dot(basis.forward)
	return total / float(vertices.size())


func _draw_face(vertices: Array[Vector3], color: Color) -> void:
	var points := PackedVector2Array()
	for vertex in vertices:
		var point := _project(vertex)
		if not is_finite(point.x) or not is_finite(point.y):
			return
		points.append(point)
	if points.size() >= 3:
		draw_colored_polygon(points, color)
	if vertices.size() == 4:
		_draw_quad_grid_lines(vertices[0], vertices[1], vertices[2], vertices[3])
	for index in vertices.size():
		_draw_segment(vertices[index], vertices[(index + 1) % vertices.size()], Color("30343a"), 0.65)


func _draw_quad_grid(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_draw_face([a, b, c, d], color)


func _draw_quad_grid_lines(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var minor: float = float(contract["greybox_grid"]["minor_interval_godot_units"])
	var u_steps: int = maxi(1, roundi(a.distance_to(b) / minor))
	var v_steps: int = maxi(1, roundi(b.distance_to(c) / minor))
	for i in range(1, u_steps):
		var t: float = float(i) / float(u_steps)
		var major_u: bool = i % 4 == 0
		_draw_segment(a.lerp(b, t), d.lerp(c, t), Color("b8b8b8") if major_u else Color("4a4e54"), 0.6 if major_u else 0.3)
	for i in range(1, v_steps):
		var t: float = float(i) / float(v_steps)
		var major_v: bool = i % 4 == 0
		_draw_segment(a.lerp(d, t), b.lerp(c, t), Color("b8b8b8") if major_v else Color("4a4e54"), 0.6 if major_v else 0.3)


func _draw_segment(a: Vector3, b: Vector3, color: Color, width: float) -> void:
	var clipped := _clip_segment_to_near_plane(a, b, NEAR_CLIP)
	if clipped.is_empty():
		return
	var from := _project(clipped[0])
	var to := _project(clipped[1])
	if is_finite(from.x) and is_finite(to.x):
		draw_line(from, to, color, width, false)


func _draw_ground_segment(a: Vector3, b: Vector3, color: Color, width: float) -> void:
	# A larger draw-only near clip avoids unstable, screen-spanning strokes
	# where a world grid line passes almost exactly through the camera.
	var clipped := _clip_segment_to_near_plane(a, b, 0.35)
	if clipped.is_empty():
		return
	var from := _project(clipped[0])
	var to := _project(clipped[1])
	if is_finite(from.x) and is_finite(to.x):
		draw_line(from, to, color, width, false)


func _clip_segment_to_near_plane(a: Vector3, b: Vector3, clip_depth: float) -> Array[Vector3]:
	var basis: Dictionary = _camera_basis()
	var origin: Vector2 = basis["origin"]
	var forward: Vector2 = basis["forward"]
	var depth_a: float = (Vector2(a.x, a.y) - origin).dot(forward)
	var depth_b: float = (Vector2(b.x, b.y) - origin).dot(forward)
	if depth_a <= clip_depth and depth_b <= clip_depth:
		return []
	var clipped_a := a
	var clipped_b := b
	if depth_a <= clip_depth:
		clipped_a = a.lerp(b, (clip_depth - depth_a) / (depth_b - depth_a))
	elif depth_b <= clip_depth:
		clipped_b = b.lerp(a, (clip_depth - depth_b) / (depth_a - depth_b))
	return [clipped_a, clipped_b]


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(4.0, 12.0), "XYBOTS GREYBOX CALIBRATION", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 5, Color("e5e9ef"))
	draw_string(font, Vector2(4.0, 20.0), "1/R: north   2: 45 deg   3: east", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3, Color("b8bec8"))
	draw_line(Vector2(0.0, horizon_y), Vector2(logical_size.x, horizon_y), Color("f0bb55"), 0.5, false)
	draw_circle(player_foot, 1.2, Color("ed5c80"))
