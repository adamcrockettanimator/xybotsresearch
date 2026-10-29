## Persisted art direction for the GPU-cage barrel comparison.
##
## Geometry and world placement remain on the controller. This resource stores
## only the artist-facing colours, logical-pixel widths, and LOD distances.
class_name GpuCageBarrelStyle
extends Resource

@export_category("Paint")
@export var wood_edge := Color8(54, 30, 12)
@export var wood_centre := Color8(142, 86, 42)
@export var interior_colour := Color8(42, 20, 8)
@export var interior_shadow_colour := Color8(12, 5, 2)
@export var interior_highlight_colour := Color8(112, 62, 27)
@export_range(0.75, 1.0, 0.01) var interior_radius_fraction := 1.0
@export var lid_colour := Color8(157, 95, 47)
@export_range(0.10, 1.0, 0.01) var lid_radius_fraction := 0.78
@export_range(0.0, 1.0, 0.01) var lid_height_fraction := 0.94
@export var lid_stave_colour := Color8(91, 50, 22)
@export var lid_stave_highlight_colour := Color8(216, 153, 83)
@export_range(0, 4, 1) var lid_stave_width_logical_pixels := 1
@export var rim_colour := Color8(196, 135, 72)
@export var rim_highlight_colour := Color8(241, 193, 119)
@export var metal_dark := Color8(57, 59, 54)
@export var metal_light := Color8(181, 188, 176)
@export var hoop_shadow_colour := Color8(35, 38, 34)
@export var hoop_highlight_colour := Color8(220, 226, 215)
@export var stave_shadow_colour := Color8(56, 28, 10)
@export var stave_highlight_colour := Color8(216, 153, 83)
@export var floor_shadow_colour := Color(0.10, 0.06, 0.025, 0.34)

@export_category("Shape")
@export_range(0.0, 0.40, 0.01) var barrel_swell := 0.20
@export_range(0.05, 0.95, 0.01) var lower_hoop_height_from_floor := 0.30
@export_range(0.05, 0.95, 0.01) var upper_hoop_height_from_floor := 0.70
@export_range(1, 8, 1) var hoop_width_logical_pixels := 2
@export_range(1, 4, 1) var rim_highlight_width_logical_pixels := 1
@export_range(1, 16, 1) var interior_rim_width_logical_pixels := 4
@export_range(0, 4, 1) var stave_shadow_width_logical_pixels := 1
@export_range(0, 4, 1) var stave_highlight_width_logical_pixels := 1
@export_range(0.0, 0.90, 0.01) var stave_silhouette_cutoff := 0.32
@export_storage var floor_shadow_radius := 1.30
@export_range(0.0, 1.0, 0.05) var floor_shadow_opacity := 0.55
@export_range(0.0, 2.0, 0.05) var stave_bottom_light := 0.65
@export_range(0.0, 2.0, 0.05) var stave_top_light := 1.10

@export_category("Interior opening LOD")
## Interior begins fading when the projected opening becomes thinner than this.
@export_range(0.0, 16.0, 0.25) var interior_full_opening_logical_pixels := 4.0
## Interior is gone at or below this apparent opening thickness.
@export_range(0.0, 16.0, 0.25) var interior_hidden_opening_logical_pixels := 1.0

@export_category("Per-detail distance LOD")
@export_range(0.10, 12.0, 0.05) var stave_detail_full_distance := 2.50
@export_range(0.15, 16.0, 0.05) var stave_detail_hidden_distance := 4.50
@export_range(0.10, 12.0, 0.05) var hoop_accent_full_distance := 2.50
@export_range(0.15, 16.0, 0.05) var hoop_accent_hidden_distance := 4.50
@export_range(0.10, 12.0, 0.05) var hoop_highlight_full_distance := 2.50
@export_range(0.15, 16.0, 0.05) var hoop_highlight_hidden_distance := 3.20
@export_range(0.10, 12.0, 0.05) var hoop_shadow_full_distance := 3.90
@export_range(0.15, 16.0, 0.05) var hoop_shadow_hidden_distance := 4.50
@export_range(0.10, 12.0, 0.05) var rim_highlight_full_distance := 2.00
@export_range(0.15, 16.0, 0.05) var rim_highlight_hidden_distance := 3.50
@export_range(0.10, 12.0, 0.05) var rim_width_full_distance := 2.00
@export_range(0.15, 20.0, 0.05) var rim_one_pixel_distance := 4.50
@export_range(0.10, 12.0, 0.05) var floor_shadow_full_distance := 2.50
@export_range(0.15, 16.0, 0.05) var floor_shadow_hidden_distance := 4.50
