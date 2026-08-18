extends Node2D

# Small self-contained HUD element for the first playable combat milestone.
# It deliberately draws in source pixels so the split-screen layout can place
# one bar beside each player view without relying on a separate UI scene.

var current_health := 10
var maximum_health := 10
var player_index := 0

func set_health(value: int, maximum: int) -> void:
	current_health = clampi(value, 0, maximum)
	maximum_health = maxi(maximum, 1)
	queue_redraw()

func _draw() -> void:
	var label_color := Color(1.0, 0.22, 0.22, 1.0)
	var fill_color := _health_color()
	# Simple red medical cross, as requested, followed by ten vertical hatch marks.
	draw_rect(Rect2(1.0, 5.0, 11.0, 3.0), label_color)
	draw_rect(Rect2(5.0, 1.0, 3.0, 11.0), label_color)
	for hatch_index in range(maximum_health):
		var x := 16.0 + float(hatch_index) * 7.0
		var hatch_rect := Rect2(x, 1.0, 4.0, 11.0)
		draw_rect(hatch_rect, Color(0.08, 0.08, 0.08, 0.95))
		if hatch_index < current_health:
			draw_rect(hatch_rect.grow(-1.0), fill_color)
	# Tiny owner tag prevents the two bars being ambiguous while retaining the
	# simple arcade treatment.
	draw_string(ThemeDB.fallback_font, Vector2(91.0, 10.0), "P%d" % (player_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color.WHITE)

func _health_color() -> Color:
	var ratio := float(current_health) / float(maximum_health)
	if ratio > 0.60:
		return Color(0.15, 0.9, 0.28, 1.0)
	if ratio > 0.30:
		return Color(1.0, 0.82, 0.14, 1.0)
	return Color(1.0, 0.22, 0.18, 1.0)
