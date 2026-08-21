extends Node2D

const HEART_TEXTURE := preload("res://assets/Items/Heart/heart.png")

# Small self-contained HUD element for the first playable combat milestone.
# It deliberately draws in source pixels so the split-screen layout can place
# one bar beside each player view without relying on a separate UI scene.

var current_health := 10
var maximum_health := 10
var player_index := 0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_health(value: int, maximum: int) -> void:
	current_health = clampi(value, 0, maximum)
	maximum_health = maxi(maximum, 1)
	queue_redraw()

func _draw() -> void:
	# One authored pixel heart per hit point. Empty hearts remain visible as a
	# dark silhouette, preserving the compact ten-unit meter.
	for heart_index in range(maximum_health):
		var rect := Rect2(Vector2(float(heart_index) * 5.0, 0.0), Vector2(5.0, 5.0))
		var tint := Color.WHITE if heart_index < current_health else Color(0.13, 0.13, 0.13, 0.95)
		draw_texture_rect(HEART_TEXTURE, rect, false, tint)
