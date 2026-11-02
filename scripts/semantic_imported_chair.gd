## Semantic chair renderer: the GLB supplies triangles and hard-edge topology;
## CPU projects model-space points, then Canvas GPU fills faces and selects
## exact logical raster cells for the edges.  There is no 3D render-card path.
extends Node2D

const CHAIR_SCENE := preload("uid://32bmw0muu074")
const EDGE_SHADER := preload("res://scripts/semantic_imported_chair.gdshader")
const STYLE_PATH := "res://resources/semantic_imported_chair_style.tres"
const STYLE_SCRIPT := preload("res://scripts/semantic_imported_chair_style.gd")
const LOGICAL_SIZE := Vector2i(160, 120)

@export_category("Semantic chair paint")
@export var wood_top_color := Color8(178, 112, 55)
@export var wood_bottom_shadow_color := Color8(66, 34, 18)
@export var wood_positive_x_color := Color8(145, 82, 38)
@export var wood_negative_x_color := Color8(117, 61, 29)
@export var wood_positive_z_color := Color8(133, 72, 32)
@export var wood_negative_z_color := Color8(101, 51, 24)
## The Blender-to-GLB chair arrives with the triangle winding opposite the
## semantic world convention. Flip it once at extraction; do not compensate in
## individual colour, culling, or edge rules.
@export var imported_normals_are_inverted := true
@export var pillow_color := Color8(126, 39, 75)
@export var convex_highlight_color := Color8(242, 184, 91)
@export var concave_shadow_color := Color8(67, 35, 19)
@export_range(0.0, 2.0, 0.05) var side_bottom_light := 0.62
@export_range(0.0, 2.0, 0.05) var side_top_light := 1.12
@export_category("Hard edge logical raster")
@export var sharp_edges_enabled := true
@export_range(1.0, 4.0, 1.0) var edge_width_logical_pixels := 1.0
@export_range(1.0, 89.0, 1.0) var sharp_angle_degrees := 35.0
@export var invert_convex_classification := false
@export_category("Per-detail distance LOD")
@export_range(0.1, 12.0, 0.05) var edge_full_distance := 1.7
@export_range(0.15, 16.0, 0.05) var edge_hidden_distance := 4.2
@export_range(0.1, 12.0, 0.05) var model_full_distance := 2.5
@export_range(0.15, 16.0, 0.05) var model_hidden_distance := 6.5
@export_category("Derived source bounds (read only)")
@export var footprint_width := 0.52008
@export var footprint_depth := 0.57003
@export var model_height := 1.07
@export var current_camera_distance_readout := 0.0

var viewport: SubViewport
var root: Node2D
var display: Sprite2D
var chair_style: Resource
var _last_saved_style_values: Dictionary = {}
var _faces: Array[Dictionary] = []
var _edges: Array[Dictionary] = []
var _scale_factor := 1.0

func _ready() -> void:
	_load_or_create_style()
	viewport = SubViewport.new()
	viewport.name = "ChairSharedLogicalRaster_160x120"
	viewport.size = LOGICAL_SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	root = Node2D.new()
	root.name = "ChairSemanticPolygonsAndHardEdges"
	viewport.add_child(root)
	display = Sprite2D.new()
	display.name = "ChairSemanticPixels"
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.texture = viewport.get_texture()
	add_child(display)
	_extract_source_topology()

func _process(_delta: float) -> void:
	if chair_style == null:
		_load_or_create_style()
	var values := _style_values_from_inspector()
	if values == _last_saved_style_values:
		return
	for key in values:
		chair_style.set(key, values[key])
	chair_style.emit_changed()
	if ResourceSaver.save(chair_style, STYLE_PATH) == OK:
		_last_saved_style_values = values
	else:
		push_error("Could not save semantic chair style.")

## Same projection contract as set_crate(). CPU supplies only immutable source
## topology and per-frame world/camera uniforms; Canvas draws the final pixels.
func set_chair(center: Vector2, width: float, depth: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> void:
	if _faces.is_empty():
		return
	_scale_factor = minf(width / footprint_width, minf(depth / footprint_depth, height / model_height))
	current_camera_distance_readout = center.distance_to(camera_origin)
	var fill_alpha := _fade(current_camera_distance_readout, model_full_distance, model_hidden_distance)
	var edge_alpha := _fade(current_camera_distance_readout, edge_full_distance, edge_hidden_distance)
	for record in _faces:
		var projected := PackedVector2Array()
		var valid := _face_visible(record["normal"], record["center"], center, camera_origin)
		var average_depth := 0.0
		for point: Vector3 in record["points"]:
			var result: Dictionary = _project(point, center, camera_origin, camera_forward, camera_right, projection_offset)
			if not result["visible"]:
				valid = false
				break
			projected.append(result["pixel"])
			average_depth += result["depth"]
		var piece: MeshInstance2D = record["node"]
		piece.visible = valid and fill_alpha > 0.001
		if valid:
			piece.mesh = _triangle_mesh(projected)
			piece.modulate = _face_colour(record["normal"], record["pillow"], fill_alpha)
			piece.z_index = clampi(-int(average_depth / 3.0 * 1000.0), -4000, 0)
	for record in _edges:
		var first: Dictionary = _project(record["a"], center, camera_origin, camera_forward, camera_right, projection_offset)
		var second: Dictionary = _project(record["b"], center, camera_origin, camera_forward, camera_right, projection_offset)
		var edge_piece: MeshInstance2D = record["node"]
		var valid_edge := bool(first["visible"]) and bool(second["visible"]) and _edge_visible(record, center, camera_origin) and sharp_edges_enabled and float(record["angle"]) >= sharp_angle_degrees and edge_alpha > 0.001
		edge_piece.visible = valid_edge
		if valid_edge:
			edge_piece.mesh = _edge_carrier_mesh(first["pixel"], second["pixel"])
			var material := edge_piece.material as ShaderMaterial
			material.set_shader_parameter("start_pixel", first["pixel"])
			material.set_shader_parameter("end_pixel", second["pixel"])
			material.set_shader_parameter("line_width", edge_width_logical_pixels)
			edge_piece.z_index = clampi(-int((float(first["depth"]) + float(second["depth"])) * 0.5 * 1000.0) + 1, -3999, 1)
			var convex := bool(record["convex"]) != invert_convex_classification
			var colour: Color = convex_highlight_color if convex else concave_shadow_color
			colour.a *= edge_alpha
			material.set_shader_parameter("line_colour", colour)

func _extract_source_topology() -> void:
	var source := CHAIR_SCENE.instantiate()
	var points: Array[Vector3] = []
	var raw_faces: Array[Dictionary] = []
	for mesh_node in source.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh_node as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var transform := _transform_relative_to_source(instance, source)
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var local_points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for index in local_points.size():
					indices.append(index)
			var base := points.size()
			for point in local_points:
				points.append(transform * point)
			var material := instance.get_active_material(surface)
			var is_pillow := material != null and material.resource_name.to_lower().contains("pillow")
			for index in range(0, indices.size() - 2, 3):
				var ids := PackedInt32Array([base + indices[index], base + indices[index + 1], base + indices[index + 2]])
				var normal := (points[ids[1]] - points[ids[0]]).cross(points[ids[2]] - points[ids[0]]).normalized()
				if imported_normals_are_inverted:
					normal = -normal
				raw_faces.append({"ids": ids, "normal": normal, "pillow": is_pillow})
	var edge_table: Dictionary = {}
	for face in raw_faces:
		var ids: PackedInt32Array = face["ids"]
		var fill := MeshInstance2D.new()
		fill.name = "ChairPolygonFill"
		root.add_child(fill)
		var center := (points[ids[0]] + points[ids[1]] + points[ids[2]]) / 3.0
		_faces.append({"points": [points[ids[0]], points[ids[1]], points[ids[2]]], "normal": face["normal"], "center": center, "pillow": face["pillow"], "node": fill})
		for edge_data in [{"pair": PackedInt32Array([ids[0], ids[1]]), "third": ids[2]}, {"pair": PackedInt32Array([ids[1], ids[2]]), "third": ids[0]}, {"pair": PackedInt32Array([ids[2], ids[0]]), "third": ids[1]}]:
			var pair: PackedInt32Array = edge_data["pair"]
			var low := mini(pair[0], pair[1])
			var high := maxi(pair[0], pair[1])
			var key := "%d:%d" % [low, high]
			if not edge_table.has(key):
				edge_table[key] = {"ids": pair, "sides": []}
			edge_table[key]["sides"].append({"normal": face["normal"], "center": center, "third": points[int(edge_data["third"])]})
	for edge_record in edge_table.values():
		var sides: Array = edge_record["sides"]
		var angle := 180.0
		if sides.size() > 1:
			angle = rad_to_deg(acos(clampf((sides[0]["normal"] as Vector3).dot(sides[1]["normal"] as Vector3), -1.0, 1.0)))
		var edge_ids: PackedInt32Array = edge_record["ids"]
		var is_convex := sides.size() == 1
		if sides.size() > 1:
			# This is winding-order independent. At an outward-facing convex edge,
			# each opposing triangle vertex lies behind the other face plane.
			var edge_point := points[edge_ids[0]]
			var first_side: Dictionary = sides[0]
			var second_side: Dictionary = sides[1]
			var first_test := (first_side["normal"] as Vector3).dot((second_side["third"] as Vector3) - edge_point)
			var second_test := (second_side["normal"] as Vector3).dot((first_side["third"] as Vector3) - edge_point)
			is_convex = first_test < -0.0001 and second_test < -0.0001
		var edge_piece := MeshInstance2D.new()
		edge_piece.name = "ChairHardEdgeRaster"
		edge_piece.z_index = 1000
		var shader_material := ShaderMaterial.new()
		shader_material.shader = EDGE_SHADER
		edge_piece.material = shader_material
		root.add_child(edge_piece)
		_edges.append({"a": points[edge_ids[0]], "b": points[edge_ids[1]], "angle": angle, "convex": is_convex, "sides": sides, "node": edge_piece})

func _transform_relative_to_source(instance: Node3D, source: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = instance
	while current != null and current != source:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

func _project(point: Vector3, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> Dictionary:
	var world := center + Vector2(point.x, point.z) * _scale_factor
	var relative := world - origin
	var depth := relative.dot(forward)
	if depth <= 0.01:
		return {"visible": false, "pixel": Vector2.ZERO, "depth": depth}
	return {"visible": true, "pixel": Vector2(80.0 + relative.dot(right) / depth * 128.0, 31.5 + (0.5 - point.y * _scale_factor) / depth * 128.0) + offset, "depth": depth}

func _triangle_mesh(points: PackedVector2Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _edge_carrier_mesh(first: Vector2, second: Vector2) -> ArrayMesh:
	var low := Vector2(minf(first.x, second.x), minf(first.y, second.y)) - Vector2(2.0, 2.0)
	var high := Vector2(maxf(first.x, second.x), maxf(first.y, second.y)) + Vector2(2.0, 2.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _face_colour(normal: Vector3, is_pillow: bool, alpha: float) -> Color:
	if is_pillow:
		return Color(pillow_color.r, pillow_color.g, pillow_color.b, pillow_color.a * alpha)
	# After the one-time import correction, the semantic convention is ordinary
	# Godot local space: +Y is upward/top and -Y is underside/shadow.
	var colour: Color
	if normal.y > 0.55:
		colour = wood_top_color
	elif normal.y < -0.55:
		colour = wood_bottom_shadow_color
	elif absf(normal.x) >= absf(normal.z):
		colour = wood_positive_x_color if normal.x > 0.0 else wood_negative_x_color
	else:
		colour = wood_positive_z_color if normal.z > 0.0 else wood_negative_z_color
	var light := 1.0 if absf(normal.y) > 0.55 else lerpf(side_bottom_light, side_top_light, 0.55)
	return Color(colour.r * light, colour.g * light, colour.b * light, alpha)

func _face_visible(normal: Vector3, face_center: Vector3, center: Vector2, camera_origin: Vector2) -> bool:
	var source_camera := Vector3((camera_origin.x - center.x) / _scale_factor, 0.5 / _scale_factor, (camera_origin.y - center.y) / _scale_factor)
	return normal.dot(source_camera - face_center) > 0.0

func _edge_visible(record: Dictionary, center: Vector2, camera_origin: Vector2) -> bool:
	for side in record["sides"]:
		if _face_visible(side["normal"], side["center"], center, camera_origin):
			return true
	return false

func _fade(distance: float, full_distance: float, hidden_distance: float) -> float:
	return 1.0 - smoothstep(minf(full_distance, hidden_distance - 0.01), maxf(hidden_distance, full_distance + 0.01), distance)

func _load_or_create_style() -> void:
	chair_style = load(STYLE_PATH)
	if chair_style == null:
		chair_style = STYLE_SCRIPT.new()
		ResourceSaver.save(chair_style, STYLE_PATH)
	for key in _style_values_from_inspector():
		set(key, chair_style.get(key))
	_last_saved_style_values = _style_values_from_inspector()

func _style_values_from_inspector() -> Dictionary:
	return {"wood_top_color": wood_top_color, "wood_bottom_shadow_color": wood_bottom_shadow_color, "wood_positive_x_color": wood_positive_x_color, "wood_negative_x_color": wood_negative_x_color, "wood_positive_z_color": wood_positive_z_color, "wood_negative_z_color": wood_negative_z_color, "imported_normals_are_inverted": imported_normals_are_inverted, "pillow_color": pillow_color, "convex_highlight_color": convex_highlight_color, "concave_shadow_color": concave_shadow_color, "side_bottom_light": side_bottom_light, "side_top_light": side_top_light, "sharp_edges_enabled": sharp_edges_enabled, "edge_width_logical_pixels": edge_width_logical_pixels, "sharp_angle_degrees": sharp_angle_degrees, "invert_convex_classification": invert_convex_classification, "edge_full_distance": edge_full_distance, "edge_hidden_distance": edge_hidden_distance, "model_full_distance": model_full_distance, "model_hidden_distance": model_hidden_distance}
