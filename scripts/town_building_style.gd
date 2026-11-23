class_name TownBuildingStyle
extends Resource
## World-space shell and street frontage for a modular town building.
## The ground floor is playable. Upper floors and balconies are facade geometry.

const FLOOR_HEIGHT := 0.05
const FLOOR_APRON_BOTTOM := 0.023
const CORNER_POST_WIDTH := 0.045
const DOOR_HEIGHT := 0.53
const RAIL_TOP := 0.258
const RAIL_WIDTH := 0.036
const WINDOW_TRIM := 0.037
const DOOR_HALF_WIDTH := 0.38
# Match the Coffee Shop single-leaf opening, not one of the wider double doors.
const ROOM_DOOR_WIDTH := 0.38
const SALOON_GATE_BOTTOM := 0.16
const SALOON_GATE_TOP := 0.40
const BALCONY_HEIGHT := 0.695
const PLANE_LIMIT := 24
const SUPPORT_LIMIT := 8

var coffee_kit: TownCoffeeKit
var blueprint_gable := false
var entrances: Array[Vector4i] = []
var side_windows_per_bay := 2
var rear_windows_per_bay := 2
var rear_window_bays: PackedInt32Array = []

@export var sign_text := ""
@export var footprint := Rect2i(1, 2, 3, 2)
@export var faces_south := true
@export var eave := 0.84
@export var rise := 0.43
@export var facade_height := 1.19
@export var porch_depth := 0.48
@export_range(0.0, 0.8, 0.01) var porch_awning_shadow := 0.68
@export_range(0.0, 0.8, 0.01) var porch_deck_shadow := 0.30
@export_range(0.0, 0.8, 0.01) var baluster_rail_shadow := 0.40
@export var balcony := false
@export var second_story := false
@export var framed_sign := false
@export var wallpaper := Color("#a09b79")
@export var front_window_offsets: PackedFloat32Array = []
@export var west_windows := true
@export var east_windows := true
@export var partitions: Array[Vector4i] = []
@export var partition_doors: Array[Vector4i] = []
@export var cover: PackedVector2Array = []
@export var timber := Color("#513a28")
@export var metal := Color("#706c61")
@export var sign_board := Color("#4c5040")
@export var sign_ink := Color("#28251e")


func frontage() -> float:
	return float(footprint.end.y if faces_south else footprint.position.y)


func rear_wall_y() -> float:
	return float(footprint.position.y if faces_south else footprint.end.y)


func direction() -> float:
	return 1.0 if faces_south else -1.0


func door_x() -> float:
	return footprint.position.x + floorf(footprint.size.x * 0.5) + door_offset()


func porch() -> Rect2:
	var front := frontage()
	return Rect2(footprint.position.x, minf(front, front + direction() * porch_depth), footprint.size.x, porch_depth)


func floor_bounds() -> Rect2:
	return Rect2(footprint).merge(porch())


func awning_heights() -> Vector2:
	if coffee_kit != null:
		var low: float = coffee_kit.reference.AWNING_FRONT
		var high: float = coffee_kit.reference.AWNING_BACK
		if blueprint_gable:
			low = coffee_kit.gable_awning.x
			high = coffee_kit.gable_awning.y
		return Vector2(high, low) if faces_south else Vector2(low, high)
	var low := 1.025 if balcony else 0.65
	return Vector2(low + 0.17, low) if faces_south else Vector2(low, low + 0.17)


func wall_role(a: Vector2, b: Vector2) -> int:
	var body := Rect2(footprint)
	if a.min(b).x < body.position.x or a.max(b).x > body.end.x or a.min(b).y < body.position.y or a.max(b).y > body.end.y:
		return 0
	if is_equal_approx(a.y, b.y):
		if is_equal_approx(a.y, frontage()):
			return 1
		if is_equal_approx(a.y, body.position.y) or is_equal_approx(a.y, body.end.y):
			return 2
	if is_equal_approx(a.x, b.x) and (is_equal_approx(a.x, body.position.x) or is_equal_approx(a.x, body.end.x)):
		return 3
	return 0


func porch_post_width() -> float:
	if blueprint_gable:
		return 0.05
	return CORNER_POST_WIDTH if coffee_kit == null else float(coffee_kit.reference.porch_post_width)


func porch_rail_top() -> float:
	return 0.30 if blueprint_gable else RAIL_TOP


func porch_faces() -> Array[Dictionary]:
	var deck := porch()
	var half_post := porch_post_width() * 0.5
	var left := float(footprint.position.x) + half_post
	var right := float(footprint.end.x) - half_post
	var edge := frontage() + direction() * (porch_depth - half_post)
	var awning := awning_heights()
	var top := minf(awning.x, awning.y)
	var faces: Array[Dictionary] = [
		{"a": Vector2(left, edge), "b": Vector2(right, edge), "top": top, "role": 4},
		{"a": Vector2(left, deck.position.y), "b": Vector2(left, deck.end.y), "top": maxf(awning.x, awning.y), "role": 5},
		{"a": Vector2(right, deck.position.y), "b": Vector2(right, deck.end.y), "top": maxf(awning.x, awning.y), "role": 5},
	]
	return faces


func porch_rail_spans() -> Array[Dictionary]:
	var faces := porch_faces()
	var a: Vector2 = faces[0]["a"]
	var b: Vector2 = faces[0]["b"]
	if blueprint_gable:
		var boundary := Vector2(footprint.position.x + floorf(footprint.size.x * 0.5) + 0.5, a.y)
		if faces_south:
			return [{"a": a, "b": a}, {"a": boundary, "b": b}]
		return [{"a": a, "b": boundary}, {"a": b, "b": b}]
	var gate_half := 0.55 if coffee_kit == null else door_half_width() + 0.09
	var left_gate := Vector2(maxf(door_x() - gate_half, a.x), a.y)
	var right_gate := Vector2(minf(door_x() + gate_half, b.x), a.y)
	return [
		{"a": a, "b": left_gate},
		{"a": right_gate, "b": b},
	]


func porch_members() -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	if porch_depth <= 0.0:
		return members
	if blueprint_gable:
		return _gable_porch_members()
	var faces := porch_faces()
	var rails := porch_rail_spans()
	var front: Dictionary = faces[0]
	var deck := porch()
	# Center the posts on the actual deck corners. Their outer halves project
	# past both fascia faces while their inner halves meet the deck.
	var outside_y := frontage() + direction() * porch_depth
	var a := Vector2(deck.position.x, outside_y)
	var b := Vector2(deck.end.x, outside_y)
	var roof: float = front["top"]
	var awning_rise := 0.17
	var post_width := porch_post_width()
	var posts: Array[Vector2] = [a, b]
	if coffee_kit != null:
		for index in range(1, footprint.size.x):
			posts.append(a + Vector2(index, 0.0))
	if balcony:
		posts.append(a + Vector2(1.055, 0.0))
		posts.append(a + Vector2(2.925, 0.0))
	for post in posts:
		members.append(_timber(post - Vector2(post_width * 0.5, 0.0), post + Vector2(post_width * 0.5, 0.0), 0.0, roof, post_width))
		for side in [-1.0, 1.0]:
			var foot := post + Vector2(side * 0.026, 0.0)
			var head := post + Vector2(side * 0.145, 0.0)
			if head.x > a.x and head.x < b.x:
				var brace := _timber(foot, head, roof - 0.19, roof - 0.035, 0.034)
				brace["brace"] = Vector2(roof - 0.17, roof - 0.05)
				brace["ramp_half"] = 0.017
				members.append(brace)
	# Split the continuous beam at the painter boundary. Both halves have
	# identical sections and meet flush, with no join visible in the paint.
	var midpoint := (a + b) * 0.5
	members.append(_timber(a, midpoint, roof - 0.061, roof - 0.005, 0.072))
	members.append(_timber(midpoint, b, roof - 0.061, roof - 0.005, 0.072))
	for index in [1, 2]:
		var end := a if index == 1 else b
		var inward := Vector2.DOWN * -direction()
		var wall := Vector2(end.x, frontage())
		var side_beam := _timber(end, wall, roof - 0.073, roof + awning_rise, 0.067)
		side_beam["brace"] = Vector2(roof - 0.040, roof + awning_rise - 0.040)
		side_beam["ramp_half"] = 0.030
		members.append(side_beam)
		var head := end + inward * 0.14
		var brace_top := roof + awning_rise * 0.14 / porch_depth - 0.057
		var brace := _timber(end + inward * 0.026, head, roof - 0.19, brace_top + 0.020, 0.034)
		brace["brace"] = Vector2(roof - 0.17, brace_top)
		brace["ramp_half"] = 0.017
		members.append(brace)
	if coffee_kit != null:
		var apron: float = coffee_kit.reference.apron_bottom()
		var depth: float = coffee_kit.reference.porch_handrail_section.x
		var lip := outside_y - direction() * depth * 0.5
		var center := Vector2(midpoint.x, lip)
		members.append(_timber(Vector2(a.x, lip), center, apron, FLOOR_HEIGHT, depth))
		members.append(_timber(center, Vector2(b.x, lip), apron, FLOOR_HEIGHT, depth))
		for x in [a.x + depth * 0.5, b.x - depth * 0.5]:
			members.append(_timber(Vector2(x, outside_y), Vector2(x, frontage()), apron, FLOOR_HEIGHT, depth))
	for span in rails:
		_add_guard(members, span["a"], span["b"], FLOOR_HEIGHT, porch_rail_top())
	if balcony:
		for face in faces:
			_add_guard(members, face["a"], face["b"], BALCONY_HEIGHT, BALCONY_HEIGHT + 0.23)
	return members


func _add_guard(members: Array[Dictionary], a: Vector2, b: Vector2, bottom: float, top: float) -> void:
	var length := a.distance_to(b)
	var spacing := 0.145 if coffee_kit == null else coffee_kit.baluster_spacing
	var count := floori(length / spacing)
	if length < 0.001 or (count < 1 and coffee_kit == null):
		return
	var rail := Vector2(RAIL_WIDTH, 0.030) if coffee_kit == null else Vector2(coffee_kit.reference.porch_handrail_section)
	var baluster := 0.024 if coffee_kit == null else float(coffee_kit.reference.porch_baluster_width)
	members.append(_timber(a, b, top - rail.y, top, rail.x))
	members.append(_timber(a, b, bottom + 0.021, bottom + 0.043, 0.028))
	var half := (b - a).normalized() * (baluster * 0.5)
	for index in count:
		var center := a.lerp(b, (index + 0.5) / count)
		members.append(_timber(center - half, center + half, bottom + 0.038, top - 0.025, baluster))


func _gable_porch_members() -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	var deck := porch()
	var outer_y := frontage() + direction() * porch_depth
	var post_width := porch_post_width()
	var half_post := post_width * 0.5
	var post_y := outer_y - direction() * half_post
	var left := deck.position.x
	var right := deck.end.x
	var middle := deck.get_center().x
	var low: float = coffee_kit.gable_awning.x
	var high: float = coffee_kit.gable_awning.y
	var beam_bottom := low - 0.037
	# Posts finish flush to the deck and awning. Beam and knee braces sit
	# behind their outer faces, with no diagonal brace on the side elevation.
	for side: float in [-1.0, 1.0]:
		var x := left + half_post if side < 0.0 else right - half_post
		var post := Vector2(x, post_y)
		members.append(_timber(post - Vector2(half_post, 0.0), post + Vector2(half_post, 0.0), 0.0, low + 0.0075, post_width))
		var toe := Vector2(x - side * (half_post - 0.001), post_y)
		var shoulder := Vector2(x - side * 0.166, post_y)
		var brace := _timber(toe, shoulder, 0.526, beam_bottom, 0.0205)
		# Extend the diagonal into the header so its visible upper cut is
		# horizontal. The timber shader clips the embedded length at the joint.
		brace["brace"] = Vector2(0.549, beam_bottom + 0.023)
		brace["ramp_half"] = 0.023
		members.append(brace)
	for run in [Vector2(left + post_width, middle), Vector2(middle, right - post_width)]:
		members.append(_timber(Vector2(run.x, post_y), Vector2(run.y, post_y), beam_bottom, low + 0.002, 0.026))
	# Two outer rafters and two narrower-spaced inner rafters support the awning.
	for offset: float in [0.025, 0.346, 0.654, 0.975]:
		var outer := offset < 0.05 or offset > 0.95
		var x := left + half_post if offset < 0.05 else (right - half_post if outer else lerpf(left, right, offset))
		var end_y := outer_y - direction() * (0.05 if outer else 0.038)
		var rafter := _timber(Vector2(x, end_y), Vector2(x, frontage()), low - 0.038, high, half_post)
		var outer_top := lerpf(low, high, absf(end_y - outer_y) / porch_depth)
		const HALF_DEPTH := 0.025
		# Keep the top flush to the slope so the metal stays uninterrupted.
		rafter["brace"] = Vector2(outer_top, high) - Vector2.ONE * (HALF_DEPTH + 0.002)
		rafter["ramp_half"] = HALF_DEPTH
		members.append(rafter)
	var apron: float = coffee_kit.reference.apron_bottom()
	var lip_y := outer_y - direction() * 0.017
	# Butt each fascia run against the post's inner face. Overlapping the
	# post box lets the fascia hide its foot when viewed across the deck.
	for run in [Vector2(left + post_width, middle), Vector2(middle, right - post_width)]:
		members.append(_timber(Vector2(run.x, lip_y), Vector2(run.y, lip_y), apron, FLOOR_HEIGHT, 0.034))
	var side_start_y := outer_y - direction() * post_width
	for x in [left + 0.017, right - 0.017]:
		members.append(_timber(Vector2(x, side_start_y), Vector2(x, frontage()), apron, FLOOR_HEIGHT, 0.034))
	var rail: Dictionary = porch_rail_spans()[1 if faces_south else 0]
	var a: Vector2 = rail["a"]
	var b: Vector2 = rail["b"]
	members.append(_timber(a, b, 0.275, 0.30, post_width))
	var inward := 1.0 if faces_south else -1.0
	for offset: float in [0.014, 0.25]:
		var center := Vector2(middle + inward * offset, post_y)
		members.append(_timber(center - Vector2(0.014, 0.0), center + Vector2(0.014, 0.0), FLOOR_HEIGHT, 0.275, 0.025))
	return members


func _timber(a: Vector2, b: Vector2, bottom: float, top: float, thickness: float) -> Dictionary:
	return {
		"a": a, "b": b, "bottom": bottom, "thickness": thickness,
		"variant": {"style": self, "role": 9, "top": top},
	}


# Local cell and cardinal edge for the ground-floor room dividers.
func partition_edges() -> Array[Vector4i]:
	var edges: Array[Vector4i] = []
	for partition in partitions:
		var cell := footprint.position + Vector2i(partition.x, partition.y)
		edges.append(Vector4i(cell.x, cell.y, partition.z, partition.w))
	return edges


# Room doors use the same swinging leaves and partial collision spans as the
# exterior doors. Each Vector4i names a cell and the edge facing its neighbor.
func room_door_spans(open_doors: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for doorway in partition_doors:
		var cell := footprint.position + Vector2i(doorway.x, doorway.y)
		var direction := Vector2i(doorway.z, doorway.w)
		var start := Vector2(cell)
		var tangent := Vector2.RIGHT if direction.y != 0 else Vector2.DOWN
		if direction == Vector2i.DOWN:
			start.y += 1.0
		elif direction == Vector2i.RIGHT:
			start.x += 1.0
		var id := "room_%s_%s_%s" % [footprint.position, cell, direction]
		var swing := float(open_doors.get(id, 0.0))
		var half_width := ROOM_DOOR_WIDTH * 0.5
		var hinge := start + tangent * (0.5 - half_width)
		var tip := hinge + (tangent * ROOM_DOOR_WIDTH).rotated(swing * PI * 0.4333333333)
		for ends in [Vector2(0.0, 0.5 - half_width), Vector2(0.5 + half_width, 1.0)]:
			result.append({"a": start + tangent * ends.x, "b": start + tangent * ends.y, "town_partition": self})
		result.append({"a": hinge, "b": start + tangent * (0.5 + half_width), "bottom": DOOR_HEIGHT, "height": 0.70, "town_partition": self, "room_lintel": true, "projectile_only": true})
		result.append({"a": hinge, "b": tip, "bottom": FLOOR_HEIGHT, "height": DOOR_HEIGHT, "paint": 3,
			"push_door": id if is_zero_approx(swing) else "", "close_door": id if absf(swing) >= 0.999 else "", "open_rotation_sign": 1.0})
	return result


func exterior_door_cells() -> Array[Vector4i]:
	if coffee_kit != null:
		var placed: Array[Vector4i] = []
		for entrance in entrances:
			placed.append(entrance + Vector4i(footprint.position.x, footprint.position.y, 0, 0))
		return placed
	var x := floori(door_x())
	return [Vector4i(x, footprint.position.y, 0, -1), Vector4i(x, footprint.end.y - 1, 0, 1)]


func door_half_width() -> float:
	if blueprint_gable:
		return (coffee_kit.gable_door.y - coffee_kit.gable_door.x) * 0.5
	return DOOR_HALF_WIDTH if coffee_kit == null else coffee_kit.door_width() * 0.5


func door_offset() -> float:
	if blueprint_gable:
		var center := (coffee_kit.gable_door.x + coffee_kit.gable_door.y) * 0.5
		return center if faces_south else 1.0 - center
	return 0.5


func exterior_door_top() -> float:
	return coffee_kit.gable_door_top if blueprint_gable else DOOR_HEIGHT


func door_edge(door: Vector4i) -> PackedVector2Array:
	var a := Vector2(door.x, door.y)
	var b := a + (Vector2.RIGHT if door.w != 0 else Vector2.DOWN)
	var shift := Vector2(maxi(0, door.z), maxi(0, door.w))
	return PackedVector2Array([a + shift, b + shift])


func door_leaf_spans(open_doors: Dictionary) -> Array[Dictionary]:
	if coffee_kit != null:
		var leaves: Array[Dictionary] = []
		for door in exterior_door_cells():
			var edge := door_edge(door)
			var tangent := edge[1] - edge[0]
			var front := door.w == int(direction())
			var reverse_hinge := blueprint_gable and (front != faces_south)
			var rotation_sign := -1.0 if reverse_hinge else 1.0
			var hinge := edge[0] + tangent * (door_offset() - rotation_sign * door_half_width())
			var id := "exterior_%s" % door
			var swing := float(open_doors.get(id, 0.0))
			var angle := swing * rotation_sign * deg_to_rad(78.0)
			var tip := hinge + tangent.rotated(angle) * rotation_sign * door_half_width() * 2.0
			var leaf := {"a": hinge, "b": tip, "bottom": FLOOR_HEIGHT, "height": exterior_door_top(),
				"paint": 3, "generated_door": true, "open_rotation_sign": rotation_sign,
				"open_leaf": not is_zero_approx(swing),
				"push_door": id if is_zero_approx(swing) else "",
				"close_door": id if absf(swing) >= 0.999 else ""}
			if blueprint_gable:
				leaf["visual_bottom"] = coffee_kit.gable_door_sill
				leaf["gable_door_kit"] = coffee_kit
				leaf["gable_knob_uv"] = coffee_kit.gable_front_knob if front else coffee_kit.gable_rear_knob
				leaf["gable_knob_normal"] = Vector2(door.z, door.w).rotated(angle)
			leaves.append(leaf)
		return leaves
	var doors: Array[Dictionary] = []
	for y in [footprint.position.y, footprint.end.y]:
		for side: float in [-1.0, 1.0]:
			var saloon_gate := sign_text == "SALOON" and is_equal_approx(float(y), frontage())
			var id := "saloon_swing_front" if saloon_gate else "%s_door_%s_%s" % [footprint.position, y, side]
			var hinge := Vector2(door_x() + side * DOOR_HALF_WIDTH, y)
			var swing := float(open_doors.get(id, 0.0))
			var leaf := (Vector2.LEFT * side).rotated(deg_to_rad(-side * swing * 78.0)) * DOOR_HALF_WIDTH
			doors.append({
				"a": hinge, "b": hinge + leaf, "bottom": SALOON_GATE_BOTTOM if saloon_gate else FLOOR_HEIGHT,
				"height": SALOON_GATE_TOP if saloon_gate else DOOR_HEIGHT, "variant_style": self, "saloon_gate": saloon_gate,
				"open_rotation_sign": -side,
				"push_door": id if is_zero_approx(swing) else "",
				"close_door": id if absf(swing) >= 0.999 else "",
				"hinge_side": side,
			})
	return doors


# X and height use world units. Each ground-floor opening stays in one
# physical wall cell so collision, vaults and projectiles use the same edge.
func ground_windows(face := "front") -> Array[Rect2]:
	var windows: Array[Rect2] = []
	if blueprint_gable:
		if face == "front":
			var window := coffee_kit.gable_window
			if not faces_south:
				window.position.x = 1.0 - window.end.x
			window.position.x += footprint.position.x + floorf(footprint.size.x * 0.5)
			windows.append(window)
		return windows
	if coffee_kit != null:
		var horizontal := face in ["front", "rear"]
		var first := footprint.position.x if horizontal else footprint.position.y
		var last := footprint.end.x if horizontal else footprint.end.y
		var direction := Vector2i(0, int(direction())) if face == "front" else Vector2i(0, -int(direction()))
		if not horizontal:
			direction = Vector2i.LEFT if face == "west" else Vector2i.RIGHT
		var door_bays := {}
		for door in exterior_door_cells():
			if Vector2i(door.z, door.w) == direction:
				door_bays[door.x if horizontal else door.y] = true
		var count := rear_windows_per_bay if face == "rear" else (2 if horizontal else side_windows_per_bay)
		var offsets: Array[float] = []
		if count == 2:
			offsets.assign([coffee_kit.window_centers.x, coffee_kit.window_centers.y])
		elif count == 1:
			offsets.append(0.5)
		for bay in range(first, last):
			if door_bays.has(bay) or (face == "rear" and not rear_window_bays.is_empty() and not rear_window_bays.has(bay - first)):
				continue
			for offset in offsets:
				var size := coffee_kit.window_size
				windows.append(Rect2(bay + offset - size.x * 0.5, coffee_kit.window_sill, size.x, size.y))
		return windows
	if face != "front":
		if (face == "west" and not west_windows) or (face == "east" and not east_windows):
			return windows
		if not second_story:
			for y in range(footprint.position.y, footprint.end.y):
				windows.append(Rect2(y + 0.285, 0.205, 0.43, 0.37))
		return windows
	var centers: Array[float] = []
	if front_window_offsets.is_empty():
		centers = [footprint.position.x + 0.5, footprint.end.x - 0.5]
	else:
		for offset in front_window_offsets:
			centers.append(float(footprint.position.x) + offset)
	for x in centers:
		if absf(x - door_x()) < 0.5:
			continue
		var half_width := 0.36 if footprint.size.x > 2 else 0.32
		windows.append(Rect2(x - half_width, 0.205, half_width * 2.0, 0.37))
	return windows


func window_id(index: int, face := "front") -> String:
	return "%s_%s_window_%d" % [footprint.position, face, index]


func step_bounds() -> Rect2:
	if porch_depth <= 0.0 or coffee_kit != null:
		return Rect2()
	var front := frontage() + direction() * porch_depth
	return Rect2(door_x() - 0.46, minf(front, front + direction() * 0.115), 0.92, 0.115)


func sign_bounds() -> Rect2:
	var width := minf(footprint.size.x * 0.77, 2.45)
	var height := 0.17 if framed_sign else 0.26
	var clearance := 0.055 if balcony else 0.09
	return Rect2((footprint.size.x - width) * 0.5, facade_height - clearance - height, width, height)


func roof_planes() -> Array[Dictionary]:
	if blueprint_gable:
		var body := Rect2(footprint)
		var half := Vector2(body.size.x * 0.5, body.size.y)
		var ridge := eave + rise
		var planes: Array[Dictionary] = [
			{"rect": Rect2(body.position, half), "heights": Vector2(eave, ridge), "slope_x": true, "light": 1.18},
			{"rect": Rect2(body.position + Vector2(half.x, 0.0), half), "heights": Vector2(ridge, eave), "slope_x": true, "light": 0.83},
			{"rect": floor_bounds(), "heights": Vector2.ONE * FLOOR_HEIGHT, "wood": true, "porch_deck": porch_depth > 0.0},
		]
		if porch_depth > 0.0:
			planes.append({"rect": porch(), "heights": awning_heights(), "light": 1.04, "gable_awning": true})
		return planes
	if coffee_kit != null:
		var roof := Rect2(footprint)
		var heights := Vector2(eave, eave + rise) if faces_south else Vector2(eave + rise, eave)
		var planes: Array[Dictionary] = [
			{"rect": roof, "heights": heights, "light": 1.1},
			{"rect": floor_bounds(), "heights": Vector2.ONE * FLOOR_HEIGHT, "wood": true, "porch_deck": porch_depth > 0.0},
		]
		if porch_depth > 0.0:
			planes.append({"rect": porch().grow(0.018), "heights": awning_heights(), "light": 1.04})
		return planes
	var roof := Rect2(footprint).grow(0.042)
	# The false front is the street-facing end of the roof. Keep the
	# overhang at the rear and sides, but stop it at the sign facade.
	if faces_south:
		roof.size.y = frontage() - roof.position.y
	else:
		var rear_edge := roof.end.y
		roof.position.y = frontage()
		roof.size.y = rear_edge - roof.position.y
	var half := roof.size.x * 0.5
	var ridge := eave + rise
	var rim := eave - rise * 0.042 / (footprint.size.x * 0.5)
	var planes: Array[Dictionary] = [
		{"rect": Rect2(roof.position, Vector2(half, roof.size.y)), "heights": Vector2(rim, ridge), "slope_x": true, "light": 1.18},
		{"rect": Rect2(roof.position + Vector2(half, 0.0), Vector2(half, roof.size.y)), "heights": Vector2(ridge, rim), "slope_x": true, "light": 0.83},
		{"rect": porch().grow(0.018), "heights": awning_heights(), "light": 1.04},
		{"rect": floor_bounds(), "heights": Vector2.ONE * FLOOR_HEIGHT, "wood": true, "porch_deck": true},
	]
	if balcony:
		planes.append({"rect": porch(), "heights": Vector2.ONE * BALCONY_HEIGHT, "wood": true})
	planes.append({"rect": step_bounds(), "heights": Vector2.ONE * 0.026, "wood": true})
	return planes
