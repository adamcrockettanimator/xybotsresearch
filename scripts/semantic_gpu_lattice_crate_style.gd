## Persisted art direction for the eight-corner GPU-cage crate.
##
## This deliberately contains only artist-facing appearance and LOD choices.
## The crate's world placement and its projected lattice remain runtime data.
class_name GpuCageCrateStyle
extends Resource

@export_category("Paint - form by axis")
@export var top_color := Color8(185, 128, 65)
@export var side_x_color := Color8(151, 94, 44)
@export var side_y_color := Color8(126, 72, 34)
@export_range(0.0, 2.0, 0.05) var side_bottom_light := 0.65
@export_range(0.0, 2.0, 0.05) var side_top_light := 1.10
@export var panel_top_color := Color8(163, 105, 50)
@export var panel_color := Color8(136, 77, 35)
@export var panel_dark_color := Color8(114, 61, 29)
@export var frame_color := Color8(207, 142, 68)
@export var inset_shadow_color := Color8(77, 42, 21)
@export var slat_color := Color8(91, 48, 23)
@export var edge_highlight_color := Color8(244, 186, 94)
@export var floor_shadow_color := Color(0.08, 0.05, 0.025, 0.45)

@export_category("Semantic pieces")
@export var lid_enabled := true
@export var panel_enabled := true
@export var slats_enabled := true
@export var diagonal_enabled := true
@export var floor_shadow_enabled := true
@export var edge_highlight_enabled := true
@export_range(0.06, 0.28, 0.01) var frame_inset := 0.14
@export_range(0.10, 12.0, 0.05) var panel_full_distance := 4.0
@export_range(0.15, 16.0, 0.05) var panel_hidden_distance := 6.0
@export_range(0.10, 12.0, 0.05) var inset_full_distance := 2.0
@export_range(0.15, 16.0, 0.05) var inset_hidden_distance := 3.5
@export_range(2, 8, 1) var slat_count := 4
@export_range(1.0, 6.0, 1.0) var diagonal_width_logical_pixels := 3.0
## Directional recess depth for the lid only; side insets use one-pixel bands.
@export_range(0.0, 0.20, 0.005) var inset_shadow_depth := 0.035
@export_range(0.0, 1.0, 0.05) var inset_shadow_strength := 0.55
@export_range(0.0, 1.0, 0.05) var floor_shadow_opacity := 0.45

@export_category("Detail distance LOD")
@export_range(0.10, 12.0, 0.05) var detail_full_distance := 2.0
@export_range(0.15, 16.0, 0.05) var detail_hidden_distance := 4.5
@export_range(0.10, 12.0, 0.05) var diagonal_full_distance := 2.5
@export_range(0.15, 16.0, 0.05) var diagonal_hidden_distance := 5.0
## Distance fade for the diagonal brace highlight, independent of the brace.
@export_range(0.10, 12.0, 0.05) var diagonal_highlight_full_distance := 1.5
@export_range(0.15, 16.0, 0.05) var diagonal_highlight_hidden_distance := 3.0
@export_range(0.5, 3.0, 0.25) var edge_highlight_width_logical_pixels := 1.0
@export_range(0.0, 1.0, 0.01) var edge_highlight_end_fade := 0.30
@export_range(0.02, 0.75, 0.01) var edge_highlight_angle_fade := 0.28
@export_range(0.10, 12.0, 0.05) var edge_highlight_full_distance := 1.5
@export_range(0.15, 16.0, 0.05) var edge_highlight_hidden_distance := 3.0
## Side-inset highlights only appear within this close camera range.
@export_range(0.10, 4.0, 0.05) var inset_side_highlight_full_distance := 0.60
@export_range(0.15, 6.0, 0.05) var inset_side_highlight_hidden_distance := 1.20
@export_range(0.0, 1.0, 0.01) var minimum_face_ratio := 0.10
@export_range(0.25, 12.0, 0.05) var panel_max_distance := 8.0
