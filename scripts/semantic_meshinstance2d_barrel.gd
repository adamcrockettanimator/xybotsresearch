## Renders the authored 3D barrel into a small offscreen viewport, then shows
## that texture through a MeshInstance2D quad in the coordinate-frame gallery.
##
## MeshInstance2D is deliberately the *2D carrier*, not the 3D barrel itself:
## it rasterizes a flat mesh in the CanvasItem layer.  The imported FBX remains
## a real MeshInstance3D inside the SubViewport, so this fixture makes the
## boundary between Godot's 3D and 2D renderers explicit and inspectable.
extends Node2D


const BARREL_3D_SOURCE_SCENE := preload("res://tests/calibration/meshinstance2d_barrel_3d_source.tscn")
# This is deliberately close to the authored 32px barrel language. The output
# becomes chunky only after the 3D render, just like the neighboring sprites.
const RENDER_SIZE := Vector2i(64, 64)
const SOURCE_CAMERA_DISTANCE := 1.9
const SOURCE_TARGET_HEIGHT := 0.62
const GAME_VIRTUAL_CAMERA_HEIGHT := 0.5
# This is a framing zoom for the tiny source target, not a new game camera.
# It makes the barrel use most of 64x64 before its pixels are mapped back into
# the fixed game-projected height. Perspective ratios remain camera-derived.
const SOURCE_FRAME_VERTICAL_FOV_DEGREES := 32.0 # Leave room for the near-view lower rim; 28° clipped it below the source target.
const LOD_01_MIN_VIEW_DEPTH := 1.46 # Match the authored world-barrel depth ladder: LOD 00 nearby, LOD 01 once it is smaller on screen.
const SHOW_DEBUG_GUIDES := false
const SHOW_SOURCE_PREVIEW := false # Keep the offscreen source inspectable in its own 3D authoring scene, not as a game-corner overlay.

var render_viewport: SubViewport
var barrel_camera: Camera3D
var barrel_source: Node3D
var barrel_lod_00_source: Node3D
var barrel_lod_01_source: Node3D
var display_mesh: MeshInstance2D
var debug_overlay: BarrelDebugOverlay
var display_material: ShaderMaterial
var last_source_crop := Rect2()
var resolution_readout: Label
var source_preview_backdrop: ColorRect
var source_preview: Sprite2D
var source_preview_label: Label


## This overlay is deliberately drawn in the same CanvasItem coordinate space as
## the carrier mesh. It lets the author see the exact handoff from the game's
## projected 3D footprint to the flat MeshInstance2D "postcard."
class BarrelDebugOverlay extends Node2D:
	var floor_center := Vector2.ZERO
	var top_center := Vector2.ZERO
	var carrier_rect := Rect2()

	func set_guides(new_floor_center: Vector2, new_top_center: Vector2, new_carrier_rect: Rect2) -> void:
		floor_center = new_floor_center
		top_center = new_top_center
		carrier_rect = new_carrier_rect
		queue_redraw()

	func _draw() -> void:
		# Cyan = real bounds of the 2D carrier mesh. Yellow = the game's
		# projected vertical centreline. Green/Magenta = floor/top centre.
		draw_rect(carrier_rect, Color(0.0, 0.95, 1.0, 0.95), false, 1.0, false)
		draw_line(floor_center, top_center, Color(1.0, 0.9, 0.1, 0.95), 1.0, false)
		_draw_cross(floor_center, Color(0.2, 1.0, 0.35, 1.0))
		_draw_cross(top_center, Color(1.0, 0.2, 0.85, 1.0))

	func _draw_cross(center: Vector2, color: Color) -> void:
		var radius := 4.0
		draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), color, 1.0, false)
		draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, radius), color, 1.0, false)
		draw_circle(center, 1.5, color, false, 1.0, false)


func _ready() -> void:
	_build_3d_source_view()
	_build_meshinstance2d_display()


func set_barrel(projected_corners: PackedVector2Array, camera_origin: Vector2, view_forward: Vector2, view_right: Vector2, world_center: Vector2) -> bool:
	if projected_corners.size() != 8 or render_viewport == null or display_mesh == null:
		return false
	var bounds := Rect2(projected_corners[0], Vector2.ZERO)
	for point in projected_corners:
		bounds = bounds.expand(point)
	if bounds.size.x < 1.0 or bounds.size.y < 1.0:
		return false
	var floor_center := _projected_center(projected_corners, 0)
	var top_center := _projected_center(projected_corners, 4)
	var world_from_camera := world_center - camera_origin
	var view_depth := maxf(world_from_camera.dot(view_forward.normalized()), 0.01)
	_set_active_barrel_lod(view_depth)
	_set_source_resolution(view_depth)
	_update_source_preview()
	_update_3d_camera(camera_origin, world_center, view_forward, view_right, view_depth)
	_fit_3d_camera_to_source_target()
	var source_layout := _source_layout_in_viewport()
	if source_layout.is_empty():
		return false
	var source_top: Vector2 = source_layout["top_center"]
	var source_floor: Vector2 = source_layout["floor_center"]
	var source_crop: Rect2 = source_layout["content_crop"]
	# The two *centres* are the anchors. In a near perspective view the front
	# lower rim can extend beneath source_floor, which is correct: it is visible
	# geometry, not the barrel's floor-contact point.
	var source_anchor_height := source_floor.y - source_top.y
	var projected_height := floor_center.y - top_center.y
	if source_anchor_height <= 0.01 or projected_height <= 0.01:
		return false
	var pixels_to_game := projected_height / source_anchor_height
	_update_carrier_mesh(source_crop)
	display_mesh.position = top_center - source_top * pixels_to_game
	display_mesh.scale = Vector2.ONE * pixels_to_game
	if debug_overlay != null:
		var carrier_rect := Rect2(display_mesh.position + source_crop.position * pixels_to_game, source_crop.size * pixels_to_game)
		debug_overlay.set_guides(floor_center, top_center, carrier_rect)
		_update_resolution_readout(carrier_rect, source_crop)
	display_mesh.visible = true
	return true


func _build_3d_source_view() -> void:
	render_viewport = SubViewport.new()
	render_viewport.name = "Barrel3DSourceViewport"
	render_viewport.size = RENDER_SIZE
	render_viewport.transparent_bg = true
	render_viewport.gui_disable_input = true
	render_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(render_viewport)

	var source_root := BARREL_3D_SOURCE_SCENE.instantiate() as Node3D
	if source_root == null:
		push_error("MeshInstance2D barrel source did not instantiate as Node3D.")
		return
	source_root.name = "Barrel3DSource"
	render_viewport.add_child(source_root)
	barrel_lod_00_source = source_root.get_node_or_null("Barrel_LOD_00_3D") as Node3D
	barrel_lod_01_source = source_root.get_node_or_null("Barrel_LOD_01_3D") as Node3D
	barrel_camera = source_root.get_node_or_null("Barrel3DSourceCamera") as Camera3D
	if barrel_lod_00_source == null or barrel_lod_01_source == null or barrel_camera == null:
		push_error("MeshInstance2D barrel source is missing an authored model or camera node.")
		return
	barrel_lod_01_source.visible = false
	barrel_source = barrel_lod_00_source
	barrel_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	barrel_camera.fov = SOURCE_FRAME_VERTICAL_FOV_DEGREES
	barrel_camera.current = true
	_update_3d_camera(Vector2(0.0, -1.0), Vector2.ZERO, Vector2.DOWN, Vector2.RIGHT, 1.0)


func _build_meshinstance2d_display() -> void:
	# MeshInstance2D accepts an ArrayMesh with XY vertices.  This is a genuine
	# Canvas mesh (not Sprite2D), carrying the live 3D SubViewport texture.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(RENDER_SIZE.x, 0.0),
		Vector2(RENDER_SIZE.x, RENDER_SIZE.y), Vector2(0.0, RENDER_SIZE.y),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var display_material := ShaderMaterial.new()
	var shader := Shader.new()
	# MeshInstance2D binds its `texture` property to the CanvasItem TEXTURE
	# uniform. Sampling a separate, unbound custom uniform was the reason the
	# carrier appeared as a white rectangle instead of the viewport result.
	shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR = texture(TEXTURE, UV); }"
	display_material.shader = shader
	self.display_material = display_material

	display_mesh = MeshInstance2D.new()
	display_mesh.name = "Barrel3DAsMeshInstance2D"
	_update_carrier_mesh(Rect2(Vector2.ZERO, Vector2(RENDER_SIZE)))
	display_mesh.texture = render_viewport.get_texture()
	display_mesh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display_mesh.visible = false
	add_child(display_mesh)

	debug_overlay = BarrelDebugOverlay.new()
	debug_overlay.name = "MeshInstance2DBarrelDebug"
	debug_overlay.z_index = 1
	debug_overlay.visible = SHOW_DEBUG_GUIDES
	add_child(debug_overlay)

	resolution_readout = Label.new()
	resolution_readout.name = "Barrel3DSourceResolution"
	resolution_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resolution_readout.z_index = 2
	resolution_readout.add_theme_font_size_override("font_size", 5)
	resolution_readout.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7, 1.0))
	resolution_readout.add_theme_color_override("font_outline_color", Color(0.0, 0.08, 0.02, 1.0))
	resolution_readout.add_theme_constant_override("outline_size", 1)
	resolution_readout.visible = SHOW_DEBUG_GUIDES
	add_child(resolution_readout)

	# This is deliberately the raw SubViewportTexture, not the carrier mesh:
	# it reveals the little 3D render before crop, scaling, or world projection.
	source_preview_backdrop = ColorRect.new()
	source_preview_backdrop.name = "RawBarrel3DSourceBackdrop"
	source_preview_backdrop.position = Vector2(106.0, 12.0)
	source_preview_backdrop.size = Vector2(52.0, 58.0)
	source_preview_backdrop.color = Color(0.015, 0.012, 0.01, 0.88)
	source_preview_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_preview_backdrop.z_index = 3
	source_preview_backdrop.visible = SHOW_SOURCE_PREVIEW
	add_child(source_preview_backdrop)

	source_preview = Sprite2D.new()
	source_preview.name = "RawBarrel3DSourcePreview"
	source_preview.centered = false
	source_preview.position = Vector2(108.0, 20.0)
	source_preview.texture = render_viewport.get_texture()
	source_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	source_preview.z_index = 4
	source_preview.visible = SHOW_SOURCE_PREVIEW
	add_child(source_preview)

	source_preview_label = Label.new()
	source_preview_label.name = "RawBarrel3DSourceLabel"
	source_preview_label.position = Vector2(108.0, 14.0)
	source_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_preview_label.z_index = 5
	source_preview_label.add_theme_font_size_override("font_size", 4)
	source_preview_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7, 1.0))
	source_preview_label.add_theme_color_override("font_outline_color", Color(0.0, 0.08, 0.02, 1.0))
	source_preview_label.add_theme_constant_override("outline_size", 1)
	source_preview_label.visible = SHOW_SOURCE_PREVIEW
	add_child(source_preview_label)
	_update_source_preview()


func _update_resolution_readout(carrier_rect: Rect2, source_crop: Rect2) -> void:
	if resolution_readout == null:
		return
	resolution_readout.visible = SHOW_DEBUG_GUIDES
	if not SHOW_DEBUG_GUIDES:
		return
	var contained_crop := source_crop.intersection(Rect2(Vector2.ZERO, Vector2(render_viewport.size)))
	resolution_readout.text = "SRC %dx%d  PROP %dx%d" % [render_viewport.size.x, render_viewport.size.y, roundi(contained_crop.size.x), roundi(contained_crop.size.y)]
	# Keep this diagnostic just above the actual cropped card, rather than in
	# screen UI, so it remains unambiguously attached to this one test barrel.
	resolution_readout.position = carrier_rect.position + Vector2(0.0, -8.0)


func _update_source_preview() -> void:
	if source_preview == null or source_preview_label == null or render_viewport == null:
		return
	# Hold the debug card at 48 logical pixels wide while its real source
	# resolution steps 64 → 12. That makes every source texel inspectable.
	var target_width := 48.0
	var scale_factor := target_width / maxf(float(render_viewport.size.x), 1.0)
	source_preview.scale = Vector2.ONE * scale_factor
	source_preview_label.text = "RAW 3D %dx%d" % [render_viewport.size.x, render_viewport.size.y]


func _update_carrier_mesh(source_crop: Rect2) -> void:
	if display_mesh == null or display_material == null:
		return
	# Crop away transparent source margins. The mesh's local positions stay in
	# source-pixel coordinates, allowing the centre anchors to map exactly to
	# the renderer's independently projected top/floor centres.
	var current_size := Vector2(render_viewport.size)
	var clamped_crop := source_crop.intersection(Rect2(Vector2.ZERO, current_size))
	if clamped_crop.size.x < 1.0 or clamped_crop.size.y < 1.0:
		return
	if clamped_crop == last_source_crop and display_mesh.mesh != null:
		return
	last_source_crop = clamped_crop
	var crop_end := clamped_crop.end
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		clamped_crop.position, Vector2(crop_end.x, clamped_crop.position.y),
		crop_end, Vector2(clamped_crop.position.x, crop_end.y),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		clamped_crop.position / current_size, Vector2(crop_end.x, clamped_crop.position.y) / current_size,
		crop_end / current_size, Vector2(clamped_crop.position.x, crop_end.y) / current_size,
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var quad := ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	quad.surface_set_material(0, display_material)
	display_mesh.mesh = quad


func _source_layout_in_viewport() -> Dictionary:
	if barrel_source == null or barrel_camera == null:
		return {}
	var bounds_ready := false
	var world_min := Vector3.ZERO
	var world_max := Vector3.ZERO
	var screen_min := Vector2.ZERO
	var screen_max := Vector2.ZERO
	for child in barrel_source.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		var local_bounds := mesh_instance.get_aabb()
		for local_x in [local_bounds.position.x, local_bounds.end.x]:
			for local_y in [local_bounds.position.y, local_bounds.end.y]:
				for local_z in [local_bounds.position.z, local_bounds.end.z]:
					var point := mesh_instance.global_transform * Vector3(local_x, local_y, local_z)
					var screen_point := barrel_camera.unproject_position(point)
					if not bounds_ready:
						world_min = point
						world_max = point
						screen_min = screen_point
						screen_max = screen_point
						bounds_ready = true
					else:
						world_min = world_min.min(point)
						world_max = world_max.max(point)
						screen_min = screen_min.min(screen_point)
						screen_max = screen_max.max(screen_point)
	if not bounds_ready:
		return {}
	var horizontal_center := Vector3((world_min.x + world_max.x) * 0.5, 0.0, (world_min.z + world_max.z) * 0.5)
	var source_floor := barrel_camera.unproject_position(horizontal_center + Vector3.UP * world_min.y)
	var source_top := barrel_camera.unproject_position(horizontal_center + Vector3.UP * world_max.y)
	# One native source pixel of breathing room avoids cutting off the outer rim
	# when the small target resolves it on a neighbouring pixel.
	var crop := Rect2(screen_min - Vector2.ONE, screen_max - screen_min + Vector2.ONE * 2.0)
	return {"top_center": source_top, "floor_center": source_floor, "content_crop": crop}


static func source_resolution_for_distance(camera_distance: float) -> Vector2i:
	# Follow the regular barrel's authored depth bands, but keep this separate
	# source image ladder. Smaller targets reduce the 3D-pass pixel work while
	# preserving deliberate, nearest-neighbour pixel steps.
	if camera_distance >= 3.63:
		return Vector2i(12, 12)
	if camera_distance >= 3.30:
		return Vector2i(16, 16)
	if camera_distance >= 2.96:
		return Vector2i(20, 20)
	if camera_distance >= 2.46:
		return Vector2i(24, 24)
	if camera_distance >= 1.96:
		return Vector2i(28, 28)
	if camera_distance >= 1.46:
		return Vector2i(32, 32)
	if camera_distance >= 1.20:
		return Vector2i(40, 40)
	if camera_distance >= 0.96:
		return Vector2i(48, 48)
	if camera_distance >= 0.64:
		return Vector2i(56, 56)
	return RENDER_SIZE


func _set_source_resolution(camera_distance: float) -> void:
	var desired_size := source_resolution_for_distance(camera_distance)
	if render_viewport.size == desired_size:
		return
	# The MeshInstance2D quad keeps its projected size. Only its source pixels
	# step down, so distance changes stay crisp rather than blurring gradually.
	render_viewport.size = desired_size
	set_meta("source_resolution", desired_size)


func _set_active_barrel_lod(view_depth: float) -> void:
	var desired_source := barrel_lod_01_source if view_depth >= LOD_01_MIN_VIEW_DEPTH else barrel_lod_00_source
	if desired_source == null or desired_source == barrel_source:
		return
	if barrel_source != null:
		barrel_source.visible = false
	desired_source.visible = true
	barrel_source = desired_source


func _projected_center(projected_corners: PackedVector2Array, start_index: int) -> Vector2:
	var center := Vector2.ZERO
	for index in range(start_index, start_index + 4):
		center += projected_corners[index]
	return center * 0.25


func _update_3d_camera(camera_origin: Vector2, world_center: Vector2, view_forward: Vector2, view_right: Vector2, view_depth: float) -> void:
	if barrel_camera == null:
		return
	# Reset the preferred near framing before the resolution-specific fit below.
	barrel_camera.fov = SOURCE_FRAME_VERTICAL_FOV_DEGREES
	# The camera-bearing is taken from the same continuously moving origin and
	# yaw basis that the wall/floor renderer uses. The source shot's elevation is
	# derived from the game's virtual-camera height over this prop's live depth:
	# near views expose more lid, far views flatten naturally.
	var camera_delta := camera_origin - world_center
	var forward := view_forward.normalized()
	var right := view_right.normalized()
	# Recompose from the renderer's live orthonormal basis rather than treating
	# map X/Y as an implicit camera basis. This remains correct during its
	# continuous 22.5-degree transition poses.
	var basis_camera_delta := right * camera_delta.dot(right) + forward * camera_delta.dot(forward)
	var horizontal := Vector3(basis_camera_delta.x, 0.0, basis_camera_delta.y)
	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3(-forward.x, 0.0, -forward.y)
	else:
		horizontal = horizontal.normalized()
	var elevation := clampf(atan2(GAME_VIRTUAL_CAMERA_HEIGHT, view_depth), deg_to_rad(8.0), deg_to_rad(38.0))
	var camera_height := SOURCE_TARGET_HEIGHT + SOURCE_CAMERA_DISTANCE * tan(elevation)
	var camera_position := horizontal * SOURCE_CAMERA_DISTANCE + Vector3.UP * camera_height
	barrel_camera.look_at_from_position(camera_position, Vector3(0.0, SOURCE_TARGET_HEIGHT, 0.0), Vector3.UP)


func _fit_3d_camera_to_source_target() -> void:
	# The target changes from 64 down to 12 pixels. A fixed source FOV that is
	# safe nearby can cut off the low rim after one of those target-size steps.
	# Use the model's projected conservative bounds to widen only as much as the
	# current target requires, leaving two real source pixels around the barrel.
	var layout := _source_layout_in_viewport()
	if layout.is_empty():
		return
	var content_crop: Rect2 = layout["content_crop"]
	var target_size := Vector2(render_viewport.size)
	var center := target_size * 0.5
	var available := center - Vector2(2.0, 2.0)
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var required_scale := 1.0
	for corner in [content_crop.position, content_crop.end]:
		required_scale = maxf(required_scale, absf(corner.x - center.x) / available.x)
		required_scale = maxf(required_scale, absf(corner.y - center.y) / available.y)
	if required_scale <= 1.0:
		return
	var current_half_fov := deg_to_rad(barrel_camera.fov) * 0.5
	barrel_camera.fov = rad_to_deg(2.0 * atan(tan(current_half_fov) * required_scale))
