extends "res://scripts/grudge_title_menu.gd"

var starting := false

func _ready() -> void:
	get_tree().set_meta("grudge_public_build", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var music := MusicAccess.get_player(get_tree())
	if music != null and not OS.has_feature("web"):
		music.call("set_music_mode", "menu")
	var font: FontFile = preload("res://assets/Fonts/High Noon.woff")
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.multichannel_signed_distance_field = false
	var backdrop := ColorRect.new()
	backdrop.color = Color("#f1c827")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_add_broadside_frame()
	var title := _make_label(font, "GRUDGE COUNTY", 64, MENU_INK)
	title.position = Vector2(60, 45)
	title.size = Vector2(840, 92)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	_splatter_decoration_setup()
	_add_horizon_silhouette()
	var start := Button.new()
	start.text = "PRESS SPACE TO PLAY"
	start.position = Vector2(54, 300)
	start.size = Vector2(400, 55)
	start.add_theme_font_override("font", font)
	start.add_theme_font_size_override("font_size", 18)
	start.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = MENU_INK
		style.set_border_width_all(3)
		style.content_margin_left = 5
		style.content_margin_right = 5
		start.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		start.add_theme_color_override(state, MENU_INK)
	start.pressed.connect(_begin_public_match.bind(-1))
	add_child(start)
	var keys := ["W A S D", "MOUSE", "LEFT CLICK", "SHIFT", "R", "Q", "E", "ESC"]
	var actions := ["MOVE / STRAFE", "LOOK", "FIRE", "CROUCH", "RELOAD", "BUY HEART (5 COINS)", "BUY GUN (10 COINS)", "PAUSE / MENU"]
	for i in range(keys.size()):
		var key_label := _make_label(font, keys[i], 12, MENU_INK)
		key_label.position = Vector2(62, 545 + i * 16)
		key_label.size = Vector2(150, 16)
		key_label.z_index = 4
		add_child(key_label)
		var action_label := _make_label(font, actions[i], 12, MENU_INK)
		action_label.position = Vector2(232, 545 + i * 16)
		action_label.size = Vector2(350, 16)
		action_label.z_index = 4
		add_child(action_label)

func _process(_delta: float) -> void:
	for device_id in Input.get_connected_joypads():
		if _just_pressed(device_id, "start", Input.is_joy_button_pressed(device_id, JOY_BUTTON_START)):
			_begin_public_match(device_id)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_begin_public_match(-1)

func _begin_public_match(device_id: int) -> void:
	if starting:
		return
	starting = true
	var music := MusicAccess.get_player(get_tree())
	if music != null:
		music.call("set_music_mode", "menu")
	var session := get_node_or_null("/root/GrudgeSession")
	if session != null:
		for slot in range(4):
			session.call("release_slot", slot)
		session.call("claim_slot", 0, device_id)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if device_id < 0 else Input.MOUSE_MODE_VISIBLE
	call_deferred("_start_match")
