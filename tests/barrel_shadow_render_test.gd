extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 96)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var floor_rect := ColorRect.new()
	floor_rect.size = Vector2(96, 96)
	floor_rect.color = Color(0.8, 0.6, 0.3, 1.0)
	viewport.add_child(floor_rect)
	var shadow := Sprite2D.new()
	shadow.centered = false
	shadow.texture = load("res://assets/Props/Barrel_16Dir/N.png")
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow.position = Vector2(32, 33)
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/barrel_contact_shadow.gdshader")
	shadow.material = material
	viewport.add_child(shadow)
	var barrel := Sprite2D.new()
	barrel.centered = false
	barrel.texture = shadow.texture
	barrel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	barrel.position = Vector2(32, 32)
	viewport.add_child(barrel)
	# A second copy without a barrel in front makes the ten-row crop measurable.
	var exposed_mask := shadow.duplicate() as Sprite2D
	exposed_mask.position = Vector2(64, 33)
	viewport.add_child(exposed_mask)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	var floor_color := result.get_pixel(20, 64)
	var shadow_color := result.get_pixel(48, 64)
	var outside_color := result.get_pixel(32, 64)
	var above_crop_color := result.get_pixel(80, 54) # Source row 21 is outside the last ten rows.
	var inside_crop_color := result.get_pixel(80, 55) # Source row 22 begins the cropped silhouette.
	var passed := shadow_color.r < floor_color.r and shadow_color.g < floor_color.g and shadow_color.b < floor_color.b and outside_color.is_equal_approx(floor_color) and above_crop_color.is_equal_approx(floor_color) and inside_crop_color.r < floor_color.r
	print("floor=%s shadow=%s outside=%s above_crop=%s inside_crop=%s" % [floor_color, shadow_color, outside_color, above_crop_color, inside_crop_color])
	viewport.queue_free()
	if not passed:
		push_error("Rendered shadow did not darken the floor only beneath the barrel silhouette")
		quit(1)
		return
	print("Barrel shadow render test passed")
	quit(0)
