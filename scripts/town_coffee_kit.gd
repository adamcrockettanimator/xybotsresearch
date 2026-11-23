extends Resource
class_name TownCoffeeKit

## The original Coffee Shop remains the source of the timber, roof and trim palette.
@export var reference: Resource
@export var baluster_spacing := 0.145
@export var window_centers := Vector2(0.255, 0.745)
@export var window_size := Vector2(0.40, 0.36)
@export var window_sill := 0.205
@export var window_trim := 0.026

@export_group("Blender Gable Shop")
## Shop_1x2.5_gableRoof / OUTLINE.001. Four Blender units per town cell,
## with the deck aligned to the common town floor.
@export var gable_heights := Vector3(0.825, 1.178, 1.225)
@export var gable_awning := Vector2(0.675, 0.825)
@export var gable_porch_depth := 0.5
@export var gable_door := Vector2(0.125, 0.425)
@export var gable_door_top := 0.60
@export var gable_door_sill := 0.075
@export var gable_frame_width := 0.025
@export var gable_panel_rows := Vector4(0.095, 0.476, 0.571, 0.905)
@export var gable_panel_inset := 0.167
## Knob centers in hinge-to-latch and head-to-sill coordinates.
@export var gable_front_knob := Vector2(0.893, 0.521)
@export var gable_rear_knob := Vector2(0.897, 0.529)
@export var gable_knob_radius := 0.0195
@export var gable_knob_color := Color("#9e8059")
@export var gable_window := Rect2(0.5, 0.225, 0.4, 0.4)
@export var gable_siding_profile := Vector3(0.0461, 0.09375, 0.00975)
@export var gable_roof_ribs := 22
@export var gable_outline := Color("#302317")
@export var gable_lining_drop := 0.055
## Roof rafters measured along the room's length, end to end.
@export var gable_rafter_positions := Vector3(0.265625, 0.5, 0.734375)
@export var gable_rafter_section := Vector2(0.025, 0.048)
@export var gable_ceiling_wood := Color("#221a11")
@export var gable_ceiling_timber := Color("#2e2316")


func door_width() -> float:
	return reference.FRONT_DOOR.y - reference.FRONT_DOOR.x


func place_storefront(origin: Vector2i) -> Resource:
	var storefront := reference.duplicate()
	storefront.FOOTPRINT = Rect2i(origin, reference.FOOTPRINT.size)
	return storefront


func build_shell() -> TownBuildingStyle:
	var building := TownBuildingStyle.new()
	building.coffee_kit = self
	building.timber = reference.wood_color
	building.metal = reference.roof_color
	building.sign_ink = reference.coffee_letter_ink
	building.eave = reference.ROOF_REAR
	building.rise = reference.ROOF_FRONT - reference.ROOF_REAR
	building.facade_height = reference.FACADE_TOP
	building.porch_awning_shadow = reference.awning_shadow
	return building
