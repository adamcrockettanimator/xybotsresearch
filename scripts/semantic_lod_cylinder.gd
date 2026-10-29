## Experimental world-anchored cylinder, rasterized in the 160x120 grid.
extends Node2D

var low_resolution_viewport: SubViewport
var canvas: CylinderCanvas

func _ready() -> void:
	low_resolution_viewport = SubViewport.new()
	low_resolution_viewport.size = Vector2i(160, 120)
	low_resolution_viewport.transparent_bg = true
	low_resolution_viewport.disable_3d = true
	low_resolution_viewport.gui_disable_input = true
	low_resolution_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(low_resolution_viewport)
	canvas = CylinderCanvas.new()
	low_resolution_viewport.add_child(canvas)
	var display := Sprite2D.new()
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.texture = low_resolution_viewport.get_texture()
	add_child(display)

func set_rings(bottom: PackedVector2Array, top: PackedVector2Array) -> void:
	if canvas == null:
		return
	canvas.set_rings(bottom, top)

class CylinderCanvas extends Node2D:
	const BODY_COLOR := Color8(118, 94, 71)
	const TOP_COLOR := Color8(135, 108, 81)
	const OUTLINE_COLOR := Color8(78, 60, 44)
	var bottom_ring := PackedVector2Array()
	var top_ring := PackedVector2Array()

	func set_rings(bottom: PackedVector2Array, top: PackedVector2Array) -> void:
		bottom_ring = bottom
		top_ring = top
		queue_redraw()

	func _draw() -> void:
		if bottom_ring.size() < 3 or bottom_ring.size() != top_ring.size():
			return
		var all_points := PackedVector2Array()
		var top_points := PackedVector2Array()
		for point in bottom_ring:
			all_points.append(point.round())
		for point in top_ring:
			var rounded := point.round()
			all_points.append(rounded)
			top_points.append(rounded)
		# The hull hides the rear bottom rim. Only the visible lid and exterior
		# boundary receive lines; no hidden construction geometry shows through.
		var hull := Geometry2D.convex_hull(all_points)
		if hull.size() < 3:
			return
		draw_colored_polygon(hull, BODY_COLOR)
		var top_hull := Geometry2D.convex_hull(top_points)
		if top_hull.size() >= 3:
			draw_colored_polygon(top_hull, TOP_COLOR)
			top_hull.append(top_hull[0])
			draw_polyline(top_hull, OUTLINE_COLOR, 1.0, false)
		hull.append(hull[0])
		draw_polyline(hull, OUTLINE_COLOR, 1.0, false)
