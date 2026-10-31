class_name SemanticStoolStyle
extends Resource

@export var top_color := Color8(76, 229, 234)
@export var x_side_color := Color8(51, 166, 222)
@export var z_side_color := Color8(8, 111, 181)
@export var shadow_color := Color8(47, 55, 78, 128)
@export_range(0.04, 0.50, 0.01) var footprint_x := 0.128
@export_range(0.04, 0.50, 0.01) var footprint_y := 0.141
@export_range(0.04, 0.50, 0.01) var leg_height := 0.205
@export_range(1, 16, 1) var maximum_leg_pixels := 5
@export_range(1, 16, 1) var maximum_seat_height_pixels := 5
@export_range(0.10, 12.0, 0.05) var maximum_pixels_distance := 0.60
@export_range(0.15, 30.0, 0.05) var one_pixel_distance := 3.00
@export var show_debug_geometry := true
@export var show_logical_pixel_grid := false
