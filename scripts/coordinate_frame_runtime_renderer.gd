# Isolated experimental wall renderer for the coordinate-frame navigation branch.
# It intentionally leaves the original sprite renderer and its slot graphs alone:
# this child only hides the old transparent wall sprites and composites one master
# wall texture through projective quads derived from the live grid camera basis.
extends Node

const VIEW_SIZE := Vector2(160.0, 120.0)
const MASTER_WALL_PATH := "res://assets/Environment/StripeTest.png"
const RUNTIME_MASTER_WALL_MAIN_PATH := "res://assets/Environment/Runtime_Master_Wall_Main.png"
const RUNTIME_MASTER_WALL_MAIN_HEIGHT_PATH := "res://assets/Environment/Runtime_Master_Wall_Main_height.png"
const DEBUG_WALL_TEXTURE_PATHS := [
	"res://assets/Environment/stripeTest_1px.png",
	"res://assets/Environment/stripeTest_2px.png",
	"res://assets/Environment/stripeTest_4px.png",
	"res://assets/Environment/stripeTest_8px.png",
]
const RUNTIME_MASTER_WALL_TEXTURE_PATHS := [
	"res://assets/Environment/Runtime_Master_Wall.png",
	"res://assets/Environment/Runtime_Master_Wall_Main.png",
	"res://assets/Environment/Runtime_Master_Wall_Concrete.png",
	"res://assets/Environment/Runtime_Master_Wall_Wood.png",
]
const SHADER_PATH := "res://scripts/coordinate_frame_homography.gdshader"
const SINGLE_WALL_SHADER_PATH := "res://scripts/coordinate_frame_single_homography.gdshader"
const TEMPLATE_ROOT := "res://assets/CoordinateFrames/"
# The canvas shader needs three vec4 rows per wall.  A 96-wall allocation can
# exceed the portable fragment-uniform budget and silently leave the layer
# transparent.  The authored five-cell view has fewer than 32 useful edges,
# which is also the proven limit from the earlier working prototype.
const MAX_WALLS := 28
const NEAR_CLIP := 0.075
const MAX_DEPTH := 5.5
# Match the Blender reference camera exactly: 28.8 mm / 36 mm × 160 px.
const FOCAL_LENGTH := 128.0
const HORIZON_Y := 31.5
## These are the Blender rig values expressed in one Godot grid-cell of width.
## Blender built each cell 2.0 units wide and 1.333 units tall, so its 0.75
## height fraction becomes 0.50 here and the wall top becomes 2/3.  Keeping
## this anisotropic cell is what registers the runtime projector to the red
## marker frames instead of merely looking broadly similar.
const VIRTUAL_CAMERA_HEIGHT := 0.5
const WALL_HEIGHT := 2.0 / 3.0
const TEMPLATE_CAMERA_REAR_OFFSET := 0.49
const FOV_RATIO := 0.70
const DIAGONAL_FRAME_SECONDS := 0.18

var controller: Node
var runtime_wall_layer: Node2D
var wall_art_sprite: Sprite2D
var wall_render_image: Image
var wall_render_texture: ImageTexture
var wall_source_image: Image
var wall_height_image: Image
var coordinate_background: Sprite2D
var status: Label
var runtime_status: Label
var parallax_tuner_panel: PanelContainer
var parallax_tuner_open := false
var last_signature := ""
var show_runtime_walls := true
var show_quad_outlines := false
var show_projection_points := false
var master_texture: Texture2D
var debug_wall_texture_index := -1
var runtime_master_wall_texture_index := -1
var active_wall_texture_label := "StripeTest"
var last_wall_entries: Array[Dictionary] = []
var wall_mip_images: Array[Image] = []
var integer_uv_scale_snap_enabled := false
var wall_ewa_filter_enabled := false
var wall_parallax_enabled := true
var parallax_max_texels := 4.0
var parallax_side_multiplier := 1.0
var parallax_vertical_multiplier := 1.0
var parallax_height_anchor := 0.0
var parallax_height_gamma := 1.0
var parallax_layer_count := 12
var template_textures: Dictionary = {}
var legacy_environment_nodes: Array[CanvasItem] = []
var diagonal_forward_clock := 0.0
var diagonal_forward_active := false
var diagonal_forward_cell := Vector2i(-999, -999)
var diagonal_forward_source_cell := Vector2i(-999, -999)
var diagonal_forward_target_cell := Vector2i(-999, -999)

func _ready() -> void:
	call_deferred("_initialize")

func _initialize() -> void:
	controller = get_parent()
	if controller == null:
		push_error("Coordinate-frame renderer requires the existing controller as its parent.")
		return
	master_texture = load(MASTER_WALL_PATH)
	_preload_coordinate_templates()
	controller.render_wall_art = false
	# Start this presentation in its clean coordinate-only state.  The original
	# F2/F3 diagnostics remain available, but should not obscure the new view.
	controller.show_slot_grid_debug = false
	controller.show_selected_wall_slot_debug = false
	controller.show_perspective_extents_overlay = false
	# The original renderer keeps updating its sprites as the player moves.
	# This experiment deliberately replaces that entire environmental image with
	# the authored black-and-white coordinate frame, while retaining the player,
	# collision, movement, and top-down map from the existing game.
	for child in controller.environment_layer.get_children():
		if child is CanvasItem:
			legacy_environment_nodes.append(child)
			child.visible = false
	coordinate_background = Sprite2D.new()
	coordinate_background.name = "CoordinateFrameBackground"
	coordinate_background.centered = false
	coordinate_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coordinate_background.z_index = 0
	controller.environment_layer.add_child(coordinate_background)
	# The wall pass is deliberately CPU-rasterized at the native 160x120 template
	# resolution.  That makes the projective mapping deterministic on this GPU,
	# retains the deliberately coarse pixel sampling, and avoids the D3D12 canvas
	# shader failure from the previous fullscreen-polygon experiment.
	runtime_wall_layer = Node2D.new()
	runtime_wall_layer.name = "CoordinateFrameHomographyWalls"
	runtime_wall_layer.z_index = 8
	# Runtime_Master_Wall is already the exact 128x88 master canvas.  The older
	# source sat inside a 160x120 authored sprite sheet and needed cropping.
	wall_source_image = master_texture.get_image()
	_set_height_texture_for_color_path(MASTER_WALL_PATH)
	_rebuild_wall_mip_chain()
	wall_render_image = Image.create(int(VIEW_SIZE.x), int(VIEW_SIZE.y), false, Image.FORMAT_RGBA8)
	wall_render_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	wall_render_texture = ImageTexture.create_from_image(wall_render_image)
	wall_art_sprite = Sprite2D.new()
	wall_art_sprite.name = "CoordinateFrameWallArt"
	wall_art_sprite.centered = false
	wall_art_sprite.texture = wall_render_texture
	wall_art_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wall_art_sprite.z_index = 0
	runtime_wall_layer.add_child(wall_art_sprite)
	controller.environment_layer.add_child(runtime_wall_layer)

	# The previous in-playfield caption was being scaled with the 160×120 view,
	# making it blurry and colliding with the player.  Retain a status node for
	# the renderer but keep it hidden; the readable CanvasLayer line below is the
	# sole on-screen readout.
	status = Label.new()
	status.visible = false
	runtime_status = Label.new()
	runtime_status.position = Vector2(12, 78)
	runtime_status.add_theme_font_size_override("font_size", 14)
	runtime_status.add_theme_color_override("font_color", Color.WHITE)
	runtime_status.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	runtime_status.add_theme_constant_override("outline_size", 3)
	controller.canvas_layer.add_child(runtime_status)
	_setup_parallax_tuner()
	_rebuild()

func _process(delta: float) -> void:
	if controller == null:
		return
	_hide_legacy_environment()
	_update_diagonal_forward_animation(delta)
	# Enforce debug visibility every frame: old queued debug nodes cannot remain
	# onscreen after their toggles are changed.
	if not show_quad_outlines:
		_remove_environment_debug_node("CoordinateFrameQuadDebug")
	if not show_projection_points:
		_remove_environment_debug_node("CoordinateFrameProjectionPoints")
	# Coordinate poses can change while the controller remains in the same cell
	# and facing (especially during a mobile diagonal run), so refresh this
	# independent background every frame rather than waiting for wall geometry.
	_update_coordinate_background()
	var signature := _render_signature()
	if signature != last_signature:
		_rebuild()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			show_runtime_walls = not show_runtime_walls
			_rebuild()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Y:
			show_quad_outlines = not show_quad_outlines
			_rebuild()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_U:
			show_projection_points = not show_projection_points
			_rebuild()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_G:
			_cycle_debug_wall_texture()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_K:
			_cycle_runtime_master_wall_texture()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_H:
			set_integer_uv_scale_snap_enabled(not integer_uv_scale_snap_enabled)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_J:
			set_wall_ewa_filter_enabled(not wall_ewa_filter_enabled)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_P:
			set_wall_parallax_enabled(not wall_parallax_enabled)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_O:
			_toggle_parallax_tuner()
			get_viewport().set_input_as_handled()

func _rebuild() -> void:
	if runtime_wall_layer == null:
		return
	last_signature = _render_signature()
	var entries: Array[Dictionary] = _visible_wall_entries()
	last_wall_entries = entries
	var accepted_count := entries.size()
	_update_coordinate_background()
	_rebuild_runtime_wall_surfaces(entries)
	_update_debug_outlines(entries)
	_update_projection_point_debug()
	runtime_wall_layer.visible = show_runtime_walls
	_refresh_runtime_status(accepted_count)

func _cycle_debug_wall_texture() -> void:
	# Deliberately do not call _rebuild(): the current map/raycast wall layout
	# remains untouched.  We only resample the already-projecting quads with the
	# next test image, which makes filtering comparisons direct and repeatable.
	debug_wall_texture_index = (debug_wall_texture_index + 1) % DEBUG_WALL_TEXTURE_PATHS.size()
	_set_wall_source_texture(String(DEBUG_WALL_TEXTURE_PATHS[debug_wall_texture_index]))


# _cycle_runtime_master_wall_texture: Switch only the source image used by the
# live quads.  Unlike a map reroll, this deliberately preserves wall geometry,
# filtering state, visibility, and the player's current position.
func _cycle_runtime_master_wall_texture() -> void:
	runtime_master_wall_texture_index = (runtime_master_wall_texture_index + 1) % RUNTIME_MASTER_WALL_TEXTURE_PATHS.size()
	_set_wall_source_texture(String(RUNTIME_MASTER_WALL_TEXTURE_PATHS[runtime_master_wall_texture_index]))


# _set_wall_source_texture: Loads one master texture and immediately resamples
# the existing CPU wall image.  Both G stripe tests and K master-art tests use
# this same path to make their comparisons directly equivalent.
func _set_wall_source_texture(path: String) -> void:
	var next_texture := load(path) as Texture2D
	if next_texture == null:
		push_error("Could not load runtime wall texture: %s" % path)
		return
	var next_image := next_texture.get_image()
	if next_image == null:
		push_error("Could not read runtime wall texture: %s" % path)
		return
	master_texture = next_texture
	wall_source_image = next_image
	_set_height_texture_for_color_path(path)
	active_wall_texture_label = path.get_file().get_basename()
	_rebuild_wall_mip_chain()
	_rebuild_runtime_wall_surfaces(last_wall_entries)
	_refresh_runtime_status(last_wall_entries.size())


# _set_height_texture_for_color_path: Height data belongs to one specific
# authored color texture.  Other test textures intentionally stay flat so the
# stripe/mip experiments remain isolated and comparable.
func _set_height_texture_for_color_path(color_path: String) -> void:
	wall_height_image = null
	if color_path != RUNTIME_MASTER_WALL_MAIN_PATH:
		return
	var height_texture := load(RUNTIME_MASTER_WALL_MAIN_HEIGHT_PATH) as Texture2D
	if height_texture == null:
		push_error("Could not load runtime wall height texture: %s" % RUNTIME_MASTER_WALL_MAIN_HEIGHT_PATH)
		return
	var height_image := height_texture.get_image()
	if height_image == null:
		push_error("Could not read runtime wall height texture: %s" % RUNTIME_MASTER_WALL_MAIN_HEIGHT_PATH)
		return
	if height_image.get_size() != wall_source_image.get_size():
		push_error("Runtime wall color and height textures must have matching dimensions.")
		return
	wall_height_image = height_image


# set_integer_uv_scale_snap_enabled: Quantizes the texture footprint before it
# chooses a mip level.  It deliberately does not move a wall quad or camera.
func set_integer_uv_scale_snap_enabled(enabled: bool) -> void:
	integer_uv_scale_snap_enabled = enabled
	_rebuild_runtime_wall_surfaces(last_wall_entries)
	_refresh_runtime_status(last_wall_entries.size())


# set_wall_ewa_filter_enabled: Toggles the wall-oriented anisotropic sample
# pass.  Its major axis is derived from the inverse homography, so it follows
# the compressed texture direction of a wall instead of assuming floor axes.
func set_wall_ewa_filter_enabled(enabled: bool) -> void:
	wall_ewa_filter_enabled = enabled
	_rebuild_runtime_wall_surfaces(last_wall_entries)
	_refresh_runtime_status(last_wall_entries.size())


# set_wall_parallax_enabled: Lets the raised/recessed master-wall test be
# compared directly against the same projected quads without relief mapping.
func set_wall_parallax_enabled(enabled: bool) -> void:
	wall_parallax_enabled = enabled
	_rebuild_runtime_wall_surfaces(last_wall_entries)
	_refresh_runtime_status(last_wall_entries.size())


# _setup_parallax_tuner: Builds a separate, visible live-tuning panel instead
# of appending controls below the clipped F3 menu.  It lives on the CanvasLayer
# and only changes this experimental CPU renderer while the game keeps running.
func _setup_parallax_tuner() -> void:
	if controller == null or controller.canvas_layer == null:
		return
	if parallax_tuner_panel != null:
		return
	parallax_tuner_panel = PanelContainer.new()
	parallax_tuner_panel.name = "RuntimeWallParallaxTuner"
	parallax_tuner_panel.position = Vector2(292.0, 104.0)
	parallax_tuner_panel.custom_minimum_size = Vector2(270.0, 0.0)
	parallax_tuner_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parallax_tuner_panel.visible = false
	controller.canvas_layer.add_child(parallax_tuner_panel)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 3)
	parallax_tuner_panel.add_child(section)
	var heading := Label.new()
	heading.text = "RUNTIME WALL PARALLAX  [O closes]"
	heading.add_theme_font_size_override("font_size", 14)
	section.add_child(heading)
	var hint := Label.new()
	hint.text = "Live tuning • applies to Runtime_Master_Wall_Main"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	section.add_child(hint)
	_add_parallax_tuning_slider(section, "Depth", "depth", 0.0, 16.0, 0.25, parallax_max_texels, "px")
	_add_parallax_tuning_slider(section, "Side", "side", -2.0, 2.0, 0.05, parallax_side_multiplier, "x")
	_add_parallax_tuning_slider(section, "Vertical", "vertical", -2.0, 2.0, 0.05, parallax_vertical_multiplier, "x")
	_add_parallax_tuning_slider(section, "Anchor tone", "anchor", 0.0, 1.0, 0.01, parallax_height_anchor, "")
	_add_parallax_tuning_slider(section, "Height curve", "gamma", 0.15, 4.0, 0.05, parallax_height_gamma, "")
	_add_parallax_tuning_slider(section, "March layers", "layers", 1.0, 32.0, 1.0, float(parallax_layer_count), "")


func _toggle_parallax_tuner() -> void:
	if parallax_tuner_panel == null:
		return
	parallax_tuner_open = not parallax_tuner_open
	parallax_tuner_panel.visible = parallax_tuner_open
	_refresh_runtime_status(last_wall_entries.size())


# _add_parallax_tuning_slider: Adds one readable label/slider pair.  The bound
# callback keeps the displayed value and the CPU wall image synchronized while
# the user drags, so it is suitable for visual tuning in a running game.
func _add_parallax_tuning_slider(parent: VBoxContainer, title: String, key: String, minimum: float, maximum: float, step: float, initial: float, suffix: String) -> void:
	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 12)
	parent.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(250.0, 18.0)
	slider.tooltip_text = "Live runtime-wall parallax tuning"
	parent.add_child(slider)
	_update_parallax_slider_label(value_label, title, initial, suffix)
	slider.value_changed.connect(func(value: float) -> void:
		_set_parallax_tuning_value(key, value)
		_update_parallax_slider_label(value_label, title, value, suffix)
	)


func _update_parallax_slider_label(label: Label, title: String, value: float, suffix: String) -> void:
	if title == "Anchor tone":
		var anchor_name := "black" if value <= 0.01 else "white" if value >= 0.99 else "grey"
		label.text = "Anchor tone: %.2f (%s stays fixed)" % [value, anchor_name]
		return
	var formatted := "%d" % roundi(value) if suffix.is_empty() and title == "March layers" else "%.2f" % value
	label.text = "%s: %s%s" % [title, formatted, suffix]


func _set_parallax_tuning_value(key: String, value: float) -> void:
	match key:
		"depth": parallax_max_texels = value
		"side": parallax_side_multiplier = value
		"vertical": parallax_vertical_multiplier = value
		"anchor": parallax_height_anchor = value
		"gamma": parallax_height_gamma = value
		"layers": parallax_layer_count = maxi(1, roundi(value))
	_rebuild_runtime_wall_surfaces(last_wall_entries)
	_refresh_runtime_status(last_wall_entries.size())

func _refresh_runtime_status(visible_wall_count: int) -> void:
	var status_text := "Coord %s | %d walls | Tex:%s [G/K] | T:%s Y:%s U:%s | H:%s J:%s P:%s O:%s" % [_pose_key(), visible_wall_count, active_wall_texture_label, "ON" if show_runtime_walls else "OFF", "ON" if show_quad_outlines else "OFF", "ON" if show_projection_points else "OFF", "ON" if integer_uv_scale_snap_enabled else "OFF", "ON" if wall_ewa_filter_enabled else "OFF", "ON" if wall_parallax_enabled and wall_height_image != null else "OFF", "ON" if parallax_tuner_open else "OFF"]
	status.text = status_text
	runtime_status.text = status_text

func _rebuild_runtime_wall_surfaces(entries: Array[Dictionary]) -> int:
	if wall_render_image == null or wall_render_texture == null or wall_source_image == null:
		return 0
	wall_render_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	# Entries are far-to-near, so nearer opaque texels naturally occlude farther
	# wall texels without requiring a separate depth buffer in this small test.
	for entry in entries:
		_rasterize_wall_entry(entry)
	wall_render_texture.update(wall_render_image)
	return entries.size()

func _rasterize_wall_entry(entry: Dictionary) -> void:
	var quad: PackedVector2Array = entry["quad"]
	if quad.size() != 4:
		return
	var inverse := _inverse_homography(quad[0], quad[1], quad[2], quad[3])
	if inverse.size() != 3:
		return
	var min_x := int(VIEW_SIZE.x) - 1
	var min_y := int(VIEW_SIZE.y) - 1
	var max_x := 0
	var max_y := 0
	for point in quad:
		min_x = mini(min_x, floori(point.x))
		min_y = mini(min_y, floori(point.y))
		max_x = maxi(max_x, ceili(point.x))
		max_y = maxi(max_y, ceili(point.y))
	min_x = clampi(min_x, 0, int(VIEW_SIZE.x) - 1)
	min_y = clampi(min_y, 0, int(VIEW_SIZE.y) - 1)
	max_x = clampi(max_x, 0, int(VIEW_SIZE.x) - 1)
	max_y = clampi(max_y, 0, int(VIEW_SIZE.y) - 1)
	var row0: Vector3 = inverse[0]
	var row1: Vector3 = inverse[1]
	var row2: Vector3 = inverse[2]
	var light := float(entry["light"])
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var uv := _inverse_homography_uv(row0, row1, row2, Vector2(x, y))
			if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
				continue
			var color := _sample_projected_wall(entry, row0, row1, row2, Vector2(x, y), uv)
			if color.a <= 0.0:
				continue
			color.r *= light
			color.g *= light
			color.b *= light
			wall_render_image.set_pixel(x, y, color)


# _inverse_homography_uv: Evaluates the inverse projective map at a screen
# pixel.  Keeping it separate lets the filter inspect neighboring UVs without
# changing any of the quad geometry or visibility code.
func _inverse_homography_uv(row0: Vector3, row1: Vector3, row2: Vector3, pixel: Vector2) -> Vector2:
	var denominator := row2.x * pixel.x + row2.y * pixel.y + row2.z
	if absf(denominator) < 0.00001:
		return Vector2(-1.0, -1.0)
	return Vector2(
		(row0.x * pixel.x + row0.y * pixel.y + row0.z) / denominator,
		(row1.x * pixel.x + row1.y * pixel.y + row1.z) / denominator
	)


# _sample_projected_wall: Samples the master texture according to the local
# screen-to-texture footprint.  The default branch preserves old nearest
# sampling exactly; the two experiments only alter this final lookup.
func _sample_projected_wall(entry: Dictionary, row0: Vector3, row1: Vector3, row2: Vector3, pixel: Vector2, uv: Vector2) -> Color:
	if wall_source_image == null:
		return Color.TRANSPARENT
	var sample_uv := _parallax_occlusion_uv(entry, uv)
	if sample_uv.x < 0.0 or sample_uv.x > 1.0 or sample_uv.y < 0.0 or sample_uv.y > 1.0:
		return Color.TRANSPARENT
	if not integer_uv_scale_snap_enabled and not wall_ewa_filter_enabled:
		return _sample_image_nearest(wall_source_image, sample_uv)
	var uv_x := _inverse_homography_uv(row0, row1, row2, pixel + Vector2.RIGHT)
	var uv_y := _inverse_homography_uv(row0, row1, row2, pixel + Vector2.DOWN)
	if uv_x.x < 0.0 or uv_y.x < 0.0:
		return _sample_image_nearest(wall_source_image, sample_uv)
	var source_size := Vector2(wall_source_image.get_width(), wall_source_image.get_height())
	var texel_span_x := (uv_x - uv) * source_size
	var texel_span_y := (uv_y - uv) * source_size
	var length_x := texel_span_x.length()
	var length_y := texel_span_y.length()
	var minor_footprint := maxf(1.0, minf(length_x, length_y))
	if integer_uv_scale_snap_enabled:
		minor_footprint = maxf(1.0, roundf(minor_footprint))
	var mip_level := _mip_level_for_footprint(minor_footprint)
	var source := wall_mip_images[mip_level] if not wall_mip_images.is_empty() else wall_source_image
	if not wall_ewa_filter_enabled:
		return _sample_image_nearest(source, sample_uv)
	# A wall's compressed source axis is not fixed in screen coordinates.  The
	# inverse homography tells us its local major axis, so these weighted taps
	# naturally run vertically into depth on straight walls and rotate correctly
	# on oblique walls (the counterpart of a floor anisotropic filter).
	var major_uv := (uv_x - uv) if length_x >= length_y else (uv_y - uv)
	var major_length := maxf(length_x, length_y)
	var sample_count := clampi(ceili(major_length / minor_footprint), 1, 8)
	if sample_count == 1:
		return _sample_image_nearest(source, sample_uv)
	var accumulated := Color(0.0, 0.0, 0.0, 0.0)
	var total_weight := 0.0
	for index in range(sample_count):
		var t := (float(index) + 0.5) / float(sample_count) - 0.5
		var tap_uv := sample_uv + major_uv * t
		if tap_uv.x < 0.0 or tap_uv.x > 1.0 or tap_uv.y < 0.0 or tap_uv.y > 1.0:
			continue
		var weight := 1.0 - absf(t) * 1.5
		accumulated += _sample_image_nearest(source, tap_uv) * weight
		total_weight += weight
	return accumulated / total_weight if total_weight > 0.0 else _sample_image_nearest(source, sample_uv)


# _parallax_occlusion_uv: Performs a deliberately shallow parallax-occlusion
# march through Runtime_Master_Wall_Main_height.  The adjustable anchor tone
# chooses the stationary greyscale: with black at 0.0, white moves along the
# ray; with white at 1.0, black moves in the opposite direction; a grey anchor
# sends lighter and darker detail away from each other.  The texture ray is
# derived from the actual wall edge and view position, so relief grows while
# looking along a hallway wall and fades on a front-facing wall.
func _parallax_occlusion_uv(entry: Dictionary, base_uv: Vector2) -> Vector2:
	if not wall_parallax_enabled or wall_height_image == null or wall_source_image == null:
		return base_uv
	var first: Vector2 = entry.get("first_local", Vector2.ZERO)
	var second: Vector2 = entry.get("second_local", Vector2.ZERO)
	var tangent := second - first
	if tangent.length_squared() < 0.00001:
		return base_uv
	tangent = tangent.normalized()
	var center := (first + second) * 0.5
	var view_distance := maxf(center.length(), NEAR_CLIP)
	var sideways_view := clampf(-center.dot(tangent) / view_distance, -1.0, 1.0)
	var vertical_view := clampf((VIRTUAL_CAMERA_HEIGHT - WALL_HEIGHT * 0.5) / maxf(center.y, NEAR_CLIP), -0.35, 0.35)
	var max_offset := Vector2(
		sideways_view * parallax_side_multiplier * parallax_max_texels / float(wall_source_image.get_width()),
		vertical_view * parallax_vertical_multiplier * parallax_max_texels / float(wall_source_image.get_height())
	)
	if max_offset.length_squared() < 0.0000001:
		return base_uv
	var uv := base_uv
	var signed_march_depth := 0.0
	var depth_step := 1.0 / float(parallax_layer_count)
	var uv_step := max_offset / float(parallax_layer_count)
	for _layer in range(parallax_layer_count):
		var height := pow(_sample_image_nearest(wall_height_image, uv).r, parallax_height_gamma)
		var relative_height := height - parallax_height_anchor
		if absf(signed_march_depth) >= absf(relative_height):
			break
		var direction := 1.0 if relative_height >= 0.0 else -1.0
		# The anchor gives each tone a signed travel direction.  At the default
		# black anchor this is the original white-moves behavior; moving the anchor
		# toward white instead keeps bright relief stable and exposes dark recesses.
		var next_uv := uv + uv_step * direction
		if next_uv.x < 0.0 or next_uv.x > 1.0 or next_uv.y < 0.0 or next_uv.y > 1.0:
			break
		uv = next_uv
		signed_march_depth += depth_step * direction
	return uv


func _sample_image_nearest(image: Image, uv: Vector2) -> Color:
	var sample_x := clampi(floori(uv.x * float(image.get_width() - 1)), 0, image.get_width() - 1)
	var sample_y := clampi(floori(uv.y * float(image.get_height() - 1)), 0, image.get_height() - 1)
	return image.get_pixel(sample_x, sample_y)


func _mip_level_for_footprint(footprint: float) -> int:
	if wall_mip_images.is_empty() or footprint <= 1.0:
		return 0
	var level := floori(log(footprint) / log(2.0))
	return clampi(level, 0, wall_mip_images.size() - 1)


# _rebuild_wall_mip_chain: Builds small CPU mip levels once per source-texture
# change.  The 160×120 render then reads these prefiltered images instead of
# averaging full-resolution texels every output pixel.
func _rebuild_wall_mip_chain() -> void:
	wall_mip_images.clear()
	if wall_source_image == null:
		return
	var current := wall_source_image
	wall_mip_images.append(current)
	while current.get_width() > 1 or current.get_height() > 1:
		var next_width := maxi(1, current.get_width() / 2)
		var next_height := maxi(1, current.get_height() / 2)
		var next := Image.create(next_width, next_height, false, Image.FORMAT_RGBA8)
		for y in range(next_height):
			for x in range(next_width):
				var color_sum := Color(0.0, 0.0, 0.0, 0.0)
				var samples := 0
				for offset_y in range(2):
					for offset_x in range(2):
						var source_x := mini(current.get_width() - 1, x * 2 + offset_x)
						var source_y := mini(current.get_height() - 1, y * 2 + offset_y)
						color_sum += current.get_pixel(source_x, source_y)
						samples += 1
				next.set_pixel(x, y, color_sum / float(samples))
		wall_mip_images.append(next)
		current = next

func _visible_wall_entries() -> Array[Dictionary]:
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	var camera_origin := _runtime_camera_origin(forward, right)
	var result: Array[Dictionary] = []
	# Reuse the controller's first-hit ray fan.  The old direct wall_edges walk
	# projected every physical edge in the cone, including walls hidden behind
	# nearer walls; that is why the green geometry could look perspectively right
	# while disagreeing with the playable top-down map.
	var physical_edges: Array = controller._visible_physical_wall_edges_for_basis(camera_origin, forward, right)
	for edge in physical_edges:
		var first_local := _to_view(Vector2(edge["a"]), camera_origin, forward, right)
		var second_local := _to_view(Vector2(edge["b"]), camera_origin, forward, right)
		if not _edge_can_be_seen(first_local, second_local):
			continue
		var quad := _project_wall_quad(first_local, second_local)
		var average_depth := (maxf(first_local.y, NEAR_CLIP) + maxf(second_local.y, NEAR_CLIP)) * 0.5
		result.append({
			"quad": quad,
			"first_local": first_local,
			"second_local": second_local,
			"depths": Vector2(maxf(first_local.y, NEAR_CLIP), maxf(second_local.y, NEAR_CLIP)),
			"depth": average_depth,
			"light": _depth_light(average_depth),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["depth"]) > float(b["depth"]))
	return result.slice(0, MAX_WALLS)

func _wall_edge_points(cell: Vector2i, edge: int) -> Array[Vector2]:
	match edge:
		0: return [Vector2(cell.x, cell.y), Vector2(cell.x + 1, cell.y)]
		1: return [Vector2(cell.x + 1, cell.y), Vector2(cell.x + 1, cell.y + 1)]
		2: return [Vector2(cell.x + 1, cell.y + 1), Vector2(cell.x, cell.y + 1)]
		_: return [Vector2(cell.x, cell.y + 1), Vector2(cell.x, cell.y)]

func _to_view(point: Vector2, origin: Vector2, forward: Vector2, right: Vector2) -> Vector2:
	var relative := point - origin
	return Vector2(relative.dot(right), relative.dot(forward))

func _edge_can_be_seen(first: Vector2, second: Vector2) -> bool:
	var samples := [first, second, (first + second) * 0.5]
	for sample in samples:
		if sample.y > NEAR_CLIP and sample.y < MAX_DEPTH and absf(sample.x / sample.y) < FOV_RATIO:
			return true
	return false

func _project_wall_quad(first: Vector2, second: Vector2) -> PackedVector2Array:
	# Vertex order follows the source wall texture: top-left, top-right,
	# bottom-right, bottom-left.  Each projected world vertical stays vertical
	# because yaw is the only camera rotation.
	var top_a := _project_view_point(first, WALL_HEIGHT)
	var top_b := _project_view_point(second, WALL_HEIGHT)
	var bottom_b := _project_view_point(second, 0.0)
	var bottom_a := _project_view_point(first, 0.0)
	return PackedVector2Array([top_a, top_b, bottom_b, bottom_a])

func _project_view_point(point: Vector2, world_height: float) -> Vector2:
	var depth := maxf(point.y, NEAR_CLIP)
	return Vector2(
		VIEW_SIZE.x * 0.5 + point.x / depth * FOCAL_LENGTH,
		HORIZON_Y + (VIRTUAL_CAMERA_HEIGHT - world_height) / depth * FOCAL_LENGTH
	)

func _template_camera_origin(forward: Vector2) -> Vector2:
	# Mirror Blender's Camera_Pivot/camera-child layout exactly: rotate around
	# the current cell centre while the level camera remains 0.49 cells behind
	# that pivot.  The original controller uses 0.46 for its sprite renderer;
	# that is intentionally not reused for authored coordinate-frame matching.
	var center := Vector2(controller.grid_position) + Vector2(0.5, 0.5)
	return center - forward.normalized() * TEMPLATE_CAMERA_REAR_OFFSET

func _runtime_camera_origin(forward: Vector2, right: Vector2) -> Vector2:
	# Stable poses use the Blender-calibrated camera.  The existing controller
	# only stores authored transition stage numbers, so this renderer turns those
	# stages into the matching camera positions before projecting walls.  Without
	# this offset, the coordinate image changed but the wall pass stayed frozen at
	# the source cell until the final grid-position snap.
	var origin := _template_camera_origin(forward)
	if int(controller.forward_step) != 0:
		var forward_fraction := 0.25 if int(controller.forward_step) == 1 else 0.50
		if String(controller.forward_transition_name) == "backward":
			forward_fraction = -forward_fraction
		return origin + forward * forward_fraction
	if int(controller.strafe_step) != 0:
		var chronological_stage := 4 - int(controller.strafe_step) if String(controller.strafe_transition_name) == "strafe_left" else int(controller.strafe_step)
		var strafe_fraction: float = [0.25, 0.50, 0.75][chronological_stage - 1]
		if String(controller.strafe_transition_name) == "strafe_left":
			strafe_fraction = -strafe_fraction
		return origin + right * strafe_fraction
	if diagonal_forward_active and diagonal_forward_source_cell.x > -900:
		var source_center := Vector2(diagonal_forward_source_cell) + Vector2(0.5, 0.5)
		var target_center := Vector2(diagonal_forward_target_cell) + Vector2(0.5, 0.5)
		return (source_center.lerp(target_center, _diagonal_forward_fraction())) - forward * TEMPLATE_CAMERA_REAR_OFFSET
	return origin

func _depth_light(depth: float) -> float:
	# Four deliberate bands retain the older discrete arcade value ramp.
	if depth < 1.35: return 1.0
	if depth < 2.5: return 0.78
	if depth < 3.8: return 0.56
	return 0.36

func _inverse_homography(p00: Vector2, p10: Vector2, p11: Vector2, p01: Vector2) -> Array[Vector3]:
	var dx1 := p10.x - p11.x
	var dx2 := p01.x - p11.x
	var dx3 := p00.x - p10.x + p11.x - p01.x
	var dy1 := p10.y - p11.y
	var dy2 := p01.y - p11.y
	var dy3 := p00.y - p10.y + p11.y - p01.y
	var determinant := dx1 * dy2 - dx2 * dy1
	if absf(determinant) < 0.00001:
		return []
	var g := (dx3 * dy2 - dx2 * dy3) / determinant
	var h := (dx1 * dy3 - dx3 * dy1) / determinant
	var a := p10.x - p00.x + g * p10.x
	var b := p01.x - p00.x + h * p01.x
	var c := p00.x
	var d := p10.y - p00.y + g * p10.y
	var e := p01.y - p00.y + h * p01.y
	var f := p00.y
	var det := a * (e - f * h) - b * (d - f * g) + c * (d * h - e * g)
	if absf(det) < 0.00001:
		return []
	return [
		Vector3((e - f * h) / det, (c * h - b) / det, (b * f - c * e) / det),
		Vector3((f * g - d) / det, (a - c * g) / det, (c * d - a * f) / det),
		Vector3((d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det),
	]

func _pose_key() -> String:
	if int(controller.turn_step) == 1: return "turn N→22.5°"
	if int(controller.turn_step) == 2: return "turn NE 45°"
	if int(controller.turn_step) == 3: return "turn NE→66.5°"
	if int(controller.forward_step) == 1: return "forward quarter"
	if int(controller.forward_step) == 2: return "forward half"
	if int(controller.strafe_step) == 1: return "strafe quarter"
	if int(controller.strafe_step) == 2: return "strafe half"
	if int(controller.strafe_step) == 3: return "strafe three-quarter"
	return "stable"

func _coordinate_frame_for_current_pose() -> Dictionary:
	# These frames describe the screen-relative camera pose, not a particular
	# world compass direction.  One cardinal (N) and one diagonal (NE) template
	# therefore cover the equivalent screen pose in every compass rotation.
	# Local-left motion reuses the right-stride drawing mirrored horizontally.
	var flip_h := false
	if int(controller.turn_step) == 1:
		flip_h = int(controller.turn_45_direction) < 0
		return {"path": TEMPLATE_ROOT + "coord_turn_n_22p5.png", "flip_h": flip_h}
	if int(controller.turn_step) == 3:
		flip_h = int(controller.turn_45_direction) < 0
		return {"path": TEMPLATE_ROOT + "coord_turn_ne_66p5.png", "flip_h": flip_h}

	# Step 2 is the stable mobile diagonal camera, not an interruption of
	# movement.  Let it select its own authored forward/strafe coordinate frames.
	var diagonal := int(controller.turn_45_direction) != 0 and int(controller.turn_step) == 2
	if int(controller.forward_step) == 1:
		return {"path": TEMPLATE_ROOT + ("coord_ne_forward_quarter.png" if diagonal else "coord_n_forward_quarter.png"), "flip_h": false}
	if int(controller.forward_step) == 2:
		return {"path": TEMPLATE_ROOT + ("coord_ne_forward_half.png" if diagonal else "coord_n_forward_half.png"), "flip_h": false}
	if diagonal:
		var diagonal_forward_frame := _diagonal_forward_frame_name()
		if not diagonal_forward_frame.is_empty():
			return {"path": TEMPLATE_ROOT + diagonal_forward_frame, "flip_h": false}
	if int(controller.strafe_step) != 0:
		flip_h = String(controller.strafe_transition_name) == "strafe_left"
		var stage_name: String = ["", "quarter", "half", "three_quarter"][int(controller.strafe_step)]
		var prefix := "coord_ne_right_se_" if diagonal else "coord_n_strafe_east_"
		return {"path": TEMPLATE_ROOT + prefix + stage_name + ".png", "flip_h": flip_h}
	return {"path": TEMPLATE_ROOT + ("coord_ne_stable.png" if diagonal else "coord_n_stable.png"), "flip_h": false}

func _diagonal_forward_frame_name() -> String:
	# The existing diagonal controller crosses a cell continuously, with no
	# forward_step state.  This experiment supplies the matching visual stages
	# from a small clock that starts on a diagonal-forward input and resets when
	# the world cell changes.
	if not diagonal_forward_active:
		return ""
	if diagonal_forward_clock < DIAGONAL_FRAME_SECONDS:
		return "coord_ne_forward_quarter.png"
	if diagonal_forward_clock < DIAGONAL_FRAME_SECONDS * 2.0:
		return "coord_ne_forward_half.png"
	if diagonal_forward_clock < DIAGONAL_FRAME_SECONDS * 3.0:
		return "coord_ne_forward_three_quarter.png"
	return ""

func _diagonal_forward_fraction() -> float:
	if not diagonal_forward_active:
		return 0.0
	if diagonal_forward_clock < DIAGONAL_FRAME_SECONDS:
		return 0.25
	if diagonal_forward_clock < DIAGONAL_FRAME_SECONDS * 2.0:
		return 0.50
	return 0.75

func _update_diagonal_forward_animation(delta: float) -> void:
	var diagonal := int(controller.turn_45_direction) != 0 and int(controller.turn_step) == 2
	if not diagonal:
		diagonal_forward_clock = 0.0
		diagonal_forward_active = false
		diagonal_forward_cell = controller.grid_position
		return
	if diagonal_forward_cell.x < -900:
		diagonal_forward_cell = controller.grid_position
		return
	# A diagonal forward sequence belongs to one actual diagonal cell crossing,
	# not to the duration of a held stick.  The old looping clock restarted these
	# three images over and over while the character ran inside a cell.
	var crossed_cells: Vector2i = controller.grid_position - diagonal_forward_cell
	if abs(crossed_cells.x) == 1 and abs(crossed_cells.y) == 1:
		diagonal_forward_source_cell = diagonal_forward_cell
		diagonal_forward_target_cell = controller.grid_position
		diagonal_forward_clock = 0.0
		diagonal_forward_active = true
		diagonal_forward_cell = controller.grid_position
	elif crossed_cells != Vector2i.ZERO:
		# Cardinal slides while looking diagonally do not use the NE-forward frames.
		diagonal_forward_cell = controller.grid_position
	if diagonal_forward_active:
		diagonal_forward_clock += delta
		if diagonal_forward_clock >= DIAGONAL_FRAME_SECONDS * 3.0:
			diagonal_forward_active = false
			diagonal_forward_clock = 0.0

func _update_coordinate_background() -> void:
	var frame := _coordinate_frame_for_current_pose()
	var path := String(frame["path"])
	var texture := _template_texture(path)
	# Retain the last valid coordinate image for the fraction of a frame during
	# any import/load delay.  A pose transition must never flash the blank legacy
	# playfield between authored coordinate images.
	if texture != null:
		coordinate_background.texture = texture
	coordinate_background.flip_h = bool(frame["flip_h"])
	coordinate_background.visible = coordinate_background.texture != null

func _hide_legacy_environment() -> void:
	for item in legacy_environment_nodes:
		if is_instance_valid(item):
			item.visible = false

func _preload_coordinate_templates() -> void:
	for file_name in [
		"coord_n_stable.png", "coord_n_forward_quarter.png", "coord_n_forward_half.png", "coord_n_forward_three_quarter.png", "coord_n_forward_next_cell.png",
		"coord_n_strafe_east_quarter.png", "coord_n_strafe_east_half.png", "coord_n_strafe_east_three_quarter.png", "coord_n_strafe_east_next_cell.png",
		"coord_n_diagonal_ne_quarter.png", "coord_n_diagonal_ne_half.png", "coord_n_diagonal_ne_three_quarter.png",
		"coord_ne_stable.png", "coord_ne_forward_quarter.png", "coord_ne_forward_half.png", "coord_ne_forward_three_quarter.png", "coord_ne_forward_next_cell.png",
		"coord_ne_right_se_quarter.png", "coord_ne_right_se_half.png", "coord_ne_right_se_three_quarter.png", "coord_ne_right_se_next_cell.png",
		"coord_ne_east_quarter.png", "coord_ne_east_half.png", "coord_ne_east_three_quarter.png", "coord_ne_east_next_cell.png",
		"coord_turn_n_22p5.png", "coord_turn_ne_66p5.png",
	]:
		var path: String = TEMPLATE_ROOT + String(file_name)
		var texture := load(path) as Texture2D
		if texture != null:
			template_textures[path] = texture

func _template_texture(path: String) -> Texture2D:
	var cached := template_textures.get(path) as Texture2D
	if cached != null:
		return cached
	# Do not leave a blank viewport if Godot's asynchronous import cache did not
	# populate this dictionary before a pose is first requested.
	var fallback := load(path) as Texture2D
	if fallback != null:
		template_textures[path] = fallback
	return fallback

func _update_debug_outlines(entries: Array[Dictionary]) -> void:
	_remove_environment_debug_node("CoordinateFrameQuadDebug")
	if not show_quad_outlines:
		return
	# Use only stock CanvasItems here.  The prior custom draw script could fail
	# while Godot was hot-reloading it, which made the Y diagnostic toggle able to
	# terminate the running game.  These child polygons/lines are equally clear
	# and have no runtime script state.
	var debug := Node2D.new()
	debug.name = "CoordinateFrameQuadDebug"
	debug.z_index = 61
	for entry in entries:
		var quad: PackedVector2Array = entry["quad"]
		var depth := float(entry["depth"])
		var light := clampf(1.0 - (depth - 0.3) / 5.3, 0.20, 1.0)
		var fill := Polygon2D.new()
		fill.polygon = quad
		fill.color = Color(0.03, 0.90 * light, 0.18 * light, 0.22)
		debug.add_child(fill)
		var outline := Line2D.new()
		outline.points = PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]])
		outline.width = 1.0
		outline.default_color = Color(0.05, 0.95 * light, 0.25 * light, 0.78)
		outline.antialiased = false
		debug.add_child(outline)
	controller.environment_layer.add_child(debug)

func _update_projection_point_debug() -> void:
	_remove_environment_debug_node("CoordinateFrameProjectionPoints")
	if not show_projection_points:
		return
	var frame := _coordinate_frame_for_current_pose()
	var expected := _red_control_points(_template_texture(String(frame["path"])))
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	var camera_origin := _runtime_camera_origin(forward, right)
	var projected: Array[Vector2] = []
	var anchor_x := floori(camera_origin.x)
	var anchor_y := floori(camera_origin.y)
	for world_y in range(anchor_y - 2, anchor_y + 8):
		for world_x in range(anchor_x - 6, anchor_x + 7):
			var local := _to_view(Vector2(world_x, world_y), camera_origin, forward, right)
			for height in [0.0, 1.0]:
				var point := _project_view_point(local, height)
				if Rect2(Vector2(-4, -4), VIEW_SIZE + Vector2(8, 8)).has_point(point):
					projected.append(point)
	var debug = preload("res://scripts/coordinate_frame_point_debug.gd").new()
	debug.name = "CoordinateFrameProjectionPoints"
	debug.z_index = 62
	debug.expected_points = expected
	debug.projected_points = projected
	controller.environment_layer.add_child(debug)

func _remove_environment_debug_node(node_name: String) -> void:
	# There may be legacy duplicates from the earlier deferred-cleanup version.
	# Free every matching node immediately before another debug redraw is added.
	for child in controller.environment_layer.get_children():
		if child.name == node_name:
			child.free()

func _red_control_points(texture: Texture2D) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if texture == null:
		return result
	var image := texture.get_image()
	if image == null:
		return result
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.7 and pixel.g < 0.35 and pixel.b < 0.35:
				result.append(Vector2(x, y))
	return result

func _render_signature() -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [controller.grid_position, controller.facing, controller.turn_step, controller.turn_45_direction, controller.forward_step, controller.forward_transition_name, controller.strafe_step, controller.strafe_transition_name, _diagonal_forward_fraction(), diagonal_forward_source_cell, controller.wall_edges.hash()]
