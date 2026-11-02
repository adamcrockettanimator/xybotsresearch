class_name SemanticImportedChairStyle
extends Resource

## Persistent artist-facing values for the imported-chair semantic prototype.
## The GLB supplies topology/material families; this resource supplies the
## logical-pixel presentation rules.

@export_category("Paint - material and local axis")
@export var wood_top_color := Color8(178, 112, 55)
@export var wood_bottom_shadow_color := Color8(66, 34, 18)
@export var wood_positive_x_color := Color8(145, 82, 38)
@export var wood_negative_x_color := Color8(117, 61, 29)
@export var wood_positive_z_color := Color8(133, 72, 32)
@export var wood_negative_z_color := Color8(101, 51, 24)
@export var imported_normals_are_inverted := true
@export var pillow_color := Color8(126, 39, 75)
@export var convex_highlight_color := Color8(242, 184, 91)
@export var concave_shadow_color := Color8(67, 35, 19)
@export_range(0.0, 2.0, 0.05) var side_bottom_light := 0.62
@export_range(0.0, 2.0, 0.05) var side_top_light := 1.12

@export_category("Sharp edge raster")
@export var sharp_edges_enabled := true
@export_range(1.0, 4.0, 1.0) var edge_width_logical_pixels := 1.0
@export_range(1.0, 89.0, 1.0) var sharp_angle_degrees := 35.0
@export var invert_convex_classification := false

@export_category("Per-detail distance LOD")
@export_range(0.10, 12.0, 0.05) var edge_full_distance := 1.7
@export_range(0.15, 16.0, 0.05) var edge_hidden_distance := 4.2
@export_range(0.10, 12.0, 0.05) var model_full_distance := 2.5
@export_range(0.15, 16.0, 0.05) var model_hidden_distance := 6.5
