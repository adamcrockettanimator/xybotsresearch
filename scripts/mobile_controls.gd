extends Control

# Touch IDs remain bound to their original purpose until released, allowing
# movement, aiming, and firing at the same time.
var game: Node
var fingers := {}
var finger_positions := {}
var stick := Vector2.ZERO
var stick_origin := Vector2.ZERO
var buttons := {}
var continue_pending := false
var fire_pending := false
var reload_pending := false
var crouch_toggled := false
const EDITABLE := ["crouch", "fire", "reload", "heart", "gun", "pause"]
var layout_path := "user://mobile_control_layout.cfg"
var saved_positions := {}
var editing := false
var edit_finger := -1
var edit_target := ""
var edit_offset := Vector2.ZERO
var save_failed := false

static func available() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("(navigator.maxTouchPoints > 0) && (matchMedia('(pointer: coarse)').matches || /iPhone|iPad|iPod|Android/i.test(navigator.userAgent))"))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_layout()

func _process(_delta: float) -> void:
	queue_redraw()

func _layout() -> Dictionary:
	var s := size
	var corner := s - Vector2(45.0, 45.0)
	var arc_radius := minf(s.x, s.y) * 0.28
	var points := {
		"stick": Vector2(s.x * 0.16, s.y * 0.76),
		"crouch": corner - Vector2(cos(deg_to_rad(15.0)), sin(deg_to_rad(15.0))) * arc_radius,
		"fire": corner - Vector2.ONE.normalized() * arc_radius,
		"reload": corner - Vector2(cos(deg_to_rad(75.0)), sin(deg_to_rad(75.0))) * arc_radius,
		"heart": Vector2(s.x * 0.38, s.y * 0.91),
		"gun": Vector2(s.x * 0.53, s.y * 0.91),
		"pause": Vector2(s.x * 0.07, s.y * 0.10),
		"continue": Vector2(s.x * 0.5, s.y * 0.8),
		"menu": Vector2(s.x * 0.5, s.y * 0.68),
		"layout": Vector2(s.x * 0.5, s.y * 0.85),
		"reset": Vector2(s.x * 0.36, s.y * 0.09),
		"done": Vector2(s.x * 0.64, s.y * 0.09),
	}
	for name in EDITABLE:
		if saved_positions.has(name):
			points[name] = saved_positions[name] * s
	# Keep pause actions outside the centered pause broadside and its buttons.
	if game != null and game.match_paused and not editing:
		points["pause"] = Vector2(s.x - 75.0, s.y * 0.25)
		points["menu"] = Vector2(s.x - 75.0, s.y * 0.50)
		points["layout"] = Vector2(s.x - 75.0, s.y * 0.75)
	return points

func _load_layout() -> void:
	var config := ConfigFile.new()
	if config.load(layout_path) != OK:
		return
	for name in EDITABLE:
		if not config.has_section_key("positions", name):
			continue
		var value = config.get_value("positions", name)
		if value is Vector2 and value.x >= 0.0 and value.x <= 1.0 and value.y >= 0.0 and value.y <= 1.0:
			saved_positions[name] = value

func _save_layout() -> bool:
	var config := ConfigFile.new()
	for name in saved_positions:
		config.set_value("positions", name, saved_positions[name])
	return config.save(layout_path) == OK

func _start_editing() -> void:
	editing = true
	save_failed = false
	fingers.clear()
	finger_positions.clear()
	buttons.clear()
	stick = Vector2.ZERO
	fire_pending = false
	reload_pending = false
	if game.options_overlay != null:
		game.options_overlay.visible = false

func _finish_editing() -> void:
	if not _save_layout():
		save_failed = true
		return
	editing = false
	edit_finger = -1
	edit_target = ""
	if game.options_overlay != null:
		game.options_overlay.visible = true

func _edit_input(event: InputEvent, points: Dictionary) -> void:
	var pos: Vector2 = event.position
	if event is InputEventScreenTouch:
		if not event.pressed:
			if event.index == edit_finger:
				edit_finger = -1
				edit_target = ""
			return
		if edit_finger != -1:
			return
		if pos.distance_to(points.done) < 55.0:
			_finish_editing()
			return
		if pos.distance_to(points.reset) < 55.0:
			saved_positions.clear()
			return
		var nearest := 999999.0
		for name in EDITABLE:
			var distance: float = pos.distance_to(points[name])
			if distance < (56.0 if name == "fire" else 48.0) and distance < nearest:
				nearest = distance
				edit_target = name
		if not edit_target.is_empty():
			edit_finger = event.index
			edit_offset = points[edit_target] - pos
	elif event is InputEventScreenDrag and event.index == edit_finger and not edit_target.is_empty():
		var radius := 56.0 if edit_target == "fire" else 48.0
		var target := pos + edit_offset
		target.x = clampf(target.x, radius, size.x - radius)
		target.y = clampf(target.y, 125.0, size.y - radius)
		saved_positions[edit_target] = target / size

# A clear-map victory remains playable until its fade and loot window ends.
func _round_prompt_active() -> bool:
	return game.clear_map_waiting_to_start or (game.combat_round_complete and not game.clear_map_finish_pending)


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var id: int = event.index
	var pos: Vector2 = event.position
	var points := _layout()
	if editing:
		_edit_input(event, points)
		queue_redraw()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var selected := ""
			if game.match_paused:
				if pos.distance_to(points.layout) < 60.0:
					_start_editing()
					queue_redraw()
					return
				elif pos.distance_to(points.menu) < 60.0:
					selected = "menu"
				elif pos.distance_to(points.pause) < 55.0:
					selected = "pause"
				else:
					return
			elif game.clear_map_waiting_to_start or (game.wanted_tally_overlay != null and game.wanted_tally_overlay.visible):
				return # Let the briefing and results buttons receive touches independently.
			elif _round_prompt_active():
				selected = "continue"
				continue_pending = true
			else:
				for name in ["pause", "crouch", "fire", "reload", "heart", "gun"]:
					if pos.distance_to(points[name]) < (56.0 if name == "fire" else 48.0):
						selected = name
						break
				if selected.is_empty():
					selected = "stick" if pos.x < size.x * 0.5 else "look"
				elif selected == "crouch":
					crouch_toggled = not crouch_toggled
				elif selected == "reload":
					reload_pending = true
				elif selected == "fire":
					fire_pending = true
			if selected == "stick" and not fingers.values().has("stick"):
				stick_origin = pos
				stick = Vector2.ZERO
			elif selected == "stick":
				return
			fingers[id] = selected
			finger_positions[id] = pos
			buttons[selected] = true
		else:
			var selected: String = fingers.get(id, "")
			fingers.erase(id)
			finger_positions.erase(id)
			if not fingers.values().has(selected):
				buttons.erase(selected)
			if selected == "stick":
				stick = Vector2.ZERO
	elif fingers.has(id):
		var selected: String = fingers[id]
		var previous: Vector2 = finger_positions.get(id, pos)
		finger_positions[id] = pos
		if selected == "stick":
			stick = (pos - stick_origin).limit_length(70.0) / 70.0
		elif (selected == "look" or selected == "fire") and not game.match_paused and not game.clear_map_waiting_to_start and not game.player_states.is_empty():
			game.player_states[0]["continuous_camera_yaw"] = wrapf(float(game.player_states[0].get("continuous_camera_yaw", 0.0)) + (pos.x - previous.x) * 0.006, -PI, PI)
	queue_redraw()

func pressed(name: String) -> bool:
	if name == "crouch":
		return crouch_toggled
	return bool(buttons.get(name, false))

func take_fire() -> bool:
	var result := fire_pending or pressed("fire")
	fire_pending = false
	return result

func take_reload() -> bool:
	var result := reload_pending or pressed("reload")
	reload_pending = false
	return result

func take_continue() -> bool:
	var result := continue_pending
	continue_pending = false
	return result

func _draw() -> void:
	var p := _layout()
	if editing:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		_draw_button(p.reset, "RESET", 48.0)
		_draw_button(p.done, "SAVE", 48.0)
		var instruction := "DRAG BUTTONS TO POSITION" if not save_failed else "COULD NOT SAVE - TRY AGAIN"
		var font := ThemeDB.fallback_font
		var text_width := font.get_string_size(instruction, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, Vector2((size.x - text_width) * 0.5, 130), instruction, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		_draw_game_buttons(p)
		return
	if game.match_paused:
		_draw_button(p.layout, "LAYOUT", 55.0)
		_draw_button(p.pause, "RESUME", 45.0)
		_draw_button(p.menu, "MENU", 55.0)
		return
	if _round_prompt_active():
		if not game.clear_map_waiting_to_start and (game.wanted_tally_overlay == null or not game.wanted_tally_overlay.visible):
			_draw_button(p.continue, "CONTINUE", 65.0)
		return
	_draw_game_buttons(p)

func _draw_game_buttons(p: Dictionary) -> void:
	_draw_button(p.crouch, "DUCK ON" if crouch_toggled else "DUCK", 42.0)
	_draw_button(p.fire, "FIRE", 52.0)
	_draw_button(p.reload, "RELOAD", 42.0)
	_draw_button(p.heart, "HEART 5", 39.0)
	_draw_button(p.gun, "GUN 10", 39.0)
	_draw_button(p.pause, "II", 35.0)

func _draw_button(center: Vector2, label: String, radius: float) -> void:
	draw_circle(center, radius, Color(0.1, 0.08, 0.05, 0.58))
	draw_arc(center, radius, 0.0, TAU, 40, Color(1, 0.9, 0.6, 0.8), 3.0)
	var font := ThemeDB.fallback_font
	var font_size := 18
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center + Vector2(-width / 2.0, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
