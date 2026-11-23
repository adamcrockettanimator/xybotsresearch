extends Resource
class_name TownLotRecipe

@export var size := Vector2i(1, 2)
@export var sign_text := "COFFEE"
@export var faces_south := false
@export var blueprint_gable := false
@export var prototype_yard := false
@export_range(0, 2) var porch_cells := 1
## Interior rectangles in lot-local cells. The space around them is circulation.
@export var rooms: Array[Rect2i] = []
## Each record is local cell X/Y, then cardinal direction X/Y.
@export var room_doors: Array[Vector4i] = []
@export var extra_exterior_doors: Array[Vector4i] = []
@export_range(0, 2) var side_windows_per_bay := 2
@export_range(0, 2) var rear_windows_per_bay := 2
## Empty means all rear bays without a door are eligible.
@export var rear_window_bays: PackedInt32Array = []
@export var furnished_room_indices: PackedInt32Array = []


func compile(kit: TownCoffeeKit, origin: Vector2i) -> TownBuildingStyle:
	var building := kit.build_shell()
	building.footprint = Rect2i(origin, size)
	building.sign_text = sign_text
	building.faces_south = faces_south
	building.porch_depth = float(porch_cells)
	if blueprint_gable:
		building.blueprint_gable = true
		building.eave = kit.gable_heights.x
		building.rise = kit.gable_heights.y - building.eave
		building.facade_height = kit.gable_heights.z
		if porch_cells > 0:
			building.porch_depth = kit.gable_porch_depth
	building.side_windows_per_bay = side_windows_per_bay
	building.rear_windows_per_bay = rear_windows_per_bay
	building.rear_window_bays = rear_window_bays
	building.partition_doors.assign(room_doors)
	var center := size.x / 2
	building.entrances.assign([
		Vector4i(center, 0, 0, -1),
		Vector4i(center, size.y - 1, 0, 1),
	])
	building.entrances.append_array(extra_exterior_doors)
	var edges := {}
	for room in rooms:
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				var cell := Vector2i(x, y)
				for delta: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
					var neighbor := cell + delta
					if room.has_point(neighbor) or not Rect2i(Vector2i.ZERO, size).has_point(neighbor):
						continue
					if room_doors.has(Vector4i(cell.x, cell.y, delta.x, delta.y)) or room_doors.has(Vector4i(neighbor.x, neighbor.y, -delta.x, -delta.y)):
						continue
					var edge := Vector4i(cell.x, cell.y, delta.x, delta.y)
					var opposite := Vector4i(neighbor.x, neighbor.y, -delta.x, -delta.y)
					if not edges.has(opposite):
						edges[edge] = true
	building.partitions.assign(edges.keys())
	return building


func dining_centers(origin: Vector2i) -> PackedVector2Array:
	var centers := PackedVector2Array()
	for index in furnished_room_indices:
		var room := Rect2(rooms[index])
		# Offset off cell boundaries and leave the doors' center lanes open.
		var toward_outside := -1.0 if room.get_center().x < size.x * 0.5 else 1.0
		centers.append(Vector2(origin) + room.get_center() + Vector2(toward_outside * 0.57, 0.18))
	return centers
