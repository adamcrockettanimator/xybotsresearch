extends Node2D

## Shows a Blender-exported transparent primitive plate over the matching
## procedural calibration renderer.  This is intentionally a full 160x120
## plate: it validates projection before a later crop/atlas authoring pass.

const CALIBRATION_SCRIPT := preload("res://tests/calibration/greybox_projection_calibration.gd")
const PLATE_ROOT := "res://assets/Calibration/primitive_plates"
const DISPLAY_SCALE := 6.0

const PRIMITIVES := [
	"sphere", "cube", "tall_narrow_box", "short_wide_box", "cone",
	"pyramid", "upright_cylinder", "sideways_cylinder", "beveled_cube", "stepped_block",
]
const VIEWS := ["north", "north_east", "east"]
const VIEW_YAWS := [0.0, PI * 0.25, PI * 0.5]

var primitive_index := 0
var view_index := 0
var show_blender_plate := true
var calibration: Node2D
var plate: Sprite2D


func _ready() -> void:
	calibration = CALIBRATION_SCRIPT.new() as Node2D
	calibration.is_capture_renderer = true
	calibration.z_index = -1
	add_child(calibration)
	calibration.scale = Vector2.ONE * DISPLAY_SCALE
	plate = Sprite2D.new()
	plate.name = "BlenderPrimitivePlate"
	plate.centered = false
	plate.z_index = 0
	plate.modulate = Color(0.35, 0.95, 1.0, 0.60)
	calibration.add_child(plate)
	_refresh_plate()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_Q:
			primitive_index = posmod(primitive_index - 1, PRIMITIVES.size())
			_refresh_plate()
		KEY_E:
			primitive_index = posmod(primitive_index + 1, PRIMITIVES.size())
			_refresh_plate()
		KEY_1:
			view_index = 0
			_refresh_plate()
		KEY_2:
			view_index = 1
			_refresh_plate()
		KEY_3:
			view_index = 2
			_refresh_plate()
		KEY_SPACE:
			show_blender_plate = not show_blender_plate
			plate.visible = show_blender_plate
			queue_redraw()
		_:
			return


func _refresh_plate() -> void:
	var path := "%s/%s/%s.png" % [PLATE_ROOT, VIEWS[view_index], PRIMITIVES[primitive_index]]
	plate.texture = load(path) as Texture2D
	plate.visible = show_blender_plate
	calibration.set("yaw_radians", VIEW_YAWS[view_index])
	calibration.queue_redraw()
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2(12.0, 8.0), Vector2(550.0, 42.0)), Color(0.04, 0.05, 0.06, 0.90), true)
	draw_string(font, Vector2(20.0, 25.0), "BLENDER SPRITE PLATE CHECK", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color("e5e9ef"))
	var state := "%s / %s    Q/E primitive   1/2/3 view   Space overlay" % [PRIMITIVES[primitive_index], VIEWS[view_index]]
	draw_string(font, Vector2(20.0, 43.0), state, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("aeb8c5"))
