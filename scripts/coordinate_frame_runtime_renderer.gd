# Isolated experimental wall renderer for the coordinate-frame navigation branch.
# It intentionally leaves the original sprite renderer and its slot graphs alone:
# this child only hides the old transparent wall sprites and composites one master
# wall texture through projective quads derived from the live grid camera basis.
extends Node

@export var target_player_index := 0

const VIEW_SIZE := Vector2(160.0, 120.0)
const OVERSCAN_SIZE := Vector2(320.0, 240.0)
const OVERSCAN_STABLE_PATH := "res://assets/CoordinateFrames/coord_n_stable_overscan.png"
# The green rectangle in the user-authored overscan sheet records the exact
# legacy 160×120 coordinate frame.  Keeping this as the neutral crop makes the
# test fully reversible: with no crop motion, the runtime projection is pixel
# for pixel in its former place.
const OVERSCAN_REFERENCE_CROP_ORIGIN := Vector2(80.0, 32.0)
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
const GPU_PLANE_SHADER_PATH := "res://scripts/coordinate_frame_gpu_plane_homography.gdshader"
const SCREEN_OVERLAY_SHADER_PATH := "res://scripts/coordinate_frame_screen_overlay.gdshader"
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
const CAMERA_CUTAWAY_DITHER_HALF_WIDTH_PIXELS := 26.0
const CAMERA_CUTAWAY_DITHER_INNER_PIXELS := 10.0
const CAMERA_CUTAWAY_DITHER_FADE_PIXELS := 72.0
# Inset the moving PNG silhouette only at its left/right edges. This filters
# run-frame edge wobble against a side wall without moving the fan's rear base
# away from a wall directly behind the cowboy.
const CAMERA_CUTAWAY_SILHOUETTE_SIDE_GUARD_PIXELS := 4.0
const HORIZON_Y := 31.5
## These are the Blender rig values expressed in one Godot grid-cell of width.
## Blender built each cell 2.0 units wide and 1.333 units tall, so its 0.75
## height fraction becomes 0.50 here and the wall top becomes 2/3.  Keeping
## this anisotropic cell is what registers the runtime projector to the red
## marker frames instead of merely looking broadly similar.
const VIRTUAL_CAMERA_HEIGHT := 0.5
const WALL_HEIGHT := 2.0 / 3.0
## Floor and wall quads meet at fractional logical-pixel coordinates.  Let the
## floor own one extra output pixel at every cell edge, then let the opaque wall
## pass draw over it.  This prevents a black, uncovered staircase from leaking
## through along the baseboard when the two independent projectors round their
## shared edge differently.
const FLOOR_EDGE_OVERDRAW_PIXELS := 2
const FLOOR_LIGHT_DITHER_NEAR_HALF_WIDTH_PIXELS := 3.0
const FLOOR_LIGHT_DITHER_FAR_HALF_WIDTH_PIXELS := 1.0
const FLOOR_LIGHT_DITHER_STEPS := 4
const TEMPLATE_CAMERA_REAR_OFFSET := 0.49
# World-projected actors are intentionally shorter than a wall.  This value was
# calibrated against the old corridor sprite sizes at useful mid-range depths,
# but is now evaluated by the same perspective equation as the environment.
const WORLD_ACTOR_HEIGHT := 0.36
# Character height comes directly from the camera perspective, except that the
# current camera square is capped at this largest safe display height. This
# prevents same-cell blowups without introducing visible LOD-size jumps.
const WORLD_ACTOR_NEAREST_CELL_DEPTH := 0.96
const WORLD_ACTOR_LOD_MAX_HEIGHT := 48.0
# A player can physically stand slightly behind the rear-biased camera origin
# while still sharing its current cell. Keep that close body visible and draw
# it from the protected nearest-cell display depth instead of clipping it.
const WORLD_ACTOR_NEAR_VISIBILITY_DEPTH := -TEMPLATE_CAMERA_REAR_OFFSET
const WORLD_ACTOR_PROTECTED_DISPLAY_DEPTH := 0.72
const FOV_RATIO := 0.70
# Keep each captured diagonal frame on the same brisk cadence as the three
# authored lateral strafe stages (0.075 s each), rather than making a diagonal
# crossing more than twice as slow simply because its capture lives here.
const DIAGONAL_FRAME_SECONDS := 0.075
const PROFILE_LOG_PATH := "user://coordinate_runtime_profile.csv"
const PROFILE_LOG_INTERVAL_USEC := 1_000_000

var controller: Node
var runtime_floor_layer: Node2D
var floor_art_sprite: Sprite2D
var floor_render_image: Image
var floor_render_texture: ImageTexture
var floor_source_image: Image
var floor_source_texture: Texture2D
var floor_mip_images: Array[Image] = []
var runtime_ceiling_layer: Node2D
var ceiling_art_sprite: Sprite2D
var ceiling_render_image: Image
var ceiling_render_texture: ImageTexture
var ceiling_layer1_image: Image
var ceiling_layer2_image: Image
var ceiling_layer1_texture: Texture2D
var ceiling_layer2_texture: Texture2D
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
var gpu_wall_base_mip_texture: Texture2D
var gpu_wall_layer1_mip_texture: Texture2D
var gpu_wall_layer2_mip_texture: Texture2D
var gpu_floor_mip_texture: Texture2D
var gpu_ceiling_layer1_mip_texture: Texture2D
var gpu_ceiling_layer2_mip_texture: Texture2D
var gpu_wall_sprites: Array[Sprite2D] = []
var gpu_wall_materials: Array[ShaderMaterial] = []
var gpu_plane_shader: Shader
var gpu_floor_sprites: Array[Sprite2D] = []
var gpu_floor_materials: Array[ShaderMaterial] = []
var gpu_ceiling_sprites: Array[Sprite2D] = []
var gpu_ceiling_materials: Array[ShaderMaterial] = []
var runtime_black_backdrop: ColorRect
var coordinate_background: Sprite2D
var coordinate_screen_overlay: Sprite2D
var status: Label
var runtime_status: Label
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
var camera_cutaway_opaque_width_cache := {}
var wall_mip_images: Array[Image] = []
var wall_layer1_mip_images: Array[Image] = []
var wall_layer2_mip_images: Array[Image] = []
# Keep the default wall pass on the same native-pixel, quantized sampling path
# as the floor and ceiling passes.  The GPU renderer now selects discrete mip
# levels itself; CPU is retained only for the optional EWA comparison pass.
var integer_uv_scale_snap_enabled := true
var wall_ewa_filter_enabled := false
# Wall_Layer2 remains available for future windows and wall art, but the
# base wallpaper should render without a permanent decorative overlay.
# Press P during play to enable the layered/parallax composition.
var wall_parallax_enabled := false
var gpu_wall_renderer_enabled := true
var gpu_plane_renderer_enabled := true
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
var diagonal_transition_kind := "" # "forward" is a diagonal cell crossing; "east" is either adjacent cardinal crossing from a diagonal view.
var diagonal_transition_flip_h := false # Mirror the authored NE-to-east frames for the other adjacent cardinal side.
var initialized := false

# This is deliberately a camera-window translation, not a cowboy correction.
# Every projected surface and world actor receives the same offset, so bullets,
# smoke, walls, pickups, and bodies retain one continuous camera projection.
@export var coordinate_overscan_test_enabled := true
@export var coordinate_screen_overlay_debug_enabled := false

# Rolling development profiler.  The renderer intentionally records timings in
# microseconds because this experiment's costly work happens in short bursts
# whenever a pose changes, rather than as one uniform GPU draw call.
var profile_pending_legacy_us := 0
var profile_pending_player_us := 0
var profile_pending_opponents_us := 0
var profile_pending_combat_us := 0
var profile_pending_map_us := 0
var profile_pending_vfx_muzzle_smoke_us := 0
var profile_pending_vfx_trails_us := 0
var profile_pending_vfx_trail_smoke_us := 0
var profile_pending_vfx_projectile_hot_us := 0
var profile_pending_vfx_wall_dust_us := 0
var profile_pending_vfx_blood_us := 0
var profile_pending_vfx_debris_us := 0
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
var profile_player_sum_us := 0
var profile_opponents_sum_us := 0
var profile_combat_sum_us := 0
var profile_map_sum_us := 0
var profile_background_sum_us := 0
var profile_floor_sum_us := 0
var profile_ceiling_sum_us := 0
var profile_wall_sum_us := 0
var profile_upload_sum_us := 0
var profile_rebuild_sum_us := 0
var profile_total_peak_us := 0
var profile_rebuild_peak_us := 0
var profile_render_cpu_sum_ms := 0.0
var profile_render_gpu_sum_ms := 0.0
var profile_frame_setup_cpu_sum_ms := 0.0
var profile_projectile_count_sum := 0
var profile_trail_count_sum := 0
var profile_muzzle_smoke_count_sum := 0
var profile_wall_dust_count_sum := 0
var profile_debris_count_sum := 0
var profile_blood_count_sum := 0
var profile_vfx_muzzle_smoke_sum_us := 0
var profile_vfx_trails_sum_us := 0
var profile_vfx_trail_smoke_sum_us := 0
var profile_vfx_projectile_hot_sum_us := 0
var profile_vfx_wall_dust_sum_us := 0
var profile_vfx_blood_sum_us := 0
var profile_vfx_debris_sum_us := 0

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
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true) # Enable per-viewport CPU/GPU render timings for the automatic runtime CSV; this is separate from the editor-only Profiler capture.
	if target_player_index == 0:
		_reset_profile_log()
	show_quad_outlines = false
	show_projection_points = false
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
	# The coordinate template previously supplied black wherever its transparent
	# pixels showed through. Stable in-map poses hide that template, so retain an
	# explicit black plate behind the runtime surfaces rather than exposing the
	# editor-grey clear colour in distant or intentionally empty areas.
	runtime_black_backdrop = ColorRect.new()
	runtime_black_backdrop.name = "CoordinateFrameBlackBackdrop"
	runtime_black_backdrop.position = Vector2.ZERO
	runtime_black_backdrop.size = VIEW_SIZE
	runtime_black_backdrop.color = Color.BLACK
	runtime_black_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	runtime_black_backdrop.z_index = -1
	controller.environment_layer.add_child(runtime_black_backdrop)
	coordinate_background = Sprite2D.new()
	coordinate_background.name = "CoordinateFrameBackground"
	coordinate_background.centered = false
	coordinate_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coordinate_background.z_index = 0
	controller.environment_layer.add_child(coordinate_background)
	coordinate_screen_overlay = Sprite2D.new()
	coordinate_screen_overlay.name = "CoordinateFrameScreenOverlay"
	coordinate_screen_overlay.centered = false
	coordinate_screen_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coordinate_screen_overlay.z_index = 4095
	coordinate_screen_overlay.z_as_relative = false
	var screen_overlay_material := ShaderMaterial.new()
	screen_overlay_material.shader = load(SCREEN_OVERLAY_SHADER_PATH) as Shader
	coordinate_screen_overlay.material = screen_overlay_material
	coordinate_screen_overlay.visible = false
	controller.environment_layer.add_child(coordinate_screen_overlay)
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
	# Walls are GPU projective quads.  Their shader reconstructs UVs per pixel,
	# chooses a discrete mip level for the deliberate coarse sampling, and keeps
	# the two authored wall layers available for parallax without CPU rasterizing.
	runtime_wall_layer = Node2D.new()
	runtime_wall_layer.name = "CoordinateFrameHomographyWalls"
	# Each child wall receives its own shared camera-depth draw layer below.
	runtime_wall_layer.z_index = 0
	# Runtime_Master_Wall is already the exact 128x88 master canvas.  The older
	# source sat inside a 160x120 authored sprite sheet and needed cropping.
	wall_source_texture = master_texture
	wall_source_image = master_texture.get_image()
	_load_runtime_wall_layers()
	active_wall_texture_label = "Wall_Layer1 + Layer2"
	_rebuild_wall_mip_chain()
	_rebuild_gpu_wall_sampling_textures()
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
	_initialize_gpu_plane_renderer()
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
	profile_pending_player_us = 0
	profile_pending_opponents_us = 0
	profile_pending_combat_us = 0
	profile_pending_map_us = 0


# record_legacy_render_breakdown: Records retained controller work by subsystem
# so live playtests can identify the expensive portion without changing it.
func record_legacy_render_breakdown(player_us: int, opponents_us: int, combat_us: int, map_us: int) -> void:
	profile_pending_player_us = maxi(0, player_us)
	profile_pending_opponents_us = maxi(0, opponents_us)
	profile_pending_combat_us = maxi(0, combat_us)
	profile_pending_map_us = maxi(0, map_us)
	profile_pending_legacy_us = profile_pending_player_us + profile_pending_opponents_us + profile_pending_combat_us + profile_pending_map_us


# record_combat_vfx_breakdown: Accepts the current camera's measured render-pass costs so the CSV can identify the expensive effect family without modifying any effect.
func record_combat_vfx_breakdown(vfx_profile: Dictionary) -> void:
	profile_pending_vfx_muzzle_smoke_us = maxi(0, int(vfx_profile.get("muzzle_smoke_us", 0)))
	profile_pending_vfx_trails_us = maxi(0, int(vfx_profile.get("trails_us", 0)))
	profile_pending_vfx_trail_smoke_us = maxi(0, int(vfx_profile.get("trail_smoke_us", 0)))
	profile_pending_vfx_projectile_hot_us = maxi(0, int(vfx_profile.get("projectile_hot_us", 0)))
	profile_pending_vfx_wall_dust_us = maxi(0, int(vfx_profile.get("wall_dust_us", 0)))
	profile_pending_vfx_blood_us = maxi(0, int(vfx_profile.get("blood_us", 0)))
	profile_pending_vfx_debris_us = maxi(0, int(vfx_profile.get("debris_us", 0)))


# _reset_profile_log: Starts a fresh, easily inspectable CSV for the current run.
func _reset_profile_log() -> void:
	var file := FileAccess.open(PROFILE_LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not create coordinate runtime profile log: %s" % ProjectSettings.globalize_path(PROFILE_LOG_PATH))
		return
	file.store_line("elapsed_s,player,samples,avg_total_ms,peak_total_ms,avg_legacy_ms,avg_player_ms,avg_opponents_ms,avg_combat_ms,avg_map_ms,avg_background_ms,avg_floor_ms,avg_ceiling_ms,avg_wall_ms,avg_upload_ms,avg_rebuild_ms,peak_rebuild_ms,avg_render_cpu_ms,avg_render_gpu_ms,avg_frame_setup_cpu_ms,avg_projectiles,avg_trails,avg_muzzle_smoke,avg_wall_dust,avg_debris,avg_blood,avg_vfx_muzzle_smoke_ms,avg_vfx_trails_ms,avg_vfx_trail_smoke_ms,avg_vfx_projectile_hot_ms,avg_vfx_wall_dust_ms,avg_vfx_blood_ms,avg_vfx_debris_ms")
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
	profile_player_sum_us += profile_pending_player_us
	profile_opponents_sum_us += profile_pending_opponents_us
	profile_combat_sum_us += profile_pending_combat_us
	profile_map_sum_us += profile_pending_map_us
	profile_background_sum_us += profile_background_us
	profile_floor_sum_us += profile_floor_raster_us
	profile_ceiling_sum_us += profile_ceiling_raster_us
	profile_wall_sum_us += profile_wall_raster_us
	profile_upload_sum_us += profile_upload_us
	profile_rebuild_sum_us += profile_rebuild_us
	profile_total_peak_us = maxi(profile_total_peak_us, total_us)
	profile_rebuild_peak_us = maxi(profile_rebuild_peak_us, profile_rebuild_us)
	var viewport_rid := get_viewport().get_viewport_rid()                                      # Read the exact local viewport rather than an editor-only profiler session.
	profile_render_cpu_sum_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) # Capture engine render-thread CPU work for this player view.
	profile_render_gpu_sum_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid) # Capture GPU frame time for this view when the active renderer supports it.
	profile_frame_setup_cpu_sum_ms += RenderingServer.get_frame_setup_time_cpu()                # Record shared CPU render preparation alongside the viewport-local timings.
	profile_projectile_count_sum += controller.active_projectiles.size()                        # Correlate timing changes with the live visual workload rather than guessing from gunfire alone.
	profile_trail_count_sum += controller.active_projectile_trails.size()
	profile_muzzle_smoke_count_sum += controller.active_muzzle_smoke_particles.size()
	profile_wall_dust_count_sum += controller.active_wall_impact_smokes.size()
	profile_debris_count_sum += controller.active_wall_debris.size()
	profile_blood_count_sum += controller.active_blood_splatters.size()
	profile_vfx_muzzle_smoke_sum_us += profile_pending_vfx_muzzle_smoke_us
	profile_vfx_trails_sum_us += profile_pending_vfx_trails_us
	profile_vfx_trail_smoke_sum_us += profile_pending_vfx_trail_smoke_us
	profile_vfx_projectile_hot_sum_us += profile_pending_vfx_projectile_hot_us
	profile_vfx_wall_dust_sum_us += profile_pending_vfx_wall_dust_us
	profile_vfx_blood_sum_us += profile_pending_vfx_blood_us
	profile_vfx_debris_sum_us += profile_pending_vfx_debris_us
	if now_us - profile_window_start_us < PROFILE_LOG_INTERVAL_USEC:
		return
	_append_profile_sample(float(now_us - profile_window_start_us) / 1_000_000.0)
	profile_window_start_us = now_us
	profile_sample_count = 0
	profile_total_sum_us = 0
	profile_legacy_sum_us = 0
	profile_player_sum_us = 0
	profile_opponents_sum_us = 0
	profile_combat_sum_us = 0
	profile_map_sum_us = 0
	profile_background_sum_us = 0
	profile_floor_sum_us = 0
	profile_ceiling_sum_us = 0
	profile_wall_sum_us = 0
	profile_upload_sum_us = 0
	profile_rebuild_sum_us = 0
	profile_total_peak_us = 0
	profile_rebuild_peak_us = 0
	profile_render_cpu_sum_ms = 0.0
	profile_render_gpu_sum_ms = 0.0
	profile_frame_setup_cpu_sum_ms = 0.0
	profile_projectile_count_sum = 0
	profile_trail_count_sum = 0
	profile_muzzle_smoke_count_sum = 0
	profile_wall_dust_count_sum = 0
	profile_debris_count_sum = 0
	profile_blood_count_sum = 0
	profile_vfx_muzzle_smoke_sum_us = 0
	profile_vfx_trails_sum_us = 0
	profile_vfx_trail_smoke_sum_us = 0
	profile_vfx_projectile_hot_sum_us = 0
	profile_vfx_wall_dust_sum_us = 0
	profile_vfx_blood_sum_us = 0
	profile_vfx_debris_sum_us = 0


# _append_profile_sample: Writes averages and spikes so quiet and moving poses are both diagnosable.
func _append_profile_sample(elapsed_seconds: float) -> void:
	if profile_sample_count <= 0:
		return
	var divisor := float(profile_sample_count) * 1000.0
	var file := FileAccess.open(PROFILE_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		return
	file.seek_end()
	var sample_divisor := float(profile_sample_count)
	file.store_line("%.3f,%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [elapsed_seconds, target_player_index + 1, profile_sample_count, profile_total_sum_us / divisor, float(profile_total_peak_us) / 1000.0, profile_legacy_sum_us / divisor, profile_player_sum_us / divisor, profile_opponents_sum_us / divisor, profile_combat_sum_us / divisor, profile_map_sum_us / divisor, profile_background_sum_us / divisor, profile_floor_sum_us / divisor, profile_ceiling_sum_us / divisor, profile_wall_sum_us / divisor, profile_upload_sum_us / divisor, profile_rebuild_sum_us / divisor, float(profile_rebuild_peak_us) / 1000.0, profile_render_cpu_sum_ms / sample_divisor, profile_render_gpu_sum_ms / sample_divisor, profile_frame_setup_cpu_sum_ms / sample_divisor, float(profile_projectile_count_sum) / sample_divisor, float(profile_trail_count_sum) / sample_divisor, float(profile_muzzle_smoke_count_sum) / sample_divisor, float(profile_wall_dust_count_sum) / sample_divisor, float(profile_debris_count_sum) / sample_divisor, float(profile_blood_count_sum) / sample_divisor, profile_vfx_muzzle_smoke_sum_us / divisor, profile_vfx_trails_sum_us / divisor, profile_vfx_trail_smoke_sum_us / divisor, profile_vfx_projectile_hot_sum_us / divisor, profile_vfx_wall_dust_sum_us / divisor, profile_vfx_blood_sum_us / divisor, profile_vfx_debris_sum_us / divisor])
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
	_update_camera_cutaway_view_debug(entries)
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
	floor_source_texture = texture
	floor_mip_images = _build_mip_chain(floor_source_image)
	_rebuild_gpu_plane_sampling_textures()
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
	_rebuild_gpu_wall_sampling_textures()
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
	_rebuild_gpu_wall_sampling_textures()


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
	_rebuild_gpu_wall_sampling_textures()


# _can_use_gpu_wall_renderer: Integer UV snapping is now a GPU shader option.
# Only the optional multi-tap EWA experiment uses the CPU fallback for now.
func _can_use_gpu_wall_renderer() -> bool:
	return gpu_wall_renderer_enabled and gpu_wall_shader != null and gpu_wall_dummy_texture != null and not wall_ewa_filter_enabled


# _initialize_gpu_plane_renderer: Shares the wall carrier texture but keeps
# floor/ceiling materials independent, so each visible plane cell is projected
# on the GPU without CPU image rasterization or uploads.
func _initialize_gpu_plane_renderer() -> void:
	gpu_plane_shader = load(GPU_PLANE_SHADER_PATH) as Shader
	if gpu_plane_shader == null:
		gpu_plane_renderer_enabled = false
		push_warning("GPU plane shader unavailable; using CPU floor and ceiling rasterizers.")


# _can_use_gpu_plane_renderer: Preserve the CPU compositor as an automatic
# fallback on a missing/unsupported shader, but use GPU planes in normal play.
func _can_use_gpu_plane_renderer() -> bool:
	return gpu_plane_renderer_enabled and gpu_plane_shader != null and gpu_wall_dummy_texture != null


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
		var source_texture: Texture2D = wall_source_texture
		var source_size: Vector2 = Vector2(source_texture.get_size()) if source_texture != null else Vector2.ONE
		var use_layers := wall_parallax_enabled and wall_layer1_texture != null and wall_layer2_texture != null
		var layer_offset: Vector2 = _layer_parallax_uv_offset(entry) if use_layers else Vector2.ZERO
		var layer1_weight := (layer_movement_balance - 1.0) * 0.5
		var layer2_weight := (layer_movement_balance + 1.0) * 0.5
		material.set_shader_parameter("inverse_row0", inverse[0])
		material.set_shader_parameter("inverse_row1", inverse[1])
		material.set_shader_parameter("inverse_row2", inverse[2])
		material.set_shader_parameter("wall_depths", Vector2(entry["depths"]))
		material.set_shader_parameter("camera_height", VIRTUAL_CAMERA_HEIGHT)
		material.set_shader_parameter("focal_length", FOCAL_LENGTH)
		material.set_shader_parameter("light_dither_near_half_width_pixels", FLOOR_LIGHT_DITHER_NEAR_HALF_WIDTH_PIXELS)
		material.set_shader_parameter("light_dither_far_half_width_pixels", FLOOR_LIGHT_DITHER_FAR_HALF_WIDTH_PIXELS)
		material.set_shader_parameter("light_dither_steps", FLOOR_LIGHT_DITHER_STEPS)
		material.set_shader_parameter("endpoint_corner_tones", Vector2(entry.get("corner_tone_a", 0.0), entry.get("corner_tone_b", 0.0)))
		material.set_shader_parameter("wall_opacity", float(entry.get("camera_cutaway_opacity", 1.0)))
		material.set_shader_parameter("use_camera_cutaway_fade", bool(entry.get("camera_cutaway_fade", false)))
		material.set_shader_parameter("wall_world_a", Vector2(entry.get("world_a", Vector2.ZERO)))
		material.set_shader_parameter("wall_world_b", Vector2(entry.get("world_b", Vector2.ZERO)))
		material.set_shader_parameter("cutaway_contact_a", Vector2(entry.get("camera_cutaway_contact_a", Vector2.ZERO)))
		material.set_shader_parameter("cutaway_contact_b", Vector2(entry.get("camera_cutaway_contact_b", Vector2.ZERO)))
		material.set_shader_parameter("cutaway_inner_radius", float(entry.get("camera_cutaway_inner_radius", 0.0)))
		material.set_shader_parameter("cutaway_fade_width", float(entry.get("camera_cutaway_fade_width", 0.01)))
		var use_gpu_mips := integer_uv_scale_snap_enabled and gpu_wall_base_mip_texture != null
		material.set_shader_parameter("base_texture", gpu_wall_base_mip_texture if use_gpu_mips else source_texture)
		material.set_shader_parameter("base_texture_size", source_size)
		material.set_shader_parameter("use_integer_uv_scale_snap", use_gpu_mips)
		material.set_shader_parameter("use_layer_parallax", use_layers)
		material.set_shader_parameter("layer1_texture", gpu_wall_layer1_mip_texture if use_gpu_mips and gpu_wall_layer1_mip_texture != null else (wall_layer1_texture if wall_layer1_texture != null else wall_source_texture))
		material.set_shader_parameter("layer2_texture", gpu_wall_layer2_mip_texture if use_gpu_mips and gpu_wall_layer2_mip_texture != null else (wall_layer2_texture if wall_layer2_texture != null else wall_source_texture))
		material.set_shader_parameter("layer_texture_size", Vector2(wall_layer1_image.get_width(), wall_layer1_image.get_height()) if wall_layer1_image != null else Vector2(wall_source_image.get_width(), wall_source_image.get_height()))
		material.set_shader_parameter("layer1_offset", layer_offset * layer1_weight)
		material.set_shader_parameter("layer2_offset", layer_offset * layer2_weight)
		material.set_shader_parameter("clamp_layer_edges", layer_uv_edge_clamp_enabled)
		# Canvas ordering is camera-space painter ordering only: farther geometry
		# draws first and nearer geometry overwrites it. Do not reassign a wall to
		# a source-cell group, which lets an actor overwrite a nearer wall.
		sprite.z_index = controller._character_layer_for_view_depth(float(entry["depth"])) if controller != null else index
	wall_art_sprite.visible = false
	return entries.size()


# _load_runtime_ceiling_layers: Read the independently-authored ceiling base
# and transparent foreground once.  Their shared dimensions are important: the
# two images use the same ceiling-cell UV coordinates before their adjustable
# view-dependent offset is applied.
func _load_runtime_ceiling_layers() -> void:
	ceiling_layer1_image = null
	ceiling_layer2_image = null
	ceiling_layer1_texture = load(CEILING_LAYER1_PATH) as Texture2D
	ceiling_layer2_texture = load(CEILING_LAYER2_PATH) as Texture2D
	if ceiling_layer1_texture == null or ceiling_layer2_texture == null:
		push_error("Could not load runtime ceiling layer textures.")
		return
	ceiling_layer1_image = ceiling_layer1_texture.get_image()
	ceiling_layer2_image = ceiling_layer2_texture.get_image()
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
	_rebuild_gpu_plane_sampling_textures()


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


# set_integer_uv_scale_snap_enabled: Quantizes each projective texture footprint
# before choosing a mip level. It deliberately does not move any surface or camera.
func set_integer_uv_scale_snap_enabled(enabled: bool) -> void:
	integer_uv_scale_snap_enabled = enabled
	_rebuild_runtime_floor_surfaces(_visible_floor_cells())
	_rebuild_runtime_ceiling_surfaces(_visible_ceiling_cells())
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


# get_parallax_tuning_value: Lets the shared F3 diagnostics display the
# current layer settings without creating a second, fixed-position overlay.
func get_parallax_tuning_value(key: String) -> float:
	match key:
		"depth": return parallax_max_texels
		"side": return parallax_side_multiplier
		"vertical": return parallax_vertical_multiplier
		"balance": return layer_movement_balance
		"ceiling_depth": return ceiling_parallax_max_texels
		"ceiling_side": return ceiling_parallax_side_multiplier
		"ceiling_forward": return ceiling_parallax_depth_multiplier
		"ceiling_balance": return ceiling_layer_movement_balance
	return 0.0


# set_parallax_tuning_value: Applies one F3 layer-tuning edit immediately.
func set_parallax_tuning_value(key: String, value: float) -> void:
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
	var status_text := "Coord %s | %d walls | %s | Wall:%s [G/K] | Floor:%s [M]\nT:%s  Y:%s  U:%s  H:%s  J:%s  P:%s  C:%s  L:%s  V:%s" % [_pose_key(), visible_wall_count, render_backend, displayed_texture_label, active_floor_texture_label, "ON" if show_runtime_walls else "OFF", "ON" if show_quad_outlines else "OFF", "ON" if show_projection_points else "OFF", "ON" if integer_uv_scale_snap_enabled else "OFF", "ON" if wall_ewa_filter_enabled else "OFF", "ON" if wall_parallax_enabled and layer_mode_available else "OFF", "ON" if ceiling_parallax_enabled and ceiling_layers_available else "OFF", "ON" if layer_uv_edge_clamp_enabled else "OFF", "ON" if gpu_wall_renderer_enabled else "OFF"]
	if is_instance_valid(status):
		status.text = status_text
	if is_instance_valid(runtime_status):
		runtime_status.text = status_text
		runtime_status.visible = controller != null and controller.debug_menu_open

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


# get_wall_depth_debug_entries: Supplies the current projected wall quads and
# their exact Canvas depth layer to the controller's F3 readout. This is
# diagnostic data only; it does not participate in wall selection or drawing.
func get_wall_depth_debug_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in last_wall_entries:
		var depth := float(entry.get("depth", 0.0))
		result.append({
			"quad": entry.get("quad", PackedVector2Array()),
			"edge_key": entry.get("edge_key", ""),
			"facing_cell": entry.get("facing_cell", Vector2i(-1, -1)),
			"depth": depth,
			"z_index": controller._character_layer_for_view_depth(depth) if controller != null else 0,
		})
	return result


# runtime_wall_impact_layer: Returns the effect layer only when this camera is
# on the projectile's impact side of the retained wall. A shared thin wall
# blocks shots from both directions, but its impact art is not visible through
# the opposite/back face.
func runtime_wall_impact_layer(edge_key: String, projectile_direction: Vector2) -> int:
	if controller == null or projectile_direction.length_squared() <= 0.000001:
		return -1
	for entry in last_wall_entries:
		if String(entry.get("edge_key", "")) != edge_key:
			continue
		var world_a: Vector2 = entry.get("world_a", Vector2.ZERO)
		var world_b: Vector2 = entry.get("world_b", Vector2.ZERO)
		var edge_direction := world_b - world_a
		if edge_direction.length_squared() <= 0.000001:
			return -1
		var normal := Vector2(-edge_direction.y, edge_direction.x).normalized()
		var midpoint := (world_a + world_b) * 0.5
		var viewer_side := (Vector2(entry.get("camera_origin", Vector2.ZERO)) - midpoint).dot(normal)
		var impact_side := -projectile_direction.normalized().dot(normal)
		if viewer_side * impact_side <= 0.0001:
			return -1
		var depth := float(entry.get("depth", 0.0))
		return controller._character_layer_for_view_depth(depth) + 2
	return -1


# runtime_wall_impact_colors: Samples a 2×2 texel patch around the real wall contact so splinters can use nearby wood-color variation.
func runtime_wall_impact_colors(edge_key: String, hit_position: Vector2) -> Array[Color]:
	var fallback_colors: Array[Color] = [Color(0.45, 0.28, 0.12, 1.0), Color(0.38, 0.22, 0.09, 1.0), Color(0.52, 0.33, 0.15, 1.0), Color(0.31, 0.18, 0.07, 1.0)] # Keep four usable wood tones while the runtime image is unavailable.
	if wall_source_image == null:
		return fallback_colors                                                                     # Fall back only while the runtime source image is unavailable.
	for entry in last_wall_entries:
		if String(entry.get("edge_key", "")) != edge_key:
			continue                                                                                 # Sample only the exact physical wall face that received this impact.
		var world_a: Vector2 = entry.get("world_a", Vector2.ZERO)
		var world_b: Vector2 = entry.get("world_b", Vector2.ZERO)
		var edge_vector := world_b - world_a
		if edge_vector.length_squared() <= 0.000001:
			break                                                                                    # Do not divide by a malformed zero-length edge.
		var u := clampf((hit_position - world_a).dot(edge_vector) / edge_vector.length_squared(), 0.0, 1.0) # Convert the actual contact point into the wall texture's left-to-right coordinate.
		var texture_x := clampi(roundi(u * float(wall_source_image.get_width() - 1)), 0, wall_source_image.get_width() - 1)
		var texture_y := clampi(roundi(float(wall_source_image.get_height() - 1) * 0.58), 0, wall_source_image.get_height() - 1) # Sample the stable mid-wall bullet-height band; the top-down hit has no independent vertical coordinate.
		var sampled_colors: Array[Color] = []
		for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var sample_x := clampi(texture_x + offset.x, 0, wall_source_image.get_width() - 1)
			var sample_y := clampi(texture_y + offset.y, 0, wall_source_image.get_height() - 1)
			var sampled_color := wall_source_image.get_pixel(sample_x, sample_y)
			sampled_colors.append(sampled_color if sampled_color.a > 0.01 else fallback_colors[sampled_colors.size()]) # Retain all four nearby texel colors, replacing only transparent samples.
		return sampled_colors                                                                     # Let each chunk choose one actual color from the contact patch.
	return fallback_colors                                                                      # Keep four visible wood-color fallbacks if this frame's wall face is not retained.


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
	if _can_use_gpu_plane_renderer() and floor_source_texture != null:
		var gpu_started_us := Time.get_ticks_usec()
		var gpu_count := _rebuild_gpu_floor_surfaces(entries)
		profile_floor_raster_us = Time.get_ticks_usec() - gpu_started_us
		return gpu_count
	_set_gpu_floor_sprites_visible(false)
	floor_art_sprite.visible = true
	var raster_started_us := Time.get_ticks_usec()
	floor_render_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for entry in entries:
		_rasterize_floor_cell(entry)
	profile_floor_raster_us = Time.get_ticks_usec() - raster_started_us
	var upload_started_us := Time.get_ticks_usec()
	floor_render_texture.update(floor_render_image)
	profile_upload_us += Time.get_ticks_usec() - upload_started_us
	return entries.size()


# _set_gpu_floor_sprites_visible: Retains allocated GPU plane materials while
# the CPU fallback is active for a future diagnostic comparison.
func _set_gpu_floor_sprites_visible(visible: bool) -> void:
	for sprite in gpu_floor_sprites:
		if is_instance_valid(sprite):
			sprite.visible = visible


# _rebuild_gpu_floor_surfaces: Assigns one live ray-to-plane material per
# visible floor cell; the GPU determines the owning cell from each world ray.
func _rebuild_gpu_floor_surfaces(entries: Array[Dictionary]) -> int:
	while gpu_floor_sprites.size() < entries.size():
		var sprite := Sprite2D.new()
		sprite.name = "GpuProjectedFloor%02d" % gpu_floor_sprites.size()
		sprite.centered = false
		sprite.texture = gpu_wall_dummy_texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := ShaderMaterial.new()
		material.shader = gpu_plane_shader
		sprite.material = material
		runtime_floor_layer.add_child(sprite)
		gpu_floor_sprites.append(sprite)
		gpu_floor_materials.append(material)
	for index in range(gpu_floor_sprites.size()):
		var sprite := gpu_floor_sprites[index]
		if not is_instance_valid(sprite):
			continue
		var is_active := index < entries.size()
		sprite.visible = is_active
		if not is_active:
			continue
		var entry := entries[index]
		var material := gpu_floor_materials[index]
		var use_gpu_mips := integer_uv_scale_snap_enabled and gpu_floor_mip_texture != null
		material.set_shader_parameter("base_texture", gpu_floor_mip_texture if use_gpu_mips else floor_source_texture)
		material.set_shader_parameter("base_texture_size", Vector2(floor_source_image.get_size()))
		material.set_shader_parameter("layer_texture_size", Vector2(floor_source_image.get_size()))
		material.set_shader_parameter("use_integer_uv_scale_snap", use_gpu_mips)
		material.set_shader_parameter("use_anisotropic_bottom_filter", false)
		material.set_shader_parameter("camera_origin", Vector2(entry["origin"]))
		material.set_shader_parameter("camera_forward", Vector2(entry["forward"]))
		material.set_shader_parameter("camera_right", Vector2(entry["right"]))
		material.set_shader_parameter("cell_world", Vector2(Vector2i(entry["cell"])))
		material.set_shader_parameter("wall_edge_mask", _cell_wall_edge_mask(Vector2i(entry["cell"]), Vector2(entry["origin"])))
		material.set_shader_parameter("projection_offset", _overscan_projection_offset())
		material.set_shader_parameter("use_depth_light_dither", true)                            # Blend only the authored depth-light boundaries; texture ownership stays exact.
		material.set_shader_parameter("use_layers", false)
		material.set_shader_parameter("plane_height_delta", VIRTUAL_CAMERA_HEIGHT)
	floor_art_sprite.visible = false
	return entries.size()


func _rasterize_floor_cell(entry: Dictionary) -> void:
	var quad: PackedVector2Array = entry["quad"]
	if quad.size() != 4:
		return
	var bounds := _quad_bounds(quad)
	var min_x := clampi(floori(bounds.position.x) - FLOOR_EDGE_OVERDRAW_PIXELS, 0, int(VIEW_SIZE.x) - 1)
	var min_y := clampi(floori(bounds.position.y) - FLOOR_EDGE_OVERDRAW_PIXELS, 0, int(VIEW_SIZE.y) - 1)
	var max_x := clampi(ceili(bounds.end.x) + FLOOR_EDGE_OVERDRAW_PIXELS, 0, int(VIEW_SIZE.x) - 1)
	var max_y := clampi(ceili(bounds.end.y) + FLOOR_EDGE_OVERDRAW_PIXELS, 0, int(VIEW_SIZE.y) - 1)
	var cell: Vector2i = entry["cell"]
	var origin: Vector2 = entry["origin"]
	var forward: Vector2 = entry["forward"]
	var right: Vector2 = entry["right"]
	for y in range(min_y, max_y + 1):
		var projection_offset := _overscan_projection_offset()
		var vertical_screen_delta := float(y) - HORIZON_Y - projection_offset.y
		if vertical_screen_delta <= 0.0001:
			continue
		var depth := VIRTUAL_CAMERA_HEIGHT * FOCAL_LENGTH / vertical_screen_delta
		if depth <= 0.0 or depth > MAX_DEPTH:
			continue
		for x in range(min_x, max_x + 1):
			var side := (float(x) - VIEW_SIZE.x * 0.5 - projection_offset.x) * depth / FOCAL_LENGTH
			var world := origin + right * side + forward * depth
			var uv := world - Vector2(cell)
			# Expand ownership by the world-space width of one logical screen pixel.
			# Sampling the clamped edge texel fills fractional shared borders below
			# the GPU wall pass, while the wall itself remains the visible owner.
			var edge_margin := clampf(depth / FOCAL_LENGTH * float(FLOOR_EDGE_OVERDRAW_PIXELS + 1), 0.002, 0.05)
			if uv.x < -edge_margin or uv.x > 1.0 + edge_margin or uv.y < -edge_margin or uv.y > 1.0 + edge_margin:
				continue
			var color := _sample_image_nearest(floor_source_image, uv.clamp(Vector2.ZERO, Vector2.ONE))
			var light := _floor_depth_light(depth, Vector2(x, y))                                   # Dither only the depth-lighting threshold, never the texture or its cell ownership.
			color.r *= light
			color.g *= light
			color.b *= light
			floor_render_image.set_pixel(x, y, color)


# _floor_depth_light: Retains the authored depth-light palette while replacing each hard horizontal boundary with a 2x2 ordered dither.
func _floor_depth_light(depth: float, pixel: Vector2) -> float:
	var thresholds := [1.35, 2.5, 3.8, 4.8, 5.2]                                              # Preserve the existing floor-light distance breaks.
	var near_lights := [1.0, 0.78, 0.56, 0.36, 0.22]                                          # Keep every original brighter-side level.
	var far_lights := [0.78, 0.56, 0.36, 0.22, 0.10]                                          # Keep every original darker-side level.
	var depth_per_pixel := maxf(depth * depth / (VIRTUAL_CAMERA_HEIGHT * FOCAL_LENGTH), 0.0001) # Convert a logical screen-pixel width into local depth units.
	var near_weight := 1.0 - clampf(inverse_lerp(1.35, 5.2, depth), 0.0, 1.0)                  # Give the visually stronger near bands more room than the already-readable distant ones.
	var half_band := depth_per_pixel * lerpf(FLOOR_LIGHT_DITHER_FAR_HALF_WIDTH_PIXELS, FLOOR_LIGHT_DITHER_NEAR_HALF_WIDTH_PIXELS, near_weight) # Spread near Bayer transitions across six pixels and far transitions across two.
	for index in range(thresholds.size()):
		var threshold := float(thresholds[index])                                                 # Read one authored brightness boundary.
		if depth < threshold - half_band:
			return float(near_lights[index])                                                        # Stay fully bright before this boundary.
		if depth <= threshold + half_band:
			var coverage := clampf((depth - (threshold - half_band)) / (half_band * 2.0), 0.0, 1.0) # Progress through the perspective-adjusted transition strip.
			return _floor_depth_dithered_light(float(near_lights[index]), float(far_lights[index]), coverage, pixel) # Bayer-select only between neighboring gradient steps, never the full bright/dark jump.
	return 0.10                                                                                 # Preserve the original farthest-depth light.


# _floor_depth_bayer2_threshold: The stable ordered pattern used only at floor-light boundaries.
func _floor_depth_bayer2_threshold(pixel: Vector2) -> float:
	var x := posmod(floori(pixel.x), 2)                                                        # Repeat horizontally on the logical floor pixel grid.
	var y := posmod(floori(pixel.y), 2)                                                        # Repeat vertically on the logical floor pixel grid.
	return (float(2 * x + 3 * y - 4 * x * y) + 0.5) / 4.0                                     # Standard 2x2 Bayer thresholds: 0.125, 0.625, 0.875, 0.375.


# _floor_depth_dithered_light: Quantizes a gradual light fade into small ordered-dithered steps instead of checkerboarding the complete brightness jump.
func _floor_depth_dithered_light(near_light: float, far_light: float, coverage: float, pixel: Vector2) -> float:
	var scaled_step := coverage * float(FLOOR_LIGHT_DITHER_STEPS)                              # Divide the original light change into subtle intermediate values.
	var lower_step := clampi(floori(scaled_step), 0, FLOOR_LIGHT_DITHER_STEPS)                 # Keep the stable lower quantized brightness level.
	var upper_step := mini(lower_step + 1, FLOOR_LIGHT_DITHER_STEPS)                           # Compare it only with the immediately darker neighboring level.
	var fraction := scaled_step - float(lower_step)                                            # Read progress between those two neighbors.
	var selected_step := upper_step if fraction >= _floor_depth_bayer2_threshold(pixel) else lower_step # Use Bayer coverage for this small adjacent-level choice.
	return lerpf(near_light, far_light, float(selected_step) / float(FLOOR_LIGHT_DITHER_STEPS)) # Preserve the existing endpoint lights while making the route between them gradual.


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
	if _can_use_gpu_plane_renderer() and ceiling_layer1_texture != null:
		var gpu_started_us := Time.get_ticks_usec()
		var gpu_count := _rebuild_gpu_ceiling_surfaces(entries)
		profile_ceiling_raster_us = Time.get_ticks_usec() - gpu_started_us
		return gpu_count
	_set_gpu_ceiling_sprites_visible(false)
	ceiling_art_sprite.visible = true
	var raster_started_us := Time.get_ticks_usec()
	ceiling_render_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for entry in entries:
		_rasterize_ceiling_cell(entry)
	profile_ceiling_raster_us = Time.get_ticks_usec() - raster_started_us
	var upload_started_us := Time.get_ticks_usec()
	ceiling_render_texture.update(ceiling_render_image)
	profile_upload_us += Time.get_ticks_usec() - upload_started_us
	return entries.size()


# _set_gpu_ceiling_sprites_visible: Keeps GPU resources reusable whenever the
# CPU fallback is selected instead of freeing/recreating view surfaces.
func _set_gpu_ceiling_sprites_visible(visible: bool) -> void:
	for sprite in gpu_ceiling_sprites:
		if is_instance_valid(sprite):
			sprite.visible = visible


# _rebuild_gpu_ceiling_surfaces: Mirrors the floor ray-to-plane pass while
# preserving the authored two-layer ceiling parallax in each cell material.
func _rebuild_gpu_ceiling_surfaces(entries: Array[Dictionary]) -> int:
	while gpu_ceiling_sprites.size() < entries.size():
		var sprite := Sprite2D.new()
		sprite.name = "GpuProjectedCeiling%02d" % gpu_ceiling_sprites.size()
		sprite.centered = false
		sprite.texture = gpu_wall_dummy_texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := ShaderMaterial.new()
		material.shader = gpu_plane_shader
		sprite.material = material
		runtime_ceiling_layer.add_child(sprite)
		gpu_ceiling_sprites.append(sprite)
		gpu_ceiling_materials.append(material)
	for index in range(gpu_ceiling_sprites.size()):
		var sprite := gpu_ceiling_sprites[index]
		if not is_instance_valid(sprite):
			continue
		var is_active := index < entries.size()
		sprite.visible = is_active
		if not is_active:
			continue
		var entry := entries[index]
		var layer_offset := _ceiling_parallax_uv_offset(Vector2i(entry["cell"]), Vector2(entry["origin"]), Vector2(entry["forward"]), Vector2(entry["right"]))
		var layer1_weight := (ceiling_layer_movement_balance - 1.0) * 0.5
		var layer2_weight := (ceiling_layer_movement_balance + 1.0) * 0.5
		var material := gpu_ceiling_materials[index]
		var use_gpu_mips := integer_uv_scale_snap_enabled and gpu_ceiling_layer1_mip_texture != null
		material.set_shader_parameter("base_texture", gpu_ceiling_layer1_mip_texture if use_gpu_mips else ceiling_layer1_texture)
		material.set_shader_parameter("base_texture_size", Vector2(ceiling_layer1_image.get_size()))
		material.set_shader_parameter("layer_texture_size", Vector2(ceiling_layer1_image.get_size()))
		material.set_shader_parameter("use_integer_uv_scale_snap", use_gpu_mips)
		material.set_shader_parameter("use_anisotropic_bottom_filter", use_gpu_mips)
		material.set_shader_parameter("camera_origin", Vector2(entry["origin"]))
		material.set_shader_parameter("camera_forward", Vector2(entry["forward"]))
		material.set_shader_parameter("camera_right", Vector2(entry["right"]))
		material.set_shader_parameter("cell_world", Vector2(Vector2i(entry["cell"])))
		material.set_shader_parameter("wall_edge_mask", _cell_wall_edge_mask(Vector2i(entry["cell"]), Vector2(entry["origin"])))
		material.set_shader_parameter("projection_offset", _overscan_projection_offset())
		material.set_shader_parameter("layer1_texture", gpu_ceiling_layer1_mip_texture if use_gpu_mips else ceiling_layer1_texture)
		material.set_shader_parameter("layer2_texture", gpu_ceiling_layer2_mip_texture if use_gpu_mips and gpu_ceiling_layer2_mip_texture != null else (ceiling_layer2_texture if ceiling_layer2_texture != null else ceiling_layer1_texture))
		material.set_shader_parameter("use_layers", ceiling_parallax_enabled and ceiling_layer2_texture != null)
		material.set_shader_parameter("use_depth_light_dither", true)                            # Use the same ordered transition as the floor so ceiling brightness bands do not form hard lines.
		material.set_shader_parameter("layer1_offset", layer_offset * layer1_weight)
		material.set_shader_parameter("layer2_offset", layer_offset * layer2_weight)
		material.set_shader_parameter("plane_height_delta", VIRTUAL_CAMERA_HEIGHT - WALL_HEIGHT)
	ceiling_art_sprite.visible = false
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
		var projection_offset := _overscan_projection_offset()
		var vertical_screen_delta := float(y) - HORIZON_Y - projection_offset.y
		if absf(vertical_screen_delta) <= 0.0001:
			continue
		var depth := height_delta * FOCAL_LENGTH / vertical_screen_delta
		if depth <= 0.0 or depth > MAX_DEPTH:
			continue
		for x in range(min_x, max_x + 1):
			var side := (float(x) - VIEW_SIZE.x * 0.5 - projection_offset.x) * depth / FOCAL_LENGTH
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
	var depths: Vector2 = entry["depths"]
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var uv := _inverse_homography_uv(row0, row1, row2, Vector2(x, y))
			if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
				continue
			var color := _sample_projected_wall(entry, row0, row1, row2, Vector2(x, y), uv)
			if color.a <= 0.0:
				continue
			var light := _floor_depth_light(lerpf(depths.x, depths.y, uv.x), Vector2(x, y))
			color.r *= light
			color.g *= light
			color.b *= light
			color.a *= float(entry.get("camera_cutaway_opacity", 1.0))
			if bool(entry.get("camera_cutaway_fade", false)):
				var coverage := _camera_cutaway_pixel_coverage(entry, uv)
				color.a *= 1.0 if coverage >= _camera_cutaway_bayer2_threshold(Vector2(x, y)) else 0.0
			wall_render_image.set_pixel(x, y, _alpha_over(wall_render_image.get_pixel(x, y), color))


# _camera_cutaway_pixel_opacity: CPU counterpart to the GPU contact mask.
# A wall is invisible around the camera-fan contact, then restores smoothly
# over the configured visible-PNG-width band across connected wall faces.
func _camera_cutaway_pixel_coverage(entry: Dictionary, source_uv: Vector2) -> float:
	if not bool(entry.get("camera_cutaway_fade", false)):
		return 1.0
	var world_a := Vector2(entry.get("world_a", Vector2.ZERO))
	var world_b := Vector2(entry.get("world_b", Vector2.ZERO))
	var contact_a := Vector2(entry.get("camera_cutaway_contact_a", Vector2.ZERO))
	var contact_b := Vector2(entry.get("camera_cutaway_contact_b", contact_a))
	var inner_radius := float(entry.get("camera_cutaway_inner_radius", 0.0))
	var fade_width := maxf(float(entry.get("camera_cutaway_fade_width", 0.01)), 0.0001)
	return smoothstep(inner_radius, inner_radius + fade_width, sqrt(_point_to_segment_distance_squared(world_a.lerp(world_b, source_uv.x), contact_a, contact_b)))


func _camera_cutaway_bayer2_threshold(pixel: Vector2) -> float:
	var x := posmod(floori(pixel.x), 2)
	var y := posmod(floori(pixel.y), 2)
	return (float(2 * x + 3 * y - 4 * x * y) + 0.5) / 4.0


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


# _rebuild_gpu_wall_sampling_textures: Creates GPU resources with native
# mipmaps.  Each visible wall shares these three textures; no per-wall image
# allocation or CPU rasterization happens during regular gameplay.
func _rebuild_gpu_wall_sampling_textures() -> void:
	gpu_wall_base_mip_texture = _create_mipmapped_texture(wall_source_image)
	gpu_wall_layer1_mip_texture = _create_mipmapped_texture(wall_layer1_image)
	gpu_wall_layer2_mip_texture = _create_mipmapped_texture(wall_layer2_image)


func _rebuild_gpu_plane_sampling_textures() -> void:
	gpu_floor_mip_texture = _create_mipmapped_texture(floor_source_image)
	gpu_ceiling_layer1_mip_texture = _create_mipmapped_texture(ceiling_layer1_image)
	gpu_ceiling_layer2_mip_texture = _create_mipmapped_texture(ceiling_layer2_image)


func _create_mipmapped_texture(source_image: Image) -> Texture2D:
	if source_image == null:
		return null
	var mipmapped := source_image.duplicate()
	var mip_error: int = mipmapped.generate_mipmaps()
	if mip_error != OK:
		push_warning("Could not generate GPU wall mipmaps; using base texture sampling.")
		return ImageTexture.create_from_image(source_image)
	return ImageTexture.create_from_image(mipmapped)


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
	var cutaway_data := get_camera_cutaway_debug_data(camera_origin)
	var result: Array[Dictionary] = []
	# The first-hit ray fan is still useful for ordinary visibility, but it can
	# miss a wall that only enters through the extreme left or right edge between
	# two rays. Start with those ray-visible edges, then supplement them with
	# every authoritative map edge that geometrically intersects the same frustum.
	var edges_by_key := {}
	var ray_visible_edge_keys := {}
	for ray_visible_edge in controller._visible_physical_wall_edges_for_basis(camera_origin, forward, right):
		var ray_visible_key := String(ray_visible_edge["key"])
		edges_by_key[ray_visible_key] = ray_visible_edge
		ray_visible_edge_keys[ray_visible_key] = true
	for physical_edge in controller._all_physical_wall_edges():
		var first_candidate := _to_view(Vector2(physical_edge["a"]), camera_origin, forward, right)
		var second_candidate := _to_view(Vector2(physical_edge["b"]), camera_origin, forward, right)
		if _segment_intersects_view_frustum(first_candidate, second_candidate):
			edges_by_key[String(physical_edge["key"])] = physical_edge
	var physical_edges: Array = edges_by_key.values()
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
		var facing_cell := _wall_facing_cell(Vector2(edge["a"]), Vector2(edge["b"]), camera_origin)
		var projected_entry := {
			"edge_key": String(edge["key"]),
			"camera_origin": camera_origin,
			"world_a": Vector2(edge["a"]),
			"world_b": Vector2(edge["b"]),
			"quad": quad,
			"first_local": first_local,
			"second_local": second_local,
			"depths": Vector2(maxf(first_local.y, NEAR_CLIP), maxf(second_local.y, NEAR_CLIP)),
			"depth": average_depth,
			"facing_cell": facing_cell,
			"light": _depth_light(average_depth),
			"corner_tone_a": _wall_endpoint_corner_tone(String(edge["key"]), Vector2(edge["a"]), Vector2(edge["b"]) - Vector2(edge["a"]), facing_cell, ray_visible_edge_keys),
			"corner_tone_b": _wall_endpoint_corner_tone(String(edge["key"]), Vector2(edge["b"]), Vector2(edge["b"]) - Vector2(edge["a"]), facing_cell, ray_visible_edge_keys),
		}
		# Fade outward from the actual camera-fan contact, not from the player's
		# centre. That keeps a still-occluding wall clear after the player backs
		# away, and carries the transition seamlessly across connected wall faces.
		var edge_a := Vector2(edge["a"])
		var edge_b := Vector2(edge["b"])
		var dither_contact := _segment_contact_points_in_cutaway_fan(edge_a, edge_b, camera_origin, Vector2(cutaway_data.get("dither_fan_left", Vector2.ZERO)), Vector2(cutaway_data.get("dither_fan_right", Vector2.ZERO)))
		# Pre-arm the immediately connected wall face before the moving fan reaches
		# its seam. This avoids a one-segment dither hitch while keeping unrelated
		# side walls outside the camera fan opaque.
		if dither_contact.is_empty() and not _is_camera_cutaway_neighbor_edge(edge_a, edge_b, cutaway_data.get("blocked_edges", [])):
			result.append(projected_entry)
			continue
		var inner_radius := float(cutaway_data.get("dither_inner_radius", 0.01))
		var fade_width := float(cutaway_data.get("dither_fade_width", 0.01))
		var nearest_contact := _nearest_camera_cutaway_contact(Vector2(edge["a"]), Vector2(edge["b"]), cutaway_data.get("blocked_contact_spans", []))
		if not nearest_contact.is_empty() and float(nearest_contact["distance"]) <= inner_radius + fade_width:
			projected_entry["camera_cutaway_fade"] = true
			projected_entry["camera_cutaway_contact_a"] = Vector2(nearest_contact["a"])
			projected_entry["camera_cutaway_contact_b"] = Vector2(nearest_contact["b"])
			projected_entry["camera_cutaway_inner_radius"] = inner_radius
			projected_entry["camera_cutaway_fade_width"] = fade_width
		result.append(projected_entry)
	# Retain the nearest useful walls if the full physical set exceeds the GPU
	# budget, then put that retained set back into far-to-near order for Canvas
	# compositing.  The previous one-step far-to-near sort accidentally kept the
	# farthest entries first whenever the map grew past MAX_WALLS.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["depth"]) < float(b["depth"]))
	if result.size() > MAX_WALLS:
		result = result.slice(0, MAX_WALLS)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["depth"]) > float(b["depth"]))
	return result


# _cell_wall_edge_mask: Give plane shaders only the camera-facing side of each
# physical wall. The reverse-side cell would otherwise add a second overlapping
# AO contour, making a one-pixel corner line look wide and unstable.
func _cell_wall_edge_mask(cell: Vector2i, camera_origin: Vector2) -> Vector4:
	if controller == null:
		return Vector4.ZERO
	return Vector4(
		_cell_has_camera_facing_wall_edge(cell, Vector2i(0, -1), camera_origin),
		_cell_has_camera_facing_wall_edge(cell, Vector2i(1, 0), camera_origin),
		_cell_has_camera_facing_wall_edge(cell, Vector2i(0, 1), camera_origin),
		_cell_has_camera_facing_wall_edge(cell, Vector2i(-1, 0), camera_origin)
	)


func _cell_has_camera_facing_wall_edge(cell: Vector2i, delta: Vector2i, camera_origin: Vector2) -> float:
	if controller == null or not controller._has_wall_edge(cell, delta):
		return 0.0
	var segment: Array = controller._physical_cell_edge_segment(cell, delta)
	return 1.0 if _wall_facing_cell(Vector2(segment[0]), Vector2(segment[1]), camera_origin) == cell else 0.0


# _wall_endpoint_corner_tone: A wall face knows whether a connected
# perpendicular face is on the camera-facing cell (a recessed/concave join) or
# outside it (an exposed/convex join). Straight runs stay unlined; a free cap
# is treated as an exposed edge.
func _wall_endpoint_corner_tone(edge_key: String, endpoint: Vector2, edge_direction: Vector2, facing_cell: Vector2i, ray_visible_edge_keys: Dictionary) -> float:
	if controller == null or edge_direction.length_squared() <= 0.00001:
		return 0.0
	var normalized_direction := edge_direction.normalized()
	var has_collinear_neighbor := false
	var has_perpendicular_neighbor := false
	for candidate in controller._all_physical_wall_edges():
		var candidate_key := String(candidate.get("key", ""))
		if candidate_key == edge_key:
			continue
		var candidate_a := Vector2(candidate.get("a", Vector2.ZERO))
		var candidate_b := Vector2(candidate.get("b", Vector2.ZERO))
		if endpoint.distance_squared_to(candidate_a) > 0.00001 and endpoint.distance_squared_to(candidate_b) > 0.00001:
			continue
		var candidate_direction := candidate_b - candidate_a
		if candidate_direction.length_squared() <= 0.00001:
			continue
		if absf(normalized_direction.dot(candidate_direction.normalized())) > 0.99:
			has_collinear_neighbor = true
			continue
		# A branch hidden behind this face at a T intersection cannot create a
		# corner on the visible side. Only first-hit faces from this camera's ray
		# fan may participate in the perpendicular endpoint relationship.
		if not ray_visible_edge_keys.has(candidate_key):
			continue
		has_perpendicular_neighbor = true
		break
	if not has_perpendicular_neighbor:
		# A continuous straight wall has two physical one-cell segments meeting at
		# this endpoint. It is not an exposed cap and must receive no accent line.
		return 0.0 if has_collinear_neighbor else 1.0
	# If the visible cell owns another physical edge at the same vertex, the two
	# surfaces meet around its interior: dark crevice. Otherwise the neighbor is
	# around the outside of the turn: bright convex highlight.
	for delta in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if not controller._has_wall_edge(facing_cell, delta):
			continue
		var segment: Array = controller._physical_cell_edge_segment(facing_cell, delta)
		var local_key := String(controller._physical_edge_key(Vector2(segment[0]), Vector2(segment[1])))
		if local_key == edge_key:
			continue
		if endpoint.distance_squared_to(Vector2(segment[0])) <= 0.00001 or endpoint.distance_squared_to(Vector2(segment[1])) <= 0.00001:
			return -1.0
	return 1.0


# _local_camera_obstruction_edge_keys: Finds every real thin wall crossed by a
# small camera-to-cowboy cone. The free third-person camera is intentionally
# allowed to sit beyond a wall to preserve its useful follow distance; locally
# cutting only obstruction faces is less disruptive than snapping the camera
# into the cowboy and losing the new framing. The fan covers the displayed body
# width, so a near wall begins to clear before it swallows the center pixel.
func _local_camera_obstruction_edge_keys(camera_origin: Vector2) -> Dictionary:
	return get_camera_cutaway_debug_data(camera_origin).get("blocked_keys", {})


# get_camera_cutaway_debug_data: Returns the exact visual-only camera fan used
# for wall fading. F3 consumes this data without changing selection, collision,
# or gameplay line-of-sight.
func get_camera_cutaway_debug_data(camera_origin: Vector2) -> Dictionary:
	if not bool(controller.get("continuous_third_person_camera")) or not controller.has_method("_current_player_world_position"):
		return {}
	var camera_right: Vector2 = controller._view_right_vector().normalized()
	var player_world: Vector2 = controller._current_player_world_position()
	var player_depth := (player_world - camera_origin).dot(controller._view_forward_vector().normalized())
	if player_depth <= 0.01:
		return {}
	# This is the entire character silhouette as seen from the camera: apex at
	# the camera, with a far edge matching the current PNG frame's displayed
	# width at the player's depth. It replaces the player-origin rear fan.
	var player_half_width := _camera_cutaway_visible_player_half_width(player_depth)
	# Detection follows each frame's visible pixels. The dither field deliberately
	# uses fixed reference pixel widths, avoiding animation-frame shimmer.
	var world_units_per_pixel := player_depth / FOCAL_LENGTH
	var side_guard := minf(CAMERA_CUTAWAY_SILHOUETTE_SIDE_GUARD_PIXELS * world_units_per_pixel, player_half_width * 0.45)
	var detection_half_width := player_half_width - side_guard
	var fan_left := player_world - camera_right * detection_half_width
	var fan_right := player_world + camera_right * detection_half_width
	var dither_half_width := CAMERA_CUTAWAY_DITHER_HALF_WIDTH_PIXELS * world_units_per_pixel
	var dither_fan_left := player_world - camera_right * dither_half_width
	var dither_fan_right := player_world + camera_right * dither_half_width
	var blocked_keys := {}
	var blocked_edges: Array[Dictionary] = []
	var blocked_edge_keys := {}
	var blocked_contact_positions: Array[Vector2] = []
	var blocked_contact_spans: Array[Dictionary] = []
	# Only the owning cowboy determines presentation cutaways. Opponents use
	# the regular back-to-front drawing order, including through a faded wall.
	# Test every physical wall against the solid camera-to-sprite triangle. A
	# wall only fades when it overlaps actual character pixels in this view.
	for edge in controller._all_physical_wall_edges():
		var contact_positions := _segment_contact_points_in_cutaway_fan(Vector2(edge["a"]), Vector2(edge["b"]), camera_origin, fan_left, fan_right)
		if contact_positions.is_empty():
			continue
		blocked_keys[String(edge["key"])] = true
		blocked_contact_positions.append_array(contact_positions)
		blocked_contact_spans.append({"edge_key": String(edge["key"]), "a": contact_positions.front(), "b": contact_positions.back()})
		if not blocked_edge_keys.has(String(edge["key"])):
			blocked_edge_keys[String(edge["key"])] = true
			blocked_edges.append(edge)
	return {"camera_origin": camera_origin, "player_world": player_world, "player_half_width": player_half_width, "detection_half_width": detection_half_width, "fan_left": fan_left, "fan_right": fan_right, "dither_fan_left": dither_fan_left, "dither_fan_right": dither_fan_right, "dither_inner_radius": CAMERA_CUTAWAY_DITHER_INNER_PIXELS * world_units_per_pixel, "dither_fade_width": CAMERA_CUTAWAY_DITHER_FADE_PIXELS * world_units_per_pixel, "blocked_keys": blocked_keys, "blocked_edges": blocked_edges, "blocked_contact_positions": blocked_contact_positions, "blocked_contact_spans": blocked_contact_spans}


# _camera_cutaway_visible_player_half_width: Converts the current frame's
# displayed PNG width back into camera-side world units at player depth.
func _camera_cutaway_visible_player_half_width(player_depth: float) -> float:
	var displayed_width := 34.0
	var sprite := controller.get("player_sprite") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null:
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		if texture != null:
			displayed_width = _camera_cutaway_opaque_texture_width(texture) * absf(sprite.scale.x)
	return maxf(displayed_width * 0.5 * player_depth / FOCAL_LENGTH, 0.005)


# _camera_cutaway_opaque_texture_width: Measures only the non-transparent x
# span of one PNG frame, then caches it. Transparent animation padding must not
# make the camera silhouette fan wider than the visible character pixels.
func _camera_cutaway_opaque_texture_width(texture: Texture2D) -> float:
	var cache_key := texture.resource_path if texture.resource_path != "" else str(texture.get_rid())
	if camera_cutaway_opaque_width_cache.has(cache_key):
		return float(camera_cutaway_opaque_width_cache[cache_key])
	var image := texture.get_image()
	if image == null:
		return float(texture.get_width())
	var minimum_x := image.get_width()
	var maximum_x := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.01:
				continue
			minimum_x = mini(minimum_x, x)
			maximum_x = maxi(maximum_x, x)
	var opaque_width := float(maximum_x - minimum_x + 1) if maximum_x >= minimum_x else float(texture.get_width())
	camera_cutaway_opaque_width_cache[cache_key] = opaque_width
	return opaque_width


# _segment_contact_points_in_cutaway_fan: Clips a wall segment to the solid
# camera-to-sprite fan triangle. Returning its contact endpoints makes the F3
# debug view show the same continuous test the renderer used to select a wall.
func _segment_contact_points_in_cutaway_fan(a: Vector2, b: Vector2, apex: Vector2, fan_left: Vector2, fan_right: Vector2) -> Array[Vector2]:
	var winding := signf((fan_left - apex).cross(fan_right - apex))
	if absf(winding) < 0.00001:
		return []
	var segment := b - a
	var interval_start := 0.0
	var interval_end := 1.0
	var triangle := PackedVector2Array([apex, fan_left, fan_right])
	for index in triangle.size():
		var edge_start := triangle[index]
		var edge_end := triangle[(index + 1) % triangle.size()]
		var edge_direction := edge_end - edge_start
		var value_at_start := winding * edge_direction.cross(a - edge_start)
		var value_slope := winding * edge_direction.cross(segment)
		if absf(value_slope) < 0.00001:
			if value_at_start < -0.00001:
				return []
			continue
		var crossing := (-0.00001 - value_at_start) / value_slope
		if value_slope > 0.0:
			interval_start = maxf(interval_start, crossing)
		else:
			interval_end = minf(interval_end, crossing)
		if interval_start > interval_end:
			return []
	var contact_start := a + segment * clampf(interval_start, 0.0, 1.0)
	var contact_end := a + segment * clampf(interval_end, 0.0, 1.0)
	if contact_start.distance_squared_to(contact_end) < 0.00000001:
		return [contact_start]
	return [contact_start, contact_end]


# _nearest_camera_cutaway_contact: Finds the closest fan-contact span to a
# drawable wall edge. Nearby connected faces inherit that span so their fade
# does not snap at a physical segment seam.
func _nearest_camera_cutaway_contact(edge_a: Vector2, edge_b: Vector2, contact_spans: Array) -> Dictionary:
	var nearest := {}
	var nearest_distance_squared := INF
	for span in contact_spans:
		var contact_a := Vector2(span.get("a", Vector2.ZERO))
		var contact_b := Vector2(span.get("b", contact_a))
		var distance_squared := _segment_to_segment_distance_squared(edge_a, edge_b, contact_a, contact_b)
		if distance_squared >= nearest_distance_squared:
			continue
		nearest_distance_squared = distance_squared
		nearest = {"a": contact_a, "b": contact_b, "distance": sqrt(nearest_distance_squared)}
	return nearest


# _is_camera_cutaway_neighbor_edge: An edge sharing a real endpoint with a
# currently camera-blocking face receives the dither a moment early. Physical
# adjacency is deliberate here: proximity alone would spill the effect onto a
# separate wall on the other side of a corridor.
func _is_camera_cutaway_neighbor_edge(edge_a: Vector2, edge_b: Vector2, blocked_edges: Array) -> bool:
	const ENDPOINT_EPSILON_SQUARED := 0.00001
	for blocked_edge in blocked_edges:
		var blocked_a := Vector2(blocked_edge.get("a", Vector2.ZERO))
		var blocked_b := Vector2(blocked_edge.get("b", Vector2.ZERO))
		if edge_a.distance_squared_to(blocked_a) <= ENDPOINT_EPSILON_SQUARED or edge_a.distance_squared_to(blocked_b) <= ENDPOINT_EPSILON_SQUARED or edge_b.distance_squared_to(blocked_a) <= ENDPOINT_EPSILON_SQUARED or edge_b.distance_squared_to(blocked_b) <= ENDPOINT_EPSILON_SQUARED:
			return true
	return false


func _segment_to_segment_distance_squared(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	var endpoint_distance_a := minf(_point_to_segment_distance_squared(a0, b0, b1), _point_to_segment_distance_squared(a1, b0, b1))
	var endpoint_distance_b := minf(_point_to_segment_distance_squared(b0, a0, a1), _point_to_segment_distance_squared(b1, a0, a1))
	return minf(endpoint_distance_a, endpoint_distance_b)


func _point_to_segment_distance_squared(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared <= 0.00000001:
		return point.distance_squared_to(a)
	var amount := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_squared_to(a + segment * amount)
# runtime_world_point_has_clear_camera_line_for_current_pose: Uses the same
# cutaway-wall decision as this renderer's wall pass. Combat VFX calls this
# instead of independently treating a locally hidden camera obstruction as
# opaque, while every other real wall remains a visual blocker.
func runtime_world_point_has_clear_camera_line_for_current_pose(target_world: Vector2) -> bool:
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	var camera_origin := _runtime_camera_origin(forward, right)
	var camera_to_target := target_world - camera_origin
	var target_distance := camera_to_target.length()
	if target_distance <= 0.002:
		return true
	var direction := camera_to_target / target_distance
	var ignored_obstruction_keys := _local_camera_obstruction_edge_keys(camera_origin)
	var maximum_distance := maxf(target_distance - 0.002, 0.0)
	for edge in controller._all_physical_wall_edges():
		if ignored_obstruction_keys.has(String(edge["key"])):
			continue
		var hit_distance: float = controller._ray_segment_hit_distance_limited(camera_origin, direction, Vector2(edge["a"]), Vector2(edge["b"]), maximum_distance)
		if hit_distance >= 0.0 and hit_distance < target_distance - 0.002:
			return false
	return true


# _wall_facing_cell: A visible thin wall belongs to the cell on the camera side
# of its plane. Its opposite side is the wall's back, so it must not participate
# in that adjacent cell's draw group.
func _wall_facing_cell(world_a: Vector2, world_b: Vector2, camera_origin: Vector2) -> Vector2i:
	var midpoint := (world_a + world_b) * 0.5
	if is_equal_approx(world_a.x, world_b.x):
		return Vector2i(floori(world_a.x) if camera_origin.x >= world_a.x else floori(world_a.x) - 1, floori(midpoint.y))
	return Vector2i(floori(midpoint.x), floori(world_a.y) if camera_origin.y >= world_a.y else floori(world_a.y) - 1)

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
	# Do not test only the endpoints and midpoint here.  A wall can cross the
	# camera frustum while all three of those samples lie outside it (most often
	# when a near side wall continues off either screen edge).  That old shortcut
	# incorrectly discarded the entire quad, leaving the black wedges reported at
	# the edges of the view.  Clip the *segment* against the view cone instead;
	# the full-frame GPU wall sprite then clips its projected quad naturally to
	# the actual screen without changing its perspective or UV mapping.
	return _segment_intersects_view_frustum(first, second)


# _segment_intersects_view_frustum: Liang-Barsky-style interval clipping for a
# world-space wall edge against the finite 2D camera cone.  The local view axes
# are X = camera side and Y = camera depth.
func _segment_intersects_view_frustum(first: Vector2, second: Vector2) -> bool:
	var direction := second - first
	var interval_start := 0.0
	var interval_end := 1.0
	# Every entry is the half-plane normal.dot(point) <= limit.  Together they
	# form the near plane, distance cap, and the left/right sides of the cone.
	var half_planes := [
		{"normal": Vector2(0.0, -1.0), "limit": -NEAR_CLIP},
		{"normal": Vector2(0.0, 1.0), "limit": MAX_DEPTH},
		{"normal": Vector2(1.0, -FOV_RATIO), "limit": 0.0},
		{"normal": Vector2(-1.0, -FOV_RATIO), "limit": 0.0},
	]
	for plane in half_planes:
		var normal: Vector2 = plane["normal"]
		var limit: float = plane["limit"]
		var origin_value := normal.dot(first)
		var slope := normal.dot(direction)
		if absf(slope) < 0.000001:
			if origin_value > limit:
				return false
			continue
		var crossing := (limit - origin_value) / slope
		if slope > 0.0:
			interval_end = minf(interval_end, crossing)
		else:
			interval_start = maxf(interval_start, crossing)
		if interval_start > interval_end:
			return false
	return interval_end >= 0.0 and interval_start <= 1.0

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
	return _project_view_point_unframed(point, world_height) + _overscan_projection_offset()


# _project_view_point_unframed: The calibrated 160×120 projector before the
# overscan window is applied.  The crop controller samples this once for the
# local player's real world feet, then shifts the *whole* camera image by that
# same amount.
func _project_view_point_unframed(point: Vector2, world_height: float) -> Vector2:
	var depth := maxf(point.y, NEAR_CLIP)
	return Vector2(
		VIEW_SIZE.x * 0.5 + point.x / depth * FOCAL_LENGTH,
		HORIZON_Y + (VIRTUAL_CAMERA_HEIGHT - world_height) / depth * FOCAL_LENGTH
	)


func _overscan_crop_origin() -> Vector2:
	if not coordinate_overscan_test_enabled or controller == null or not controller.has_method("_current_player_world_position"):
		return OVERSCAN_REFERENCE_CROP_ORIGIN
	if bool(controller.get("continuous_third_person_camera")):
		# Free-camera mode deliberately decouples the crop from intra-cell movement.
		# Keep its framing neutral while the vertical-look experiment is disabled.
		# The authored blue and magenta rectangles remain reference artwork only.
		var maximum_origin := OVERSCAN_SIZE - VIEW_SIZE
		return Vector2(OVERSCAN_REFERENCE_CROP_ORIGIN.x, clampf(OVERSCAN_REFERENCE_CROP_ORIGIN.y, 0.0, maximum_origin.y))
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	var cell_center := Vector2(controller.grid_position) + Vector2(0.5, 0.5)
	var player_world_position: Vector2 = controller._current_player_world_position()
	var within_cell: Vector2 = player_world_position - cell_center
	var half_extent := maxf(float(controller.LOCAL_TILE_WORLD_HALF_EXTENT), 0.001)
	# The player begins at this cell center, so the green rectangle is the
	# neutral crop. Moving rearward pans down; moving left/right pans to the
	# magenta/blue guide rectangles. These are camera-window limits, applied once
	# to the shared projection rather than separately to a cowboy sprite.
	var side_fraction := clampf(within_cell.dot(right) / half_extent, -1.0, 1.0)
	var rear_fraction := clampf(-within_cell.dot(forward) / half_extent, 0.0, 1.0)
	var horizontal_limit := clampf(float(controller.near_overscan_pan_limit_x_pixels), 0.0, 80.0)
	var rear_limit := clampf(float(controller.near_overscan_pan_limit_y_pixels), 0.0, 80.0)
	var desired_origin := OVERSCAN_REFERENCE_CROP_ORIGIN + Vector2(side_fraction * horizontal_limit, rear_fraction * rear_limit)
	var maximum_origin := OVERSCAN_SIZE - VIEW_SIZE
	return Vector2(
		clampf(roundf(desired_origin.x), 0.0, maximum_origin.x),
		clampf(roundf(desired_origin.y), 0.0, maximum_origin.y)
	)


func _overscan_projection_offset() -> Vector2:
	# Moving the output window across the 320×240 sheet is equivalent to a
	# principal-point translation. Do this after perspective projection so it
	# affects every depth equally and cannot bend a projectile trajectory.
	return OVERSCAN_REFERENCE_CROP_ORIGIN - _overscan_crop_origin()


# _overscan_calibrated_camera_origin: Solves the physical camera point that
# places the local player's feet at the corresponding point on the virtual
# 320×240 overscan canvas. The resulting camera is used by every render and
# culling path; this is deliberately not a local-cowboy screen correction.
func _overscan_calibrated_camera_origin(base_origin: Vector2, forward: Vector2, right: Vector2) -> Vector2:
	if not coordinate_overscan_test_enabled or controller == null or not controller.has_method("_current_player_world_position"):
		return base_origin
	# Do not blend this stable-pose calibration into the authored between-cell
	# capture frames. Those frames already own an independently animated camera
	# path and must remain byte-for-byte compatible with their source images.
	if int(controller.forward_step) != 0 or int(controller.strafe_step) != 0 or diagonal_forward_active:
		return base_origin
	var cell_center := Vector2(controller.grid_position) + Vector2(0.5, 0.5)
	var home_local := _to_view(cell_center, base_origin, forward, right)
	var home_foot := _project_view_point_unframed(home_local, 0.0)
	# Green is the zero-motion camera window. At the rear corners, the desired
	# virtual foot shifts by exactly the green-to-magenta/blue crop displacement.
	# After the selected 160×120 crop is removed, the cowboy remains in the same
	# safe on-screen presentation while the entire visible world shares the pan.
	var virtual_target_foot := home_foot + (_overscan_crop_origin() - OVERSCAN_REFERENCE_CROP_ORIGIN)
	if bool(controller.get("continuous_third_person_camera")):
		# Place feet high enough that the upright 48×64 cowboy is visible from hat
		# to boots at neutral/down look. The crop then supplies right-stick up/down
		# presentation without applying a special transform to the cowboy alone.
		virtual_target_foot = Vector2(VIEW_SIZE.x * 0.5, 112.0)
	var vertical_delta := virtual_target_foot.y - HORIZON_Y
	if vertical_delta <= 0.0001:
		return base_origin
	var target_depth := VIRTUAL_CAMERA_HEIGHT * FOCAL_LENGTH / vertical_delta
	if target_depth <= NEAR_CLIP:
		return base_origin
	var target_side := (virtual_target_foot.x - VIEW_SIZE.x * 0.5) * target_depth / FOCAL_LENGTH
	var player_world_position: Vector2 = controller._current_player_world_position()
	# Solve player = camera + right * side + forward * depth. This is a full
	# world-space camera translation, so all shared effects retain one transform.
	return player_world_position - right * target_side - forward * target_depth

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
		var is_backward := String(controller.forward_transition_name) == "backward"
		# Backward playback shows the authored art in reverse (Fwd 2 then Fwd 1),
		# but its camera positions must still progress away from the source cell.
		# Convert the displayed stage back to chronological camera stage before
		# choosing the quarter/half distance.
		var chronological_stage := 3 - int(controller.forward_step) if is_backward else int(controller.forward_step)
		var forward_fraction := 0.25 if chronological_stage == 1 else 0.50
		if is_backward:
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
	return _overscan_calibrated_camera_origin(origin, forward, right)


# runtime_camera_origin_for_current_pose: exposes the exact camera point used
# by runtime walls, floors, and ceilings. Character projection uses this during
# authored translation stages so opponents advance with the same camera instead
# of staying at the source-cell position until the final snap.
func runtime_camera_origin_for_current_pose() -> Vector2:
	if controller == null:
		return Vector2.ZERO
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	return _runtime_camera_origin(forward, right)


# runtime_project_world_point_for_current_pose: a shared bridge for players,
# pickups, projectiles, and impacts.  Its camera pose is exactly the pose used
# by the wall, floor, and ceiling quads for all authored transition frames.
func runtime_project_world_point_for_current_pose(world_position: Vector2, object_height := WORLD_ACTOR_HEIGHT, allow_protected_near_debug := false, protect_near_display := true) -> Dictionary:
	if controller == null:
		return {"visible": false}
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	var origin := _runtime_camera_origin(forward, right)
	var local := _to_view(world_position, origin, forward, right)
	var raw_depth := local.y
	# Keep the actor in the same forward-facing display volume as the local
	# player.  A body genuinely behind the camera should still be discarded.
	if raw_depth <= WORLD_ACTOR_NEAR_VISIBILITY_DEPTH and not allow_protected_near_debug:
		return {"visible": false, "view_depth": raw_depth, "view_side": local.x}
	# Keep world movement continuous.  Discrete LOD bands affect only the source
	# pixel grid; they must never make an opponent jog in place then lurch.
	var display_local := Vector2(local.x, maxf(raw_depth, WORLD_ACTOR_PROTECTED_DISPLAY_DEPTH) if protect_near_display else raw_depth) # Keep actors stable in the protected near cell, but let explicitly world-space effects continue through it.
	var feet := _project_view_point(display_local, 0.0)
	var head := _project_view_point(display_local, object_height)
	var visual_depth := maxf(raw_depth - TEMPLATE_CAMERA_REAR_OFFSET, 0.0)
	var continuous_actor_height := maxf(absf(feet.y - head.y), 1.0)
	var actor_height := WORLD_ACTOR_LOD_MAX_HEIGHT if raw_depth <= WORLD_ACTOR_NEAREST_CELL_DEPTH else continuous_actor_height
	return {
		"visible": (allow_protected_near_debug or raw_depth >= WORLD_ACTOR_NEAR_VISIBILITY_DEPTH) and raw_depth <= MAX_DEPTH + 0.75,
		"screen_x": feet.x,
		"feet_y": feet.y,
		"screen_y": (feet.y + head.y) * 0.5,
		"actor_height": actor_height,
		"continuous_actor_height": continuous_actor_height,
		"view_depth": raw_depth,
		"visual_depth": visual_depth,
		"view_side": local.x,
		"corridor_width": maxf(FOCAL_LENGTH / raw_depth, 1.0),
		"camera_origin": origin,
		"forward": forward,
		"right": right,
	}


# runtime_project_world_effect_point_for_current_pose: Projects a point-sized world effect through the live camera without the actor-only near-cell display clamp.
func runtime_project_world_effect_point_for_current_pose(world_position: Vector2) -> Dictionary:
	return runtime_project_world_point_for_current_pose(world_position, WORLD_ACTOR_HEIGHT, false, false) # Preserve the same camera, walls, and far clip while allowing a bullet/trail to cross the local cell continuously.


func _depth_light(depth: float) -> float:
	# Deep extra bands make the extended sixth-cell combat test visibly recede before the 5.5 depth clip.
	if depth < 1.35: return 1.0
	if depth < 2.5: return 0.78
	if depth < 3.8: return 0.56
	if depth < 4.8: return 0.36
	if depth < 5.2: return 0.22
	return 0.10

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
		var diagonal_transition_frame := _diagonal_transition_frame_name()
		if not diagonal_transition_frame.is_empty():
			return {"path": TEMPLATE_ROOT + diagonal_transition_frame, "flip_h": diagonal_transition_flip_h}
	if int(controller.strafe_step) != 0:
		flip_h = String(controller.strafe_transition_name) == "strafe_left"
		var stage_name: String = ["", "quarter", "half", "three_quarter"][int(controller.strafe_step)]
		var prefix := "coord_ne_right_se_" if diagonal else "coord_n_strafe_east_"
		return {"path": TEMPLATE_ROOT + prefix + stage_name + ".png", "flip_h": flip_h}
	return {"path": TEMPLATE_ROOT + ("coord_ne_stable.png" if diagonal else "coord_n_stable.png"), "flip_h": false}

func _diagonal_transition_frame_name() -> String:
	# Diagonal movement crosses real grid edges continuously, so the controller
	# has no authored phase state to select a coordinate frame.  Watch one actual
	# cell change and use the Blender capture that matches its path.  The NE-east
	# set is mirrored for NE-north (and, after the camera-basis rotation, for the
	# equivalent adjacent-cardinal move from every other diagonal view).
	if not diagonal_forward_active:
		return ""
	var prefix := "coord_ne_forward_" if diagonal_transition_kind == "forward" else "coord_ne_east_"
	if diagonal_forward_clock < DIAGONAL_FRAME_SECONDS:
		return prefix + "quarter.png"
	if diagonal_forward_clock < DIAGONAL_FRAME_SECONDS * 2.0:
		return prefix + "half.png"
	if diagonal_forward_clock < DIAGONAL_FRAME_SECONDS * 3.0:
		return prefix + "three_quarter.png"
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
		diagonal_transition_kind = ""
		diagonal_transition_flip_h = false
		diagonal_forward_cell = controller.grid_position
		return
	if diagonal_forward_cell.x < -900:
		diagonal_forward_cell = controller.grid_position
		return
	# A captured transition belongs to one actual diagonal-view cell crossing,
	# never the duration of a held stick.  This covers both a true diagonal move
	# and the previously missing single-cardinal move to either side of a diagonal
	# view (for example NE -> E and NE -> N).
	var crossed_cells: Vector2i = controller.grid_position - diagonal_forward_cell
	if abs(crossed_cells.x) == 1 and abs(crossed_cells.y) == 1:
		diagonal_forward_source_cell = diagonal_forward_cell
		diagonal_forward_target_cell = controller.grid_position
		diagonal_forward_clock = 0.0
		diagonal_forward_active = true
		diagonal_transition_kind = "forward"
		diagonal_transition_flip_h = false
		diagonal_forward_cell = controller.grid_position
	elif crossed_cells != Vector2i.ZERO:
		# The Blender NE-east capture supplies one adjacent cardinal path.  Its
		# mirror supplies the other: classify the world edge using the active
		# camera-right vector instead of hard-coding N/E, so all four diagonals use
		# the same authored image pair correctly.
		diagonal_forward_source_cell = diagonal_forward_cell
		diagonal_forward_target_cell = controller.grid_position
		diagonal_forward_clock = 0.0
		diagonal_forward_active = true
		diagonal_transition_kind = "east"
		diagonal_transition_flip_h = Vector2(crossed_cells).dot(controller._view_right_vector()) < 0.0
		diagonal_forward_cell = controller.grid_position
	if diagonal_forward_active:
		diagonal_forward_clock += delta
		if diagonal_forward_clock >= DIAGONAL_FRAME_SECONDS * 3.0:
			diagonal_forward_active = false
			diagonal_forward_clock = 0.0
			diagonal_transition_kind = ""
			diagonal_transition_flip_h = false

func _update_coordinate_background() -> void:
	var frame := _coordinate_frame_for_current_pose()
	var path := String(frame["path"])
	var use_overscan_sheet := coordinate_overscan_test_enabled and path.ends_with("coord_n_stable.png")
	if use_overscan_sheet:
		path = OVERSCAN_STABLE_PATH
	var texture := _template_texture(path)
	# Retain the last valid coordinate image for the fraction of a frame during
	# any import/load delay.  A pose transition must never flash the blank legacy
	# playfield between authored coordinate images.
	if texture != null:
		coordinate_background.texture = texture
		coordinate_screen_overlay.texture = texture
	coordinate_background.flip_h = bool(frame["flip_h"])
	coordinate_screen_overlay.flip_h = bool(frame["flip_h"])
	coordinate_background.region_enabled = use_overscan_sheet
	coordinate_screen_overlay.region_enabled = use_overscan_sheet
	if use_overscan_sheet:
		coordinate_background.region_rect = Rect2(_overscan_crop_origin(), VIEW_SIZE)
		coordinate_screen_overlay.region_rect = Rect2(_overscan_crop_origin(), VIEW_SIZE)
	var player_is_inside_playable_map: bool = controller != null and controller._is_open_cell(controller.grid_position)
	# The coordinate sheet is calibration/reference art, not an environmental
	# surface. The live floor, ceiling, and wall passes own every in-map pixel;
	# leaving the overscan sheet visible behind them leaked its blue/red/green
	# guide pixels through distant gaps that must read as darkness.
	coordinate_background.visible = coordinate_background.texture != null and not player_is_inside_playable_map
	coordinate_screen_overlay.visible = coordinate_screen_overlay_debug_enabled and coordinate_screen_overlay.texture != null


# set_coordinate_screen_overlay_debug_enabled: Controls a true screen-blend
# overlay. Black guide pixels leave the game untouched; brighter source pixels
# progressively brighten the already-rendered game view.
func set_coordinate_screen_overlay_debug_enabled(enabled: bool) -> void:
	coordinate_screen_overlay_debug_enabled = enabled
	if coordinate_screen_overlay != null:
		coordinate_screen_overlay.visible = enabled and coordinate_screen_overlay.texture != null

func _hide_legacy_environment() -> void:
	for item in legacy_environment_nodes:
		if is_instance_valid(item):
			item.visible = false

func _preload_coordinate_templates() -> void:
	for file_name in [
		"coord_n_stable_overscan.png",
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
	var cheat_wireframe := bool(controller.get("continuous_third_person_camera")) and bool(controller.get("walk_through_walls_cheat"))
	if not show_quad_outlines and not cheat_wireframe:
		return
	# Use only stock CanvasItems here.  The prior custom draw script could fail
	# while Godot was hot-reloading it, which made the Y diagnostic toggle able to
	# terminate the running game.  These child polygons/lines are equally clear
	# and have no runtime script state.
	var debug := Node2D.new()
	debug.name = "CoordinateFrameQuadDebug"
	debug.z_index = 61
	if show_quad_outlines:
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
	if bool(controller.get("continuous_third_person_camera")):
		# The texture renderer only has finite maze faces to outline.  The free
		# camera also needs a coordinate-frame cage outside that finite map so the
		# walk-through-walls cheat remains a useful projection diagnostic.
		_append_continuous_world_wireframe(debug)
	controller.environment_layer.add_child(debug)


# _update_camera_cutaway_view_debug: Draws the cutaway decision directly over
# the player view, including the floor-projected camera-to-sprite silhouette
# fan and the selected wall quads.
func _update_camera_cutaway_view_debug(entries: Array[Dictionary]) -> void:
	_remove_environment_debug_node("CoordinateFrameCameraCutawayDebug")
	if controller == null or not bool(controller.get("show_camera_cutaway_debug")):
		return
	var data := get_camera_cutaway_debug_data(_runtime_camera_origin(controller._view_forward_vector().normalized(), controller._view_right_vector().normalized()))
	if data.is_empty():
		return
	var debug := Node2D.new()
	debug.name = "CoordinateFrameCameraCutawayDebug"
	debug.z_index = 63
	_append_camera_cutaway_floor_fan(debug, data)
	var blocked_keys: Dictionary = data.get("blocked_keys", {})
	for entry in entries:
		if not blocked_keys.has(String(entry.get("edge_key", ""))):
			continue
		var quad: PackedVector2Array = entry.get("quad", PackedVector2Array())
		if quad.size() != 4:
			continue
		var fill := Polygon2D.new()
		fill.polygon = quad
		fill.color = Color(1.0, 0.05, 0.80, 0.07)
		debug.add_child(fill)
		var outline := Line2D.new()
		outline.points = PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]])
		outline.width = 2.0
		outline.default_color = Color(1.0, 0.12, 0.86, 0.98)
		outline.antialiased = false
		debug.add_child(outline)
	controller.environment_layer.add_child(debug)


# _append_camera_cutaway_floor_fan: Projects the finite part of the exact
# camera-origin fan onto the rendered floor. The camera apex itself cannot be
# projected at depth zero, so the wedge begins at the normal near clip plane.
func _append_camera_cutaway_floor_fan(debug: Node2D, data: Dictionary) -> void:
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	var origin := Vector2(data.get("camera_origin", Vector2.ZERO))
	var left_local := _to_view(Vector2(data.get("fan_left", origin)), origin, forward, right)
	var right_local := _to_view(Vector2(data.get("fan_right", origin)), origin, forward, right)
	if left_local.y <= NEAR_CLIP or right_local.y <= NEAR_CLIP:
		return
	var near_left := left_local * (NEAR_CLIP / left_local.y)
	var near_right := right_local * (NEAR_CLIP / right_local.y)
	var floor_height := 0.002
	var polygon := PackedVector2Array([
		_project_view_point(near_left, floor_height),
		_project_view_point(near_right, floor_height),
		_project_view_point(right_local, floor_height),
		_project_view_point(left_local, floor_height),
	])
	var fill := Polygon2D.new()
	fill.name = "CameraCutawayFloorFan"
	fill.polygon = polygon
	fill.color = Color(0.0, 0.90, 1.0, 0.14)
	debug.add_child(fill)
	var outline := Line2D.new()
	outline.points = PackedVector2Array([polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]])
	outline.width = 1.25
	outline.default_color = Color(0.0, 1.0, 1.0, 0.92)
	outline.antialiased = false
	debug.add_child(outline)


# _append_continuous_world_wireframe: Draws the current camera's infinite
# projected grid cage, rather than replaying an authored PNG wireframe.  It is
# intentionally generated from the same origin/basis/projector as walls so it
# remains meaningful after yawing or walking beyond the textured maze.
func _append_continuous_world_wireframe(debug: Node2D) -> void:
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	var origin := _runtime_camera_origin(forward, right)
	var anchor_x := floori(origin.x)
	var anchor_y := floori(origin.y)
	var world_min_x := anchor_x - 7
	var world_max_x := anchor_x + 8
	var world_min_y := anchor_y - 4
	var world_max_y := anchor_y + 10
	# Floor, ceiling, and vertical posts form the black-and-white vector room
	# even where there are no authored texture walls beyond the playable maze.
	for world_x in range(world_min_x, world_max_x + 1):
		_append_wire_segment(debug, Vector2(world_x, world_min_y), 0.0, Vector2(world_x, world_max_y), 0.0, Color(0.92, 0.95, 1.0, 0.78))
		_append_wire_segment(debug, Vector2(world_x, world_min_y), WALL_HEIGHT, Vector2(world_x, world_max_y), WALL_HEIGHT, Color(0.45, 0.52, 0.62, 0.52))
	for world_y in range(world_min_y, world_max_y + 1):
		_append_wire_segment(debug, Vector2(world_min_x, world_y), 0.0, Vector2(world_max_x, world_y), 0.0, Color(0.92, 0.95, 1.0, 0.78))
		_append_wire_segment(debug, Vector2(world_min_x, world_y), WALL_HEIGHT, Vector2(world_max_x, world_y), WALL_HEIGHT, Color(0.45, 0.52, 0.62, 0.52))
	for world_x in range(world_min_x, world_max_x + 1):
		for world_y in range(world_min_y, world_max_y + 1):
			_append_wire_segment(debug, Vector2(world_x, world_y), 0.0, Vector2(world_x, world_y), WALL_HEIGHT, Color(1.0, 1.0, 1.0, 0.66))


# _append_wire_segment: Adds only safely projectable portions of one wire.  A
# segment touching the near plane is skipped instead of becoming a giant line
# through the view; the neighboring grid segments still describe the room.
func _append_wire_segment(debug: Node2D, first_world: Vector2, first_height: float, second_world: Vector2, second_height: float, color: Color) -> void:
	var forward: Vector2 = controller._view_forward_vector().normalized()
	var right: Vector2 = controller._view_right_vector().normalized()
	var origin := _runtime_camera_origin(forward, right)
	var first_local := _to_view(first_world, origin, forward, right)
	var second_local := _to_view(second_world, origin, forward, right)
	if first_local.y <= NEAR_CLIP or second_local.y <= NEAR_CLIP:
		return
	if not _edge_can_be_seen(first_local, second_local):
		return
	var line := Line2D.new()
	line.points = PackedVector2Array([_project_view_point(first_local, first_height), _project_view_point(second_local, second_height)])
	line.width = 1.0
	line.default_color = color
	line.antialiased = false
	debug.add_child(line)

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
	var continuous_world_position: Vector2 = controller._current_player_world_position() if controller.has_method("_current_player_world_position") else Vector2.ZERO
	var continuous_yaw := float(controller.get("continuous_camera_yaw")) if bool(controller.get("continuous_third_person_camera")) else 0.0
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [controller.grid_position, controller.facing, controller.turn_step, controller.turn_45_direction, controller.forward_step, controller.forward_transition_name, controller.strafe_step, controller.strafe_transition_name, _diagonal_forward_fraction(), diagonal_forward_source_cell, diagonal_transition_kind, diagonal_transition_flip_h, controller.wall_edges.hash(), coordinate_overscan_test_enabled, _overscan_crop_origin(), continuous_world_position, continuous_yaw, bool(controller.get("walk_through_walls_cheat"))]
