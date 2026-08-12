extends Node2D

var quads: Array = []
var depths: Array[float] = []

func _draw() -> void:
	for index in range(quads.size()):
		var quad = quads[index]
		if quad is PackedVector2Array and quad.size() == 4:
			var depth := depths[index] if index < depths.size() else 4.0
			# A translucent fill makes the actual quad coverage obvious, while the
			# value ramp preserves which wall is near/far without pretending these
			# are final art.  The line is deliberately a little dimmer than before.
			var light := clampf(1.0 - (depth - 0.3) / 5.3, 0.20, 1.0)
			var fill := Color(0.03, 0.90 * light, 0.18 * light, 0.22)
			var edge := Color(0.05, 0.95 * light, 0.25 * light, 0.78)
			draw_colored_polygon(quad, fill)
			draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]), edge, 1.0, true)
			for point in quad:
				draw_circle(point, 1.0, Color(1.0, 0.2, 0.1, 1.0))
