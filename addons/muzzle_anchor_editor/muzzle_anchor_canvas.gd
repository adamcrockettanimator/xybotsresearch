@tool
extends Control

signal anchor_placed(hand: StringName, pixel: Vector2i)

var texture: Texture2D
var anchors: Dictionary = {}
var selected_hand: StringName = &"right"
var zoom := 6.0
var _image_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(360.0, 360.0)


func set_frame(frame_texture: Texture2D, frame_anchors: Dictionary) -> void:
	texture = frame_texture
	anchors = frame_anchors.duplicate()
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	var image_size := texture.get_size()
	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return
	var fit_zoom := minf((size.x - 24.0) / image_size.x, (size.y - 24.0) / image_size.y)
	zoom = maxf(1.0, floorf(fit_zoom))
	var draw_size := image_size * zoom
	_image_rect = Rect2((size - draw_size) * 0.5, draw_size)
	draw_rect(_image_rect.grow(2.0), Color(0.08, 0.08, 0.08, 1.0), true)
	draw_texture_rect(texture, _image_rect, false)
	for hand_value in anchors:
		var pixel: Variant = anchors[hand_value]
		if pixel is Vector2i:
			_draw_anchor(StringName(hand_value), pixel)


func _draw_anchor(hand: StringName, pixel: Vector2i) -> void:
	var center := _image_rect.position + (Vector2(pixel) + Vector2(0.5, 0.5)) * zoom
	var color := Color(0.20, 0.85, 1.0, 1.0) if hand == &"right" else Color(1.0, 0.72, 0.12, 1.0)
	if hand == selected_hand:
		color = Color(1.0, 0.15, 0.95, 1.0)
	draw_line(center + Vector2(-7.0, 0.0), center + Vector2(7.0, 0.0), color, 2.0)
	draw_line(center + Vector2(0.0, -7.0), center + Vector2(0.0, 7.0), color, 2.0)
	draw_circle(center, 3.0, Color(color, 0.30))


func _gui_input(event: InputEvent) -> void:
	if texture == null or not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed or not _image_rect.has_point(mouse.position):
		return
	var pixel := Vector2i(floori((mouse.position.x - _image_rect.position.x) / zoom), floori((mouse.position.y - _image_rect.position.y) / zoom))
	var image_size := texture.get_size()
	if pixel.x >= 0 and pixel.y >= 0 and pixel.x < image_size.x and pixel.y < image_size.y:
		anchor_placed.emit(selected_hand, pixel)
