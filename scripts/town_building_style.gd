class_name TownBuildingStyle
extends Resource
## World-space shell and street frontage for a modular town building.
## The ground floor is playable. Upper floors and balconies are facade geometry.

const FLOOR_HEIGHT := 0.05
const DOOR_HEIGHT := 0.53
const RAIL_TOP := 0.258
const RAIL_WIDTH := 0.036
const WINDOW_TRIM := 0.037
const DOOR_HALF_WIDTH := 0.38
const BALCONY_HEIGHT := 0.695
const PLANE_LIMIT := 16

@export var sign_text := ""
@export var footprint := Rect2i(1, 2, 3, 2)
@export var faces_south := true
@export var eave := 0.84
@export var rise := 0.43
@export var facade_height := 1.19
@export var porch_depth := 0.48
@export var balcony := false
@export var second_story := false
@export var framed_sign := false
@export var wallpaper := Color("#a09b79")
@export var partitions: Array[Vector4i] = []
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
	return footprint.position.x + floorf(footprint.size.x * 0.5) + 0.5


func porch() -> Rect2:
	var front := frontage()
	return Rect2(footprint.position.x, minf(front, front + direction() * porch_depth), footprint.size.x, porch_depth)


func floor_bounds() -> Rect2:
	return Rect2(footprint).merge(porch())


func awning_heights() -> Vector2:
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


func porch_faces() -> Array[Dictionary]:
	var deck := porch()
	var left := float(footprint.position.x) + 0.025
	var right := float(footprint.end.x) - 0.025
	var edge := frontage() + direction() * porch_depth
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
	var left_gate := Vector2(maxf(door_x() - 0.55, a.x), a.y)
	var right_gate := Vector2(minf(door_x() + 0.55, b.x), a.y)
	return [
		{"a": a, "b": left_gate},
		{"a": right_gate, "b": b},
		{"a": faces[1]["a"], "b": faces[1]["b"]},
		{"a": faces[2]["a"], "b": faces[2]["b"]},
	]


func porch_members() -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	var faces := porch_faces()
	var rails := porch_rail_spans()
	var front: Dictionary = faces[0]
	var a: Vector2 = front["a"]
	var b: Vector2 = front["b"]
	var roof: float = front["top"]
	var posts: Array[Vector2] = [a, b]
	if balcony:
		posts.append(a + Vector2(1.055, 0.0))
		posts.append(a + Vector2(2.925, 0.0))
	for post in posts:
		members.append(_timber(post - Vector2(0.036, 0.0), post + Vector2(0.036, 0.0), 0.0, roof, 0.072))
		for side in [-1.0, 1.0]:
			var foot := post + Vector2(side * 0.026, 0.0)
			var head := post + Vector2(side * 0.205, 0.0)
			if head.x > a.x and head.x < b.x:
				var brace := _timber(foot, head, roof - 0.26, roof - 0.035, 0.052)
				brace["brace"] = Vector2(roof - 0.24, roof - 0.06)
				members.append(brace)
	# Split the continuous beam at the painter boundary. Both halves have
	# identical sections and meet flush, with no join visible in the paint.
	var midpoint := (a + b) * 0.5
	members.append(_timber(a, midpoint, roof - 0.061, roof - 0.005, 0.072))
	members.append(_timber(midpoint, b, roof - 0.061, roof - 0.005, 0.072))
	for index in [1, 2]:
		var end := a if index == 1 else b
		var inward := Vector2.DOWN * -direction()
		var wall := end + inward * porch_depth
		var side_beam := _timber(end, wall, roof - 0.073, roof + 0.17, 0.067)
		side_beam["brace"] = Vector2(roof - 0.040, roof + 0.13)
		side_beam["ramp_half"] = 0.030
		members.append(side_beam)
		var head := end + inward * 0.195
		var brace_top := roof + 0.17 * 0.195 / porch_depth - 0.057
		var brace := _timber(end + inward * 0.026, head, roof - 0.265, brace_top + 0.027, 0.052)
		brace["brace"] = Vector2(roof - 0.24, brace_top)
		members.append(brace)
	for span in rails:
		_add_guard(members, span["a"], span["b"], FLOOR_HEIGHT, RAIL_TOP)
	if balcony:
		for face in faces:
			_add_guard(members, face["a"], face["b"], BALCONY_HEIGHT, BALCONY_HEIGHT + 0.23)
	return members


func _add_guard(members: Array[Dictionary], a: Vector2, b: Vector2, bottom: float, top: float) -> void:
	var count := floori(a.distance_to(b) / 0.145)
	if count < 1:
		return
	members.append(_timber(a, b, top - 0.030, top, RAIL_WIDTH))
	members.append(_timber(a, b, bottom + 0.021, bottom + 0.043, 0.028))
	var half := (b - a).normalized() * 0.012
	for index in count:
		var center := a.lerp(b, (index + 0.5) / count)
		members.append(_timber(center - half, center + half, bottom + 0.038, top - 0.025, 0.024))


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


func door_leaf_spans(open_doors: Dictionary) -> Array[Dictionary]:
	var doors: Array[Dictionary] = []
	for y in [footprint.position.y, footprint.end.y]:
		for side: float in [-1.0, 1.0]:
			var id := "%s_door_%s_%s" % [footprint.position, y, side]
			var hinge := Vector2(door_x() + side * DOOR_HALF_WIDTH, y)
			var swing := float(open_doors.get(id, 0.0))
			var leaf := (Vector2.LEFT * side).rotated(deg_to_rad(-side * swing * 78.0)) * DOOR_HALF_WIDTH
			doors.append({
				"a": hinge, "b": hinge + leaf, "bottom": FLOOR_HEIGHT,
				"height": DOOR_HEIGHT, "variant_style": self,
				"push_door": id if is_zero_approx(swing) else "",
				"close_door": id if absf(swing) >= 0.999 else "",
				"hinge_side": side,
			})
	return doors


# X and height use world units. Each ground-floor opening stays in one
# physical wall cell so collision, vaults and projectiles use the same edge.
func ground_windows(face := "front") -> Array[Rect2]:
	var windows: Array[Rect2] = []
	if face != "front":
		if not second_story:
			for y in range(footprint.position.y, footprint.end.y):
				windows.append(Rect2(y + 0.285, 0.205, 0.43, 0.37))
		return windows
	for x in [footprint.position.x + 0.5, footprint.end.x - 0.5]:
		if absf(x - door_x()) < 0.5:
			continue
		var half_width := 0.36 if footprint.size.x > 2 else 0.32
		windows.append(Rect2(x - half_width, 0.205, half_width * 2.0, 0.37))
	return windows


func window_id(index: int, face := "front") -> String:
	return "%s_%s_window_%d" % [footprint.position, face, index]


func step_bounds() -> Rect2:
	var front := frontage() + direction() * porch_depth
	return Rect2(door_x() - 0.46, minf(front, front + direction() * 0.115), 0.92, 0.115)


func sign_bounds() -> Rect2:
	var width := minf(footprint.size.x * 0.77, 2.45)
	var height := 0.26
	var clearance := 0.055 if balcony else 0.09
	return Rect2((footprint.size.x - width) * 0.5, facade_height - clearance - height, width, height)


func roof_planes() -> Array[Dictionary]:
	var roof := Rect2(footprint).grow(0.042)
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
