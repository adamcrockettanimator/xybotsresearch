## Shared pixel-raster barrel layer.
##
## Barrel geometry stays continuous in 160x120 logical-view coordinates. A
## single SubViewport per player view rasterizes every Canvas barrel into that
## fixed pixel grid; its nearest-filtered texture is then displayed in-game.
## This is deliberately not one viewport per barrel.
extends Node2D


# ====================================================================================================
# 1. SHARED LOGICAL PIXEL TARGET
# The target is the same authored resolution as the game view. It decides which
# pixels are covered by continuous projected shapes, without moving vertices.
# ====================================================================================================
const LOGICAL_CANVAS_SIZE := Vector2i(160, 120)
const LAYER_DEFINITIONS: Array[Dictionary] = [
	{"id": "floor_shadow", "label": "Floor shadow"},
	{"id": "body_silhouette", "label": "Body silhouette"},
	{"id": "body_panels", "label": "Wood face panels"},
	{"id": "body_panel_gradient", "label": "Wood panel smooth gradient"},
	{"id": "body_panel_dithered_gradient", "label": "Wood panel three-colour stepped gradient"},
	{"id": "body_panel_planar_gradient", "label": "Wood planar + height gradient"},
	{"id": "body_panel_borders", "label": "Wood panel borders"},
	{"id": "stave_seams", "label": "Stave seams"},
	{"id": "stave_highlights", "label": "Stave highlights"},
	{"id": "hoop_shadows", "label": "Hoop wood shadows"},
	{"id": "hoops", "label": "Metal hoops"},
	{"id": "hoop_highlights", "label": "Hoop highlights"},
	{"id": "lid_outer", "label": "Lid outer wood"},
	{"id": "lid_inset_shadow", "label": "Lid inset shadow"},
	{"id": "lid_inset", "label": "Lid inset boards"},
	{"id": "lid_seams", "label": "Lid seams"},
	{"id": "lid_seam_highlights", "label": "Lid seam highlights"},
	{"id": "distant_closed_lid", "label": "Distant closed lid"},
	{"id": "lid_rim", "label": "Lid rim"},
]

var pixel_viewport: SubViewport
var raster_root: Node2D
var pixel_display: Sprite2D
var barrel_rasters: Dictionary = {}
var layer_order: Array[String] = []
var layer_visible: Dictionary = {}
var last_geometry_update_us := 0
var last_geometry_point_count := 0


func _ready() -> void:
	_reset_layer_debug()


func _reset_layer_debug() -> void:
	layer_order.clear()
	layer_visible.clear()
	# Adopt the useful construction found in the authoring panel: the lid starts
	# behind the body boards, while the final rim alone closes the top opening.
	var authored_order: Array[String] = [
		"floor_shadow", "body_silhouette", "lid_outer", "lid_inset", "lid_inset_shadow",
		"lid_seam_highlights", "lid_seams", "body_panels", "body_panel_gradient", "body_panel_dithered_gradient", "body_panel_planar_gradient", "body_panel_borders", "stave_seams", "stave_highlights",
		"hoop_shadows", "hoops", "hoop_highlights", "distant_closed_lid", "lid_rim",
	]
	for layer_id in authored_order:
		layer_order.append(layer_id)
		layer_visible[layer_id] = true
	# Default authoring preset: retain every complementary wood treatment visible
	# together, while leaving only genuinely redundant fill, inset shadow, and
	# explicit panel-outline layers disabled.
	layer_visible["body_silhouette"] = false
	layer_visible["body_panels"] = true
	layer_visible["body_panel_gradient"] = true
	layer_visible["body_panel_dithered_gradient"] = true
	layer_visible["body_panel_planar_gradient"] = false
	layer_visible["body_panel_borders"] = false
	layer_visible["lid_inset_shadow"] = false
	layer_visible["stave_seams"] = true
	layer_visible["stave_highlights"] = true


func get_layer_debug_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for layer_id in layer_order:
		for definition in LAYER_DEFINITIONS:
			if definition["id"] == layer_id:
				entries.append({"id": layer_id, "label": definition["label"], "visible": bool(layer_visible.get(layer_id, true))})
				break
	return entries


func set_layer_visible(layer_id: String, is_visible: bool) -> void:
	if not layer_visible.has(layer_id):
		return
	layer_visible[layer_id] = is_visible
	_refresh_layer_debug()


func isolate_layer(layer_id: String) -> void:
	if not layer_visible.has(layer_id):
		return
	for candidate_id in layer_visible:
		layer_visible[candidate_id] = candidate_id == layer_id
	_refresh_layer_debug()


func reveal_all_layers() -> void:
	for layer_id in layer_visible:
		layer_visible[layer_id] = true
	_refresh_layer_debug()


func move_layer(layer_id: String, direction: int) -> void:
	var old_index := layer_order.find(layer_id)
	var new_index := clampi(old_index + direction, 0, layer_order.size() - 1)
	if old_index < 0 or old_index == new_index:
		return
	layer_order.remove_at(old_index)
	layer_order.insert(new_index, layer_id)
	_refresh_layer_debug()


func _refresh_layer_debug() -> void:
	for raster in barrel_rasters.values():
		if is_instance_valid(raster):
			raster.set_layer_debug(layer_order, layer_visible)


# ====================================================================================================
# 2. CPU-TO-PIXEL-RASTER HANDOFF
# One retained layer owns any number of barrel canvases. Each barrel gets a
# named geometry record, but they all draw into the one shared pixel target.
# ====================================================================================================
func set_projected_barrel(
	barrel_id: String,
	new_body_silhouette: PackedVector2Array,
	new_body_panels: Array,
	new_lid_ring: PackedVector2Array,
	new_lid_inset: PackedVector2Array,
	new_lower_hoop: PackedVector2Array,
	new_upper_hoop: PackedVector2Array,
	new_floor_shadow: PackedVector2Array,
	new_stave_segments: PackedVector2Array,
	new_lid_seam_segments: PackedVector2Array,
	new_camera_distance: float,
	draw_layer: int,
	new_body_style: String,
) -> void:
	var started_us := Time.get_ticks_usec()
	_ensure_pixel_target()
	var raster: BarrelPixelRaster = barrel_rasters.get(barrel_id, null)
	if raster == null or not is_instance_valid(raster):
		raster = BarrelPixelRaster.new()
		raster.name = "BarrelPixels_%s" % barrel_id
		raster_root.add_child(raster)
		barrel_rasters[barrel_id] = raster
	raster.z_index = draw_layer
	raster.set_layer_debug(layer_order, layer_visible)
	raster.set_projected_barrel(
		new_body_silhouette,
		new_body_panels,
		new_lid_ring,
		new_lid_inset,
		new_lower_hoop,
		new_upper_hoop,
		new_floor_shadow,
		new_stave_segments,
		new_lid_seam_segments,
		new_camera_distance,
		new_body_style,
	)
	last_geometry_point_count = new_body_silhouette.size() + new_lid_ring.size() + new_lid_inset.size() + new_lower_hoop.size() + new_upper_hoop.size() + new_floor_shadow.size() + new_stave_segments.size() + new_lid_seam_segments.size()
	for panel in new_body_panels:
		if panel is Dictionary and panel.get("points", null) is PackedVector2Array:
			last_geometry_point_count += (panel["points"] as PackedVector2Array).size()
	last_geometry_update_us = Time.get_ticks_usec() - started_us
	visible = true


func get_telemetry() -> Dictionary:
	var active_layers := 0
	for layer_id in layer_order:
		if bool(layer_visible.get(layer_id, true)):
			active_layers += 1
	return {
		"viewport_size": pixel_viewport.size if pixel_viewport != null else Vector2i.ZERO,
		"barrel_count": barrel_rasters.size(),
		"active_layers": active_layers,
		"geometry_update_us": last_geometry_update_us,
		"geometry_points": last_geometry_point_count,
	}


# ====================================================================================================
# 3. ONE VIEWPORT, MANY BARRELS
# This viewport belongs to the player view's complete Canvas-prop layer. It is
# never created by an individual barrel raster, so a populated map still has
# one 160x120 texture per player—not a texture per prop.
# ====================================================================================================
func _ensure_pixel_target() -> void:
	if pixel_viewport != null:
		return
	pixel_viewport = SubViewport.new()
	pixel_viewport.name = "SemanticCanvasPropPixelViewport"
	pixel_viewport.size = LOGICAL_CANVAS_SIZE
	pixel_viewport.transparent_bg = true
	pixel_viewport.disable_3d = true
	pixel_viewport.gui_disable_input = true
	pixel_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pixel_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pixel_viewport)

	raster_root = Node2D.new()
	raster_root.name = "SemanticCanvasPropRasterRoot"
	pixel_viewport.add_child(raster_root)

	pixel_display = Sprite2D.new()
	pixel_display.name = "SemanticCanvasPropPixelDisplay"
	pixel_display.centered = false
	pixel_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pixel_display.texture = pixel_viewport.get_texture()
	add_child(pixel_display)


# ====================================================================================================
# 4. ONE BARREL'S LOW-RES CANVAS
# This child owns shapes, never a viewport. Godot fills its continuous polygons
# and strokes at the shared target's 160x120 resolution, creating the desired
# stepped pixel coverage only after projection has already established form.
# ====================================================================================================
class BarrelPixelRaster extends Node2D:
	# -----------------------------------------------------------------------------------------------
	# 4A. AUTHORED MATERIAL PALETTE
	# -----------------------------------------------------------------------------------------------
	# This is the reference barrel's warm base wood. Its volume comes from
	# lighting, not by pushing the unlit paint toward yellow.
	const BODY_WOOD := Color8(133, 92, 56)
	const BODY_WOOD_DARK := Color8(62, 43, 27)
	const BODY_WOOD_DITHER_DARK := Color8(96, 66, 40)
	const BODY_WOOD_DITHER_MID := Color8(126, 87, 53)
	const BODY_WOOD_DITHER_LIGHT := Color8(158, 109, 66)
	const BAYER_4X4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	const BODY_PANEL_BORDER := Color(0.20, 0.13, 0.075, 0.58)
	const LID_TOP_WOOD := Color8(118, 82, 49)
	const LID_FAR_CAP_WOOD := Color8(132, 90, 48)
	const LID_INSET_WOOD := Color8(153, 106, 64)
	const LID_RIM_WOOD := LID_INSET_WOOD
	const LID_INSET_SHADOW := Color8(73, 49, 29)
	# Small accents, not outlines: wood texture should never beat the broad form.
	const STAVE_DARK := Color(0.25, 0.15, 0.08, 0.30)
	const STAVE_LIGHT := Color(0.95, 0.65, 0.34, 0.22)
	const METAL := Color8(40, 38, 34)
	const METAL_LOWER := Color8(62, 58, 50)
	const METAL_BRIGHT := Color8(108, 102, 88)
	const METAL_HIGHLIGHT := Color8(138, 130, 111)
	const METAL_SOFT_LIGHT := Color8(65, 62, 54)
	# A hoop casts only a modest wood-darkening edge. Keep it lighter than the
	# actual stave seam, which represents a deeper gap between boards.
	const HOOP_WOOD_SHADOW := Color(0.25, 0.15, 0.08, 0.20)
	const FLOOR_SHADOW := Color(0.12, 0.08, 0.045, 0.28)
	# These neutral swatches intentionally match the unpainted Curved Lines
	# source barrel. It makes that source unmistakable in gameplay before its
	# art pass, instead of pretending it already belongs to the warm wood set.
	const AUTHORED_VECTOR_BODY := Color8(112, 112, 112)
	const AUTHORED_VECTOR_LID := Color8(132, 132, 132)
	const AUTHORED_VECTOR_METAL := Color8(236, 236, 236)
	const AUTHORED_VECTOR_METAL_CENTRE := Color8(255, 255, 255)

	# -----------------------------------------------------------------------------------------------
	# 4B. CONTINUOUS PROJECTED GEOMETRY
	# These are intentionally not rounded. The low-resolution viewport, rather
	# than the projection, turns their coverage into authored game pixels.
	# -----------------------------------------------------------------------------------------------
	var body_silhouette := PackedVector2Array()
	var body_panels: Array[Dictionary] = []
	var lid_ring := PackedVector2Array()
	var lid_inset := PackedVector2Array()
	var lower_hoop := PackedVector2Array()
	var upper_hoop := PackedVector2Array()
	var floor_shadow := PackedVector2Array()
	var stave_segments := PackedVector2Array()
	var lid_seam_segments := PackedVector2Array()
	var camera_distance := INF
	var body_style := "smooth"
	var layer_order: Array[String] = []
	var layer_visible: Dictionary = {}

	func set_layer_debug(new_order: Array[String], new_visibility: Dictionary) -> void:
		layer_order = new_order.duplicate()
		layer_visible = new_visibility.duplicate()
		queue_redraw()

	# -----------------------------------------------------------------------------------------------
	# 4C. GEOMETRY UPDATE
	# -----------------------------------------------------------------------------------------------
	func set_projected_barrel(
		new_body_silhouette: PackedVector2Array,
		new_body_panels: Array,
		new_lid_ring: PackedVector2Array,
		new_lid_inset: PackedVector2Array,
		new_lower_hoop: PackedVector2Array,
		new_upper_hoop: PackedVector2Array,
		new_floor_shadow: PackedVector2Array,
		new_stave_segments: PackedVector2Array,
		new_lid_seam_segments: PackedVector2Array,
		new_camera_distance: float,
		new_body_style: String,
	) -> void:
		body_silhouette = new_body_silhouette
		body_panels.clear()
		for panel in new_body_panels:
			if panel is Dictionary and panel.get("points", null) is PackedVector2Array:
				body_panels.append(panel)
		lid_ring = new_lid_ring
		lid_inset = new_lid_inset
		lower_hoop = new_lower_hoop
		upper_hoop = new_upper_hoop
		floor_shadow = new_floor_shadow
		stave_segments = new_stave_segments
		lid_seam_segments = new_lid_seam_segments
		camera_distance = new_camera_distance
		body_style = new_body_style
		visible = body_silhouette.size() >= 3 and lid_ring.size() >= 3
		queue_redraw()

	# -----------------------------------------------------------------------------------------------
	# 4D. DIRECT SHAPE LAYERS
	# The fill and line calls are still ordinary Canvas drawing. Their pixel-art
	# appearance comes from rasterizing this whole layer inside the shared target.
	# -----------------------------------------------------------------------------------------------
	func _draw() -> void:
		if not visible:
			return
		for layer_id in layer_order:
			if bool(layer_visible.get(layer_id, true)):
				_draw_layer(layer_id)


	func _draw_layer(layer_id: String) -> void:
		match layer_id:
			"floor_shadow":
				_draw_bottom_contact_edge()
			"body_silhouette": draw_colored_polygon(body_silhouette, AUTHORED_VECTOR_BODY if body_style == "authored_vector" else BODY_WOOD)
			"body_panels":
				for panel in body_panels:
					var panel_points: PackedVector2Array = panel["points"]
					var panel_light := clampf(float(panel.get("light", 0.7)), 0.38, 1.15)
					var panel_color := AUTHORED_VECTOR_BODY.lerp(AUTHORED_VECTOR_LID, (panel_light - 0.38) / 0.77) if body_style == "authored_vector" else Color(BODY_WOOD.r * panel_light, BODY_WOOD.g * panel_light, BODY_WOOD.b * panel_light, 1.0)
					draw_colored_polygon(panel_points, panel_color)
			"body_panel_gradient":
				if body_style == "smooth": _draw_smooth_wood_panels()
				elif body_style == "authored_vector": _draw_authored_vector_panels()
			"body_panel_dithered_gradient":
				if body_style == "three_colour_steps": _draw_three_colour_stepped_wood_panels()
			"body_panel_planar_gradient":
				_draw_planar_height_wood_panels()
			"body_panel_borders":
				_draw_wood_panel_borders()
			"stave_seams":
				# Keep the stave rhythm present through the middle LOD. Its low-contrast
				# fade carries the "wooden barrel" read farther than a dark outline would.
				var seam_fade := 1.0 - smoothstep(2.25, 3.60, camera_distance)
				if seam_fade > 0.01 and body_style != "authored_vector":
					var fading_seam := STAVE_DARK
					fading_seam.a *= seam_fade
					_draw_segment_pairs(stave_segments, fading_seam)
			"stave_highlights":
				var stave_highlight_fade := 1.0 - smoothstep(1.75, 3.25, camera_distance)
				if stave_highlight_fade > 0.01 and body_style != "authored_vector":
					var fading_stave_highlight := STAVE_LIGHT
					fading_stave_highlight.a *= stave_highlight_fade
					_draw_segment_pairs(stave_segments, fading_stave_highlight, Vector2.RIGHT)
			"hoop_shadows":
				# Pixel-art LOD changes in discrete, readable stages—never through a
				# half-transparent in-between row. The wood shadow is the last extra
				# mark to leave, after the highlight and upper metal have gone.
				# Retain the subtle wood-darkening line through the middle LOD. Without
				# it, the surviving one-pixel metal band reads flat before the staves do.
				var hoop_shadow_fade := 1.0 - smoothstep(2.25, 3.60, camera_distance)
				if hoop_shadow_fade > 0.01:
					var fading_hoop_shadow := HOOP_WOOD_SHADOW
					fading_hoop_shadow.a *= hoop_shadow_fade
					_draw_open_polyline(lower_hoop, fading_hoop_shadow, Vector2.DOWN * 2.0)
					_draw_open_polyline(upper_hoop, fading_hoop_shadow, Vector2.DOWN * 2.0)
			"hoops":
				# The close hoop is two matching metal rows. Both receive the same
				# outer-dark to centre-bright sweep, so it reads as one shiny band
				# instead of a light top stripe above a different dark stripe.
				if camera_distance < 1.75:
					_draw_gradient_hoop(lower_hoop, METAL)
					_draw_gradient_hoop(upper_hoop, METAL)
				# This lower row survives as the distant one-pixel metal hoop.
				_draw_gradient_hoop(lower_hoop, METAL, Vector2.DOWN)
				_draw_gradient_hoop(upper_hoop, METAL, Vector2.DOWN)
			"hoop_highlights":
				# It is solid metal at close range, then fades farther out than before.
				# This fade completes before the upper metal row has its discrete exit.
				var highlight_alpha := 1.0 - smoothstep(1.05, 1.65, camera_distance)
				if highlight_alpha > 0.01:
					var highlight_metal := METAL_SOFT_LIGHT
					highlight_metal.a = highlight_alpha
					# Close-range hoop stack, top to bottom: one light-catching edge,
					# two grey metal rows, then the transparent wood shadow. The separate
					# highlight fades first so the hoop becomes compact with distance.
					_draw_gradient_hoop(lower_hoop, highlight_metal, Vector2.UP, METAL_HIGHLIGHT)
					_draw_gradient_hoop(upper_hoop, highlight_metal, Vector2.UP, METAL_HIGHLIGHT)
			"lid_outer": _draw_authored_vector_lid() if body_style == "authored_vector" else _draw_gradient_lid_outer()
			"lid_inset_shadow":
				if lid_inset.size() >= 3: draw_colored_polygon(_offset_polygon(lid_inset, Vector2.DOWN), LID_INSET_SHADOW)
			"lid_inset":
				if body_style != "authored_vector" and lid_inset.size() >= 3: draw_colored_polygon(lid_inset, LID_INSET_WOOD)
			"lid_seams":
				if body_style != "authored_vector" and camera_distance < 2.5: _draw_segment_pairs(lid_seam_segments, STAVE_DARK)
			"lid_seam_highlights":
				if body_style != "authored_vector" and camera_distance < 1.7: _draw_segment_pairs(lid_seam_segments, STAVE_LIGHT, Vector2.RIGHT)
			"distant_closed_lid":
				if camera_distance >= 2.15: draw_colored_polygon(lid_ring, LID_FAR_CAP_WOOD)
			"lid_rim": _draw_lod_lid_rim()


	func _draw_smooth_wood_panels() -> void:
		# Mirror the reference barrel's material rule on ordinary Canvas polygons:
		# darken the outside curve, then brighten from the lower rim to the top.
		# Each projected board receives its own four vertex colours, so its edges
		# remain visible without becoming separate flat colour tiles.
		for panel in body_panels:
			var panel_points: PackedVector2Array = panel["points"]
			if panel_points.size() != 4:
				continue
			var round_light := clampf(float(panel.get("light", 0.7)), 0.68, 1.0)
			var lower_height := clampf(float(panel.get("lower_height", 0.0)), 0.0, 1.0)
			var upper_height := clampf(float(panel.get("upper_height", 1.0)), 0.0, 1.0)
			var lower_color := _wood_color(round_light * lerpf(0.68, 1.15, lower_height))
			var upper_color := _wood_color(round_light * lerpf(0.68, 1.15, upper_height))
			draw_polygon(panel_points, PackedColorArray([lower_color, lower_color, upper_color, upper_color]))


	func _draw_authored_vector_panels() -> void:
		# This is the deliberately plain source barrel: a grey curved body with a
		# broad centre lift, not a second attempt at finished wood painting.
		for panel in body_panels:
			var panel_points: PackedVector2Array = panel["points"]
			if panel_points.size() != 4:
				continue
			var light := clampf(float(panel.get("light", 0.7)), 0.68, 1.0)
			var shade := AUTHORED_VECTOR_BODY.lerp(AUTHORED_VECTOR_LID, (light - 0.68) / 0.32)
			draw_colored_polygon(panel_points, shade)


	func _draw_three_colour_dithered_wood_panels() -> void:
		# Comparison variant: calculate the same continuous body-light amount, but
		# express it through only three authored colours. The 4x4 Bayer order is
		# indexed in barrel-local stave/height coordinates—not screen pixels—so the
		# pattern is bound to this curved surface instead of crawling across it.
		for panel in body_panels:
			var panel_points: PackedVector2Array = panel["points"]
			if panel_points.size() != 4:
				continue
			var min_x := panel_points[0].x
			var max_x := panel_points[0].x
			var min_y := panel_points[0].y
			var max_y := panel_points[0].y
			for point in panel_points:
				min_x = minf(min_x, point.x)
				max_x = maxf(max_x, point.x)
				min_y = minf(min_y, point.y)
				max_y = maxf(max_y, point.y)
			var lower_y := (panel_points[0].y + panel_points[1].y) * 0.5
			var upper_y := (panel_points[2].y + panel_points[3].y) * 0.5
			var vertical_span := upper_y - lower_y
			if absf(vertical_span) < 0.001:
				continue
			var round_light := clampf(float(panel.get("light", 0.7)), 0.68, 1.0)
			for pixel_y in range(floori(min_y), ceili(max_y)):
				for pixel_x in range(floori(min_x), ceili(max_x)):
					var sample_point := Vector2(float(pixel_x) + 0.5, float(pixel_y) + 0.5)
					if not Geometry2D.is_point_in_polygon(sample_point, panel_points):
						continue
					var panel_v := clampf((sample_point.y - lower_y) / vertical_span, 0.0, 1.0)
					var left_edge := panel_points[0].lerp(panel_points[3], panel_v)
					var right_edge := panel_points[1].lerp(panel_points[2], panel_v)
					var edge_span := right_edge - left_edge
					var panel_u := clampf((sample_point - left_edge).dot(edge_span) / maxf(0.001, edge_span.length_squared()), 0.0, 1.0)
					var lower_height := float(panel.get("lower_height", 0.0))
					var upper_height := float(panel.get("upper_height", 1.0))
					var barrel_height := lerpf(lower_height, upper_height, panel_v)
					var continuous_light := round_light * lerpf(0.68, 1.15, barrel_height)
					var stepped_light := clampf((continuous_light - 0.55) / 0.60 * 2.0, 0.0, 2.0)
					var lower_step := clampi(floori(stepped_light), 0, 2)
					var step_fraction := stepped_light - float(lower_step)
					var stave_index := int(panel.get("stave_index", 0))
					var dither_u := floori(panel_u * 12.0) + stave_index * 12
					var dither_v := floori(barrel_height * 24.0)
					var bayer_index := posmod(dither_u, 4) + posmod(dither_v, 4) * 4
					var bayer_threshold := (float(BAYER_4X4[bayer_index]) + 0.5) / 16.0
					var colour_step := lower_step
					if step_fraction > bayer_threshold:
						colour_step = mini(colour_step + 1, 2)
					var wood_colour := BODY_WOOD_DITHER_MID
					if colour_step == 0:
						wood_colour = BODY_WOOD_DITHER_DARK
					elif colour_step == 2:
						wood_colour = BODY_WOOD_DITHER_LIGHT
					draw_rect(Rect2(Vector2(float(pixel_x), float(pixel_y)), Vector2.ONE), wood_colour)


	func _draw_three_colour_stepped_wood_panels() -> void:
		# This is the non-dither comparison: calculate lighting at each body pixel,
		# then snap it to dark, mid, or light. The resulting hard bands follow the
		# curved barrel surface, instead of making each whole board one flat tile.
		for panel in body_panels:
			var panel_points: PackedVector2Array = panel["points"]
			if panel_points.size() != 4:
				continue
			var min_x := panel_points[0].x
			var max_x := panel_points[0].x
			var min_y := panel_points[0].y
			var max_y := panel_points[0].y
			for point in panel_points:
				min_x = minf(min_x, point.x)
				max_x = maxf(max_x, point.x)
				min_y = minf(min_y, point.y)
				max_y = maxf(max_y, point.y)
			var lower_y := (panel_points[0].y + panel_points[1].y) * 0.5
			var upper_y := (panel_points[2].y + panel_points[3].y) * 0.5
			var vertical_span := upper_y - lower_y
			if absf(vertical_span) < 0.001:
				continue
			var round_light := clampf(float(panel.get("light", 0.7)), 0.68, 1.0)
			var lower_height := float(panel.get("lower_height", 0.0))
			var upper_height := float(panel.get("upper_height", 1.0))
			for pixel_y in range(floori(min_y), ceili(max_y)):
				for pixel_x in range(floori(min_x), ceili(max_x)):
					var sample_point := Vector2(float(pixel_x) + 0.5, float(pixel_y) + 0.5)
					if not Geometry2D.is_point_in_polygon(sample_point, panel_points):
						continue
					var panel_v := clampf((sample_point.y - lower_y) / vertical_span, 0.0, 1.0)
					var barrel_height := lerpf(lower_height, upper_height, panel_v)
					var continuous_light := round_light * lerpf(0.68, 1.15, barrel_height)
					var stepped_light := clampf((continuous_light - 0.55) / 0.60 * 2.0, 0.0, 2.0)
					var colour_step := clampi(roundi(stepped_light), 0, 2)
					var wood_colour := BODY_WOOD_DITHER_MID
					if colour_step == 0:
						wood_colour = BODY_WOOD_DITHER_DARK
					elif colour_step == 2:
						wood_colour = BODY_WOOD_DITHER_LIGHT
					draw_rect(Rect2(Vector2(float(pixel_x), float(pixel_y)), Vector2.ONE), wood_colour)


	func _draw_wood_panel_borders() -> void:
		for panel in body_panels:
			var panel_points: PackedVector2Array = panel["points"]
			if panel_points.size() == 4:
				_draw_closed_polyline(panel_points, BODY_PANEL_BORDER)


	func _draw_planar_height_wood_panels() -> void:
		# Hybrid comparison: preserve the existing planar brightness from each
		# world-facing panel, then apply one restrained vertical barrel-volume ramp.
		if body_silhouette.size() < 3:
			return
		var body_top := body_silhouette[0].y
		var body_bottom := body_silhouette[0].y
		for body_point in body_silhouette:
			body_top = minf(body_top, body_point.y)
			body_bottom = maxf(body_bottom, body_point.y)
		var body_height := maxf(1.0, body_bottom - body_top)
		for panel in body_panels:
			var panel_points: PackedVector2Array = panel["points"]
			if panel_points.size() != 4:
				continue
			var planar_light := clampf(float(panel.get("light", 0.7)), 0.38, 1.15)
			var colors := PackedColorArray()
			for panel_point in panel_points:
				var down_body := clampf((panel_point.y - body_top) / body_height, 0.0, 1.0)
				var height_light := lerpf(1.0, 0.72, down_body)
				colors.append(_wood_color(planar_light * height_light))
			draw_polygon(panel_points, colors)


	func _draw_gradient_hoop(points: PackedVector2Array, color: Color, offset := Vector2.ZERO, centre_metal := METAL_BRIGHT) -> void:
		if points.size() < 2:
			return
		if body_style == "authored_vector":
			color = AUTHORED_VECTOR_METAL
			centre_metal = AUTHORED_VECTOR_METAL_CENTRE
		for index in range(points.size() - 1):
			var segment_start := points[index] + offset
			var segment_end := points[index + 1] + offset
			# A coarse 6-segment arc made only six flat colour bands. Split each
			# curved segment into logical-pixel-sized pieces so the value can ramp
			# continuously from dark outer metal to the bright front centre.
			var slice_count := maxi(1, ceili(segment_start.distance_to(segment_end)))
			for slice in range(slice_count):
				var local_start := float(slice) / float(slice_count)
				var local_end := float(slice + 1) / float(slice_count)
				var arc_position := (float(index) + (local_start + local_end) * 0.5) / float(points.size() - 1)
				var center_amount := sin(arc_position * PI)
				var slice_color := color.lerp(centre_metal, center_amount * color.a)
				slice_color.a = color.a
				draw_line(segment_start.lerp(segment_end, local_start), segment_start.lerp(segment_end, local_end), slice_color, 1.0, false)


	func _draw_gradient_lid_outer() -> void:
		if lid_ring.size() < 3:
			return
		var top_y := lid_ring[0].y
		var bottom_y := lid_ring[0].y
		for point in lid_ring:
			top_y = minf(top_y, point.y)
			bottom_y = maxf(bottom_y, point.y)
		var span := maxf(1.0, bottom_y - top_y)
		var colors := PackedColorArray()
		for point in lid_ring:
			var down_amount := (point.y - top_y) / span
			colors.append(LID_TOP_WOOD.lerp(LID_TOP_WOOD.darkened(0.28), down_amount))
		draw_polygon(lid_ring, colors)


	func _draw_authored_vector_lid() -> void:
		if lid_ring.size() >= 3:
			draw_colored_polygon(lid_ring, AUTHORED_VECTOR_LID)


	func _draw_lod_lid_rim() -> void:
		if lid_ring.size() < 3:
			return
		# The rim must thicken the barrel inward from its true silhouette—not use
		# a wide centred line, which would hang half its width outside the barrel.
		# Its colours use the same top-of-body lighting rule as the panels below.
		if camera_distance < 1.10:
			_draw_inner_lid_rim_band(2.0)
			_draw_foreground_lid_bevel()
		elif camera_distance < 1.70:
			_draw_inner_lid_rim_band(1.0)
		else:
			_draw_inner_lid_rim_band(0.5)


	func _lid_ring_center() -> Vector2:
		var center := Vector2.ZERO
		for point in lid_ring:
			center += point
		return center / float(lid_ring.size())


	func _draw_inner_lid_rim_band(thickness: float) -> void:
		var center := _lid_ring_center()
		for index in lid_ring.size():
			var next_index := (index + 1) % lid_ring.size()
			var outer_a := lid_ring[index]
			var outer_b := lid_ring[next_index]
			var inner_a := outer_a.move_toward(center, thickness)
			var inner_b := outer_b.move_toward(center, thickness)
			# Keep the wooden collar as one simple, flat material. The form comes
			# from its geometry and the separate foreground bevel—not a colour ramp.
			draw_colored_polygon(PackedVector2Array([outer_a, outer_b, inner_b, inner_a]), LID_RIM_WOOD)


	func _draw_foreground_lid_bevel() -> void:
		var center := _lid_ring_center()
		var center_y := center.y
		var half_width := 1.0
		for point in lid_ring:
			half_width = maxf(half_width, absf(point.x - center.x))
		for index in lid_ring.size():
			var next_index := (index + 1) % lid_ring.size()
			var midpoint_y := (lid_ring[index].y + lid_ring[next_index].y) * 0.5
			if midpoint_y >= center_y:
				# The foreground outer perimeter is also where the staves meet the lid.
				# Keeping the bevel on that shared edge makes the barrel feel thick,
				# rather than placing a floating light line inside the opening.
				var midpoint_x := (lid_ring[index].x + lid_ring[next_index].x) * 0.5
				var across := clampf((midpoint_x - center.x) / half_width, -1.0, 1.0)
				var centre_amount := sqrt(maxf(0.0, 1.0 - across * across))
				var fading_bevel := STAVE_LIGHT
				fading_bevel.a *= centre_amount
				draw_line(lid_ring[index], lid_ring[next_index], fading_bevel, 1.0, false)


	func _wood_color(light: float) -> Color:
		var bounded_light := clampf(light, 0.38, 1.15)
		return Color(BODY_WOOD.r * bounded_light, BODY_WOOD.g * bounded_light, BODY_WOOD.b * bounded_light, 1.0)


	func _draw_bottom_contact_edge() -> void:
		if body_silhouette.size() < 3:
			return
		var center_y := 0.0
		for point in body_silhouette:
			center_y += point.y
		center_y /= float(body_silhouette.size())
		# One quiet dark wood pixel along the near/lower perimeter grounds the
		# barrel. It replaces the broad translucent floor blob at this scale.
		for index in body_silhouette.size():
			var next_index := (index + 1) % body_silhouette.size()
			var midpoint_y := (body_silhouette[index].y + body_silhouette[next_index].y) * 0.5
			if midpoint_y >= center_y:
				draw_line(body_silhouette[index], body_silhouette[next_index], STAVE_DARK, 1.0, false)

	# -----------------------------------------------------------------------------------------------
	# 4E. SMALL DRAWING HELPERS
	# -----------------------------------------------------------------------------------------------
	func _draw_hoop(ring: PackedVector2Array) -> void:
		if ring.size() < 3:
			return
		if camera_distance < 1.6:
			_draw_open_polyline(ring, BODY_WOOD_DARK, Vector2.DOWN)
		_draw_open_polyline(ring, METAL)
		if camera_distance < 1.4:
			_draw_open_polyline(ring, METAL_SOFT_LIGHT)


	func _draw_segment_pairs(segments: PackedVector2Array, color: Color, offset := Vector2.ZERO) -> void:
		for index in range(0, segments.size() - 1, 2):
			draw_line(segments[index] + offset, segments[index + 1] + offset, color, 1.0, false)


	func _draw_closed_polyline(points: PackedVector2Array, color: Color, offset := Vector2.ZERO, width := 1.0) -> void:
		if points.size() < 3:
			return
		var closed := points.duplicate()
		closed.append(points[0])
		for index in closed.size() - 1:
			draw_line(closed[index] + offset, closed[index + 1] + offset, color, width, false)


	func _draw_open_polyline(points: PackedVector2Array, color: Color, offset := Vector2.ZERO) -> void:
		for index in range(points.size() - 1):
			draw_line(points[index] + offset, points[index + 1] + offset, color, 1.0, false)


	func _offset_polygon(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
		var result := PackedVector2Array()
		for point in points:
			result.append(point + offset)
		return result
