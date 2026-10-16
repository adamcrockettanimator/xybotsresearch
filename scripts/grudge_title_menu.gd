extends Control

const GAME_SCENE := "res://coordinate_frame_navigation.tscn"
const PLAYER_NAMES := ["BART", "JED", "HANK", "WYATT"]
const MENU_INK := Color("#3b1b12")
const DISPLAY_ORDER := [0, 2, 1, 3]
const SPLATTER_FRAME_PATHS := [
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed1.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed2.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed3.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed4.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed5.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed6.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed7.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed8.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed9.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed10.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed11.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed12.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed13.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed14.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed15.png",
	"res://assets/Effects/Splatter/MenuSmall/FootageCrate-Ink_Bleed16.png",
]
var slot_name_labels: Array[Label] = []
var slot_status_labels: Array[Label] = []
var entrants: Dictionary = {}
var input_latches: Dictionary = {}
var splatter: AnimatedSprite2D
var masked_cowboy: AnimatedSprite2D

func _ready() -> void:
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
	var lawmen := _make_label(font, "LAWMEN", 18, MENU_INK)
	lawmen.position = Vector2(90, 184)
	lawmen.size = Vector2(350, 28)
	add_child(lawmen)
	_add_team_underline(Vector2(90, 212), Vector2(220, 212))
	var outlaws := _make_label(font, "OUTLAWS", 18, MENU_INK)
	outlaws.position = Vector2(90, 340)
	outlaws.size = Vector2(350, 28)
	add_child(outlaws)
	_add_team_underline(Vector2(90, 368), Vector2(220, 368))
	var member_y := [222.0, 262.0, 378.0, 418.0]
	for display_index in range(4):
		var slot_index: int = DISPLAY_ORDER[display_index]
		var name_label := _make_label(font, "", 25, MENU_INK)
		name_label.position = Vector2(90, member_y[display_index])
		name_label.size = Vector2(170, 42)
		add_child(name_label)
		slot_name_labels.append(name_label)
		var status_label := _make_label(font, "", 10, MENU_INK)
		status_label.position = Vector2(270, member_y[display_index] + 12.0)
		status_label.size = Vector2(180, 22)
		add_child(status_label)
		slot_status_labels.append(status_label)
	_splatter_decoration_setup()
	_add_horizon_silhouette()
	var directions := ["STICK: SELECT", "A: CONFIRM", "B: BACK", "START: JOIN / START MATCH"]
	for direction_index in range(directions.size()):
		var direction_label := _make_label(font, directions[direction_index], 10, MENU_INK)
		direction_label.position = Vector2(90, 566 + direction_index * 22)
		direction_label.size = Vector2(260, 20)
		direction_label.z_index = 4
		add_child(direction_label)
	var vacancy_note := _make_label(font, "VACANCIES BECOME BOTS", 10, MENU_INK)
	vacancy_note.position = Vector2(90, 666)
	vacancy_note.size = Vector2(260, 20)
	vacancy_note.z_index = 4
	add_child(vacancy_note)
	_refresh_slots()

func _make_label(font: Font, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _add_broadside_frame() -> void:
	# A clean rectangular rule keeps the flat pixel-art menu reading as a
	# printed broadside without a broken corner. These child lines sit above the backdrop but underneath
	# later text/splatter children.
	var border := PackedVector2Array([
		Vector2(14, 14), Vector2(946, 14), Vector2(946, 706), Vector2(14, 706),
	])
	var border_line := Line2D.new()
	border_line.points = border
	border_line.closed = true
	border_line.width = 3.0
	border_line.default_color = MENU_INK
	border_line.antialiased = false
	border_line.z_index = 5
	add_child(border_line)
	# Simple square-ended divider between the masthead and roster.
	var divider := Line2D.new()
	divider.points = PackedVector2Array([Vector2(62, 128), Vector2(898, 128)])
	divider.width = 3.0
	divider.default_color = MENU_INK
	divider.antialiased = false
	add_child(divider)

func _add_team_underline(from: Vector2, to: Vector2) -> void:
	var underline := Line2D.new()
	underline.points = PackedVector2Array([from, to])
	underline.width = 2.0
	underline.default_color = MENU_INK
	underline.antialiased = false
	add_child(underline)

func _add_horizon_silhouette() -> void:
	# This standalone transparent texture can be opened directly in a pixel-art
	# editor to repaint the horizon without modifying menu code.
	var horizon := Sprite2D.new()
	horizon.texture = load("res://assets/UI/GrudgeMenu/grudge_menu_horizon.png")
	horizon.centered = false
	horizon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	horizon.z_index = 3
	add_child(horizon)

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
	for display_index in range(slot_name_labels.size()):
		var slot_index: int = DISPLAY_ORDER[display_index]
		var occupied := false
		if slot_index < slots.size():
			occupied = bool(slots[slot_index])
		var selecting := _is_slot_selected(slot_index)
		var state := "SELECTING" if selecting else "OPEN"
		if occupied:
			var device_ids = session.get("slot_device_ids") if session != null else []
			var device_id := int(device_ids[slot_index]) if slot_index < device_ids.size() else -1
			var source := "PAD %d" % device_id if device_id >= 0 else "KEYBOARD"
			state = "P%d READY [%s]" % [slot_index + 1, source]
		slot_name_labels[display_index].text = PLAYER_NAMES[slot_index]
		slot_status_labels[display_index].text = state

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

func _splatter_decoration_setup() -> void:
	# The supplied ink sequence is a red window in the yellow menu, rather than
	# an opaque panel. The cowboy's rendered texture is alpha-clipped by the
	# current ink frame, so he only exists inside the animated splatter.
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"bleed")
	# This is an arrival accent: reveal the red field once, then preserve the
	# completed splatter as the backdrop for the looping silhouette.
	frames.set_animation_loop(&"bleed", false)
	frames.set_animation_speed(&"bleed", 9.0)
	for frame_path in SPLATTER_FRAME_PATHS:
		frames.add_frame(&"bleed", load(frame_path), 1.0)

	splatter = AnimatedSprite2D.new()
	splatter.sprite_frames = frames
	splatter.animation = &"bleed"
	splatter.position = Vector2(720, 390)
	splatter.scale = Vector2(2.5, 2.5)
	splatter.modulate = Color("#b52b24")
	splatter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	splatter.z_index = 1
	var ink_shader := Shader.new()
	ink_shader.code = """shader_type canvas_item;
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float ink_alpha = max(ink.r, max(ink.g, ink.b));
	COLOR = vec4(COLOR.rgb, COLOR.a * ink_alpha);
}"""
	var ink_material := ShaderMaterial.new()
	ink_material.shader = ink_shader
	splatter.material = ink_material
	splatter.frame_changed.connect(_update_cowboy_mask)
	add_child(splatter)

	masked_cowboy = AnimatedSprite2D.new()
	masked_cowboy.sprite_frames = load("res://assets/Characters/Cowboy2_Run_8Dir/Cowboy2_Run_8Dir_Strafe.tres")
	masked_cowboy.animation = &"RunW_AimW"
	masked_cowboy.position = splatter.position
	masked_cowboy.scale = Vector2(10.9, 10.9)
	masked_cowboy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	masked_cowboy.z_index = 2
	var mask_shader := Shader.new()
	mask_shader.code = """shader_type canvas_item;
uniform sampler2D mask_texture : source_color, filter_nearest;
void fragment() {
	vec4 cowboy = texture(TEXTURE, UV);
	// Keep the cowboy's 32x48 frame aligned to the source 320x240 splatter.
	vec2 mask_uv = vec2(0.5, 0.525) + (UV - vec2(0.5)) * vec2(0.5, 1.0);
	vec4 ink = texture(mask_texture, mask_uv);
	float mask_alpha = max(ink.r, max(ink.g, ink.b));
	COLOR = vec4(vec3(0.04), cowboy.a * mask_alpha);
}"""
	var mask_material := ShaderMaterial.new()
	mask_material.shader = mask_shader
	masked_cowboy.material = mask_material
	add_child(masked_cowboy)
	# Keep the menu quiet for a beat, then play the one-shot reveal. Hiding both
	# nodes prevents frame zero from flashing before the intended delay.
	splatter.visible = false
	masked_cowboy.visible = false
	masked_cowboy.play()
	get_tree().create_timer(1.0).timeout.connect(_start_splatter_reveal)
	_update_cowboy_mask()

func _start_splatter_reveal() -> void:
	if splatter == null or masked_cowboy == null:
		return
	splatter.visible = true
	masked_cowboy.visible = true
	splatter.play()

func _update_cowboy_mask() -> void:
	if splatter == null or masked_cowboy == null:
		return
	var material := masked_cowboy.material as ShaderMaterial
	material.set_shader_parameter(&"mask_texture", splatter.sprite_frames.get_frame_texture(splatter.animation, splatter.frame))
