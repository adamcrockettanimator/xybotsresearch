## GPU-lattice comparison barrel.
##
## The 8×5 vertex lattice is created once on the client. Each frame the CPU
## supplies only world/camera uniforms; the vertex shader projects the barrel.
extends Node2D

const LATTICE_SHADER := preload("res://scripts/semantic_gpu_lattice_barrel.gdshader")
const SIDES := 8
var heights := [0.0, 0.25, 0.50, 0.75, 1.0] # Five evenly-spaced fixed rows in the shared lattice; converted into mesh data once in _ready().
const LOGICAL_VIEW_SIZE := Vector2i(160, 120)


class FullResolutionLatticeOverlay extends Node2D:
	# This deliberately lives beside the SubViewport display, not inside it.
	# Geometry is projected only for authoring diagnostics; gameplay still sends
	# the fixed lattice through the GPU without any CPU point list.
	var rows: Array[PackedVector2Array] = []
	var overlay_colour := Color(0.10, 1.0, 0.90, 0.96)
	const SIDE_COUNT := 8

	func set_lattice(new_rows: Array[PackedVector2Array]) -> void:
		rows = new_rows
		queue_redraw()

	func _draw() -> void:
		if rows.is_empty():
			return
		var transform := get_global_transform()
		var display_scale := maxf(transform.x.length(), transform.y.length())
		var line_width := 1.0 / maxf(display_scale, 1.0) # Exactly one physical display pixel.
		for row in rows:
			for index in row.size():
				draw_line(row[index], row[(index + 1) % row.size()], overlay_colour, line_width, false)
		for column in SIDE_COUNT:
			for row_index in rows.size() - 1:
				draw_line(rows[row_index][column], rows[row_index + 1][column], overlay_colour, line_width, false)
		var cross_span := line_width * 2.0
		for row in rows:
			for point in row:
				draw_line(point - Vector2(cross_span, 0.0), point + Vector2(cross_span, 0.0), Color.WHITE, line_width, false)
				draw_line(point - Vector2(0.0, cross_span), point + Vector2(0.0, cross_span), Color.WHITE, line_width, false)

@export_category("GPU lattice barrel")
@export var show_gpu_lattice_wireframe := false
@export var show_gpu_lattice_readout := false # Authoring caption: enable only when studying the GPU construction.
@export var wood_edge := Color8(54, 30, 12)
@export var wood_centre := Color8(142, 86, 42)
@export var interior_colour := Color8(42, 20, 8)
@export var rim_colour := Color8(196, 135, 72)
@export var metal_dark := Color8(57, 59, 54)
@export var metal_light := Color8(181, 188, 176)
@export var stave_shadow_colour := Color8(56, 28, 10)
@export var stave_highlight_colour := Color8(216, 153, 83)
@export var floor_shadow_colour := Color(0.10, 0.06, 0.025, 0.34)

@export_category("GPU lattice style")
@export_range(0.0, 0.40, 0.01) var barrel_swell := 0.20
@export_range(0.05, 0.95, 0.01) var lower_hoop_height_from_floor := 0.30
@export_range(0.05, 0.95, 0.01) var upper_hoop_height_from_floor := 0.70
@export_range(1, 8, 1) var hoop_width_logical_pixels := 2
@export_range(1, 8, 1) var rim_width_logical_pixels := 2
@export_range(0, 4, 1) var stave_shadow_width_logical_pixels := 1
@export_range(0, 4, 1) var stave_highlight_width_logical_pixels := 1
@export_range(0.5, 2.0, 0.05) var floor_shadow_width := 1.30
@export_range(0.0, 1.0, 0.05) var floor_shadow_opacity := 0.55

var lattice_mesh: MeshInstance2D
var lid_mesh: MeshInstance2D
var floor_shadow_mesh: MeshInstance2D
var upper_hoop_mesh: MeshInstance2D
var lower_hoop_mesh: MeshInstance2D
var rim_mesh: MeshInstance2D
var lattice_material: ShaderMaterial
var lid_material: ShaderMaterial
var floor_shadow_material: ShaderMaterial
var upper_hoop_material: ShaderMaterial
var lower_hoop_material: ShaderMaterial
var rim_material: ShaderMaterial
var readout: Label
var lattice_viewport: SubViewport
var lattice_root: Node2D
var lattice_display: Sprite2D
var full_resolution_wireframe: FullResolutionLatticeOverlay

func _ready() -> void:
	_build_static_gpu_meshes()


func set_barrel(center: Vector2, radius: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> void:
	if lattice_mesh == null:
		return
	for shader_material in [lattice_material, lid_material, floor_shadow_material, upper_hoop_material, lower_hoop_material, rim_material]:
		shader_material.set_shader_parameter("camera_origin", camera_origin)
		shader_material.set_shader_parameter("camera_forward", camera_forward)
		shader_material.set_shader_parameter("camera_right", camera_right)
		shader_material.set_shader_parameter("projection_offset", projection_offset)
		shader_material.set_shader_parameter("barrel_center", center)
		shader_material.set_shader_parameter("barrel_radius", radius)
		shader_material.set_shader_parameter("barrel_height", height)
		shader_material.set_shader_parameter("barrel_swell", barrel_swell)
		shader_material.set_shader_parameter("upper_hoop_height", upper_hoop_height_from_floor)
		shader_material.set_shader_parameter("lower_hoop_height", lower_hoop_height_from_floor)
		shader_material.set_shader_parameter("hoop_width_logical_pixels", float(hoop_width_logical_pixels))
		shader_material.set_shader_parameter("rim_width_logical_pixels", float(rim_width_logical_pixels))
		shader_material.set_shader_parameter("stave_shadow_width_logical_pixels", float(stave_shadow_width_logical_pixels))
		shader_material.set_shader_parameter("stave_highlight_width_logical_pixels", float(stave_highlight_width_logical_pixels))
		shader_material.set_shader_parameter("floor_shadow_width", floor_shadow_width)
		shader_material.set_shader_parameter("floor_shadow_opacity", floor_shadow_opacity)
		# The debug construction drawing is never painted into the 160×120 target.
		shader_material.set_shader_parameter("show_lattice_wireframe", false)
		shader_material.set_shader_parameter("wood_edge", wood_edge)
		shader_material.set_shader_parameter("wood_centre", wood_centre)
		shader_material.set_shader_parameter("interior_colour", interior_colour)
		shader_material.set_shader_parameter("rim_colour", rim_colour)
		shader_material.set_shader_parameter("metal_dark", metal_dark)
		shader_material.set_shader_parameter("metal_light", metal_light)
		shader_material.set_shader_parameter("stave_shadow_colour", stave_shadow_colour)
		shader_material.set_shader_parameter("stave_highlight_colour", stave_highlight_colour)
		shader_material.set_shader_parameter("floor_shadow_colour", floor_shadow_colour)
	readout.visible = show_gpu_lattice_readout
	if show_gpu_lattice_readout:
		readout.text = "GPU LATTICE 8×5\n40 STATIC VERTICES\nCPU: PROP + CAMERA\nGPU: PROJECT + SHADE"
		# This label is only a diagram caption, anchored by one centre projection.
		var relative := center - camera_origin
		var depth := maxf(relative.dot(camera_forward), 0.02)
		readout.position = Vector2(80.0 + relative.dot(camera_right) / depth * 128.0, 31.5 + (0.5 - height) / depth * 128.0 + projection_offset.y - 14.0)
	if full_resolution_wireframe != null:
		full_resolution_wireframe.visible = show_gpu_lattice_wireframe
		if show_gpu_lattice_wireframe:
			full_resolution_wireframe.set_lattice(_project_debug_lattice(center, radius, height, camera_origin, camera_forward, camera_right, projection_offset))
	visible = true


func _build_static_gpu_meshes() -> void:
	# Unlike an ordinary scaled CanvasItem, this is rasterized at the same
	# 160×120 logical resolution as the vector-barrel comparison before nearest
	# enlargement.  The static lattice therefore has to earn every game pixel.
	lattice_viewport = SubViewport.new()
	lattice_viewport.name = "GpuLatticeLogicalViewport"
	lattice_viewport.size = LOGICAL_VIEW_SIZE
	lattice_viewport.transparent_bg = true
	lattice_viewport.disable_3d = true
	lattice_viewport.gui_disable_input = true
	lattice_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	lattice_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(lattice_viewport)
	lattice_root = Node2D.new()
	lattice_root.name = "GpuLatticeLogicalRoot"
	lattice_viewport.add_child(lattice_root)
	lattice_display = Sprite2D.new()
	lattice_display.name = "GpuLatticePixels_160x120"
	lattice_display.centered = false
	lattice_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lattice_display.texture = lattice_viewport.get_texture()
	add_child(lattice_display)
	full_resolution_wireframe = FullResolutionLatticeOverlay.new()
	full_resolution_wireframe.name = "FullResolutionLatticeWireframe"
	full_resolution_wireframe.z_index = 50
	full_resolution_wireframe.visible = false
	add_child(full_resolution_wireframe)
	lattice_material = _new_material(0)
	lid_material = _new_material(1)
	floor_shadow_material = _new_material(5)
	upper_hoop_material = _new_material(2)
	lower_hoop_material = _new_material(3)
	rim_material = _new_material(4)
	lattice_mesh = MeshInstance2D.new()
	lattice_mesh.name = "05 OutsideWood_8x5"
	lattice_mesh.mesh = _make_side_lattice_mesh(lattice_material)
	# MeshInstance2D accepts the surface material above, but assigning the same
	# material at the CanvasItem level makes the ownership explicit and avoids a
	# renderer path that drops the surface override on a texture-less mesh.
	lattice_mesh.material = lattice_material
	lattice_root.add_child(lattice_mesh)
	lid_mesh = MeshInstance2D.new()
	lid_mesh.name = "02 InteriorAndLid_8"
	lid_mesh.mesh = _make_lid_mesh(lid_material)
	lid_mesh.material = lid_material
	lid_mesh.z_index = 1
	lattice_root.add_child(lid_mesh)
	floor_shadow_mesh = MeshInstance2D.new()
	floor_shadow_mesh.name = "01 FloorShadow_8"
	floor_shadow_mesh.mesh = _make_lid_mesh(floor_shadow_material)
	floor_shadow_mesh.material = floor_shadow_material
	floor_shadow_mesh.z_index = -1
	lattice_root.add_child(floor_shadow_mesh)
	upper_hoop_mesh = _make_semantic_band("07 UpperHoop_8x5", upper_hoop_material, 2)
	lower_hoop_mesh = _make_semantic_band("08 LowerHoop_8x5", lower_hoop_material, 3)
	rim_mesh = _make_semantic_band("10 WoodRim_8x5", rim_material, 4)
	readout = Label.new()
	readout.name = "GpuLatticeReadout"
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.z_index = 2
	readout.add_theme_font_size_override("font_size", 4)
	readout.add_theme_color_override("font_color", Color(0.45, 1.0, 0.85, 1.0))
	readout.add_theme_color_override("font_outline_color", Color(0.0, 0.08, 0.05, 1.0))
	readout.add_theme_constant_override("outline_size", 1)
	add_child(readout)


func _new_material(surface_mode: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = LATTICE_SHADER
	material.set_shader_parameter("surface_mode", surface_mode)
	return material


func _make_semantic_band(component_name: String, material: Material, draw_order: int) -> MeshInstance2D:
	# Reuse the exact same 8×5 static construction for each paint component.
	# This adds no screen-space points or CPU geometry work; each material simply
	# discards every fragment except its named semantic band.
	var component := MeshInstance2D.new()
	component.name = component_name
	component.mesh = _make_side_lattice_mesh(material)
	component.material = material
	component.z_index = draw_order
	lattice_root.add_child(component)
	return component


func _project_debug_lattice(center: Vector2, radius: float, height: float, camera_origin: Vector2, camera_forward: Vector2, camera_right: Vector2, projection_offset: Vector2) -> Array[PackedVector2Array]:
	# Exact CPU mirror of the vertex shader, used only while the checkbox is on.
	# It makes the *static* GPU lattice inspectable without contaminating its
	# low-resolution colour target.
	var projected_rows: Array[PackedVector2Array] = []
	for height_fraction in heights:
		var row := PackedVector2Array()
		for side_index in SIDES:
			var angle := TAU * float(side_index) / float(SIDES)
			var radial := Vector2(cos(angle), sin(angle))
			var swell := 1.0 + barrel_swell * sin(PI * height_fraction)
			var world := center + radial * radius * swell
			var relative := world - camera_origin
			var depth := maxf(relative.dot(camera_forward), 0.02)
			row.append(Vector2(
				80.0 + relative.dot(camera_right) / depth * 128.0,
				31.5 + (0.5 - height * height_fraction) / depth * 128.0
			) + projection_offset)
		projected_rows.append(row)
	return projected_rows


func _make_side_lattice_mesh(material: Material) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	for height_fraction in heights:
		for side in SIDES:
			vertices.append(Vector2(float(side), height_fraction))
			uvs.append(Vector2(float(side) / float(SIDES), height_fraction))
			colours.append(Color(1.0, 1.0, 1.0, 1.0))
	var indices := PackedInt32Array()
	for row in heights.size() - 1:
		for side in SIDES:
			var next_side := (side + 1) % SIDES
			var a := row * SIDES + side
			var b := row * SIDES + next_side
			var c := (row + 1) * SIDES + next_side
			var d := (row + 1) * SIDES + side
			indices.append_array(PackedInt32Array([a, b, c, a, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _make_lid_mesh(material: Material) -> ArrayMesh:
	var vertices := PackedVector2Array([Vector2.ZERO])
	var uvs := PackedVector2Array([Vector2(0.0, 1.0)])
	var colours := PackedColorArray([Color(1.0, 1.0, 1.0, 0.0)])
	for side in SIDES:
		vertices.append(Vector2(float(side), 1.0))
		uvs.append(Vector2(float(side) / float(SIDES), 1.0))
		colours.append(Color.WHITE)
	var indices := PackedInt32Array()
	for side in SIDES:
		indices.append_array(PackedInt32Array([0, side + 1, (side + 1) % SIDES + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh
