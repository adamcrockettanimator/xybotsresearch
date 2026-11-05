extends Control

signal boundary_changed(mode: String, is_start: bool, seconds: float)
signal seek_requested(mode: String, seconds: float)

const MODES := ["menu", "combat", "win", "lose"]
const COLORS := {"menu": Color("e8c456"), "combat": Color("ef7f6d"), "win": Color("91c8f4"), "lose": Color("c49bea")}
const LEFT := 76.0
const RIGHT := 12.0
const ROW_HEIGHT := 52.0
var peaks: Array = []
var loops: Dictionary = {}
var duration := 0.0
var playhead := -1.0
var active_mode := ""
var dragging := false
var drag_mode := ""
var drag_start := false

func _ready() -> void:
	custom_minimum_size = Vector2(700, ROW_HEIGHT * float(MODES.size()) + 23.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Click to listen from that point; drag colored markers to adjust the loop."

func _track_width() -> float:
	return maxf(size.x - LEFT - RIGHT, 1.0)

func _time_x(seconds: float) -> float:
	return LEFT + clampf(seconds / maxf(duration, 0.001), 0.0, 1.0) * _track_width()

func _x_time(x: float) -> float:
	return clampf((x - LEFT) / _track_width(), 0.0, 1.0) * duration

func _draw() -> void:
	var font := get_theme_default_font()
	for row in range(MODES.size()):
		var mode: String = MODES[row]
		var color: Color = COLORS[mode]
		var top := float(row) * ROW_HEIGHT + 2.0
		var center := top + 22.0
		var track_rect := Rect2(LEFT, top, _track_width(), 43.0)
		draw_rect(track_rect, Color("20252c"))
		draw_string(font, Vector2(3, center + 5.0), "Calm" if mode == "menu" else mode.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, 70, 14, color)
		if loops.has(mode) and duration > 0.0:
			var bounds: Vector2 = loops[mode]
			var start_x := _time_x(bounds.x)
			var end_x := _time_x(bounds.y)
			draw_rect(Rect2(start_x, top, maxf(end_x - start_x, 0.0), 43.0), Color(color.r, color.g, color.b, 0.17))
		if not peaks.is_empty():
			var columns := maxi(1, int(_track_width()))
			for column in range(columns):
				var first := int(float(column) * peaks.size() / columns)
				var last := mini(peaks.size(), maxi(first + 1, int(float(column + 1) * peaks.size() / columns)))
				var low := 0.0
				var high := 0.0
				for index in range(first, last):
					var pair: Array = peaks[index]
					low = minf(low, float(pair[0]))
					high = maxf(high, float(pair[1]))
				draw_line(Vector2(LEFT + column, center - high * 18.0), Vector2(LEFT + column, center - low * 18.0), Color(0.82, 0.85, 0.88, 0.75), 1.0)
		if loops.has(mode) and duration > 0.0:
			var bounds: Vector2 = loops[mode]
			for time in [bounds.x, bounds.y]:
				var x := _time_x(time)
				draw_line(Vector2(x, top), Vector2(x, top + 43.0), color, 2.0)
				draw_circle(Vector2(x, top + 4.0), 5.0, color)
		if mode == active_mode and playhead >= 0.0:
			var x := _time_x(playhead)
			draw_line(Vector2(x, top), Vector2(x, top + 43.0), Color.WHITE, 1.0)
	for tick in range(5):
		var time := duration * float(tick) / 4.0
		var x := _time_x(time)
		draw_string(font, Vector2(x - 8.0, ROW_HEIGHT * float(MODES.size()) + 16.0), "%d:%02d" % [int(time) / 60, int(time) % 60], HORIZONTAL_ALIGNMENT_LEFT, 48, 11, Color(0.8, 0.8, 0.8))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var row := int(event.position.y / ROW_HEIGHT)
			if row < 0 or row >= MODES.size():
				return
			var mode: String = MODES[row]
			if not loops.has(mode):
				return
			var bounds: Vector2 = loops[mode]
			var start_distance := absf(event.position.x - _time_x(bounds.x))
			var end_distance := absf(event.position.x - _time_x(bounds.y))
			if minf(start_distance, end_distance) > 14.0:
				if event.position.x >= LEFT and event.position.x <= size.x - RIGHT:
					seek_requested.emit(mode, _x_time(event.position.x))
					accept_event()
				return
			dragging = true
			drag_mode = mode
			drag_start = start_distance <= end_distance
			accept_event()
		else:
			dragging = false
	elif event is InputEventMouseMotion and dragging:
		boundary_changed.emit(drag_mode, drag_start, _x_time(event.position.x))
		accept_event()
