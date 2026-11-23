extends RefCounted
class_name GeneratedTown

var size: Vector2i
var spawn: Vector2i
var spawn_facing: int
var street_center_y: float
var populate_pickups := true
var prototype: Resource
var prototype_copy: Resource
var buildings: Array[TownBuildingStyle] = []
var cover: Array[Dictionary] = []
var benches: PackedVector2Array = []
var dining: PackedVector2Array = []
