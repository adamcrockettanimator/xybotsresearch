## Live controls for the semantic crate in the existing playable gallery.
extends "res://tests/calibration/primitive_sprite_gallery_game.gd"

const PRESET_PATH := "user://semantic_crate_authoring.cfg"
var settings := {
	"top_color": Color8(135, 108, 81),
	"side_x_color": Color8(118, 94, 71),
	"side_y_color": Color8(101, 81, 60),
	"panel_top_color": Color8(118, 94, 71),
	"panel_color": Color8(101, 81, 60),
	"panel_dark_color": Color8(82, 64, 47),
	"shadow_color": Color8(78, 60, 44),
	"panel_enabled": true, "shadow_enabled": true,
	"frame_inset": 0.19, "min_panel_pixels": 1.5,
	"full_contrast_pixels": 6.0, "fade_steps": 0,
	"panel_max_distance": 1000.0, "min_face_ratio": 0.0,
	"lighting_shadow": 0.0,
	"edge_enabled": true, "edge_full_distance": 0.55,
	"edge_fade_distance": 1.15, "edge_color_balance": 0.5, "edge_brightening": 0.2,
	"ao_enabled": true, "ao_depth": 0.08, "ao_strength": 0.55, "ao_color": Color8(78, 60, 44),
	"shadow_depth": 0.07, "slats_enabled": true, "slat_count": 3, "slat_color": Color8(78, 60, 44),
	"side_slats_max_angle": 90.0, "top_slats_max_distance": 1000.0,
	"inset_highlight_enabled": true, "inset_highlight_color": Color8(167, 141, 108),
	"inset_highlight_full_distance": 0.55, "inset_highlight_fade_distance": 1.5,
	"bevel_shadow_enabled": true, "bevel_shadow_fade_distance": 1.0,
}
var controls := {}
var feature_groups := {}
var status: Label

func _ready() -> void:
	super._ready()
	_build_controls()

func _process(_delta: float) -> void:
	var game := get_node_or_null("CoordinateFrameGame")
	if game == null:
		return
	var nodes: Dictionary = game.get("semantic_lod_floor_outline_nodes")
	for key in nodes:
		if not String(key).contains("crate_semantic_flat_box"):
			continue
		var outline = nodes[key]
		if not is_instance_valid(outline):
			continue
		var canvas = outline.get("low_resolution_canvas")
		if is_instance_valid(canvas):
			canvas.authoring_settings = settings

func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var panel := PanelContainer.new()
	# Keep the editor controls away from the upper-left player viewport.
	panel.position = Vector2(660, 8)
	panel.size = Vector2(290, 620)
	panel.visible = false # Keep the older crate-authoring panel out of the way until F6 deliberately opens it.
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 265
	scroll.add_child(column)
	var title := Label.new()
	title.text = "SEMANTIC CRATE  |  F6: hide/show"
	column.add_child(title)
	var faces := _add_feature_group(column, "Face colors and lighting")
	_add_color(faces, "Top", "top_color")
	_add_color(faces, "Side A", "side_x_color")
	_add_color(faces, "Side B", "side_y_color")
	_add_slider(faces, "Side lighting shadow", "lighting_shadow", 0.0, 0.6, 0.01)
	var panel_feature := _add_feature_group(column, "Inset panel")
	_add_toggle(panel_feature, "Enabled", "panel_enabled")
	_add_color(panel_feature, "Top panel", "panel_top_color")
	_add_color(panel_feature, "Side A panel", "panel_color")
	_add_color(panel_feature, "Side B panel", "panel_dark_color")
	_add_slider(panel_feature, "Frame inset", "frame_inset", 0.05, 0.4, 0.01)
	_add_slider(panel_feature, "Minimum logical pixels", "min_panel_pixels", 0.5, 6.0, 0.1)
	_add_slider(panel_feature, "Full contrast at panel pixels", "full_contrast_pixels", 2.0, 20.0, 0.5)
	_add_slider(panel_feature, "Fade steps (0 = smooth)", "fade_steps", 0.0, 12.0, 1.0)
	_add_slider(panel_feature, "Maximum distance", "panel_max_distance", 0.5, 20.0, 0.1)
	_add_slider(panel_feature, "Minimum face width ratio", "min_face_ratio", 0.0, 0.8, 0.01)
	var shadow := _add_feature_group(column, "Upper drop shadow")
	_add_toggle(shadow, "Enabled", "shadow_enabled")
	_add_color(shadow, "Color", "shadow_color")
	_add_slider(shadow, "Depth", "shadow_depth", 0.01, 0.2, 0.01)
	var bevel := _add_feature_group(column, "Upper bevel shadow")
	_add_toggle(bevel, "Enabled", "bevel_shadow_enabled")
	_add_slider(bevel, "Fade distance", "bevel_shadow_fade_distance", 0.05, 5.0, 0.05)
	var ao := _add_feature_group(column, "Inset parallax shadow")
	_add_toggle(ao, "Enabled", "ao_enabled")
	_add_color(ao, "Color", "ao_color")
	_add_slider(ao, "Depth", "ao_depth", 0.0, 0.2, 0.01)
	_add_slider(ao, "Strength", "ao_strength", 0.0, 1.0, 0.05)
	var slats := _add_feature_group(column, "Panel slats")
	_add_toggle(slats, "Enabled", "slats_enabled")
	_add_color(slats, "Seam color", "slat_color")
	_add_slider(slats, "Number of slats", "slat_count", 2.0, 8.0, 1.0)
	_add_slider(slats, "Side slats: maximum angle (degrees)", "side_slats_max_angle", 0.0, 90.0, 1.0)
	_add_slider(slats, "Top slats: maximum distance", "top_slats_max_distance", 0.5, 20.0, 0.1)
	var inset_edge := _add_feature_group(column, "Inset frame highlight")
	_add_toggle(inset_edge, "Enabled", "inset_highlight_enabled")
	_add_color(inset_edge, "Color", "inset_highlight_color")
	_add_slider(inset_edge, "Full strength distance", "inset_highlight_full_distance", 0.0, 5.0, 0.05)
	_add_slider(inset_edge, "Fade distance", "inset_highlight_fade_distance", 0.05, 5.0, 0.05)
	var edge := _add_feature_group(column, "Shared edge highlight")
	_add_toggle(edge, "Enabled", "edge_enabled")
	_add_slider(edge, "Full strength distance", "edge_full_distance", 0.0, 5.0, 0.05)
	_add_slider(edge, "Disappears at distance", "edge_fade_distance", 0.05, 5.0, 0.05)
	_add_slider(edge, "Color: dark to light", "edge_color_balance", 0.0, 1.0, 0.05)
	_add_slider(edge, "Extra brightness", "edge_brightening", 0.0, 0.6, 0.01)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var save := Button.new()
	save.text = "Save preset"
	save.pressed.connect(_save_preset)
	buttons.add_child(save)
	var load_button := Button.new()
	load_button.text = "Load preset"
	load_button.pressed.connect(_load_preset)
	buttons.add_child(load_button)
	status = Label.new()
	status.text = "Use the existing game controls to navigate."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	set_meta("authoring_panel", panel)

func _add_feature_group(parent: VBoxContainer, title: String) -> VBoxContainer:
	var header := Button.new()
	header.text = "+  " + title
	header.toggle_mode = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(header)
	var contents := VBoxContainer.new()
	contents.visible = false
	parent.add_child(contents)
	header.toggled.connect(func(expanded: bool):
		contents.visible = expanded
		header.text = ("-  " if expanded else "+  ") + title
	)
	feature_groups[title] = {"header": header, "contents": contents}
	return contents

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		var panel: Control = get_meta("authoring_panel")
		panel.visible = not panel.visible
		get_viewport().set_input_as_handled()

func _add_color(parent: VBoxContainer, label_text: String, key: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(70, 25)
	picker.color = settings[key]
	picker.color_changed.connect(func(value: Color): settings[key] = value)
	row.add_child(picker)
	controls[key] = picker

func _add_toggle(parent: VBoxContainer, label_text: String, key: String) -> void:
	var toggle := CheckBox.new()
	toggle.text = label_text
	toggle.button_pressed = settings[key]
	toggle.toggled.connect(func(value: bool): settings[key] = value)
	parent.add_child(toggle)
	controls[key] = toggle

func _add_slider(parent: VBoxContainer, label_text: String, key: String, minimum: float, maximum: float, step: float) -> void:
	var label := Label.new()
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	# A maximum-distance value of 20 means no explicit distance cutoff.
	var unlimited_distance := key == "panel_max_distance" or key == "top_slats_max_distance"
	var initial: float = settings[key]
	slider.value = minf(initial, maximum)
	label.text = "%s: %s" % [label_text, "off" if unlimited_distance and initial >= maximum else str(slider.value)]
	slider.value_changed.connect(func(value: float):
		settings[key] = 1000.0 if unlimited_distance and value >= maximum else value
		label.text = "%s: %s" % [label_text, "off" if unlimited_distance and value >= maximum else str(value)]
		# Keep the fade range meaningful while either distance slider moves.
		if key == "edge_full_distance" and controls.has("edge_fade_distance") and value >= float(settings["edge_fade_distance"]):
			if value >= 5.0:
				controls["edge_full_distance"].value = 4.95
			controls["edge_fade_distance"].value = minf(5.0, value + 0.05)
		elif key == "edge_fade_distance" and controls.has("edge_full_distance") and value <= float(settings["edge_full_distance"]):
			controls["edge_full_distance"].value = maxf(0.0, value - 0.05)
		elif key == "inset_highlight_full_distance" and controls.has("inset_highlight_fade_distance") and value >= float(settings["inset_highlight_fade_distance"]):
			if value >= 5.0:
				controls[key].value = 4.95
			controls["inset_highlight_fade_distance"].value = minf(5.0, value + 0.05)
		elif key == "inset_highlight_fade_distance" and controls.has("inset_highlight_full_distance") and value <= float(settings["inset_highlight_full_distance"]):
			controls["inset_highlight_full_distance"].value = maxf(0.0, value - 0.05)
	)
	parent.add_child(slider)
	controls[key] = slider

func _save_preset() -> void:
	var config := ConfigFile.new()
	for key in settings:
		config.set_value("crate", key, settings[key])
	var error := config.save(PRESET_PATH)
	status.text = "Saved to " + PRESET_PATH if error == OK else "Save failed: %s" % error

func _load_preset() -> void:
	var config := ConfigFile.new()
	var error := config.load(PRESET_PATH)
	if error != OK:
		status.text = "No saved preset found (%s)." % error
		return
	for key in settings:
		var value = config.get_value("crate", key, settings[key])
		settings[key] = value
		var control: Control = controls[key]
		if control is ColorPickerButton:
			control.color = value
		elif control is CheckBox:
			control.button_pressed = value
		elif control is HSlider:
			control.value = minf(float(value), control.max_value)
	status.text = "Loaded " + PRESET_PATH
