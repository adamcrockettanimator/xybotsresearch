extends Node2D

var expected_points: Array[Vector2] = []
var projected_points: Array[Vector2] = []

func _draw() -> void:
	# Red = authored marker pixels extracted from the selected coordinate frame.
	# Cyan = the runtime yaw-only projector's equivalent grid intersections.
	for point in expected_points:
		draw_rect(Rect2(point - Vector2(1, 1), Vector2(3, 3)), Color(1.0, 0.05, 0.05, 0.95), false, 1.0)
	for point in projected_points:
		draw_circle(point, 1.25, Color(0.0, 0.95, 1.0, 0.95))
