extends Node2D

const HEART_TEXTURE := preload("res://assets/Items/Heart/heart_icon.png")

# Small self-contained HUD element for the first playable combat milestone.
# It deliberately draws in source pixels so the split-screen layout can place
# one bar beside each player view without relying on a separate UI scene.

var current_health := 10
var maximum_health := 10
var player_index := 0
# Zero keeps the original single-row layout.
var columns := 0
var heart_spacing := 5.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_health(value: int, maximum: int) -> void:
	current_health = clampi(value, 0, maximum)
	maximum_health = maxi(maximum, 1)
	queue_redraw()

func _draw() -> void:
	# Draw only earned/current hearts; the maximum remains a ten-heart gameplay cap
	# without reserving empty silhouettes in the HUD.
	for heart_index in range(current_health):
		var column := heart_index if columns <= 0 else heart_index % columns
		var row := 0 if columns <= 0 else int(heart_index / columns)
		var rect := Rect2(Vector2(float(column) * heart_spacing, float(row) * 10.0), Vector2(10.0, 10.0)) # Draw the new icon at its authored 10x10 canvas size so its pixels map directly to the logical game grid.
		draw_texture_rect(HEART_TEXTURE, rect, false, Color.WHITE)
