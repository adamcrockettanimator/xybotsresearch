## Saved art direction for the illustrative vector barrel.
##
## This is deliberately only paint and line-weight information.  The barrel's
## position, radius and height remain world/gameplay properties on the gallery
## controller, so one palette can be reused by many barrels later.
class_name VectorBarrelStyle
extends Resource


@export_category("Outside wood")
@export var wood_edge := Color8(41, 18, 5)
@export var wood_centre := Color8(173, 79, 19)
@export_range(0.25, 1.75, 0.05) var wood_bottom_light := 0.76
@export_range(0.25, 1.75, 0.05) var wood_top_light := 1.14

@export_category("Interior and lid")
@export var barrel_interior_colour := Color8(46, 19, 5)
@export var lid_colour := Color8(156, 69, 15)

@export_category("Gradient treatment")
@export_enum("Linear", "Radial") var body_gradient_mode := 0
@export_enum("Linear", "Radial") var lid_gradient_mode := 0
@export_range(0, 8, 1) var gradient_steps := 0
@export_range(0.0, 1.0, 0.05) var gradient_dither := 0.0

@export_category("Rim and hoops")
@export var rim_colour := Color8(212, 142, 67)
@export_range(0.5, 8.0, 0.5) var rim_width := 2.0
@export var hoop_edge := Color8(35, 37, 34)
@export var hoop_centre := Color8(201, 207, 194)
@export var hoop_shadow_colour := Color(0.03, 0.025, 0.02, 0.56)
@export var hoop_highlight_colour := Color(1.0, 1.0, 1.0, 0.48)
@export_range(0.5, 8.0, 0.5) var hoop_width := 3.0

@export_category("Details")
@export var side_stave_colour := Color(0.13, 0.055, 0.012, 0.64)
@export var side_stave_highlight_colour := Color(1.0, 0.72, 0.36, 0.30)
@export var lid_stave_colour := Color(0.08, 0.035, 0.01, 0.72)
@export var lid_stave_highlight_colour := Color(1.0, 0.74, 0.36, 0.38)
@export_range(0.5, 6.0, 0.5) var stave_width := 1.0
@export var floor_shadow_colour := Color(0.10, 0.06, 0.025, 0.34)

@export_category("Saved child-node edits")
## Per-barrel, per-piece paint and local-transform overrides captured from the
## Remote tree.  Projected points stay procedural so the asset remains locked
## to its world position while an artist's visual changes persist.
@export_storage var child_visual_overrides: Dictionary = {}

# Read old saved palettes once, then migrate them into the semantic names above.
@export_storage var lid_dark := Color8(46, 19, 5)
@export_storage var lid_light := Color8(156, 69, 15)
@export_storage var stave_colour := Color(0.13, 0.055, 0.012, 0.64)
@export_storage var style_version := 1
