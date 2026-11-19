extends Resource
## The cage is authored facing south and placed facing north into town.

const FOOTPRINT := Rect2i(2, 8, 1, 2)
const FRONT_DOOR := Vector2(0.16, 0.54)
const REAR_DOOR := Vector2(0.31, 0.69)

@export_range(0.22, 0.70, 0.01) var porch_depth := 0.47
@export_range(0.01, 0.08, 0.005) var porch_height := 0.035
@export var siding_color := Color("#97704b")
@export var trim_color := Color("#513a28")
@export var foundation_color := Color("#513a28")
@export var roof_color := Color("#635d56")
@export_range(0.015, 0.065, 0.005) var door_casing_width := 0.04
@export_range(0.005, 0.04, 0.001) var door_reveal_width := 0.017
@export_range(0.0, 0.045, 0.001) var door_panel_depth := 0.030

@export_group("Porch and fence timber")
@export_range(0.02, 0.06, 0.001) var porch_post_width := 0.036
@export_range(0.012, 0.04, 0.001) var porch_baluster_width := 0.019
@export var porch_handrail_section := Vector2(0.034, 0.029)
@export_range(0.005, 0.025, 0.001) var fence_post_half_width := 0.011
@export_range(0.003, 0.02, 0.001) var fence_rail_half_width := 0.008
@export_range(0.015, 0.05, 0.001) var fence_rail_height := 0.022
@export_range(0.0, 0.6, 0.01) var timber_edge_highlight := 0.34
@export_range(0.0, 0.6, 0.01) var ledge_shadow := 0.34
@export_range(0.0, 0.6, 0.01) var awning_shadow := 0.40

@export_group("Dry grass")
## X/Y are offsets from the storefront footprint, Z scales the spread, and W scales stalk height.
@export var grass_clumps: Array[Vector4] = [
	Vector4(-0.10, 0.20, 1.05, 1.05), Vector4(1.11, 0.25, 1.12, 1.12),
	Vector4(-0.10, 1.82, 0.96, 0.96), Vector4(1.10, 1.76, 1.12, 1.12),
	# Side-wall crate and barrel pockets, including the exposed base between them.
	Vector4(-0.105, 0.66, 0.64, 1.34), Vector4(-0.284, 0.98, 0.59, 0.92),
	Vector4(-0.11, 1.32, 0.72, 1.46),
	Vector4(1.12, 1.065, 0.68, 1.43), Vector4(1.29, 1.38, 0.63, 0.96),
	Vector4(1.19, 1.66, 0.60, 1.26),
	# Around the rear corner outside each prop, away from the door lane.
	Vector4(-0.03, 2.15, 0.76, 1.48), Vector4(1.035, 2.14, 0.72, 1.38),
]

@export_group("Window")
@export_range(0.0, 0.035, 0.001) var window_recess_depth := 0.018
@export var glass_tint := Color(0.47, 0.55, 0.56, 0.22)
@export var glass_shine := Color(0.90, 0.94, 0.88, 0.72)
## Half-widths of the diagonal shine, in window UVs, head-on and oblique.
@export var glass_shine_width := Vector2(0.055, 0.24)
@export_range(0.15, 0.40, 0.01) var glass_fragment_reach := 0.33

const ROOF_FRONT := 0.82
const ROOF_REAR := 0.70
const FACADE_TOP := 1.05
const DOOR_TOP := 0.53
const WINDOW_APERTURE := Rect2(0.22, 0.23, 0.56, 0.23)
const WINDOW_MULLION_HALF_SIZE := Vector2(0.035, 0.012)
const AWNING_BACK := 0.78
const AWNING_FRONT := 0.55


func porch_rect() -> Rect2:
	return Rect2(FOOTPRINT.position.x, FOOTPRINT.position.y - porch_depth, 1.0, porch_depth)


func door_frame_center(front: bool) -> Vector2:
	var opening := FRONT_DOOR if front else REAR_DOOR
	return Vector2(FOOTPRINT.end.x - (opening.x + opening.y) * 0.5, FOOTPRINT.position.y if front else FOOTPRINT.end.y)


func window_has_opening(point: Vector2) -> bool:
	return point.x > WINDOW_APERTURE.position.x and point.x < WINDOW_APERTURE.end.x and point.y > WINDOW_APERTURE.position.y and point.y < WINDOW_APERTURE.end.y


func roof_height(world_y: float) -> float:
	return lerpf(ROOF_FRONT, ROOF_REAR, (world_y - FOOTPRINT.position.y) / FOOTPRINT.size.y)


func door_spans() -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	for front in [false, true]:
		var y := float(FOOTPRINT.end.y if front else FOOTPRINT.position.y)
		var x := float(FOOTPRINT.position.x)
		var opening := FRONT_DOOR if front else REAR_DOOR
		spans.append({"a": Vector2(x, y), "b": Vector2(x + opening.x, y), "height": FACADE_TOP if front else ROOF_REAR, "door_casing_ends": Vector2(0.0, 1.0)})
		spans.append({"a": Vector2(x + opening.y, y), "b": Vector2(x + 1.0, y), "height": FACADE_TOP if front else ROOF_REAR, "window": front, "door_casing_ends": Vector2(1.0, 0.0)})
	return _rotate_into_town(spans)


func trim_spans() -> Array[Dictionary]:
	var x := float(FOOTPRINT.position.x)
	var front := float(FOOTPRINT.end.y)
	var rear := float(FOOTPRINT.position.y)
	var lip := front + porch_depth
	var rail_top := porch_height + 0.23
	var rail_bottom := rail_top - porch_handrail_section.y
	var timber_y := lip - 0.015
	var spans: Array[Dictionary] = [
		{"a": Vector2(x + FRONT_DOOR.x, front), "b": Vector2(x + FRONT_DOOR.y, front), "bottom": DOOR_TOP, "height": FACADE_TOP, "door_casing_ends": Vector2.ONE},
		{"a": Vector2(x + REAR_DOOR.x, rear), "b": Vector2(x + REAR_DOOR.y, rear), "bottom": DOOR_TOP, "height": ROOF_REAR, "door_casing_ends": Vector2.ONE},
		{"a": Vector2(x, lip), "b": Vector2(x + 1.0, lip), "height": porch_height, "paint": 2},
		{"a": Vector2(x, front), "b": Vector2(x, lip), "height": porch_height, "paint": 2},
		{"a": Vector2(x + 1.0, front), "b": Vector2(x + 1.0, lip), "height": porch_height, "paint": 2},
		{"a": Vector2(x, lip), "b": Vector2(x + 1.0, lip), "bottom": AWNING_FRONT - 0.013, "height": AWNING_FRONT + 0.016, "paint": 4, "awning_edge": true},
		{"a": Vector2(x - 0.025, rear - 0.025), "b": Vector2(x + 1.025, rear - 0.025), "bottom": ROOF_REAR - 0.025, "height": ROOF_REAR + 0.035, "paint": 4},
		{"a": Vector2(x - 0.02, front + 0.008), "b": Vector2(x + 1.02, front + 0.008), "bottom": FACADE_TOP - 0.045, "height": FACADE_TOP + 0.018, "paint": 2},
		{"a": Vector2(x + 0.62, timber_y), "b": Vector2(x + 0.945 + porch_post_width * 0.5, timber_y), "bottom": rail_bottom, "height": rail_top, "paint": 2, "partial": true, "thickness": porch_handrail_section.x, "porch_rail": true},
	]
	for post: float in [x + 0.055, x + 0.945]:
		spans.append({"a": Vector2(post - porch_post_width * 0.5, timber_y), "b": Vector2(post + porch_post_width * 0.5, timber_y), "bottom": porch_height, "height": AWNING_FRONT, "paint": 2, "partial": true, "thickness": porch_post_width, "overhang_height": AWNING_FRONT})
	for baluster: float in [x + 0.643, x + 0.733, x + 0.823]:
		spans.append({"a": Vector2(baluster - porch_baluster_width * 0.5, timber_y), "b": Vector2(baluster + porch_baluster_width * 0.5, timber_y), "bottom": porch_height, "height": rail_bottom, "paint": 2, "thickness": porch_baluster_width, "overhang_height": rail_bottom})
	# A low foundation closes the gap below the raised floor at both thresholds.
	spans.append({"a": Vector2(x + FRONT_DOOR.x, front), "b": Vector2(x + FRONT_DOOR.y, front), "height": porch_height, "paint": 2})
	spans.append({"a": Vector2(x + REAR_DOOR.x, rear), "b": Vector2(x + REAR_DOOR.y, rear), "height": porch_height, "paint": 2})
	return _rotate_into_town(spans)


func door_leaf_spans(open_doors: Dictionary) -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	for front in [false, true]:
		var id := "front" if front else "rear"
		var opening := FRONT_DOOR if front else REAR_DOOR
		var y := float(FOOTPRINT.end.y if front else FOOTPRINT.position.y)
		var hinge := Vector2(float(FOOTPRINT.position.x) + opening.x, y)
		var width := opening.y - opening.x
		var swing := float(open_doors.get(id, 0.0))
		# Leave room for a player capsule on either side of the open leaf.
		var leaf_end := hinge + Vector2(width, 0.0).rotated(deg_to_rad(-swing * 78.0))
		spans.append({
			"a": hinge, "b": leaf_end, "bottom": porch_height,
			"height": DOOR_TOP, "paint": 3, "partial": true,
			"push_door": id if is_zero_approx(swing) else "",
			"open_leaf": not is_zero_approx(swing),
			"front_door": front,
			"close_door": id if absf(swing) >= 0.999 else "",
		})
	return _rotate_into_town(spans)


func _rotate_into_town(spans: Array[Dictionary]) -> Array[Dictionary]:
	var twice_center := Vector2(FOOTPRINT.position + FOOTPRINT.end)
	for span in spans:
		span["a"] = twice_center - Vector2(span["a"])
		span["b"] = twice_center - Vector2(span["b"])
	return spans
