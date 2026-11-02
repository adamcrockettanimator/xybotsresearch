## Blender markup renderer. `poly` faces fill; marked-sharp edges and poly
## boundaries rasterize as exact logical-pixel strokes in this 160x120 target.
extends Node2D

const EDGE_SHADER := preload("res://scripts/semantic_imported_chair.gdshader")
const DATA_PATH := "res://assets/semantic_props/SM_Prop_Chair_02_edges.semantic.json"
const STYLE_PATH := "res://resources/semantic_imported_chair_edges_style.tres"
const STYLE_SCRIPT := preload("res://scripts/semantic_imported_chair_edges_style.gd")
const LOGICAL_SIZE := Vector2i(160, 120)
const MAX_EDGE_LANES := 12

@export_category("Three-axis cube material")
## `poly` and `edge` are raster-markup labels, not two materials. Every chair
## pixel belongs to one of these normal-owned cube colours.
@export var y_axis_top_color := Color8(76, 229, 234)
@export var x_axis_side_color := Color8(51, 166, 222)
@export var z_axis_side_color := Color8(8, 111, 181)
@export var y_axis_edge_highlight_color := Color8(255, 255, 255)
@export var x_axis_edge_highlight_color := Color8(90, 222, 255)
@export var z_axis_edge_highlight_color := Color8(27, 156, 226)
@export var floor_shadow_color := Color8(47, 55, 78, 180)
@export var imported_normals_are_inverted := true
@export_category("Inferred cube parts")
## `poly` rectangles are inferred as thin closed slabs; loose vertical vectors
## become square posts. These are authoring-space dimensions, not pixels.
@export_range(0.005, 0.16, 0.005) var slab_box_thickness := 0.055
@export_range(0.005, 0.12, 0.005) var post_box_half_width := 0.028
@export_category("Logical edge-width ramp")
## At or closer than this distance, each derived chair edge is this many crisp
## logical pixels wide. The count decreases one whole pixel at a time until it
## reaches one at `one_pixel_distance`.
@export_range(1, MAX_EDGE_LANES, 1) var maximum_edge_pixels := 10
@export_range(0.1, 20.0, 0.05) var maximum_edge_distance := 0.62
@export_range(0.15, 30.0, 0.05) var one_pixel_distance := 3.00
## The centre transition lane is fully visible up to this distance, then fades
## independently while the two normal-owned edge lanes remain crisp.
@export_range(0.1, 20.0, 0.05) var edge_highlight_full_distance := 0.60
@export_range(0.15, 30.0, 0.05) var edge_highlight_hidden_distance := 2.00
@export var close_highlight_color := Color8(245, 188, 96)
@export var close_crevice_shadow_color := Color8(74, 37, 17)
@export_range(0.1, 12.0, 0.05) var accent_full_distance := 0.70
@export_range(0.15, 16.0, 0.05) var accent_hidden_distance := 1.20
@export_category("Read only")
@export var current_camera_distance_readout := 0.0

var viewport: SubViewport
var root: Node2D
var display: Sprite2D
var chair_style: Resource
var _saved: Dictionary = {}
var _points: Array[Vector3] = []
var _faces: Array[Dictionary] = []
var _edges: Array[Dictionary] = []
var _scale_factor := 1.0
var _footprint: Array[Vector3] = []
var ground_shadow: MeshInstance2D

func _ready() -> void:
	_load_style()
	viewport = SubViewport.new()
	viewport.name = "ChairEdgesLogicalRaster_160x120"
	viewport.size = LOGICAL_SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	root = Node2D.new()
	root.name = "ChairEdgeMarkupStrokes"
	viewport.add_child(root)
	ground_shadow = MeshInstance2D.new()
	ground_shadow.name = "ChairProjectedFloorShadow"
	ground_shadow.z_index = -4096
	root.add_child(ground_shadow)
	display = Sprite2D.new()
	display.name = "ChairEdgeMarkupPixels"
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.texture = viewport.get_texture()
	add_child(display)
	_load_markup()

func _process(_delta: float) -> void:
	var values := _style_values()
	if chair_style != null and values != _saved:
		for key in values:
			chair_style.set(key, values[key])
		chair_style.emit_changed()
		if ResourceSaver.save(chair_style, STYLE_PATH) == OK:
			_saved = values

func set_chair(center: Vector2, width: float, depth: float, height: float, camera_origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> void:
	_scale_factor = minf(width / 0.48001, minf(depth / 0.53001, height / 1.07))
	current_camera_distance_readout = center.distance_to(camera_origin)
	_draw_floor_shadow(center, camera_origin, forward, right, offset)
	for face in _faces:
		var pixels := PackedVector2Array()
		var average_depth := 0.0
		var visible := _face_visible(face.normal, face.center, center, camera_origin)
		for point: Vector3 in face.points:
			var projected := _project(point, center, camera_origin, forward, right, offset)
			if not projected.visible:
				visible = false
				break
			pixels.append(projected.pixel)
			average_depth += projected.depth
		face.node.visible = visible
		if visible:
			face.node.mesh = _polygon_mesh(pixels)
			face.node.modulate = _axis_colour(face.normal)
			face.node.z_index = clampi(-int(average_depth / pixels.size() * 1000.0), -4000, 0)
	for edge in _edges:
		_draw_edge(edge, center, camera_origin, forward, right, offset)

func _load_markup() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		push_error("Could not read chair semantic markup")
		return
	var data: Dictionary = parsed
	for value in data.get("vertices", []):
		_points.append(Vector3(float(value[0]), float(value[2]), -float(value[1])))
	_build_footprint()
	# The Blender source is intentionally sparse: two `poly` rectangles and
	# four loose vertical vectors. Interpret those vectors as six *closed* box
	# volumes before any pixels are rasterized. Do not render the source lines
	# directly; that was the cause of edge strokes cutting through a solid plane.
	for raw in data.get("faces", []):
		var ids: Array = raw.get("vertices", [])
		if ids.size() < 3:
			continue
		var points: Array[Vector3] = []
		for id in ids:
			points.append(_points[id])
		var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
		if imported_normals_are_inverted:
			normal = -normal
		var centroid := Vector3.ZERO
		for point in points:
			centroid += point
		centroid /= points.size()
		var is_poly := String(raw.get("material", "")).to_lower() == "poly"
		if is_poly:
			_append_slab_box(points, normal)
	# Consecutive rear-leg vectors meet the back rectangle's lower and upper
	# corners. Merge every collinear vertical chain before making posts: this is
	# four continuous posts, not six small ones plus the two slabs.
	var post_groups: Dictionary = {}
	for raw in data.get("edges", []):
		var ids: Array = raw.get("vertices", [])
		if ids.size() != 2 or not bool(raw.get("sharp", false)):
			continue
		var a := _points[int(ids[0])]
		var b := _points[int(ids[1])]
		var direction := (b - a).normalized()
		if absf(direction.y) < 0.80:
			continue
		var xz_key := "%.5f:%.5f" % [(a.x + b.x) * 0.5, (a.z + b.z) * 0.5]
		if not post_groups.has(xz_key):
			post_groups[xz_key] = {"x": (a.x + b.x) * 0.5, "z": (a.z + b.z) * 0.5, "bottom": minf(a.y, b.y), "top": maxf(a.y, b.y)}
		else:
			post_groups[xz_key].bottom = minf(minf(float(post_groups[xz_key].bottom), a.y), b.y)
			post_groups[xz_key].top = maxf(maxf(float(post_groups[xz_key].top), a.y), b.y)
	for group in post_groups.values():
		_append_post_box(Vector3(float(group.x), float(group.bottom), float(group.z)), Vector3(float(group.x), float(group.top), float(group.z)))

func _append_slab_box(front: Array[Vector3], outward_normal: Vector3) -> void:
	if front.size() != 4:
		push_warning("Semantic chair slab needs four source corners")
		return
	var vertices: Array[Vector3] = []
	for point in front:
		vertices.append(point)
	for point in front:
		vertices.append(point - outward_normal * slab_box_thickness)
	_append_closed_box(vertices)

func _append_post_box(first: Vector3, second: Vector3) -> void:
	var axis := (second - first).normalized()
	if absf(axis.y) < 0.80:
		return # Current sparse source uses loose vectors only for chair posts.
	var x := Vector3.RIGHT * post_box_half_width
	var z := Vector3.FORWARD * post_box_half_width
	var vertices: Array[Vector3] = [first - x - z, first + x - z, first + x + z, first - x + z, second - x - z, second + x - z, second + x + z, second - x + z]
	_append_closed_box(vertices)

func _append_closed_box(vertices: Array[Vector3]) -> void:
	var center := Vector3.ZERO
	for point in vertices:
		center += point
	center /= vertices.size()
	var box_edges: Dictionary = {}
	var faces: Array = [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
	for ids in faces:
		var points: Array[Vector3] = []
		for id in ids:
			points.append(vertices[int(id)])
		var normal := (points[1] - points[0]).cross(points[2] - points[0]).normalized()
		var centroid := Vector3.ZERO
		for point in points:
			centroid += point
		centroid /= points.size()
		if normal.dot(centroid - center) < 0.0:
			normal = -normal
			points.reverse()
		var fill := MeshInstance2D.new()
		fill.name = "ChairInferredCubePlane"
		root.add_child(fill)
		_faces.append({"points": points, "normal": normal, "center": centroid, "node": fill})
		for index in points.size():
			var next := (index + 1) % points.size()
			var a: Vector3 = points[index]
			var b: Vector3 = points[next]
			var key := _vector_edge_key(a, b)
			if not box_edges.has(key):
				box_edges[key] = {"a": a, "b": b, "sides": [], "fill_sides": []}
			var side := {"normal": normal, "center": centroid}
			box_edges[key].sides.append(side)
			box_edges[key].fill_sides.append(side)
	for edge in box_edges.values():
		_append_stroke_points(edge.a, edge.b, edge.sides, edge.fill_sides)

func _append_stroke(first: int, second: int, sides: Array, fill_sides: Array) -> void:
	_append_stroke_points(_points[first], _points[second], sides, fill_sides)

func _append_stroke_points(first: Vector3, second: Vector3, sides: Array, fill_sides: Array) -> void:
	var record := {"a": first, "b": second, "sides": sides, "fill_sides": fill_sides, "nodes": []}
	for band in range(MAX_EDGE_LANES):
		var piece := MeshInstance2D.new()
		piece.name = "ChairSharpRasterBand"
		var raster := ShaderMaterial.new()
		raster.shader = EDGE_SHADER
		piece.material = raster
		root.add_child(piece)
		record["nodes"].append(piece)
	_edges.append(record)

func _draw_edge(edge: Dictionary, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> void:
	var first := _project(edge.a, center, origin, forward, right, offset)
	var second := _project(edge.b, center, origin, forward, right, offset)
	# These are now physical inferred-box edges. A boundary appears only when at
	# least one of its two owning cube planes faces the camera.
	var visible: bool = bool(first.visible) and bool(second.visible) and _edge_visible(edge, center, origin)
	var count := _band_count(current_camera_distance_readout)
	var line_direction: Vector3 = (edge.b - edge.a).normalized()
	var base_z := _edge_z_index(edge, first, second, center, origin, forward, right, offset)
	var lanes := _edge_lanes(edge, first, second, center, origin, forward, right, offset, count, line_direction)
	for band in range(MAX_EDGE_LANES):
		var piece: MeshInstance2D = edge.nodes[band]
		piece.visible = visible and band < lanes.size()
		if not piece.visible:
			continue
		# Every band covers the same endpoint carrier.  The shader chooses a
		# neighbouring logical lane, not a separately offset vector path.
		piece.mesh = _carrier(first.pixel, second.pixel)
		piece.z_index = base_z + band
		var shader := piece.material as ShaderMaterial
		shader.set_shader_parameter("start_pixel", first.pixel)
		shader.set_shader_parameter("end_pixel", second.pixel)
		shader.set_shader_parameter("line_width", 1.0)
		var lane := 0.0
		var lane_data: Dictionary = lanes[band]
		lane = float(lane_data.lane)
		var is_highlight := bool(lane_data.get("highlight", false))
		var colour := _axis_colour(lane_data.normal)
		if is_highlight:
			# A faded highlight is still a physical edge cell. Blend it back into
			# its underlying normal colour; never fade its alpha or it becomes a
			# transparent notch through an otherwise continuous edge ribbon.
			var highlight := _axis_highlight_colour(lane_data.get("highlight_normal", lane_data.normal))
			colour = colour.lerp(highlight, _fade(current_camera_distance_readout, edge_highlight_full_distance, edge_highlight_hidden_distance))
		shader.set_shader_parameter("line_lane", lane)
		shader.set_shader_parameter("line_colour", colour)

func _band_count(distance: float) -> int:
	var close_distance := minf(maximum_edge_distance, one_pixel_distance - 0.01)
	var far_distance := maxf(one_pixel_distance, close_distance + 0.01)
	if distance > far_distance:
		return 0
	if distance <= close_distance:
		return maximum_edge_pixels
	# This is deliberately a linear logical-pixel ramp, then rounded. For
	# maximum=10 it visits 10, 9, 8 ... 2, 1 evenly over the authored range.
	var amount := inverse_lerp(far_distance, close_distance, distance)
	return clampi(roundi(lerpf(1.0, float(maximum_edge_pixels), amount)), 1, maximum_edge_pixels)

func _edge_lanes(edge: Dictionary, first: Dictionary, second: Dictionary, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2, count: int, direction: Vector3) -> Array[Dictionary]:
	# Inferred boxes have real adjacent cube planes. Their normals own the lanes;
	# no independent screen-space stroke rule can contradict the solid volume.
	var sides: Array = edge.sides if edge.sides.size() >= 2 else _derived_beam_sides(edge, center, origin)
	var bevel_normal := _edge_bevel_normal_from_sides(sides, direction)
	if sides.is_empty():
		return _loose_edge_lanes(bevel_normal, count)
	var midpoint: Vector2 = (first.pixel + second.pixel) * 0.5
	var delta: Vector2 = second.pixel - first.pixel
	# This matches the fragment rasterizer's minor coordinate: X-major walks
	# claim Y lanes; Y-major walks claim X lanes.
	var minor_axis := Vector2.DOWN if absf(delta.x) >= absf(delta.y) else Vector2.RIGHT
	var first_side := _side_lane_info(sides[0], midpoint, minor_axis, center, origin, forward, right, offset)
	if sides.size() == 1:
		return _loose_edge_lanes(first_side.normal, count)
	var second_side := _side_lane_info(sides[1], midpoint, minor_axis, center, origin, forward, right, offset)
	if first_side.sign == second_side.sign:
		# Face-centre projection can collapse on an end-on plane.  Preserve two
		# dedicated lanes rather than flickering their orientation at that angle.
		second_side.sign = -first_side.sign
	var front_side: Dictionary = first_side if first_side.facing >= second_side.facing else second_side
	if count <= 1:
		return [{"lane": 0.0, "normal": front_side.normal}]
	var negative_side: Dictionary = first_side if first_side.sign < 0.0 else second_side
	var positive_side: Dictionary = second_side if first_side.sign < 0.0 else first_side
	# The entire width remains one contiguous GPU-cell ribbon.  Its negative and
	# positive halves belong to the two derived box normals; the centre cell is
	# their directional cube-style transition highlight.  Wider close-up edges
	# therefore grow as real material lanes, not as a blurry line-width setting.
	var highlight_normal := _highlight_owner_normal(sides, front_side.normal)
	return _split_normal_lanes(negative_side.normal, positive_side.normal, highlight_normal, count)

func _loose_edge_lanes(normal: Vector3, count: int) -> Array[Dictionary]:
	if count <= 1:
		return [{"lane": 0.0, "normal": normal}]
	return _split_normal_lanes(normal, normal, normal, count)

func _split_normal_lanes(negative_normal: Vector3, positive_normal: Vector3, highlight_normal: Vector3, count: int) -> Array[Dictionary]:
	var lanes: Array[Dictionary] = []
	var width := clampi(count, 1, MAX_EDGE_LANES)
	var first_lane := -int(width / 2)
	for index in width:
		var lane := first_lane + index
		if lane == 0 and width >= 3:
			lanes.append({"lane": float(lane), "normal": _edge_bevel_normal_from_sides([{"normal": negative_normal}, {"normal": positive_normal}], Vector3.UP), "highlight": true, "highlight_normal": highlight_normal})
		else:
			lanes.append({"lane": float(lane), "normal": negative_normal if lane < 0 else positive_normal})
	return lanes

func _side_lane_info(side: Dictionary, midpoint: Vector2, minor_axis: Vector2, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> Dictionary:
	var projection := _project(side.center, center, origin, forward, right, offset)
	var sign := 1.0
	if bool(projection.visible):
		var side_value: float = (projection.pixel - midpoint).dot(minor_axis)
		if absf(side_value) > 0.01:
			sign = signf(side_value)
	return {"normal": side.normal, "sign": sign, "facing": _normal_camera_score(side.normal, side.center, center, origin)}

func _normal_camera_score(normal: Vector3, face_center: Vector3, center: Vector2, origin: Vector2) -> float:
	var camera := Vector3((origin.x - center.x) / _scale_factor, 0.5 / _scale_factor, (origin.y - center.y) / _scale_factor)
	return normal.dot(camera - face_center)

func _edge_bevel_normal_from_sides(sides: Array, fallback_direction: Vector3) -> Vector3:
	var average := Vector3.ZERO
	for side in sides:
		average += side.normal
	if average.length_squared() > 0.0001:
		return average.normalized()
	# A loose authored edge has no adjoining polygon normal.  Keep it in the
	# material family with a stable upward-facing fallback, rather than bringing
	# back a separate arbitrary edge colour.
	return Vector3.UP if absf(fallback_direction.y) > 0.5 else Vector3(0.0, 0.35, 0.94).normalized()

func _derived_beam_sides(edge: Dictionary, center: Vector2, origin: Vector2) -> Array[Dictionary]:
	var midpoint: Vector3 = (edge.a + edge.b) * 0.5
	var direction: Vector3 = (edge.b - edge.a).normalized()
	var viewer := Vector3((origin.x - center.x) / _scale_factor, 0.5 / _scale_factor, (origin.y - center.y) / _scale_factor) - midpoint
	var first_axis: Vector3
	var second_axis: Vector3
	if absf(direction.y) >= 0.80:
		# Chair legs and back uprights: a small square post has one visible X
		# side and one visible Z side. These remain constant down the full run.
		first_axis = Vector3.RIGHT
		second_axis = Vector3.FORWARD
	else:
		# Rails and crossbeams: one plane is always the physical top; the other
		# is the horizontal side perpendicular to the beam's long direction.
		first_axis = Vector3.UP
		var horizontal := Vector3(direction.x, 0.0, direction.z).normalized()
		second_axis = Vector3(-horizontal.z, 0.0, horizontal.x)
	if first_axis.dot(viewer) < 0.0 and first_axis.y < 0.5:
		first_axis = -first_axis
	if second_axis.dot(viewer) < 0.0:
		second_axis = -second_axis
	return [{"normal": first_axis, "center": midpoint + first_axis * 0.01}, {"normal": second_axis, "center": midpoint + second_axis * 0.01}]

func _highlight_owner_normal(sides: Array, fallback: Vector3) -> Vector3:
	for side in sides:
		if side.normal.y > 0.5:
			return side.normal
	return fallback

func _axis_colour(normal: Vector3) -> Color:
	var unit := normal.normalized()
	if absf(unit.y) >= maxf(absf(unit.x), absf(unit.z)):
		return y_axis_top_color
	if absf(unit.x) >= absf(unit.z):
		return x_axis_side_color
	return z_axis_side_color

func _axis_highlight_colour(normal: Vector3) -> Color:
	var unit := normal.normalized()
	if absf(unit.y) >= maxf(absf(unit.x), absf(unit.z)):
		return y_axis_edge_highlight_color
	if absf(unit.x) >= absf(unit.z):
		return x_axis_edge_highlight_color
	return z_axis_edge_highlight_color

func _edge_z_index(edge: Dictionary, first: Dictionary, second: Dictionary, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> int:
	# A physical box edge draws immediately above a camera-facing owning plane.
	# It is otherwise behind that plane. This replaces the old sparse-line rule
	# whose average depth could leak a stroke across a solid seat or back slab.
	var edge_depth := (float(first.depth) + float(second.depth)) * 0.5
	var z := -int(edge_depth * 1000.0) - 4
	for fill_side in edge.fill_sides:
		var fill_projection := _project(fill_side.center, center, origin, forward, right, offset)
		if not bool(fill_projection.visible):
			continue
		var fill_z := -int(float(fill_projection.depth) * 1000.0)
		if _face_visible(fill_side.normal, fill_side.center, center, origin):
			z = max(z, fill_z + 4)
		else:
			z = min(z, fill_z - 4)
	return clampi(z, -4096, 4092)

func _is_near_fill_boundary(edge: Dictionary, fill_side: Dictionary, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> bool:
	# A horizontal `poly` is the chair's solid top plane.  In this renderer that
	# plane reads as a projected rectangle: its front (screen-bottom) rim is the
	# only perimeter that can be exposed.  The screen-top rim is the back line
	# the artist called out, and must stay under the cyan top fill even when a
	# neighbouring `edge` face also references the same Blender edge.
	if fill_side.normal.y > 0.5:
		var midpoint_projection := _project((edge.a + edge.b) * 0.5, center, origin, forward, right, offset)
		var center_projection := _project(fill_side.center, center, origin, forward, right, offset)
		return bool(midpoint_projection.visible) and bool(center_projection.visible) and float(midpoint_projection.pixel.y) > float(center_projection.pixel.y) + 0.25
	# From the centre of a filled face, the vector toward an edge tells us which
	# side of that face the edge occupies.  Only a component toward the camera
	# owns the visible perimeter.  This is the 3D equivalent of putting a sheet
	# of paper over the far/underside strokes, rather than deciding from a
	# screen-space line's average depth.
	var midpoint: Vector3 = (edge.a + edge.b) * 0.5
	var face_center: Vector3 = fill_side.center
	var boundary_direction := midpoint - face_center
	var camera := Vector3((origin.x - center.x) / _scale_factor, 0.5 / _scale_factor, (origin.y - center.y) / _scale_factor)
	var toward_camera := camera - face_center
	# A small positive threshold prevents the left/right rims of an exactly
	# symmetric face from randomly becoming foreground due to float noise.
	return boundary_direction.dot(toward_camera) > 0.0005


func _build_footprint() -> void:
	if _points.is_empty():
		return
	var min_x := _points[0].x
	var max_x := min_x
	var min_z := _points[0].z
	var max_z := min_z
	var floor_y := _points[0].y
	for point in _points:
		min_x = minf(min_x, point.x); max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z); max_z = maxf(max_z, point.z)
		floor_y = minf(floor_y, point.y)
	_footprint = [Vector3(min_x, floor_y, min_z), Vector3(max_x, floor_y, min_z), Vector3(max_x, floor_y, max_z), Vector3(min_x, floor_y, max_z)]

func _draw_floor_shadow(center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> void:
	if ground_shadow == null or _footprint.is_empty():
		return
	var pixels := PackedVector2Array()
	for point in _footprint:
		var projected := _project(point, center, origin, forward, right, offset)
		if not bool(projected.visible):
			ground_shadow.visible = false
			return
		pixels.append(projected.pixel)
	ground_shadow.visible = true
	ground_shadow.mesh = _polygon_mesh(pixels)
	ground_shadow.modulate = floor_shadow_color

func _face_visible(normal: Vector3, face_center: Vector3, center: Vector2, origin: Vector2) -> bool:
	var camera := Vector3((origin.x - center.x) / _scale_factor, 0.5 / _scale_factor, (origin.y - center.y) / _scale_factor)
	return normal.dot(camera - face_center) > 0.0

func _edge_visible(edge: Dictionary, center: Vector2, origin: Vector2) -> bool:
	for side in edge.sides:
		if _face_visible(side.normal, side.center, center, origin): return true
	return edge.sides.is_empty()

func _interior_edge(edge: Dictionary, center: Vector2, origin: Vector2) -> bool:
	var seen := 0
	for side in edge.sides:
		if _face_visible(side.normal, side.center, center, origin): seen += 1
	return seen >= 2 # no silhouette highlight

func _project(point: Vector3, center: Vector2, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> Dictionary:
	var relative := center + Vector2(point.x, point.z) * _scale_factor - origin
	var depth := relative.dot(forward)
	if depth <= 0.01: return {"visible": false, "pixel": Vector2.ZERO, "depth": depth}
	return {"visible": true, "pixel": Vector2(80.0 + relative.dot(right) / depth * 128.0, 31.5 + (0.5 - point.y * _scale_factor) / depth * 128.0) + offset, "depth": depth}

func _polygon_mesh(points: PackedVector2Array) -> ArrayMesh:
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = points
	var ids := PackedInt32Array()
	for index in range(1, points.size() - 1): ids.append_array(PackedInt32Array([0, index, index + 1]))
	arrays[Mesh.ARRAY_INDEX] = ids
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays); return mesh

func _carrier(first: Vector2, second: Vector2) -> ArrayMesh:
	var low := Vector2(minf(first.x, second.x), minf(first.y, second.y)) - Vector2(2.0, 2.0)
	var high := Vector2(maxf(first.x, second.x), maxf(first.y, second.y)) + Vector2(2.0, 2.0)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays); return mesh

func _key(first: int, second: int) -> String: return "%d:%d" % [mini(first, second), maxi(first, second)]
func _vector_key(point: Vector3) -> String: return "%.5f:%.5f:%.5f" % [point.x, point.y, point.z]
func _vector_edge_key(first: Vector3, second: Vector3) -> String:
	var a := _vector_key(first)
	var b := _vector_key(second)
	return a + "|" + b if a < b else b + "|" + a
func _fade(distance: float, full: float, hidden: float) -> float: return 1.0 - smoothstep(minf(full, hidden - 0.01), maxf(hidden, full + 0.01), distance)

func _load_style() -> void:
	chair_style = load(STYLE_PATH)
	if chair_style == null:
		chair_style = STYLE_SCRIPT.new(); ResourceSaver.save(chair_style, STYLE_PATH)
	for key in _style_values(): set(key, chair_style.get(key))
	_saved = _style_values()

func _style_values() -> Dictionary:
	return {"y_axis_top_color": y_axis_top_color, "x_axis_side_color": x_axis_side_color, "z_axis_side_color": z_axis_side_color, "y_axis_edge_highlight_color": y_axis_edge_highlight_color, "x_axis_edge_highlight_color": x_axis_edge_highlight_color, "z_axis_edge_highlight_color": z_axis_edge_highlight_color, "floor_shadow_color": floor_shadow_color, "imported_normals_are_inverted": imported_normals_are_inverted, "slab_box_thickness": slab_box_thickness, "post_box_half_width": post_box_half_width, "maximum_edge_pixels": maximum_edge_pixels, "maximum_edge_distance": maximum_edge_distance, "one_pixel_distance": one_pixel_distance, "edge_highlight_full_distance": edge_highlight_full_distance, "edge_highlight_hidden_distance": edge_highlight_hidden_distance, "close_highlight_color": close_highlight_color, "close_crevice_shadow_color": close_crevice_shadow_color, "accent_full_distance": accent_full_distance, "accent_hidden_distance": accent_hidden_distance}
