extends Resource
## The cage is authored facing south and placed facing north into town.

var instance_prefix := ""
var FOOTPRINT := Rect2i(1, 6, 1, 2)
const FRONT_DOOR := Vector2(0.16, 0.54)
const REAR_DOOR := Vector2(0.31, 0.69)

enum EavePaint { PORCH_BEAM = 4, REAR_TRIM, FRONT_CORNICE }

@export_range(0.22, 0.70, 0.01) var porch_depth := 0.47
@export_range(0.01, 0.08, 0.005) var porch_height := 0.050
@export var wood_color := Color("#443421")
@export var roof_color := Color("#666865")
@export var roof_rust_color := Color("#795b49")
@export_range(0.015, 0.065, 0.005) var door_casing_width := 0.04
@export_range(0.005, 0.04, 0.001) var door_reveal_width := 0.017
@export_range(0.0, 0.045, 0.001) var door_panel_depth := 0.030

@export_group("Storefront construction")
@export_range(0.02, 0.08, 0.001) var corner_post_width := 0.043
@export_range(0.005, 0.045, 0.001) var floor_apron_depth := 0.027
## Siding overhang shadow on the top logical row of the foundation.
@export_range(0.0, 0.8, 0.01) var siding_foundation_shadow := 0.48
@export_range(0.02, 0.16, 0.005) var foundation_shadow_reach := 0.095
@export_range(0.0, 0.85, 0.01) var foundation_shadow_strength := 0.62
@export_range(4, 24) var siding_course_count := 8
## Dark at the upper edge below the lap, light at the lower edge above the lap.
@export var siding_face_light := Vector2(0.72, 1.24)
## Nearest footprint distances where the building starts and finishes simplifying its siding.
@export var siding_detail_distance := Vector2(1.65, 3.75)
## Darkest and lightest board multipliers once the siding has simplified.
@export var siding_distant_variation := Vector2(0.71, 1.27)
## Fraction of an upper board painted as its underside.
@export_range(0.34, 0.66, 0.01) var siding_upper_shadow_fraction := 0.49
@export_range(0.0, 0.035, 0.001) var siding_lap_relief := 0.020
@export_range(0.025, 0.080, 0.005) var eave_beam_depth := 0.045
@export_range(4, 24) var roof_rib_count := 18
@export_range(0.0, 0.6, 0.01) var roof_rib_contrast := 0.25

@export_group("Sunlight")
## Face light from east through north/south to west.
@export var exterior_wall_light := Vector3(0.72, 0.96, 1.20)
@export_range(0.6, 1.4, 0.01) var roof_top_light := 1.10

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

@export_group("Coffee lettering")
## Horizontal coordinates are fractions of the facade, measured from its left.
@export var coffee_lettering_rect := Rect2(0.065, 0.790, 0.870, 0.195)
@export var coffee_letter_ink := Color("#1f1b16")

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
const FOUNDATION_BAND_HEIGHT := 0.035
const WALL_TOP_TRIM_DEPTH := 0.042
const WINDOW_APERTURE := Rect2(0.22, 0.23, 0.56, 0.23)
const WINDOW_MULLION_HALF_SIZE := Vector2(0.035, 0.012)
const AWNING_BACK := 0.78
const AWNING_FRONT := 0.55


func porch_rect() -> Rect2:
	return Rect2(FOOTPRINT.position.x, FOOTPRINT.position.y - porch_depth, 1.0, porch_depth)


func siding_course_height() -> float:
	var cladding_height := FACADE_TOP - WALL_TOP_TRIM_DEPTH - porch_height - FOUNDATION_BAND_HEIGHT
	return cladding_height / siding_course_count


func floor_rect() -> Rect2:
	return porch_rect().merge(Rect2(FOOTPRINT))


func porch_rail_top() -> float:
	return porch_height + 0.23


func apron_bottom() -> float:
	return maxf(0.0, porch_height - floor_apron_depth)


func door_frame_center(front: bool) -> Vector2:
	var opening := FRONT_DOOR if front else REAR_DOOR
	return Vector2(FOOTPRINT.end.x - (opening.x + opening.y) * 0.5, FOOTPRINT.position.y if front else FOOTPRINT.end.y)


func window_id() -> String:
	return "" if instance_prefix.is_empty() else instance_prefix + "front_window"


func window_has_opening(point: Vector2) -> bool:
	return point.x > WINDOW_APERTURE.position.x and point.x < WINDOW_APERTURE.end.x and point.y > WINDOW_APERTURE.position.y and point.y < WINDOW_APERTURE.end.y


func roof_height(world_y: float) -> float:
	return lerpf(ROOF_FRONT, ROOF_REAR, (world_y - FOOTPRINT.position.y) / FOOTPRINT.size.y)


# Render the solid shell from four corner points. The collision apertures
# still come from door_spans(), and moving doors keep their own planes.
func footprint_faces() -> Array[Dictionary]:
	var front_left := Vector2(FOOTPRINT.position)
	var rear_right := Vector2(FOOTPRINT.end)
	var front_right := Vector2(rear_right.x, front_left.y)
	var rear_left := Vector2(front_left.x, rear_right.y)
	return [
		{"a": front_right, "b": front_left, "doorway": FRONT_DOOR, "window": true, "window_span": Vector2(FRONT_DOOR.y, 1.0), "height": FACADE_TOP},
		{"a": rear_right, "b": rear_left, "doorway": REAR_DOOR, "height": ROOF_REAR},
		{"a": front_left, "b": rear_left},
		{"a": front_right, "b": rear_right},
	]


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
	var rail_top := porch_rail_top()
	var rail_bottom := rail_top - porch_handrail_section.y
	var post_half := porch_post_width * 0.5
	var timber_y := lip - post_half
	var apron := apron_bottom()
	var front_beam_top := lerpf(AWNING_FRONT, AWNING_BACK, post_half / porch_depth) - 0.003
	var rail_outer_right := x + 1.0 - porch_post_width
	var spans: Array[Dictionary] = [
		{"a": Vector2(x + FRONT_DOOR.x, front), "b": Vector2(x + FRONT_DOOR.y, front), "bottom": DOOR_TOP, "height": FACADE_TOP, "door_casing_ends": Vector2.ONE},
		{"a": Vector2(x + REAR_DOOR.x, rear), "b": Vector2(x + REAR_DOOR.y, rear), "bottom": DOOR_TOP, "height": ROOF_REAR, "door_casing_ends": Vector2.ONE},
		{"a": Vector2(x + porch_post_width, lip), "b": Vector2(x + 1.0 - porch_post_width, lip), "bottom": apron, "height": porch_height, "paint": 2},
		{"a": Vector2(x, front), "b": Vector2(x, lip - porch_post_width), "bottom": apron, "height": porch_height, "paint": 2},
		{"a": Vector2(x + 1.0, front), "b": Vector2(x + 1.0, lip - porch_post_width), "bottom": apron, "height": porch_height, "paint": 2},
		{"a": Vector2(x + porch_post_width - 0.002, timber_y), "b": Vector2(x + 1.002 - porch_post_width, timber_y), "bottom": front_beam_top - eave_beam_depth, "height": front_beam_top, "paint": EavePaint.PORCH_BEAM},
		{"a": Vector2(x, rear - 0.005), "b": Vector2(x + 1.0, rear - 0.005), "bottom": ROOF_REAR - 0.022, "height": ROOF_REAR + 0.003, "paint": EavePaint.REAR_TRIM},
		{"a": Vector2(x - 0.02, front + 0.008), "b": Vector2(x + 1.02, front + 0.008), "bottom": FACADE_TOP - 0.058, "height": FACADE_TOP + 0.022, "paint": EavePaint.FRONT_CORNICE},
		{"a": Vector2(x + FRONT_DOOR.y, timber_y), "b": Vector2(rail_outer_right, timber_y), "bottom": rail_bottom, "height": rail_top, "paint": 2, "partial": true, "thickness": porch_handrail_section.x, "porch_rail": true},
	]
	for post: float in [x + post_half, x + 1.0 - post_half]:
		spans.append({"a": Vector2(post - post_half, timber_y), "b": Vector2(post + post_half, timber_y), "bottom": 0.0, "height": AWNING_FRONT, "paint": 2, "partial": true, "thickness": porch_post_width, "overhang_height": AWNING_FRONT})
	for baluster: float in [x + FRONT_DOOR.y + porch_baluster_width * 0.5, x + 0.65, x + 0.75, x + 0.85]:
		spans.append({"a": Vector2(baluster - porch_baluster_width * 0.5, timber_y), "b": Vector2(baluster + porch_baluster_width * 0.5, timber_y), "bottom": porch_height, "height": rail_bottom, "paint": 2, "thickness": porch_baluster_width, "overhang_height": rail_bottom})
	# The rear threshold is part of the exposed floor apron.
	spans.append({"a": Vector2(x + REAR_DOOR.x, rear), "b": Vector2(x + REAR_DOOR.y, rear), "bottom": apron, "height": porch_height, "paint": 2})
	return _rotate_into_town(spans)


func door_leaf_spans(open_doors: Dictionary) -> Array[Dictionary]:
	var spans: Array[Dictionary] = []
	for front in [false, true]:
		var id := instance_prefix + ("front" if front else "rear")
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
			"close_door": id if absf(swing) >= 0.999 else "", "open_rotation_sign": -1.0,
		})
	return _rotate_into_town(spans)


func _rotate_into_town(spans: Array[Dictionary]) -> Array[Dictionary]:
	var twice_center := Vector2(FOOTPRINT.position + FOOTPRINT.end)
	for span in spans:
		span["a"] = twice_center - Vector2(span["a"])
		span["b"] = twice_center - Vector2(span["b"])
	return spans
