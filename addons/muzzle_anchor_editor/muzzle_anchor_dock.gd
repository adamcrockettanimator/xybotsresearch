@tool
extends VBoxContainer

const MuzzleAnchorLibrary := preload("res://scripts/muzzle_anchor_library.gd")
const AnchorCanvas := preload("res://addons/muzzle_anchor_editor/muzzle_anchor_canvas.gd")

var frames_path_edit: LineEdit
var anchors_path_edit: LineEdit
var animation_picker: OptionButton
var frame_slider: HSlider
var frame_label: Label
var canvas: Control
var frames: SpriteFrames
var library: Resource
var animation_name: StringName


func _ready() -> void:
	name = "Muzzle Anchors"
	custom_minimum_size = Vector2(390.0, 0.0)
	_add_path_row("SpriteFrames", "res://assets/Characters/Cowboy2_DualWield_Idle_8Dir/Cowboy2_DualWield_Idle_8Dir.tres", true)
	_add_path_row("Anchor resource", "res://assets/Characters/Cowboy2_MuzzleAnchors.tres", false)
	var animation_row := HBoxContainer.new()
	animation_row.add_child(_label("Animation"))
	animation_picker = OptionButton.new()
	animation_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	animation_picker.item_selected.connect(_on_animation_selected)
	animation_row.add_child(animation_picker)
	add_child(animation_row)
	var frame_row := HBoxContainer.new()
	frame_row.add_child(_label("Frame"))
	frame_slider = HSlider.new()
	frame_slider.step = 1.0
	frame_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_slider.value_changed.connect(_on_frame_changed)
	frame_row.add_child(frame_slider)
	frame_label = Label.new()
	frame_label.custom_minimum_size = Vector2(62.0, 0.0)
	frame_row.add_child(frame_label)
	add_child(frame_row)
	var hands := HBoxContainer.new()
	for hand in [&"right", &"left"]:
		var button := Button.new()
		button.text = "Place %s muzzle" % String(hand)
		button.pressed.connect(_select_hand.bind(hand))
		hands.add_child(button)
	add_child(hands)
	canvas = AnchorCanvas.new()
	canvas.anchor_placed.connect(_on_anchor_placed)
	add_child(canvas)
	var actions := HBoxContainer.new()
	var clear := Button.new()
	clear.text = "Clear selected"
	clear.pressed.connect(_clear_selected_anchor)
	actions.add_child(clear)
	var save := Button.new()
	save.text = "Save anchors"
	save.pressed.connect(_save_anchors)
	actions.add_child(save)
	add_child(actions)
	var hint := Label.new()
	hint.text = "Click the actual barrel tip. Blue=right, orange=left, magenta=currently placing. Anchors are animation defaults; frame overrides can be added later."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	_load_frames()
	_load_library()


func _add_path_row(title: String, initial_path: String, is_frames: bool) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label(title))
	var edit := LineEdit.new()
	edit.text = initial_path
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var load_button := Button.new()
	load_button.text = "Load" if is_frames else "Open"
	if is_frames:
		load_button.pressed.connect(_load_frames)
	else:
		load_button.pressed.connect(_load_library)
	row.add_child(load_button)
	add_child(row)
	if is_frames:
		frames_path_edit = edit
	else:
		anchors_path_edit = edit


func _label(value: String) -> Label:
	var result := Label.new()
	result.text = value
	result.custom_minimum_size = Vector2(96.0, 0.0)
	return result


func _load_frames() -> void:
	var candidate := load(frames_path_edit.text)
	if candidate is SpriteFrames:
		frames = candidate
		animation_picker.clear()
		for name in frames.get_animation_names():
			animation_picker.add_item(String(name))
		if animation_picker.item_count > 0:
			_on_animation_selected(0)
	else:
		push_warning("Muzzle Anchor Editor could not load SpriteFrames: %s" % frames_path_edit.text)


func _load_library() -> void:
	var candidate := load(anchors_path_edit.text)
	if candidate != null and candidate.get_script() == MuzzleAnchorLibrary:
		library = candidate
	else:
		library = MuzzleAnchorLibrary.new()
		library.sprite_frames_path = frames_path_edit.text
	_refresh_canvas()


func _on_animation_selected(index: int) -> void:
	if frames == null or index < 0:
		return
	animation_name = StringName(animation_picker.get_item_text(index))
	frame_slider.max_value = maxf(0.0, float(frames.get_frame_count(animation_name) - 1))
	frame_slider.value = 0.0
	_refresh_canvas()


func _on_frame_changed(_value: float) -> void:
	_refresh_canvas()


func _select_hand(hand: StringName) -> void:
	canvas.selected_hand = hand
	canvas.queue_redraw()


func _on_anchor_placed(hand: StringName, pixel: Vector2i) -> void:
	_ensure_library()
	library.set_anchor(animation_name, hand, pixel)
	_refresh_canvas()


func _clear_selected_anchor() -> void:
	if library == null:
		return
	library.clear_anchor(animation_name, canvas.selected_hand)
	_refresh_canvas()


func _ensure_library() -> void:
	if library == null:
		library = MuzzleAnchorLibrary.new()
		library.sprite_frames_path = frames_path_edit.text


func _refresh_canvas() -> void:
	if frames == null or animation_name.is_empty():
		return
	var frame_index := int(frame_slider.value)
	frame_label.text = "%d / %d" % [frame_index + 1, frames.get_frame_count(animation_name)]
	var frame_texture := frames.get_frame_texture(animation_name, frame_index)
	var frame_anchors: Dictionary = {}
	if library != null:
		for hand in [&"right", &"left"]:
			var point: Variant = library.get_anchor(animation_name, hand)
			if point is Vector2i:
				frame_anchors[String(hand)] = point
	canvas.set_frame(frame_texture, frame_anchors)


func _save_anchors() -> void:
	_ensure_library()
	library.sprite_frames_path = frames_path_edit.text
	var result := ResourceSaver.save(library, anchors_path_edit.text)
	if result != OK:
		push_error("Could not save muzzle anchors to %s (error %d)" % [anchors_path_edit.text, result])
