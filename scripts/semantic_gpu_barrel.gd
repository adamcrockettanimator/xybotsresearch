extends Node2D

const BARREL_SHADER := preload("res://scripts/semantic_gpu_barrel.gdshader")
var viewport: SubViewport
var carrier: ColorRect
var shader_material: ShaderMaterial

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(160, 120)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	shader_material = ShaderMaterial.new()
	shader_material.shader = BARREL_SHADER
	carrier = ColorRect.new()
	carrier.material = shader_material
	viewport.add_child(carrier)
	var display := Sprite2D.new()
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.texture = viewport.get_texture()
	add_child(display)

func set_barrel(corners: PackedVector2Array, center: Vector2, radius: float, height: float, origin: Vector2, forward: Vector2, right: Vector2, offset: Vector2) -> void:
	if corners.size() < 8:
		set_screen_active(false)
		return
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for point in corners:
		bounds = bounds.expand(point)
	# The middle bulges beyond the rim square; leave a conservative margin.
	bounds = bounds.grow(maxf(3.0, bounds.size.x * 0.15)).intersection(Rect2(Vector2.ZERO, Vector2(160, 120)))
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		set_screen_active(false)
		return
	set_screen_active(true)
	carrier.position = bounds.position.floor()
	carrier.size = (bounds.end.ceil() - carrier.position).max(Vector2.ONE)
	shader_material.set_shader_parameter("rect_origin", carrier.position)
	shader_material.set_shader_parameter("rect_size", carrier.size)
	shader_material.set_shader_parameter("camera_origin", origin)
	shader_material.set_shader_parameter("camera_forward", forward)
	shader_material.set_shader_parameter("camera_right", right)
	shader_material.set_shader_parameter("barrel_center", center)
	shader_material.set_shader_parameter("projection_offset", offset)
	shader_material.set_shader_parameter("radius", radius)
	shader_material.set_shader_parameter("barrel_height", height)


## Stops the whole off-screen target, not just its displayed Sprite2D. The
## ray-march shader is otherwise still evaluated in its 160x120 SubViewport.
func set_screen_active(is_active: bool) -> void:
	visible = is_active
	carrier.visible = is_active
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_active else SubViewport.UPDATE_DISABLED
