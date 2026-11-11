extends "res://scripts/grudge_title_menu.gd"

var starting := false
var rotation_prompt: Label

var headline_font: FontFile
var body_font: Font
var feedback_button: Button

func _ready() -> void:
	get_tree().set_meta("grudge_public_build", true)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if preload("res://scripts/mobile_controls.gd").available():
		get_tree().set_meta("grudge_mobile_wide", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var music := MusicAccess.get_player(get_tree())
	if music != null and not OS.has_feature("web"):
		music.call("set_music_mode", "menu")
	headline_font = preload("res://assets/Fonts/High Noon.woff")
	headline_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	headline_font.multichannel_signed_distance_field = false
	body_font = ThemeDB.fallback_font
	var background := ColorRect.new()
	background.color = Color("#eee4ca")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	feedback_button = FeedbackAccess.add_button(self, body_font, MENU_INK)
	feedback_button.text = "GIVE FEEDBACK"
	feedback_button.add_theme_font_override("font", headline_font)
	feedback_button.add_theme_font_size_override("font_size", 19)
	feedback_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_style_print_button(feedback_button)
	feedback_button.pressed.connect(_open_title_feedback)
	resized.connect(_rebuild_broadside)
	_rebuild_broadside()

func _rebuild_broadside() -> void:
	if headline_font == null or feedback_button == null:
		return
	var old := get_node_or_null("Broadside")
	var show_rotation := rotation_prompt != null and rotation_prompt.visible
	if old != null:
		remove_child(old)
		old.queue_free()
	var page := Control.new()
	page.name = "Broadside"
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	_add_print_details(page)
	# Expand the paper to the viewport while keeping comfortable line lengths.
	var page_size := get_viewport_rect().size
	var content_width := minf(page_size.x - 140.0, 1200.0)
	var left := (page_size.x - content_width) * 0.5
	var stacked := page_size.y >= 1150.0 and page_size.y > page_size.x
	var top := maxf(20.0, (page_size.y - (1075.0 if stacked else 680.0)) * 0.5)
	var right_column := left + content_width * 0.46
	var guide_left := left if stacked else right_column
	var right_width := content_width if stacked else content_width * 0.54
	var guide_heading_y := top + (690.0 if stacked else 258.0)
	var guide_text_y := top + (732.0 if stacked else 300.0)
	_page_label(page, headline_font, "GRUDGE COUNTY", 60, Rect2(left, top + 26, content_width, 80), true)
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	_page_label(page, body_font, version, 12, Rect2(left + content_width - 185, top + 82, 185, 20), true)
	_print_rule(page, left, top + 105, left + content_width, 3)
	var start := Button.new()
	start.name = "PlayButton"
	start.text = "TAP TO PLAY" if preload("res://scripts/mobile_controls.gd").available() else "CLICK TO PLAY"
	start.position = Vector2(page_size.x * 0.5 - 180, top + 137)
	start.size = Vector2(360, 60)
	start.add_theme_font_override("font", headline_font)
	start.add_theme_font_size_override("font_size", 23)
	_style_print_button(start)
	start.pressed.connect(_begin_public_match.bind(-1))
	page.add_child(start)
	_page_label(page, body_font, "SPACE / CONTROLLER START" if not preload("res://scripts/mobile_controls.gd").available() else "", 12, Rect2(page_size.x * 0.5 - 235, top + 199, 470, 20), true)
	rotation_prompt = _page_label(page, body_font, "ROTATE YOUR PHONE SIDEWAYS", 16, Rect2(page_size.x * 0.5 - 235, top + 218, 470, 22), true)
	rotation_prompt.visible = show_rotation
	_print_rule(page, left, top + 245, right_column - 25, 3)
	if not stacked:
		_print_rule(page, guide_left, top + 245, left + content_width, 3)
	_page_label(page, headline_font, "CONTROLS", 27, Rect2(left, top + 258, right_column - left - 25, 35), false)
	if stacked:
		_print_rule(page, guide_left, guide_heading_y - 13, left + content_width, 3)
	_page_label(page, headline_font, "STRATEGY GUIDE", 27, Rect2(guide_left, guide_heading_y, right_width, 35), false)
	var actions := ["Move / strafe", "Look", "Fire", "Crouch", "Dive roll", "Reload", "Buy heart", "Buy dual pistols", "Pause / menu"]
	var keys := ["WASD / LEFT STICK", "MOUSE / RIGHT STICK", "CLICK / RT", "SHIFT / LT", "SPACE / A", "R / X", "Q / LB", "E / RB", "ESC / SELECT"]
	if preload("res://scripts/mobile_controls.gd").available():
		actions = ["Move", "Look", "Fire", "Crouch", "Reload", "Buy heart", "Buy dual pistols", "Pause / menu"]
		keys = ["DRAG LEFT SIDE", "DRAG RIGHT SIDE", "FIRE", "DUCK", "RELOAD", "HEART 5", "GUN 10", "II"]
	for i in range(actions.size()):
		_page_label(page, body_font, actions[i], 15, Rect2(left, top + 302 + i * 27, 185, 24), false)
		_page_label(page, body_font, keys[i], 12, Rect2(left + 190, top + 304 + i * 27, right_column - left - 200, 22), false)
	var tips := ["Shoot barrels and crates for loot.", "Enemies hear footsteps and gunshots. Crouch to sneak.", "Dive roll to evade shots and reach cover.", "Collect coins to buy hearts and dual pistols.", "You can carry up to 10 hearts.", "Dual pistols run out after 12 shots.", "Keep 10 coins handy to buy dual pistols in a fight!", "Enemies flank you. Keep an eye on the map.", "Fire around the right side of cover to stay hidden.", "Use the third-person camera to spy on enemies.", "Gather resources before picking a fight.", "Bait enemies into firing, then attack as they reload."]
	for i in range(tips.size()):
		_page_label(page, body_font, "-  " + tips[i], 15, Rect2(guide_left, guide_text_y + i * 26, right_width, 25), false)
	_print_rule(page, left, top + 565, right_column - 25, 3)
	var feedback_width := minf(330, right_column - left - 25)
	var feedback_left := left + (right_column - 25 - left - feedback_width) * 0.5
	var feedback_bottom := guide_heading_y - 13 if stacked else page_size.y - 14
	var feedback_top := floorf((top + 568 + feedback_bottom - 76) * 0.5)
	feedback_button.position = Vector2(feedback_left, feedback_top)
	feedback_button.size = Vector2(feedback_width, 52)
	_page_label(page, body_font, "ENTER" if not preload("res://scripts/mobile_controls.gd").available() else "", 12, Rect2(feedback_left, feedback_top + 56, feedback_width, 20), true)

func _style_print_button(button: Button) -> void:
	button.flat = false
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = MENU_INK if state in ["hover", "pressed"] else Color(0, 0, 0, 0)
		style.border_color = MENU_INK
		style.set_border_width_all(3)
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_focus_color"]:
		button.add_theme_color_override(state, MENU_INK)
	for state in ["font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, Color("#eee4ca"))

func _page_label(parent: Control, font: Font, text: String, font_size: int, rect: Rect2, centered: bool) -> Label:
	var label := _make_label(font, text, font_size, MENU_INK)
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(label)
	return label

func _print_rule(parent: Control, left: float, y: float, right: float, thickness: float) -> void:
	var line := ColorRect.new()
	line.color = MENU_INK
	line.position = Vector2(left, y)
	line.size = Vector2(right - left, thickness)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func _add_print_details(parent: Control) -> void:
	var page_size := get_viewport_rect().size
	var frame := ReferenceRect.new()
	frame.position = Vector2(14, 14)
	frame.size = page_size - Vector2(28, 28)
	frame.border_color = MENU_INK
	frame.border_width = 3.0
	frame.editor_only = false
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	# Small square-edged paper stains touch the border, away from the text.
	for rect in [Rect2(15, page_size.y * 0.24, 9, 4), Rect2(15, page_size.y * 0.70, 6, 4), Rect2(page_size.x - 24, page_size.y * 0.38, 9, 4), Rect2(page_size.x * 0.68, 15, 12, 4), Rect2(page_size.x * 0.30, page_size.y - 19, 11, 4)]:
		var stain := ColorRect.new()
		stain.color = Color("#dfd0ad")
		stain.position = rect.position
		stain.size = rect.size
		stain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(stain)

func _process(_delta: float) -> void:
	for device_id in Input.get_connected_joypads():
		if _just_pressed(device_id, "start", Input.is_joy_button_pressed(device_id, JOY_BUTTON_START)):
			_begin_public_match(device_id)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_SPACE or (not FeedbackAccess.available() and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER))):
		get_viewport().set_input_as_handled()
		_begin_public_match(-1)

func _begin_public_match(device_id: int) -> void:
	if bool(get_tree().get_meta("grudge_mobile_wide", false)) and get_viewport_rect().size.y > get_viewport_rect().size.x:
		if rotation_prompt != null:
			rotation_prompt.visible = true
		return
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if device_id < 0 and not preload("res://scripts/mobile_controls.gd").available() else Input.MOUSE_MODE_VISIBLE
	call_deferred("_start_match")
