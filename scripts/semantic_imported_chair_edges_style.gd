class_name SemanticImportedChairEdgesStyle
extends Resource

# The three-axis cube material. `poly` and `edge` are raster-markup labels,
# not material slots: both use these same normal-owned colours.
@export var y_axis_top_color := Color8(76, 229, 234)
@export var x_axis_side_color := Color8(51, 166, 222)
@export var z_axis_side_color := Color8(8, 111, 181)
@export var y_axis_edge_highlight_color := Color8(255, 255, 255)
@export var x_axis_edge_highlight_color := Color8(90, 222, 255)
@export var z_axis_edge_highlight_color := Color8(27, 156, 226)
@export var floor_shadow_color := Color8(47, 55, 78, 180)
@export var imported_normals_are_inverted := true
@export_range(0.005, 0.16, 0.005) var slab_box_thickness := 0.055
@export_range(0.005, 0.12, 0.005) var post_box_half_width := 0.028
@export_range(1, 12, 1) var maximum_edge_pixels := 10
@export_range(0.1, 20.0, 0.05) var maximum_edge_distance := 0.62
@export_range(0.15, 30.0, 0.05) var one_pixel_distance := 3.00
@export_range(0.1, 20.0, 0.05) var edge_highlight_full_distance := 0.60
@export_range(0.15, 30.0, 0.05) var edge_highlight_hidden_distance := 2.00
@export var close_highlight_color := Color8(245, 188, 96)
@export var close_crevice_shadow_color := Color8(74, 37, 17)
@export_range(0.1, 12.0, 0.05) var accent_full_distance := 0.70
@export_range(0.15, 16.0, 0.05) var accent_hidden_distance := 1.20
