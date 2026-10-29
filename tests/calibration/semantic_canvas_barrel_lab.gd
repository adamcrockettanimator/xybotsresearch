extends Node2D


const CANVAS_BARREL_SCRIPT := preload("res://scripts/semantic_projected_canvas_barrel.gd")
const LOGICAL_ORIGIN := Vector2(18.0, 38.0)
const LOGICAL_SCALE := 4.0
const PANEL_X := 676.0

var canvas_barrel: Node2D
var distance := 1.0
var yaw_degrees := 0.0
var body_style := "smooth"
var telemetry_label: Label
var distance_value: Label
var yaw_value: Label
var update_cpu_us := 0
var sample_frames := 0
var gpu_ms_sum := 0.0
var viewport_timing_enabled := false


func _ready() -> void:
	_build_backdrop()
	canvas_barrel = CANVAS_BARREL_SCRIPT.new()
	canvas_barrel.name = "OneSemanticCanvasBarrel"
	canvas_barrel.position = LOGICAL_ORIGIN
	canvas_barrel.scale = Vector2.ONE * LOGICAL_SCALE
	add_child(canvas_barrel)
	_build_side_panel()


func _process(_delta: float) -> void:
	_draw_test_barrel()
	if canvas_barrel.pixel_viewport != null:
		if not viewport_timing_enabled:
			RenderingServer.viewport_set_measure_render_time(canvas_barrel.pixel_viewport.get_viewport_rid(), true)
			viewport_timing_enabled = true
		gpu_ms_sum += RenderingServer.viewport_get_measured_render_time_gpu(canvas_barrel.pixel_viewport.get_viewport_rid())
	sample_frames += 1
	if sample_frames % 10 == 0:
		_refresh_telemetry()


func _draw_test_barrel() -> void:
	var width := lerpf(31.0, 11.0, clampf((distance - 0.35) / 3.65, 0.0, 1.0))
	var body_height := width * 1.55
	var center := Vector2(80.0, 72.0)
	var top_center := center - Vector2(0.0, body_height * 0.43)
	var bottom_y := center.y + body_height * 0.57
	var lid_squash := lerpf(0.40, 0.18, clampf(distance / 3.5, 0.0, 1.0))
	var yaw_shift := sin(deg_to_rad(yaw_degrees)) * width * 0.16
	var lid_ring := _ellipse(top_center + Vector2(yaw_shift, 0.0), width, width * lid_squash, 12)
	var lid_inset := _ellipse(top_center + Vector2(yaw_shift, 0.0), width * 0.73, width * lid_squash * 0.60, 12)
	var silhouette := PackedVector2Array([
		top_center + Vector2(-width, 0.0), top_center + Vector2(width, 0.0),
		Vector2(center.x + width * 1.08, bottom_y), Vector2(center.x - width * 1.08, bottom_y),
	])
	var panels: Array[Dictionary] = []
	for index in 6:
		var left_t := float(index) / 6.0
		var right_t := float(index + 1) / 6.0
		var left_x := lerpf(-width, width, left_t)
		var right_x := lerpf(-width, width, right_t)
		var top_left := top_center + Vector2(left_x + yaw_shift * left_t, 0.0)
		var top_right := top_center + Vector2(right_x + yaw_shift * right_t, 0.0)
		var bottom_left := Vector2(center.x + left_x * 1.08, bottom_y)
		var bottom_right := Vector2(center.x + right_x * 1.08, bottom_y)
		panels.append({"points": PackedVector2Array([bottom_left, bottom_right, top_right, top_left]), "light": 0.72 + sin((left_t + right_t) * PI) * 0.28, "lower_height": 0.0, "upper_height": 1.0})
	var lower_hoop := _arc(Vector2(center.x, lerpf(top_center.y, bottom_y, 0.70)), width * 1.08, width * 0.13, 12)
	var upper_hoop := _arc(Vector2(center.x, lerpf(top_center.y, bottom_y, 0.36)), width * 1.03, width * 0.12, 12)
	var shadow := PackedVector2Array([Vector2(center.x - width * 1.15, bottom_y), Vector2(center.x + width * 1.15, bottom_y), Vector2(center.x + width * 0.82, bottom_y + 2.0), Vector2(center.x - width * 0.82, bottom_y + 2.0)])
	var staves := PackedVector2Array()
	for fraction in [0.18, 0.34, 0.66, 0.82]:
		var x := lerpf(-width, width, fraction)
		staves.append(top_center + Vector2(x, 0.0))
		staves.append(Vector2(center.x + x * 1.08, bottom_y))
	var lid_seams := PackedVector2Array()
	for fraction in [-0.33, 0.33]:
		lid_seams.append(top_center + Vector2(width * fraction, -width * lid_squash * 0.72))
		lid_seams.append(top_center + Vector2(width * fraction, width * lid_squash * 0.72))
	var started_us := Time.get_ticks_usec()
	canvas_barrel.set_projected_barrel("lab_barrel", silhouette, panels, lid_ring, lid_inset, lower_hoop, upper_hoop, shadow, staves, lid_seams, distance, 0, body_style)
	update_cpu_us = Time.get_ticks_usec() - started_us


func _ellipse(center: Vector2, radius_x: float, radius_y: float, count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in count:
		var angle := TAU * float(index) / float(count)
		result.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return result


func _arc(center: Vector2, radius_x: float, radius_y: float, count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in count:
		var angle := lerpf(PI, TAU, float(index) / float(count - 1))
		result.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return result


func _build_backdrop() -> void:
	var background := ColorRect.new()
	background.color = Color("1a1713")
	background.position = Vector2.ZERO
	background.size = Vector2(1024.0, 560.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -10
	add_child(background)
	var title := Label.new()
	title.text = "SEMANTIC CANVAS BARREL — RASTER LAB"
	title.position = Vector2(18.0, 10.0)
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)


func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(PANEL_X, 14.0)
	panel.size = Vector2(330.0, 530.0)
	add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.custom_minimum_size.x = 306.0
	scroll.add_child(column)
	var heading := Label.new()
	heading.text = "BARREL PARAMETERS"
	heading.add_theme_font_size_override("font_size", 16)
	column.add_child(heading)
	distance_value = _add_slider(column, "Camera distance", 0.35, 4.0, distance, _set_distance)
	yaw_value = _add_slider(column, "View yaw", -90.0, 90.0, yaw_degrees, _set_yaw)
	var style := OptionButton.new()
	style.add_item("Smooth wood", 0)
	style.add_item("Three-colour steps", 1)
	style.item_selected.connect(func(index: int) -> void: body_style = "smooth" if index == 0 else "three_colour_steps")
	column.add_child(style)
	var all_layers := Button.new()
	all_layers.text = "Enable all layers"
	all_layers.pressed.connect(func() -> void: canvas_barrel.reveal_all_layers())
	column.add_child(all_layers)
	var layers_heading := Label.new()
	layers_heading.text = "Visible raster layers"
	column.add_child(layers_heading)
	for entry in canvas_barrel.get_layer_debug_entries():
		var checkbox := CheckBox.new()
		checkbox.text = String(entry["label"])
		checkbox.button_pressed = bool(entry["visible"])
		checkbox.toggled.connect(_set_lab_layer_visible.bind(String(entry["id"])))
		column.add_child(checkbox)
	telemetry_label = Label.new()
	telemetry_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	telemetry_label.add_theme_font_size_override("font_size", 12)
	column.add_child(telemetry_label)


func _add_slider(column: VBoxContainer, title: String, minimum: float, maximum: float, initial: float, handler: Callable) -> Label:
	var label := Label.new()
	column.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.05
	slider.value = initial
	slider.value_changed.connect(handler)
	column.add_child(slider)
	label.set_meta("title", title)
	label.text = "%s: %.2f" % [title, initial]
	return label


func _set_distance(value: float) -> void:
	distance = value
	distance_value.text = "%s: %.2f" % [String(distance_value.get_meta("title")), value]


func _set_yaw(value: float) -> void:
	yaw_degrees = value
	yaw_value.text = "%s: %.0f°" % [String(yaw_value.get_meta("title")), value]


func _set_lab_layer_visible(is_on: bool, layer_id: String) -> void:
	canvas_barrel.set_layer_visible(layer_id, is_on)


func _refresh_telemetry() -> void:
	var stats: Dictionary = canvas_barrel.get_telemetry()
	var viewport_size: Vector2i = stats["viewport_size"]
	var average_gpu_ms := gpu_ms_sum / float(maxi(sample_frames, 1))
	telemetry_label.text = "TELEMETRY\nShared target: %d×%d\nBarrels: %d | active layers: %d\nGeometry feed: %d µs\nRenderer geometry update: %d µs\nGeometry points: %d\nCanvas viewport GPU: %.3f ms\nFrame FPS: %.1f\nMain draw calls: %d\nMain primitives: %d\nTexture memory: %.1f MB" % [viewport_size.x, viewport_size.y, int(stats["barrel_count"]), int(stats["active_layers"]), update_cpu_us, int(stats["geometry_update_us"]), int(stats["geometry_points"]), average_gpu_ms, Performance.get_monitor(Performance.TIME_FPS), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0]
	gpu_ms_sum = 0.0
	sample_frames = 0
