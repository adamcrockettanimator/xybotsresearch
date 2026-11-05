extends RefCounted

# The entry ID belongs to the optional, editable technical-information question.
const FORM_URL := "https://docs.google.com/forms/d/e/1FAIpQLSeLLxFRPSK2xVsyh4nfOxHMIHWRke9gf1KI58GLNGRhAhXQYg/viewform?usp=header"

static func available() -> bool:
	return not FORM_URL.is_empty()

static func is_shortcut(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and not event.alt_pressed and not event.ctrl_pressed and not event.meta_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)

static func diagnostics(context: String, viewport_size: Vector2) -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if version.is_empty():
		version = "development (unversioned)"
	var lines := ["Game build: " + version, "Game context: " + context]
	var browser_info: Dictionary = {}
	if OS.has_feature("web"):
		var result = JavaScriptBridge.eval("""JSON.stringify({
			user_agent: navigator.userAgent || '',
			platform: (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '',
			window_size: window.innerWidth + ' x ' + window.innerHeight,
			screen_size: screen.width + ' x ' + screen.height,
			pixel_ratio: window.devicePixelRatio || 1
		})""")
		var parsed = JSON.parse_string(str(result))
		if parsed is Dictionary:
			browser_info = parsed
		lines.append("Browser: " + str(browser_info.get("user_agent", "Unavailable")))
		lines.append("Operating system: " + str(browser_info.get("platform", "Unavailable")))
		lines.append("Browser window (CSS pixels): " + str(browser_info.get("window_size", "Unavailable")))
		lines.append("Screen (CSS pixels): " + str(browser_info.get("screen_size", "Unavailable")))
		lines.append("Device pixel ratio: " + str(browser_info.get("pixel_ratio", "Unavailable")))
	else:
		lines.append("Operating system: " + OS.get_name())
		lines.append("Screen (pixels): %s" % DisplayServer.screen_get_size())
	lines.append("Game viewport: %d x %d" % [int(viewport_size.x), int(viewport_size.y)])
	lines.append("Controllers connected: %d" % Input.get_connected_joypads().size())
	return "\n".join(lines)

static func feedback_url(context: String, viewport_size: Vector2) -> String:
	return FORM_URL + "&entry.1263596551=" + diagnostics(context, viewport_size).uri_encode()

static func open_form(context: String = "Title screen", viewport_size: Vector2 = Vector2.ZERO) -> Error:
	if not available():
		return ERR_UNCONFIGURED
	return OS.shell_open(feedback_url(context, viewport_size))

static func add_button(parent: Control, font: Font, color: Color) -> Button:
	var button := Button.new()
	button.name = "FeedbackButton"
	button.text = "PRESS ENTER TO GIVE FEEDBACK"
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 10)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, color)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -330
	button.offset_top = -48
	button.offset_right = -22
	button.offset_bottom = -18
	button.z_index = 10
	button.visible = available()
	parent.add_child(button)
	return button
