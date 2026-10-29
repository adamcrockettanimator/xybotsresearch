## Places the artist-authored Curved Lines barrel directly in a live game view.
## The six source objects remain the actual rear body, front body, rim, and hoops.
extends Node2D


const AUTHORED_VECTOR_SCENE := preload("res://tests/calibration/semantic_canvas_barrel_editor_preview.tscn")
const SOURCE_FEET_ANCHOR := Vector2(50.0, 293.0)
const SOURCE_ART_HEIGHT := 121.0
const LOGICAL_VIEW_SIZE := Vector2i(160, 120)
const SOURCE_HEIGHT_TO_ACTOR_HEIGHT := 0.48

var source_barrels: Dictionary = {}
var used_source_ids: Dictionary = {}
var pixel_viewport: SubViewport
var raster_root: Node2D
var pixel_display: Sprite2D


func _ready() -> void:
	# The Curved Lines plugin is still free to evaluate its continuous curves,
	# but this one shared logical target decides their final pixel coverage.
	# That gives the authored source the same hard-pixel language as the game.
	pixel_viewport = SubViewport.new()
	pixel_viewport.name = "AuthoredVectorBarrelPixelViewport"
	pixel_viewport.size = LOGICAL_VIEW_SIZE
	pixel_viewport.transparent_bg = true
	pixel_viewport.disable_3d = true
	pixel_viewport.gui_disable_input = true
	pixel_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pixel_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pixel_viewport)
	raster_root = Node2D.new()
	raster_root.name = "AuthoredVectorBarrelRasterRoot"
	pixel_viewport.add_child(raster_root)
	pixel_display = Sprite2D.new()
	pixel_display.name = "AuthoredVectorBarrelPixelDisplay"
	pixel_display.centered = false
	pixel_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pixel_display.texture = pixel_viewport.get_texture()
	add_child(pixel_display)


## A player view calls this once before offering its visible vector props.
## Any source not re-submitted by end_frame is fully hidden and its viewport
## stops updating when no authored barrels survive culling.
func begin_frame() -> void:
	used_source_ids.clear()


func end_frame() -> void:
	var has_visible_source := false
	for barrel_id in source_barrels:
		var source: Node2D = source_barrels[barrel_id]
		var is_used := used_source_ids.has(barrel_id)
		source.visible = is_used
		has_visible_source = has_visible_source or is_used
	pixel_display.visible = has_visible_source
	pixel_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if has_visible_source else SubViewport.UPDATE_DISABLED


func set_projected_barrel(barrel_id: String, feet: Vector2, projected_actor_height: float, draw_layer: int) -> void:
	# A target which was idle last frame must wake as soon as a barrel passes
	# culling; waiting for end_frame would make the prop appear a frame late.
	pixel_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var source_barrel: Node2D = source_barrels.get(barrel_id, null)
	if source_barrel == null or not is_instance_valid(source_barrel):
		source_barrel = AUTHORED_VECTOR_SCENE.instantiate() as Node2D
		source_barrel.name = "AuthoredVectorSource_%s" % barrel_id
		source_barrel.set("runtime_asset_only", true)
		# Keep the source curves visible for this first live comparison.
		source_barrel.set("preview_lod", 1)
		raster_root.add_child(source_barrel)
		source_barrels[barrel_id] = source_barrel
	# The direct source was a little too dominant beside the established prop
	# ruler. Its physical floor anchor stays fixed; only its displayed height is
	# brought to the barrel's shared visual scale.
	var displayed_height := maxf(4.0, projected_actor_height * SOURCE_HEIGHT_TO_ACTOR_HEIGHT)
	var source_scale := displayed_height / SOURCE_ART_HEIGHT
	source_barrel.scale = Vector2.ONE * source_scale
	source_barrel.position = (feet - SOURCE_FEET_ANCHOR * source_scale).round()
	# The source nodes retain their relative painter order inside the shared
	# target. The target itself stays in the view's prop layer.
	source_barrel.z_index = draw_layer
	visible = true
	used_source_ids[barrel_id] = true
