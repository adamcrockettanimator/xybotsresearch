# Isolated experimental wall renderer for the coordinate-frame navigation branch.
# It intentionally leaves the original sprite renderer and its slot graphs alone:
# this child only hides the old transparent wall sprites and composites one master
# wall texture through projective quads derived from the live grid camera basis.
extends Node

@export var target_player_index := 0

const VIEW_SIZE := Vector2(160.0, 120.0)
const WALL_LAYER1_PATH := "res://assets/Environment/Wall_Layer1.png"
const WALL_LAYER2_PATH := "res://assets/Environment/Wall_layer2.png"
const CEILING_LAYER1_PATH := "res://assets/Environment/ceiling_layer1.png"
const CEILING_LAYER2_PATH := "res://assets/Environment/ceiling_layer2.png"
const MASTER_WALL_PATH := WALL_LAYER1_PATH
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
const RUNTIME_FLOOR_TEXTURE_PATHS := [
	"res://assets/Environment/DirtRoad1.png",
	"res://assets/Environment/DirtRoad2.png",
	"res://assets/Environment/DirtRoad3.png",
	"res://assets/Environment/WoodFloor.png",
	"res://assets/Environment/WoodFloor2.png",
	"res://assets/Environment/SimpleWood.png",
]
const SHADER_PATH := "res://scripts/coordinate_frame_homography.gdshader"
const SINGLE_WALL_SHADER_PATH := "res://scripts/coordinate_frame_single_homography.gdshader"
const GPU_WALL_SHADER_PATH := "res://scripts/coordinate_frame_gpu_wall_homography.gdshader"
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
const PROFILE_LOG_PATH := "user://coordinate_runtime_profile.csv"
const PROFILE_LOG_INTERVAL_USEC := 1_000_000

var controller: Node
var runtime_floor_layer: Node2D
var floor_art_sprite: Sprite2D
var floor_render_image: Image
var floor_render_texture: ImageTexture
var floor_source_image: Image
var floor_mip_images: Array[Image] = []
var runtime_ceiling_layer: Node2D
var ceiling_art_sprite: Sprite2D
var ceiling_render_image: Image
var ceiling_render_texture: ImageTexture
var ceiling_layer1_image: Image
var ceiling_layer2_image: Image
var ceiling_layer1_mip_images: Array[Image] = []
var ceiling_layer2_mip_images: Array[Image] = []
var runtime_wall_layer: Node2D
var wall_art_sprite: Sprite2D
var wall_render_image: Image
var wall_render_texture: ImageTexture
var wall_source_image: Image
var wall_source_texture: Texture2D
var wall_height_image: Image
var wall_layer1_image: Image
var wall_layer2_image: Image
var wall_layer1_texture: Texture2D
var wall_layer2_texture: Texture2D
var gpu_wall_shader: Shader
var gpu_wall_dummy_texture: ImageTexture
var gpu_wall_sprites: Array[Sprite2D] = []
var gpu_wall_materials: Array[ShaderMaterial] = []
var coordinate_background: Sprite2D
var status: Label
var runtime_status: Label
var parallax_tuner_panel: PanelContainer
var parallax_tuner_canvas_layer: CanvasLayer
var parallax_tuner_open := false
var last_signature := ""
var show_runtime_walls := true
var show_quad_outlines := false
var show_projection_points := false
var master_texture: Texture2D
var debug_wall_texture_index := -1
var runtime_master_wall_texture_index := -1
var active_wall_texture_label := "StripeTest"
var active_floor_texture_label := "WoodFloor2"
# Start the experiment with the wood floor selected; M still cycles through the
# full diagnostic floor list without rebuilding the maze or wall layout.
var floor_texture_index := 4
var last_wall_entries: Array[Dictionary] = []
var wall_mip_images: Array[Image] = []
var wall_layer1_mip_images: Array[Image] = []
var wall_layer2_mip_images: Array[Image] = []
var integer_uv_scale_snap_enabled := false
var wall_ewa_filter_enabled := false
var wall_parallax_enabled := true
var gpu_wall_renderer_enabled := true
var parallax_max_texels := 4.0
var parallax_side_multiplier := 1.0
var parallax_vertical_multiplier := 1.0
var layer_movement_balance := 1.0
var layer_uv_edge_clamp_enabled := true
var ceiling_parallax_enabled := true
var ceiling_parallax_max_texels := 4.0
var ceiling_parallax_side_multiplier := 1.0
var ceiling_parallax_depth_multiplier := 1.0
var ceiling_layer_movement_balance := 1.0
var template_textures: Dictionary = {}
var legacy_environment_nodes: Array[CanvasItem] = []
var diagonal_forward_clock := 0.0
var diagonal_forward_active := false
var diagonal_forward_cell := Vector2i(-999, -999)
var diagonal_forward_source_cell := Vector2i(-999, -999)
var diagonal_forward_target_cell := Vector2i(-999, -999)
var initialized := false

# Rolling development profiler.  The renderer intentionally records timings in
# microseconds because this experiment's costly work happens in short bursts
# whenever a pose changes, rather than as one uniform GPU draw call.
var profile_pending_legacy_us := 0
var profile_floor_raster_us := 0
var profile_ceiling_raster_us := 0
var profile_wall_raster_us := 0
var profile_upload_us := 0
var profile_background_us := 0
var profile_rebuild_us := 0
var profile_window_start_us := 0
var profile_sample_count := 0
var profile_total_sum_us := 0
var profile_legacy_sum_us := 0
var profile_background_sum_us := 0
var profile_floor_sum_us := 0
var profile_ceiling_sum_us := 0
var profile_wall_sum_us := 0
var profile_upload_sum_us := 0
var profile_rebuild_sum_us := 0
var profile_total_peak_us := 0
var profile_rebuild_peak_us := 0

func _ready() -> void:
	call_deferred("_initialize")

func _initialize() -> void:
	controller = get_parent()
	if controller == null:
		push_error("Coordinate-frame renderer requires the existing controller as its parent.")
		return
	if target_player_index < 0 or target_player_index >= controller.player_views.size():
		push_error("Coordinate-frame renderer was attached before player %d exists." % target_player_index)
		return
	if target_player_index == 0:
		_reset_profile_log()
	# All construction below deliberately uses the controller's currently-bound
	# environment globals.  Bind only our assigned local view, then restore P1
	# afterwards; normal per-frame drawing is performed by the controller hook.
	controller._bind_player_context(target_player_index)
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
	# Floors use the same derived camera basis as the walls, but render beneath
	# them.  This is deliberately a separate native-resolution image so cycling
	# a floor texture never rebuilds the maze or invalidates wall visibility.
	runtime_floor_layer = Node2D.new()
	runtime_floor_layer.name = "CoordinateFrameHomographyFloors"
	runtime_floor_layer.z_index = 1
	_load_floor_source_texture(String(RUNTIME_FLOOR_TEXTURE_PATHS[floor_texture_index]))
	floor_render_image = Image.create(int(VIEW_SIZE.x), int(VIEW_SIZE.y), false, Image.FORMAT_RGBA8)
	floor_render_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	floor_render_texture = ImageTexture.create_from_image(floor_render_image)
	floor_art_sprite = Sprite2D.new()
	floor_art_sprite.name = "CoordinateFrameFloorArt"
	floor_art_sprite.centered = false
	floor_art_sprite.texture = floor_render_texture
	floor_art_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	runtime_floor_layer.add_child(floor_art_sprite)
	controller.environment_layer.add_child(runtime_floor_layer)
	# Like walls, the ceiling is an authored opaque base plus a transparent
	# foreground surface.  It remains a separate pass because its projection is
	# a horizontal plane rather than a vertical wall quad.
	runtime_ceiling_layer = Node2D.new()
	runtime_ceiling_layer.name = "CoordinateFrameHomographyCeilings"
	runtime_ceiling_layer.z_index = 2
	_load_runtime_ceiling_layers()
	ceiling_render_image = Image.create(int(VIEW_SIZE.x), int(VIEW_SIZE.y), false, Image.FORMAT_RGBA8)
	ceiling_render_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	ceiling_render_texture = ImageTexture.create_from_image(ceiling_render_image)
	ceiling_art_sprite = Sprite2D.new()
	ceiling_art_sprite.name = "CoordinateFrameCeilingArt"
	ceiling_art_sprite.centered = false
	ceiling_art_sprite.texture = ceiling_render_texture
	ceiling_art_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	runtime_ceiling_layer.add_child(ceiling_art_sprite)
	controller.environment_layer.add_child(runtime_ceiling_layer)
	# The wall pass is deliberately CPU-rasterized at the native 160x120 template
	# resolution.  That makes the projective mapping deterministic on this GPU,
	# retains the deliberately coarse pixel sampling, and avoids the D3D12 canvas
	# shader failure from the previous fullscreen-polygon experiment.
	runtime_wall_layer = Node2D.new()
	runtime_wall_layer.name = "CoordinateFrameHomographyWalls"
	runtime_wall_layer.z_index = 8
	# Runtime_Master_Wall is already the exact 128x88 master canvas.  The older
	# source sat inside a 160x120 authored sprite sheet and needed cropping.
	wall_source_texture = master_texture
	wall_source_image = master_texture.get_image()
	_load_runtime_wall_layers()
	active_wall_texture_label = "Wall_Layer1 + Layer2"
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
	_initialize_gpu_wall_renderer()
	controller.environment_layer.add_child(runtime_wall_layer)

	# The previous in-playfield caption was being scaled with the 160×120 view,
	# making it blurry and colliding with the player.  Retain a status node for
	# the renderer but keep it hidden; the readable CanvasLayer line below is the
	# sole on-screen readout.
	status = Label.new()
	status.visible = false
	# Keep one shared status and tuning panel, anchored by player one.  Creating
	# those UI controls for player two would duplicate them over the shared map.
	if target_player_index == 0:
		runtime_status = Label.new()
		runtime_status.position = Vector2(12, 78)
		runtime_status.add_theme_font_size_override("font_size", 14)
		runtime_status.add_theme_color_override("font_color", Color.WHITE)
		runtime_status.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		runtime_status.add_theme_constant_override("outline_size", 3)
		controller.canvas_layer.add_child(runtime_status)
		_setup_parallax_tuner()
	initialized = true
	_rebuild()
	controller._bind_player_context(0)

func _process(delta: float) -> void:
	# Rendering is driven by the controller's per-player pass below.  That avoids
	# a child renderer rebinding the other player's legacy globals after a frame.
	pass


# render_bound_player_context: Rebuild this compositor only while the controller
# has the matching player state and environment layer bound.
func render_bound_player_context(delta: float) -> void:
	if not initialized or controller == null or int(controller.active_player_index) != target_player_index:
		return
	var frame_started_us := Time.get_ticks_usec()
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
	var background_started_us := Time.get_ticks_usec()
	_update_coordinate_background()
	profile_background_us = Time.get_ticks_usec() - background_started_us
	var signature := _render_signature()
	profile_floor_raster_us = 0
	profile_ceiling_raster_us = 0
	profile_wall_raster_us = 0
	profile_upload_us = 0
	profile_rebuild_us = 0
	if signature != last_signature:
		_rebuild()
	_profile_record_frame(Time.get_ticks_usec() - frame_started_us)


# record_legacy_render_time: Called by the controller after its original
# sprite/debug render pass, before this coordinate compositor replaces it.
func record_legacy_render_time(elapsed_us: int) -> void:
	profile_pending_legacy_us = maxi(0, elapsed_us)


# _reset_profile_log: Starts a fresh, easily inspectable CSV for the current run.
func _reset_profile_log() -> void:
	var file := FileAccess.open(PROFILE_LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not create coordinate runtime profile log: %s" % ProjectSettings.globalize_path(PROFILE_LOG_PATH))
		return
	file.store_line("elapsed_s,player,samples,avg_total_ms,peak_total_ms,avg_legacy_ms,avg_background_ms,avg_floor_ms,avg_ceiling_ms,avg_wall_ms,avg_upload_ms,avg_rebuild_ms,peak_rebuild_ms")
	file.close()
	print("Coordinate runtime profile log: %s" % ProjectSettings.globalize_path(PROFILE_LOG_PATH))


# _profile_record_frame: Adds one renderer frame to a one-second rolling sample.
func _profile_record_frame(total_us: int) -> void:
	var now_us := Time.get_ticks_usec()
	if profile_window_start_us == 0:
		profile_window_start_us = now_us
	profile_sample_count += 1
	profile_total_sum_us += total_us
	profile_legacy_sum_us += profile_pending_legacy_us
	profile_background_sum_us += profile_background_us
	profile_floor_sum_us += profile_floor_raster_us
	profile_ceiling_sum_us += profile_ceiling_raster_us
	profile_wall_sum_us += profile_wall_raster_us
	profile_upload_sum_us += profile_upload_us
	profile_rebuild_sum_us += profile_rebuild_us
	profile_total_peak_us = maxi(profile_total_peak_us, total_us)
	profile_rebuild_peak_us = maxi(profile_rebuild_peak_us, profile_rebuild_us)
	if now_us - profile_window_start_us < PROFILE_LOG_INTERVAL_USEC:
		return
	_append_profile_sample(float(now_us - profile_window_start_us) / 1_000_000.0)
	profile_window_start_us = now_us
	profile_sample_count = 0
	profile_total_sum_us = 0
	profile_legacy_sum_us = 0
	profile_background_sum_us = 0
	profile_floor_sum_us = 0
	profile_ceiling_sum_us = 0
	profile_wall_sum_us = 0
	profile_upload_sum_us = 0
	profile_rebuild_sum_us = 0
	profile_total_peak_us = 0
	profile_rebuild_peak_us = 0


# _append_profile_sample: Writes averages and spikes so quiet and moving poses are both diagnosable.
func _append_profile_sample(elapsed_seconds: float) -> void:
	if profile_sample_count <= 0:
		return
	var divisor := float(profile_sample_count) * 1000.0
	var file := FileAccess.open(PROFILE_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("%.3f,%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [elapsed_seconds, target_player_index + 1, profile_sample_count, profile_total_sum_us / divisor, float(profile_total_peak_us) / 1000.0, profile_legacy_sum_us / divisor, profile_background_sum_us / divisor, profile_floor_sum_us / divisor, profile_ceiling_sum_us / divisor, profile_wall_sum_us / divisor, profile_upload_sum_us / divisor, profile_rebuild_sum_us / divisor, float(profile_rebuild_peak_us) / 1000.0])
	file.close()

func _input(event: InputEvent) -> void:
	# The two local compositors receive the same input event.  Player one owns the
	# shared diagnostic controls so a single press cannot toggle each layer twice.
	if target_player_index != 0:
		return
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
		elif event.keycode == KEY_M:
			_cycle_floor_texture()
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
		elif event.keycode == KEY_C:
			set_ceiling_parallax_enabled(not ceiling_parallax_enabled)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_L:
			set_layer_uv_edge_clamp_enabled(not layer_uv_edge_clamp_enabled)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_O:
			_toggle_parallax_tuner()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_V:
			# Keep a live CPU fallback available while the GPU path is being
			# evaluated.  This is also useful for comparing the two projective
			# renderers without rerolling the map or moving either player.
			gpu_wall_renderer_enabled = not gpu_wall_renderer_enabled
			_rebuild_runtime_wall_surfaces(last_wall_entries)
			_refresh_runtime_status(last_wall_entries.size())
			get_viewport().set_input_as_handled()

func _rebuild() -> void:
	if runtime_wall_layer == null or runtime_floor_layer == null or runtime_ceiling_layer == null:
		return
	var rebuild_started_us := Time.get_ticks_usec()
	last_signature = _render_signature()
	var entries: Array[Dictionary] = _visible_wall_entries()
	last_wall_entries = entries
	var accepted_count := entries.size()
	_update_coordinate_background()
	_rebuild_runtime_floor_surfaces(_visible_floor_cells())
	_rebuild_runtime_ceiling_surfaces(_visible_ceiling_cells())
	_rebuild_runtime_wall_surfaces(entries)
	_update_debug_outlines(entries)
	_update_projection_point_debug()
	runtime_wall_layer.visible = show_runtime_walls
	_refresh_runtime_status(accepted_count)
	profile_rebuild_us = Time.get_ticks_usec() - rebuild_started_us

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


# _cycle_floor_texture: Change only the source bitmap used by the live floor
# pass.  The projected cells, player, camera pose, and wall layout all remain
# exactly where they are, making the dirt/wood comparison immediate.
func _cycle_floor_texture() -> void:
	floor_texture_index = (floor_texture_index + 1) % RUNTIME_FLOOR_TEXTURE_PATHS.size()
	_load_floor_source_texture(String(RUNTIME_FLOOR_TEXTURE_PATHS[floor_texture_index]))
	_rebuild_runtime_floor_surfaces(_visible_floor_cells())
	_refresh_runtime_status(last_wall_entries.size())


func _load_floor_source_texture(path: String) -> void:
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("Could not load runtime floor texture: %s" % path)
		return
	var image := texture.get_image()
	if image == null:
		push_error("Could not read runtime floor texture: %s" % path)
		return
	floor_source_image = image
	floor_mip_images = _build_mip_chain(floor_source_image)
	active_floor_texture_label = path.get_file().get_basename()


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
	wall_source_texture = next_texture
	wall_source_image = next_image
	_set_height_texture_for_color_path(path)
	active_wall_texture_label = path.get_file().get_basename()
	_rebuild_wall_mip_chain()
	_rebuild_runtime_wall_surfaces(last_wall_entries)
	_refresh_runtime_status(last_wall_entries.size())


# _load_runtime_wall_layers: Reads the two authored 128×88 surfaces once.  The
# base layer is opaque; the front layer's alpha is preserved and composited only
# after both images have received their individual view-dependent UV offsets.
func _load_runtime_wall_layers() -> void:
	wall_layer1_image = null
	wall_layer2_image = null
	wall_layer1_texture = load(WALL_LAYER1_PATH) as Texture2D
	wall_layer2_texture = load(WALL_LAYER2_PATH) as Texture2D
	if wall_layer1_texture == null or wall_layer2_texture == null:
		push_error("Could not load runtime wall layer textures.")
		return
	wall_layer1_image = wall_layer1_texture.get_image()
	wall_layer2_image = wall_layer2_texture.get_image()
	if wall_layer1_image == null or wall_layer2_image == null:
		push_error("Could not read runtime wall layer textures.")
		return
	if wall_layer1_image.get_size() != wall_layer2_image.get_size():
		push_error("Runtime wall layers must share the same dimensions.")
		wall_layer1_image = null
		wall_layer2_image = null
		return
	wall_layer1_mip_images = _build_mip_chain(wall_layer1_image)
	wall_layer2_mip_images = _build_mip_chain(wall_layer2_image)


# _initialize_gpu_wall_renderer: Builds a shared 160×120 carrier texture and
# loads the per-wall shader.  The carrier is only geometry; every actual wall
# texel comes from a shader uniform, so the master source texture remains loaded
# once and is shared by all visible projected walls.
func _initialize_gpu_wall_renderer() -> void:
	gpu_wall_shader = load(GPU_WALL_SHADER_PATH) as Shader
	if gpu_wall_shader == null:
		gpu_wall_renderer_enabled = false
		push_warning("GPU wall shader unavailable; using CPU wall rasterizer.")
		return
	var carrier := Image.create(int(VIEW_SIZE.x), int(VIEW_SIZE.y), false, Image.FORMAT_RGBA8)
	carrier.fill(Color.WHITE)
	gpu_wall_dummy_texture = ImageTexture.create_from_image(carrier)


# _can_use_gpu_wall_renderer: The custom CPU filtering experiments deliberately
# stay on their proven CPU implementation.  Normal nearest/layered rendering
# goes through the GPU projective pass.
func _can_use_gpu_wall_renderer() -> bool:
	return gpu_wall_renderer_enabled and gpu_wall_shader != null and gpu_wall_dummy_texture != null and not integer_uv_scale_snap_enabled and not wall_ewa_filter_enabled


# _set_gpu_wall_sprites_visible: Avoids destroying working GPU materials when a
# diagnostic filter requests the CPU fallback; they can be reused immediately.
func _set_gpu_wall_sprites_visible(visible: bool) -> void:
	for sprite in gpu_wall_sprites:
		if is_instance_valid(sprite):
			sprite.visible = visible


# _rebuild_gpu_wall_surfaces: Converts the existing accepted wall entries into
# one full-frame GPU canvas item each.  Far-to-near sibling ordering matches the
# CPU compositor's draw order, while each shader discards pixels outside its own
# homography, preserving wall occlusion without a CPU pixel loop.
func _rebuild_gpu_wall_surfaces(entries: Array[Dictionary]) -> int:
	if not _can_use_gpu_wall_renderer():
		return 0
	while gpu_wall_sprites.size() < entries.size():
		var sprite := Sprite2D.new()
		sprite.name = "GpuProjectedWall%02d" % gpu_wall_sprites.size()
		sprite.centered = false
		sprite.texture = gpu_wall_dummy_texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := ShaderMaterial.new()
		material.shader = gpu_wall_shader
		sprite.material = material
		runtime_wall_layer.add_child(sprite)
		gpu_wall_sprites.append(sprite)
		gpu_wall_materials.append(material)
	for index in range(gpu_wall_sprites.size()):
		var sprite := gpu_wall_sprites[index]
		if not is_instance_valid(sprite):
			continue
		var is_active := index < entries.size()
		sprite.visible = is_active
		if not is_active:
			continue
		var entry := entries[index]
		var quad: PackedVector2Array = entry["quad"]
		var inverse := _inverse_homography(quad[0], quad[1], quad[2], quad[3])
		if inverse.size() != 3:
			sprite.visible = false
			continue
		var material := gpu_wall_materials[index]
		var use_layers := wall_parallax_enabled and wall_layer1_texture != null and wall_layer2_texture != null
		var layer_offset := _layer_parallax_uv_offset(entry) if use_layers else Vector2.ZERO
		var layer1_weight := (layer_movement_balance - 1.0) * 0.5
		var layer2_weight := (layer_movement_balance + 1.0) * 0.5
		material.set_shader_parameter("inverse_row0", inverse[0])
		material.set_shader_parameter("inverse_row1", inverse[1])
		material.set_shader_parameter("inverse_row2", inverse[2])
		material.set_shader_parameter("wall_light", float(entry["light"]))
		material.set_shader_parameter("base_texture", wall_source_texture)
		material.set_shader_parameter("base_texture_size", Vector2(wall_source_image.get_width(), wall_source_image.get_height()))
		material.set_shader_parameter("use_layer_parallax", use_layers)
		material.set_shader_parameter("layer1_texture", wall_layer1_texture if wall_layer1_texture != null else wall_source_texture)
		material.set_shader_parameter("layer2_texture", wall_layer2_texture if wall_layer2_texture != null else wall_source_texture)
		material.set_shader_parameter("layer_texture_size", Vector2(wall_layer1_image.get_width(), wall_layer1_image.get_height()) if wall_layer1_image != null else Vector2(wall_source_image.get_width(), wall_source_image.get_height()))
		material.set_shader_parameter("layer1_offset", layer_offset * layer1_weight)
		material.set_shader_parameter("layer2_offset", layer_offset * layer2_weight)
		material.set_shader_parameter("clamp_layer_edges", layer_uv_edge_clamp_enabled)
		sprite.z_index = index
	wall_art_sprite.visible = false
	return entries.size()


# _load_runtime_ceiling_layers: Read the independently-authored ceiling base
# and transparent foreground once.  Their shared dimensions are important: the
# two images use the same ceiling-cell UV coordinates before their adjustable
# view-dependent offset is applied.
func _load_runtime_ceiling_layers() -> void:
	ceiling_layer1_image = null
	ceiling_layer2_image = null
	var layer1_texture := load(CEILING_LAYER1_PATH) as Texture2D
	var layer2_texture := load(CEILING_LAYER2_PATH) as Texture2D
	if layer1_texture == null or layer2_texture == null:
		push_error("Could not load runtime ceiling layer textures.")
		return
	ceiling_layer1_image = layer1_texture.get_image()
	ceiling_layer2_image = layer2_texture.get_image()
	if ceiling_layer1_image == null or ceiling_layer2_image == null:
		push_error("Could not read runtime ceiling layer textures.")
		return
	if ceiling_layer1_image.get_size() != ceiling_layer2_image.get_size():
		push_error("Runtime ceiling layers must share the same dimensions.")
		ceiling_layer1_image = null
		ceiling_layer2_image = null
		return
	ceiling_layer1_mip_images = _build_mip_chain(ceiling_layer1_image)
	ceiling_layer2_mip_images = _build_mip_chain(ceiling_layer2_image)


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


# set_ceiling_parallax_enabled: Retain the base ceiling texture but turn its
# independent transparent relief layer on/off for direct comparison.
func set_ceiling_parallax_enabled(enabled: bool) -> void:
	ceiling_parallax_enabled = enabled
	_rebuild_runtime_ceiling_surfaces(_visible_ceiling_cells())
	_refresh_runtime_status(last_wall_entries.size())


# set_layer_uv_edge_clamp_enabled: Extends an offset layer's outermost texel
# when its UV shift exits the source rectangle.  Unlike tiling, this never
# repeats windows or trim; it only prevents transparent fringe gaps at a wall.
func set_layer_uv_edge_clamp_enabled(enabled: bool) -> void:
	layer_uv_edge_clamp_enabled = enabled
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
	# The map and its debug drawing share the normal CanvasLayer and can paint
	# over ordinary Controls.  Keep this temporary live-tuning UI in a dedicated
	# higher CanvasLayer so it remains readable while the map is visible.
	parallax_tuner_canvas_layer = CanvasLayer.new()
	parallax_tuner_canvas_layer.name = "RuntimeLayerParallaxCanvas"
	parallax_tuner_canvas_layer.layer = 100
	controller.add_child(parallax_tuner_canvas_layer)
	parallax_tuner_panel = PanelContainer.new()
	parallax_tuner_panel.name = "RuntimeLayerParallaxTuner"
	# Keep the live material controls out of the 160×120 player view; the
	# top-down map is the appropriate temporary overlay surface for tuning.
	parallax_tuner_panel.position = Vector2(860.0, 104.0)
	parallax_tuner_panel.custom_minimum_size = Vector2(270.0, 0.0)
	parallax_tuner_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parallax_tuner_panel.z_index = 1000
	parallax_tuner_panel.z_as_relative = false
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.035, 0.055, 0.96)
	panel_style.border_color = Color(0.18, 0.82, 0.96, 0.95)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(3)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_bottom = 8.0
	parallax_tuner_panel.add_theme_stylebox_override("panel", panel_style)
	parallax_tuner_panel.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	parallax_tuner_panel.visible = false
	parallax_tuner_canvas_layer.add_child(parallax_tuner_panel)
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 3)
	parallax_tuner_panel.add_child(section)
	var heading := Label.new()
	heading.text = "RUNTIME LAYERS  [O closes]"
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", Color(0.30, 0.92, 1.0, 1.0))
	section.add_child(heading)
	var hint := Label.new()
	hint.text = "Layer 1 base + transparent Layer 2 • live tuning"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.88, 0.92, 0.98, 1.0))
	section.add_child(hint)
	_add_parallax_tuning_slider(section, "Layer separation", "depth", 0.0, 16.0, 0.25, parallax_max_texels, "px")
	_add_parallax_tuning_slider(section, "Movement balance", "balance", -1.0, 1.0, 0.05, layer_movement_balance, "")
	_add_parallax_tuning_slider(section, "Side response", "side", -2.0, 2.0, 0.05, parallax_side_multiplier, "x")
	_add_parallax_tuning_slider(section, "Vertical response", "vertical", -2.0, 2.0, 0.05, parallax_vertical_multiplier, "x")
	var ceiling_heading := Label.new()
	ceiling_heading.text = "CEILING LAYERS  [C toggles]"
	ceiling_heading.add_theme_font_size_override("font_size", 13)
	ceiling_heading.add_theme_color_override("font_color", Color(0.30, 0.92, 1.0, 1.0))
	section.add_child(ceiling_heading)
	_add_parallax_tuning_slider(section, "Ceiling separation", "ceiling_depth", 0.0, 16.0, 0.25, ceiling_parallax_max_texels, "px")
	_add_parallax_tuning_slider(section, "Ceiling movement balance", "ceiling_balance", -1.0, 1.0, 0.05, ceiling_layer_movement_balance, "")
	_add_parallax_tuning_slider(section, "Ceiling side response", "ceiling_side", -2.0, 2.0, 0.05, ceiling_parallax_side_multiplier, "x")
	_add_parallax_tuning_slider(section, "Ceiling depth response", "ceiling_forward", -2.0, 2.0, 0.05, ceiling_parallax_depth_multiplier, "x")


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
	value_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	parent.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(250.0, 18.0)
	slider.tooltip_text = "Live runtime-layer parallax tuning"
	parent.add_child(slider)
	_update_parallax_slider_label(value_label, title, initial, suffix)
	slider.value_changed.connect(func(value: float) -> void:
		_set_parallax_tuning_value(key, value)
		_update_parallax_slider_label(value_label, title, value, suffix)
	)


func _update_parallax_slider_label(label: Label, title: String, value: float, suffix: String) -> void:
	if title == "Movement balance" or title == "Ceiling movement balance":
		var balance_name := "Layer 1 moves" if value <= -0.99 else "Layer 2 moves" if value >= 0.99 else "split opposite"
		label.text = "Movement balance: %.2f (%s)" % [value, balance_name]
		return
	var formatted := "%d" % roundi(value) if suffix.is_empty() and title == "March layers" else "%.2f" % value
	label.text = "%s: %s%s" % [title, formatted, suffix]


func _set_parallax_tuning_value(key: String, value: float) -> void:
	match key:
		"depth": parallax_max_texels = value
		"side": parallax_side_multiplier = value
		"vertical": parallax_vertical_multiplier = value
		"balance": layer_movement_balance = value
		"ceiling_depth": ceiling_parallax_max_texels = value
		"ceiling_side": ceiling_parallax_side_multiplier = value
		"ceiling_forward": ceiling_parallax_depth_multiplier = value
		"ceiling_balance": ceiling_layer_movement_balance = value
	if key.begins_with("ceiling_"):
		_rebuild_runtime_ceiling_surfaces(_visible_ceiling_cells())
	else:
		_rebuild_runtime_wall_surfaces(last_wall_entries)
	_refresh_runtime_status(last_wall_entries.size())

func _refresh_runtime_status(visible_wall_count: int) -> void:
	var layer_mode_available := wall_layer1_image != null and wall_layer2_image != null
	var displayed_texture_label := "Wall_Layer1+Layer2" if wall_parallax_enabled and layer_mode_available else active_wall_texture_label
	var ceiling_layers_available := ceiling_layer1_image != null and ceiling_layer2_image != null
	var render_backend := "GPU" if _can_use_gpu_wall_renderer() else "CPU"
	var status_text := "Coord %s | %d walls | %s | Wall:%s [G/K] | Floor:%s [M]\nT:%s  Y:%s  U:%s  H:%s  J:%s  P:%s  C:%s  L:%s  O:%s  V:%s" % [_pose_key(), visible_wall_count, render_backend, displayed_texture_label, active_floor_texture_label, "ON" if show_runtime_walls else "OFF", "ON" if show_quad_outlines else "OFF", "ON" if show_projection_points else "OFF", "ON" if integer_uv_scale_snap_enabled else "OFF", "ON" if wall_ewa_filter_enabled else "OFF", "ON" if wall_parallax_enabled and layer_mode_available else "OFF", "ON" if ceiling_parallax_enabled and ceiling_layers_available else "OFF", "ON" if layer_uv_edge_clamp_enabled else "OFF", "ON" if parallax_tuner_open else "OFF", "ON" if gpu_wall_renderer_enabled else "OFF"]
	if is_instance_valid(status):
		status.text = status_text
	if is_instance_valid(runtime_status):
		runtime_status.text = status_text

func _rebuild_runtime_wall_surfaces(entries: Array[Dictionary]) -> int:
	if wall_render_image == null or wall_render_texture == null or wall_source_image == null:
		return 0
	if _can_use_gpu_wall_renderer():
		var gpu_started_us := Time.get_ticks_usec()
		var gpu_count := _rebuild_gpu_wall_surfaces(entries)
		# The visible raster work is now asynchronous GPU work.  Keep timing the
		# small uniform/sprite update so the CSV can show the CPU saving directly.
		profile_wall_raster_us = Time.get_ticks_usec() - gpu_started_us
		profile_upload_us = 0
		return gpu_count
	_set_gpu_wall_sprites_visible(false)
	wall_art_sprite.visible = true
	var raster_started_us := Time.get_ticks_usec()
	wall_render_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	# Entries are far-to-near, so nearer opaque texels naturally occlude farther
	# wall texels without requiring a separate depth buffer in this small test.
	for entry in entries:
		_rasterize_wall_entry(entry)
	profile_wall_raster_us = Time.get_ticks_usec() - raster_started_us
	var upload_started_us := Time.get_ticks_usec()
	wall_render_texture.update(wall_render_image)
	profile_upload_us += Time.get_ticks_usec() - upload_started_us
	return entries.size()


# _visible_floor_cells: Produces one projected quad per real maze cell using
# the exact same camera origin and yaw basis as _visible_wall_entries.  The
# authored red dots are therefore a diagnostic of this data, not a fragile
# requirement: cells touching the player or screen boundary remain valid even
# when their corner dots lie offscreen or behind a nearer wall.
func _visible_floor_cells() -> Array[Dictionary]:
	if controller == null:
		return []
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	var camera_origin := _runtime_camera_origin(forward, right)
	var result: Array[Dictionary] = []
	for y in range(int(controller.MAP_HEIGHT)):
		for x in range(int(controller.MAP_WIDTH)):
			var cell := Vector2i(x, y)
			var world_corners := [
				Vector2(cell.x, cell.y),
				Vector2(cell.x + 1, cell.y),
				Vector2(cell.x + 1, cell.y + 1),
				Vector2(cell.x, cell.y + 1),
			]
			var local_corners: Array[Vector2] = []
			var quad := PackedVector2Array()
			var nearest_depth := INF
			var farthest_depth := -INF
			for corner in world_corners:
				var local := _to_view(corner, camera_origin, forward, right)
				local_corners.append(local)
				nearest_depth = minf(nearest_depth, local.y)
				farthest_depth = maxf(farthest_depth, local.y)
				quad.append(_project_view_point(local, 0.0))
			# A cell wholly behind the level camera cannot contribute.  Do retain
			# cells that cross the near plane: their visible part is reconstructed
			# analytically in _rasterize_floor_cell instead of being dropped because
			# two authored dots are outside the frame.
			if farthest_depth <= 0.0 or nearest_depth >= MAX_DEPTH:
				continue
			var bounds := _quad_bounds(quad)
			if not bounds.intersects(Rect2(Vector2.ZERO, VIEW_SIZE)):
				continue
			result.append({
				"cell": cell,
				"quad": quad,
				"origin": camera_origin,
				"forward": forward,
				"right": right,
				"depth": clampf((maxf(nearest_depth, NEAR_CLIP) + maxf(farthest_depth, NEAR_CLIP)) * 0.5, NEAR_CLIP, MAX_DEPTH),
			})
	# Far-to-near retains predictable ownership at shared cell borders.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["depth"]) > float(b["depth"]))
	return result


func _quad_bounds(quad: PackedVector2Array) -> Rect2:
	if quad.is_empty():
		return Rect2()
	var minimum := quad[0]
	var maximum := quad[0]
	for point in quad:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


# _rebuild_runtime_floor_surfaces: Rasterizes the independent floor texture
# below the wall pass.  Its inverse mapping is the floor-plane form of the
# same homography used for a four-corner floor quad: screen pixels are returned
# to the world plane, then sampled from the owning cell's complete texture.
func _rebuild_runtime_floor_surfaces(entries: Array[Dictionary]) -> int:
	if floor_render_image == null or floor_render_texture == null or floor_source_image == null:
		return 0
	var raster_started_us := Time.get_ticks_usec()
	floor_render_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for entry in entries:
		_rasterize_floor_cell(entry)
	profile_floor_raster_us = Time.get_ticks_usec() - raster_started_us
	var upload_started_us := Time.get_ticks_usec()
	floor_render_texture.update(floor_render_image)
	profile_upload_us += Time.get_ticks_usec() - upload_started_us
	return entries.size()


func _rasterize_floor_cell(entry: Dictionary) -> void:
	var quad: PackedVector2Array = entry["quad"]
	if quad.size() != 4:
		return
	var bounds := _quad_bounds(quad)
	var min_x := clampi(floori(bounds.position.x), 0, int(VIEW_SIZE.x) - 1)
	var min_y := clampi(floori(bounds.position.y), 0, int(VIEW_SIZE.y) - 1)
	var max_x := clampi(ceili(bounds.end.x), 0, int(VIEW_SIZE.x) - 1)
	var max_y := clampi(ceili(bounds.end.y), 0, int(VIEW_SIZE.y) - 1)
	var cell: Vector2i = entry["cell"]
	var origin: Vector2 = entry["origin"]
	var forward: Vector2 = entry["forward"]
	var right: Vector2 = entry["right"]
	for y in range(min_y, max_y + 1):
		var vertical_screen_delta := float(y) - HORIZON_Y
		if vertical_screen_delta <= 0.0001:
			continue
		var depth := VIRTUAL_CAMERA_HEIGHT * FOCAL_LENGTH / vertical_screen_delta
		if depth <= 0.0 or depth > MAX_DEPTH:
			continue
		for x in range(min_x, max_x + 1):
			var side := (float(x) - VIEW_SIZE.x * 0.5) * depth / FOCAL_LENGTH
			var world := origin + right * side + forward * depth
			var uv := world - Vector2(cell)
			# Keep one exact cell owner per screen pixel.  This is also what makes
			# the near/offscreen player cell render correctly rather than requiring
			# four visible red control dots.
			if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
				continue
			var color := _sample_image_nearest(floor_source_image, uv)
			var light := _depth_light(depth)
			color.r *= light
			color.g *= light
			color.b *= light
			floor_render_image.set_pixel(x, y, color)


# _visible_ceiling_cells: Ceiling cells share the grid x/y footprint of their
# floor partners but use WALL_HEIGHT in the same two-point projection.  This is
# why a ceiling polygon lands on the Blender-derived upper wireframe without
# needing every upper red dot to remain visible.
func _visible_ceiling_cells() -> Array[Dictionary]:
	if controller == null:
		return []
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	var camera_origin := _runtime_camera_origin(forward, right)
	var result: Array[Dictionary] = []
	for y in range(int(controller.MAP_HEIGHT)):
		for x in range(int(controller.MAP_WIDTH)):
			var cell := Vector2i(x, y)
			var world_corners := [
				Vector2(cell.x, cell.y),
				Vector2(cell.x + 1, cell.y),
				Vector2(cell.x + 1, cell.y + 1),
				Vector2(cell.x, cell.y + 1),
			]
			var quad := PackedVector2Array()
			var nearest_depth := INF
			var farthest_depth := -INF
			for corner in world_corners:
				var local := _to_view(corner, camera_origin, forward, right)
				nearest_depth = minf(nearest_depth, local.y)
				farthest_depth = maxf(farthest_depth, local.y)
				quad.append(_project_view_point(local, WALL_HEIGHT))
			if farthest_depth <= 0.0 or nearest_depth >= MAX_DEPTH:
				continue
			if not _quad_bounds(quad).intersects(Rect2(Vector2.ZERO, VIEW_SIZE)):
				continue
			result.append({
				"cell": cell,
				"quad": quad,
				"origin": camera_origin,
				"forward": forward,
				"right": right,
				"depth": clampf((maxf(nearest_depth, NEAR_CLIP) + maxf(farthest_depth, NEAR_CLIP)) * 0.5, NEAR_CLIP, MAX_DEPTH),
			})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["depth"]) > float(b["depth"]))
	return result


# _rebuild_runtime_ceiling_surfaces: Reconstructs an upper horizontal plane at
# native resolution.  Wall/floor ordering is explicit: background → floor →
# ceiling → vertical walls → player/debug.
func _rebuild_runtime_ceiling_surfaces(entries: Array[Dictionary]) -> int:
	if ceiling_render_image == null or ceiling_render_texture == null or ceiling_layer1_image == null:
		return 0
	var raster_started_us := Time.get_ticks_usec()
	ceiling_render_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for entry in entries:
		_rasterize_ceiling_cell(entry)
	profile_ceiling_raster_us = Time.get_ticks_usec() - raster_started_us
	var upload_started_us := Time.get_ticks_usec()
	ceiling_render_texture.update(ceiling_render_image)
	profile_upload_us += Time.get_ticks_usec() - upload_started_us
	return entries.size()


func _rasterize_ceiling_cell(entry: Dictionary) -> void:
	var quad: PackedVector2Array = entry["quad"]
	if quad.size() != 4:
		return
	var bounds := _quad_bounds(quad)
	var min_x := clampi(floori(bounds.position.x), 0, int(VIEW_SIZE.x) - 1)
	var min_y := clampi(floori(bounds.position.y), 0, int(VIEW_SIZE.y) - 1)
	var max_x := clampi(ceili(bounds.end.x), 0, int(VIEW_SIZE.x) - 1)
	var max_y := clampi(ceili(bounds.end.y), 0, int(VIEW_SIZE.y) - 1)
	var cell: Vector2i = entry["cell"]
	var origin: Vector2 = entry["origin"]
	var forward: Vector2 = entry["forward"]
	var right: Vector2 = entry["right"]
	var layer_offset := _ceiling_parallax_uv_offset(cell, origin, forward, right)
	var layer1_weight := (ceiling_layer_movement_balance - 1.0) * 0.5
	var layer2_weight := (ceiling_layer_movement_balance + 1.0) * 0.5
	var height_delta := VIRTUAL_CAMERA_HEIGHT - WALL_HEIGHT
	for y in range(min_y, max_y + 1):
		var vertical_screen_delta := float(y) - HORIZON_Y
		if absf(vertical_screen_delta) <= 0.0001:
			continue
		var depth := height_delta * FOCAL_LENGTH / vertical_screen_delta
		if depth <= 0.0 or depth > MAX_DEPTH:
			continue
		for x in range(min_x, max_x + 1):
			var side := (float(x) - VIEW_SIZE.x * 0.5) * depth / FOCAL_LENGTH
			var world := origin + right * side + forward * depth
			var uv := world - Vector2(cell)
			if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
				continue
			var color := _sample_ceiling_layers(uv, layer_offset, layer1_weight, layer2_weight)
			if color.a <= 0.0:
				continue
			var light := _depth_light(depth)
			color.r *= light
			color.g *= light
			color.b *= light
			ceiling_render_image.set_pixel(x, y, color)


func _sample_ceiling_layers(uv: Vector2, layer_offset: Vector2, layer1_weight: float, layer2_weight: float) -> Color:
	if ceiling_layer1_image == null:
		return Color.TRANSPARENT
	if not ceiling_parallax_enabled or ceiling_layer2_image == null:
		return _sample_image_nearest(ceiling_layer1_image, uv)
	var bottom_uv := (uv + layer_offset * layer1_weight).clamp(Vector2.ZERO, Vector2.ONE)
	var top_uv := (uv + layer_offset * layer2_weight).clamp(Vector2.ZERO, Vector2.ONE)
	var bottom := _sample_image_nearest(ceiling_layer1_image, bottom_uv)
	var top := _sample_image_nearest(ceiling_layer2_image, top_uv)
	return _alpha_over(bottom, top)


# _ceiling_parallax_uv_offset: On a horizontal plane the meaningful obliqueness
# is the direction from the camera's floor footprint toward this cell.  The
# side and forward responses are independently exposed in the O panel.
func _ceiling_parallax_uv_offset(cell: Vector2i, origin: Vector2, forward: Vector2, right: Vector2) -> Vector2:
	if ceiling_layer1_image == null:
		return Vector2.ZERO
	var center_local := _to_view(Vector2(cell) + Vector2(0.5, 0.5), origin, forward, right)
	var view_distance := maxf(center_local.length(), NEAR_CLIP)
	return Vector2(
		center_local.x / view_distance * ceiling_parallax_side_multiplier * ceiling_parallax_max_texels / float(ceiling_layer1_image.get_width()),
		center_local.y / view_distance * ceiling_parallax_depth_multiplier * ceiling_parallax_max_texels / float(ceiling_layer1_image.get_height())
	)

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


# _sample_projected_wall: Projects two authored surfaces independently.  The
# visible base is Layer 1; transparent Layer 2 is then alpha-composited over
# it.  Their relative UV shift is driven solely by view obliqueness, not a
# height field, so an artist can control relief directly in the two bitmaps.
func _sample_projected_wall(entry: Dictionary, row0: Vector3, row1: Vector3, row2: Vector3, pixel: Vector2, uv: Vector2) -> Color:
	if wall_parallax_enabled and wall_layer1_image != null and wall_layer2_image != null:
		var view_offset := _layer_parallax_uv_offset(entry)
		# -1 = Layer 1 moves and Layer 2 stays; 0 = equal/opposite; +1 = Layer
		# 1 stays and Layer 2 moves.  This makes the requested movement sharing a
		# single continuous control rather than an all-or-nothing inversion.
		var layer1_weight := (layer_movement_balance - 1.0) * 0.5
		var layer2_weight := (layer_movement_balance + 1.0) * 0.5
		var bottom := _sample_projected_image(wall_layer1_image, wall_layer1_mip_images, row0, row1, row2, pixel, uv + view_offset * layer1_weight, layer_uv_edge_clamp_enabled)
		var top := _sample_projected_image(wall_layer2_image, wall_layer2_mip_images, row0, row1, row2, pixel, uv + view_offset * layer2_weight, layer_uv_edge_clamp_enabled)
		return _alpha_over(bottom, top)
	return _sample_projected_image(wall_source_image, wall_mip_images, row0, row1, row2, pixel, uv)


func _layer_parallax_uv_offset(entry: Dictionary) -> Vector2:
	var first: Vector2 = entry.get("first_local", Vector2.ZERO)
	var second: Vector2 = entry.get("second_local", Vector2.ZERO)
	var tangent := second - first
	if tangent.length_squared() < 0.00001 or wall_layer1_image == null:
		return Vector2.ZERO
	tangent = tangent.normalized()
	var center := (first + second) * 0.5
	var view_distance := maxf(center.length(), NEAR_CLIP)
	var sideways_view := clampf(-center.dot(tangent) / view_distance, -1.0, 1.0)
	var vertical_view := clampf((VIRTUAL_CAMERA_HEIGHT - WALL_HEIGHT * 0.5) / maxf(center.y, NEAR_CLIP), -0.35, 0.35)
	return Vector2(
		sideways_view * parallax_side_multiplier * parallax_max_texels / float(wall_layer1_image.get_width()),
		vertical_view * parallax_vertical_multiplier * parallax_max_texels / float(wall_layer1_image.get_height())
	)


func _sample_projected_image(source_image: Image, mip_chain: Array[Image], row0: Vector3, row1: Vector3, row2: Vector3, pixel: Vector2, sample_uv: Vector2, clamp_to_edge := false) -> Color:
	if source_image == null:
		return Color.TRANSPARENT
	if clamp_to_edge:
		sample_uv = sample_uv.clamp(Vector2.ZERO, Vector2.ONE)
	elif sample_uv.x < 0.0 or sample_uv.x > 1.0 or sample_uv.y < 0.0 or sample_uv.y > 1.0:
		return Color.TRANSPARENT
	if not integer_uv_scale_snap_enabled and not wall_ewa_filter_enabled:
		return _sample_image_nearest(source_image, sample_uv)
	var uv := _inverse_homography_uv(row0, row1, row2, pixel)
	var uv_x := _inverse_homography_uv(row0, row1, row2, pixel + Vector2.RIGHT)
	var uv_y := _inverse_homography_uv(row0, row1, row2, pixel + Vector2.DOWN)
	if uv_x.x < 0.0 or uv_y.x < 0.0:
		return _sample_image_nearest(source_image, sample_uv)
	var source_size := Vector2(source_image.get_width(), source_image.get_height())
	var texel_span_x := (uv_x - uv) * source_size
	var texel_span_y := (uv_y - uv) * source_size
	var length_x := texel_span_x.length()
	var length_y := texel_span_y.length()
	var minor_footprint := maxf(1.0, minf(length_x, length_y))
	if integer_uv_scale_snap_enabled:
		minor_footprint = maxf(1.0, roundf(minor_footprint))
	var mip_level := _mip_level_for_footprint(minor_footprint, mip_chain)
	var source := mip_chain[mip_level] if not mip_chain.is_empty() else source_image
	if not wall_ewa_filter_enabled:
		return _sample_image_nearest(source, sample_uv)
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
		if clamp_to_edge:
			tap_uv = tap_uv.clamp(Vector2.ZERO, Vector2.ONE)
		elif tap_uv.x < 0.0 or tap_uv.x > 1.0 or tap_uv.y < 0.0 or tap_uv.y > 1.0:
			continue
		var weight := 1.0 - absf(t) * 1.5
		accumulated += _sample_image_nearest(source, tap_uv) * weight
		total_weight += weight
	return accumulated / total_weight if total_weight > 0.0 else _sample_image_nearest(source, sample_uv)


func _alpha_over(bottom: Color, top: Color) -> Color:
	var output_alpha := top.a + bottom.a * (1.0 - top.a)
	if output_alpha <= 0.0:
		return Color.TRANSPARENT
	return Color(
		(top.r * top.a + bottom.r * bottom.a * (1.0 - top.a)) / output_alpha,
		(top.g * top.a + bottom.g * bottom.a * (1.0 - top.a)) / output_alpha,
		(top.b * top.a + bottom.b * bottom.a * (1.0 - top.a)) / output_alpha,
		output_alpha
	)


func _sample_image_nearest(image: Image, uv: Vector2) -> Color:
	var sample_x := clampi(floori(uv.x * float(image.get_width() - 1)), 0, image.get_width() - 1)
	var sample_y := clampi(floori(uv.y * float(image.get_height() - 1)), 0, image.get_height() - 1)
	return image.get_pixel(sample_x, sample_y)


func _mip_level_for_footprint(footprint: float, mip_chain: Array[Image]) -> int:
	if mip_chain.is_empty() or footprint <= 1.0:
		return 0
	var level := floori(log(footprint) / log(2.0))
	return clampi(level, 0, mip_chain.size() - 1)


# _rebuild_wall_mip_chain: Builds small CPU mip levels once per source-texture
# change.  The 160×120 render then reads these prefiltered images instead of
# averaging full-resolution texels every output pixel.
func _rebuild_wall_mip_chain() -> void:
	wall_mip_images = _build_mip_chain(wall_source_image)


func _build_mip_chain(source_image: Image) -> Array[Image]:
	var mip_chain: Array[Image] = []
	if source_image == null:
		return mip_chain
	var current := source_image
	mip_chain.append(current)
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
		mip_chain.append(next)
		current = next
	return mip_chain

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
		# Keep the source wall's complete physical endpoints.  A ray-visible span
		# may tell us that only half this wall is exposed, but shortening the quad
		# here incorrectly remaps the *entire* master texture into that half.  The
		# Canvas viewport naturally clips the projected offscreen portion instead.
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
