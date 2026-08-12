# Isolated experimental wall renderer for the coordinate-frame navigation branch.
# It intentionally leaves the original sprite renderer and its slot graphs alone:
# this child only hides the old transparent wall sprites and composites one master
# wall texture through projective quads derived from the live grid camera basis.
extends Node

const VIEW_SIZE := Vector2(160.0, 120.0)
const MASTER_WALL_PATH := "res://assets/Environment/WallsStraight/Walls_Straight_25.png"
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
var coordinate_background: Sprite2D
var status: Label
var runtime_status: Label
var last_signature := ""
var show_runtime_walls := true
var show_quad_outlines := false
var show_projection_points := false
var master_texture: Texture2D
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
	wall_source_image = master_texture.get_image().get_region(Rect2i(16, 8, 128, 88))
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

func _rebuild() -> void:
	if runtime_wall_layer == null:
		return
	last_signature = _render_signature()
	var entries: Array[Dictionary] = _visible_wall_entries()
	var accepted_count := entries.size()
	_update_coordinate_background()
	_rebuild_runtime_wall_surfaces(entries)
	_update_debug_outlines(entries)
	_update_projection_point_debug()
	runtime_wall_layer.visible = show_runtime_walls
	var status_text := "Coordinate world: %s | %d ray-visible walls | T art %s | Y quads %s | U points %s" % [_pose_key(), accepted_count, "ON" if show_runtime_walls else "OFF", "ON" if show_quad_outlines else "OFF", "ON" if show_projection_points else "OFF"]
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
	var source_width := wall_source_image.get_width()
	var source_height := wall_source_image.get_height()
	var light := float(entry["light"])
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var denominator := row2.x * float(x) + row2.y * float(y) + row2.z
			if absf(denominator) < 0.00001:
				continue
			var u := (row0.x * float(x) + row0.y * float(y) + row0.z) / denominator
			var v := (row1.x * float(x) + row1.y * float(y) + row1.z) / denominator
			if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
				continue
			var sample_x := clampi(floori(u * float(source_width - 1)), 0, source_width - 1)
			var sample_y := clampi(floori(v * float(source_height - 1)), 0, source_height - 1)
			var color := wall_source_image.get_pixel(sample_x, sample_y)
			if color.a <= 0.0:
				continue
			color.r *= light
			color.g *= light
			color.b *= light
			wall_render_image.set_pixel(x, y, color)

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
