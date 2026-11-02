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
@export var near_edge_highlight_color := Color8(244, 186, 94)
@export_range(0.0, 1.0, 0.01) var near_edge_highlight_end_fade := 0.30
@export_range(0.02, 0.75, 0.01) var near_edge_highlight_angle_fade := 0.28
@export_range(0.10, 12.0, 0.05) var near_edge_highlight_full_distance := 1.50
@export_range(0.15, 16.0, 0.05) var near_edge_highlight_hidden_distance := 3.00
@export_range(1, 8, 1) var seat_slat_count := 1
@export var seat_slat_shadow_color := Color8(87, 65, 47)
@export var seat_slat_highlight_color := Color8(220, 180, 122)
@export_range(0.10, 12.0, 0.05) var seat_slat_shadow_full_distance := 2.50
@export_range(0.15, 16.0, 0.05) var seat_slat_shadow_hidden_distance := 4.50
@export_range(0.10, 12.0, 0.05) var seat_slat_highlight_full_distance := 1.25
@export_range(0.15, 16.0, 0.05) var seat_slat_highlight_hidden_distance := 2.50
@export_range(0.0, 1.0, 0.01) var floor_darkening_strength := 0.32
@export var underside_shadow_color := Color8(48, 35, 27, 180)
@export_range(0.0, 1.0, 0.01) var underside_shadow_fade := 0.72
@export_range(0.0, 1.0, 0.01) var under_table_leg_darkening_strength := 0.42
@export_range(0.0, 1.0, 0.01) var exterior_corner_brightening_strength := 0.22
@export_range(1.0, 120.0, 1.0) var exterior_corner_brightening_fade_pixels := 28.0
@export_range(0.05, 8.0, 0.05) var face_horizontal_span_hidden_pixels := 0.75
@export_range(0.10, 8.0, 0.05) var face_horizontal_span_full_pixels := 1.50
@export var show_debug_geometry := true
@export var show_logical_pixel_grid := false
