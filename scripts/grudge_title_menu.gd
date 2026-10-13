extends Control

const GAME_SCENE := "res://coordinate_frame_navigation.tscn"
const PLAYER_NAMES := ["BART", "JED", "HANK", "WYATT"]
const TEAM_COLORS := [Color("#943dde"), Color("#27b84d"), Color("#943dde"), Color("#27b84d")]
const DISPLAY_ORDER := [0, 2, 1, 3]
var slot_labels: Array[Label] = []
var entrants: Dictionary = {}
var input_latches: Dictionary = {}
var decoration: AnimatedSprite2D

func _ready() -> void:
	var font: FontFile = preload("res://assets/Fonts/High Noon.woff")
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.multichannel_signed_distance_field = false
	var backdrop := ColorRect.new()
	backdrop.color = Color("#f1c827")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var title := _make_label(font, "GRUDGE COUNTY", 64, Color("#3b1b12"))
	title.add_theme_color_override("font_shadow_color", Color("#fff0a8"))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.position = Vector2(60, 45)
	title.size = Vector2(840, 92)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var lawmen := _make_label(font, "LAWMEN", 18, TEAM_COLORS[0])
	lawmen.position = Vector2(90, 190)
	lawmen.size = Vector2(350, 28)
	add_child(lawmen)
	var outlaws := _make_label(font, "OUTLAWS", 18, TEAM_COLORS[1])
	outlaws.position = Vector2(90, 365)
	outlaws.size = Vector2(350, 28)
	add_child(outlaws)
	for display_index in range(4):
		var slot_index: int = DISPLAY_ORDER[display_index]
		var slot := _make_label(font, "", 25, TEAM_COLORS[slot_index])
		slot.position = Vector2(90, 228 + display_index * 72 + (32 if display_index >= 2 else 0))
		slot.size = Vector2(440, 52)
		slot.add_theme_color_override("font_shadow_color", Color("#32170e"))
		slot.add_theme_constant_override("shadow_offset_x", 2)
		slot.add_theme_constant_override("shadow_offset_y", 2)
		add_child(slot)
		slot_labels.append(slot)
	_decoration_setup()
	var start_hint := _make_label(font, "START: JOIN / START MATCH", 16, Color("#3b1b12"))
	start_hint.position = Vector2(90, 590)
	start_hint.size = Vector2(780, 34)
	add_child(start_hint)
	var join_hint := _make_label(font, "STICK: SELECT   A: CONFIRM   B: BACK   •   VACANCIES BECOME BOTS", 10, Color("#5a2d14"))
	join_hint.position = Vector2(90, 635)
	join_hint.size = Vector2(780, 24)
	add_child(join_hint)
	_refresh_slots()

func _make_label(font: Font, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _process(delta: float) -> void:
	for device_id in Input.get_connected_joypads():
		var start_pressed := Input.is_joy_button_pressed(device_id, JOY_BUTTON_START)
		if _just_pressed(device_id, "start", start_pressed):
			_handle_start(device_id)
		var select_axis := Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		var direction := 1 if select_axis > 0.65 else -1 if select_axis < -0.65 else 0 # Down advances; up moves to the preceding character.
		if direction != 0 and _just_pressed(device_id, "select", true):
			_cycle_selection(device_id, direction)
		elif direction == 0:
			_just_pressed(device_id, "select", false)
		if _just_pressed(device_id, "confirm", Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)):
			_confirm_selection(device_id)
		if _just_pressed(device_id, "back", Input.is_joy_button_pressed(device_id, JOY_BUTTON_B)):
			_back_out(device_id)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	var keyboard_id := -1
	if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_handle_start(keyboard_id)
	elif event.keycode == KEY_A:
		_confirm_selection(keyboard_id)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_B:
		_back_out(keyboard_id)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_LEFT or event.keycode == KEY_UP:
		_cycle_selection(keyboard_id, -1)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_RIGHT or event.keycode == KEY_DOWN:
		_cycle_selection(keyboard_id, 1)
		get_viewport().set_input_as_handled()

func _start_match() -> void:
	# SceneTree survives the scene replacement. Keep an immutable match-start
	# roster here as well as in the autoload, so controller ownership cannot be
	# reset by a scene reload or a hot-reloaded autoload script.
	var session := get_node_or_null("/root/GrudgeSession")
	if session != null:
		get_tree().set_meta("grudge_match_human_slots", session.get("human_slots").duplicate())
		get_tree().set_meta("grudge_match_device_ids", session.get("slot_device_ids").duplicate())
	get_tree().change_scene_to_file(GAME_SCENE)

func _refresh_slots() -> void:
	var session := get_node_or_null("/root/GrudgeSession")
	var slots: Array = session.get("human_slots") if session != null else [false, false, false, false]
	for display_index in range(slot_labels.size()):
		var slot_index: int = DISPLAY_ORDER[display_index]
		var occupied: bool = slot_index < slots.size() and bool(slots[slot_index])
		var selecting := _is_slot_selected(slot_index)
		var state := "SELECTING" if selecting else "OPEN"
		if occupied:
			var device_ids = session.get("slot_device_ids") if session != null else []
			var device_id := int(device_ids[slot_index]) if slot_index < device_ids.size() else -1
			var source := "PAD %d" % device_id if device_id >= 0 else "KEYBOARD"
			state = "P%d READY [%s]" % [slot_index + 1, source]
		slot_labels[display_index].text = "%s  %s" % [PLAYER_NAMES[slot_index], state]

func _handle_start(device_id: int) -> void:
	if not entrants.has(device_id):
		entrants[device_id] = {"selection": _first_available_slot(), "ready": false}
		_refresh_slots()
		return
	if bool(entrants[device_id].get("ready", false)):
		get_viewport().set_input_as_handled()
		call_deferred("_start_match")

func _cycle_selection(device_id: int, step: int) -> void:
	if not entrants.has(device_id) or bool(entrants[device_id].get("ready", false)):
		return
	var entry: Dictionary = entrants[device_id]
	var current := int(entry.get("selection", _first_available_slot()))
	for attempt in range(4):
		current = posmod(current + step, 4)
		if _slot_is_available(current):
			entry["selection"] = current
			entrants[device_id] = entry
			_refresh_slots()
			return

func _confirm_selection(device_id: int) -> void:
	if not entrants.has(device_id):
		return
	var entry: Dictionary = entrants[device_id]
	if bool(entry.get("ready", false)):
		return
	var slot_index := int(entry.get("selection", -1))
	var session := get_node_or_null("/root/GrudgeSession")
	var slots: Array = session.get("human_slots") if session != null else []
	if slot_index < 0 or slot_index >= slots.size() or bool(slots[slot_index]):
		return
	if session != null and session.has_method("claim_slot"):
		session.call("claim_slot", slot_index, device_id)
		entry["ready"] = true
		entrants[device_id] = entry
		_refresh_slots()

func _back_out(device_id: int) -> void:
	if not entrants.has(device_id):
		return
	var entry: Dictionary = entrants[device_id]
	if bool(entry.get("ready", false)):
		var session := get_node_or_null("/root/GrudgeSession")
		if session != null and session.has_method("release_slot"):
			session.call("release_slot", int(entry.get("selection", -1)))
		entry["ready"] = false
		entrants[device_id] = entry
	else:
		entrants.erase(device_id)
	_refresh_slots()

func _first_available_slot() -> int:
	for slot_index in range(4):
		if _slot_is_available(slot_index):
			return slot_index
	return 0

func _slot_is_available(slot_index: int) -> bool:
	var session := get_node_or_null("/root/GrudgeSession")
	var slots: Array = session.get("human_slots") if session != null else []
	return slot_index >= 0 and slot_index < slots.size() and not bool(slots[slot_index]) and not _is_slot_selected(slot_index)

func _is_slot_selected(slot_index: int) -> bool:
	for entry in entrants.values():
		if not bool(entry.get("ready", false)) and int(entry.get("selection", -1)) == slot_index:
			return true
	return false

func _just_pressed(device_id: int, action: String, pressed: bool) -> bool:
	var key := "%d:%s" % [device_id, action]
	var was_pressed := bool(input_latches.get(key, false))
	input_latches[key] = pressed
	return pressed and not was_pressed

func _decoration_setup() -> void:
	decoration = AnimatedSprite2D.new()
	decoration.sprite_frames = load("res://assets/Characters/Cowboy2_Run_8Dir/Cowboy2_Run_8Dir_Strafe.tres")
	decoration.animation = &"RunW_AimW"
	decoration.position = Vector2(710, 368)
	decoration.scale = Vector2(6.4, 6.4)
	decoration.modulate = Color(0.04, 0.025, 0.02, 1.0)
	decoration.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	decoration.play()
	add_child(decoration)
