extends Resource
class_name TownLevelRecipe

@export var kit: TownCoffeeKit
@export var shops: Array[TownLotRecipe] = []
@export var hall: TownLotRecipe
@export var shops_beside_hall: Array[TownLotRecipe] = []
@export var include_prototypes := true
@export var populate_pickups := true
@export var square_bounds := false
@export_range(1, 4) var alley_cells := 1
@export_range(1, 6) var street_cells := 2


func generate() -> GeneratedTown:
	var town := GeneratedTown.new()
	town.populate_pickups = populate_pickups
	var prototype_size: Vector2i = kit.reference.FOOTPRINT.size
	var row_width := prototype_size.x * 2 + alley_cells if include_prototypes else 0
	var row_depth := prototype_size.y if include_prototypes else 0
	var porch_row_depth := 1 if include_prototypes else 0
	for shop in shops:
		row_width += (alley_cells if row_width > 0 else 0) + shop.size.x
		row_depth = maxi(row_depth, shop.size.y)
		porch_row_depth = maxi(porch_row_depth, shop.porch_cells)

	var north_width := hall.size.x if hall != null else 0
	var north_depth := hall.size.y if hall != null else 0
	var north_porch_depth := hall.porch_cells if hall != null else 0
	for shop in shops_beside_hall:
		north_width += (alley_cells if north_width > 0 else 0) + shop.size.x
		north_depth = maxi(north_depth, shop.size.y)
		north_porch_depth = maxi(north_porch_depth, shop.porch_cells)
	var width := maxi(row_width, north_width) + alley_cells * 2
	var north_frontage := alley_cells + north_depth
	var street_start := north_frontage + north_porch_depth if north_width > 0 else 0
	var street_end := street_start + street_cells
	var frontage := street_end + porch_row_depth
	town.size = Vector2i(width, frontage + row_depth + alley_cells)
	if square_bounds:
		var side := maxi(town.size.x, town.size.y)
		var top_padding := (side - town.size.y) / 2
		north_frontage += top_padding
		street_start += top_padding
		street_end += top_padding
		frontage += top_padding
		town.size = Vector2i(side, side)
	var row_x := (town.size.x - row_width) / 2
	town.street_center_y = (street_start + street_end) * 0.5
	var spawn_x := row_x + prototype_size.x + alley_cells + 1 if include_prototypes else row_x + row_width / 2
	town.spawn = Vector2i(spawn_x, street_end - 1)
	town.spawn_facing = 2
	if include_prototypes:
		town.prototype = kit.place_storefront(Vector2i(row_x, frontage))
		row_x += prototype_size.x + alley_cells
		town.prototype_copy = kit.place_storefront(Vector2i(row_x, frontage))
		town.prototype_copy.instance_prefix = "coffee_copy_"
		town.prototype_copy.porch_depth = 1.0
		row_x += prototype_size.x + alley_cells
	for shop in shops:
		_add_lot(town, shop, Vector2i(row_x, frontage))
		row_x += shop.size.x + alley_cells
	var north_x := (town.size.x - north_width) / 2
	if hall != null:
		_add_lot(town, hall, Vector2i(north_x, north_frontage - hall.size.y))
		north_x += hall.size.x + alley_cells
	for shop in shops_beside_hall:
		_add_lot(town, shop, Vector2i(north_x, north_frontage - shop.size.y))
		north_x += shop.size.x + alley_cells
	return town


func _add_lot(town: GeneratedTown, lot: TownLotRecipe, origin: Vector2i) -> void:
	var building := lot.compile(kit, origin)
	town.buildings.append(building)
	town.dining.append_array(lot.dining_centers(origin))
	if lot.prototype_yard:
		_append_prototype_yard(town, building)
	else:
		_append_cover(town.cover, building)


func _append_prototype_yard(town: GeneratedTown, building: TownBuildingStyle) -> void:
	var lot := Rect2(building.footprint)
	var window_side := -1.0 if building.door_x() > lot.get_center().x else 1.0
	var windows := building.ground_windows()
	var window_x := lot.get_center().x + window_side * lot.size.x * 0.20
	if not windows.is_empty():
		window_x = windows[0].get_center().x
	town.benches.append(Vector2(window_x, building.frontage() + building.direction() * 0.12))
	town.dining.append(lot.get_center() + Vector2(window_side * 0.28, 0.0))
	var placements := [
		Vector2(-0.12, 0.65), Vector2(-0.12, 1.02),
		Vector2(lot.size.x + 0.12, 1.22), Vector2(lot.size.x + 0.12, 1.59),
	]
	for index in placements.size():
		var offset: Vector2 = placements[index]
		town.cover.append({"position": lot.position + offset, "barrel": index % 2 == 1})
	var rear := building.rear_wall_y() - building.direction() * 0.12
	town.cover.append({"position": Vector2(lot.get_center().x + window_side * 0.46, rear), "barrel": true})
	town.cover.append({"position": Vector2(lot.get_center().x + window_side * 0.16, rear), "barrel": false})


func _append_cover(cover: Array[Dictionary], building: TownBuildingStyle) -> void:
	var lot := building.footprint
	var front_offset := building.direction() * (building.porch_depth + 0.22)
	var rear_offset := -building.direction() * 0.36
	var candidates: Array[Vector2] = [
		Vector2(lot.position.x + 0.12, building.frontage() + front_offset),
		Vector2(lot.end.x - 0.12, building.frontage() + front_offset),
		Vector2(lot.position.x - 0.17, building.rear_wall_y() + rear_offset),
		Vector2(lot.end.x + 0.17, building.rear_wall_y() + rear_offset),
	]
	for index in candidates.size():
		var point := candidates[index]
		var near_door := false
		for door in building.exterior_door_cells():
			var edge := building.door_edge(door)
			var tangent := edge[1] - edge[0]
			var midpoint := edge[0] + tangent * building.door_offset()
			var offset := point - midpoint
			if absf(offset.dot(tangent)) < building.door_half_width() + 0.14 and absf(offset.cross(tangent)) < 1.55:
				near_door = true
				break
		if not near_door:
			cover.append({"position": point, "barrel": (index + lot.position.x) % 2 == 0})
