## One real projected-Canvas barrel, driven through the same controller and
## camera projection as the calibration game. This is intentionally not a
## synthetic geometry preview.
extends "res://tests/calibration/primitive_sprite_gallery_game.gd"


var layer_panel: VBoxContainer
var telemetry: Label
var canvas_barrel: Node
var tracked_game: Node
var sample_count := 0
var gpu_ms_sum := 0.0


func _ready() -> void:
	super._ready()
	call_deferred("_isolate_real_canvas_barrel")


func _isolate_real_canvas_barrel() -> void:
	for frame in 4:
		await get_tree().process_frame
	tracked_game = get_node_or_null("CoordinateFrameGame")
	if tracked_game == null:
		push_error("Canvas barrel lab could not find CoordinateFrameGame")
		return
	var source_fixture := {}
	for fixture in tracked_game.semantic_lod_floor_footprints:
		if String(fixture.get("id", "")) == "barrel_projected_canvas_experiment":
			source_fixture = fixture.duplicate()
			break
	if source_fixture.is_empty():
		push_error("Canvas barrel lab could not find the real Canvas fixture")
		return
	for node in tracked_game.semantic_lod_floor_outline_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	tracked_game.semantic_lod_floor_outline_nodes.clear()
	tracked_game.semantic_lod_floor_footprints.clear()
	tracked_game.semantic_lod_floor_footprints.append(source_fixture)
	# Keep the genuine world/camera calculation but hide the unrelated gallery
	# and player art, leaving a clean black stage around this one real barrel.
	var content := tracked_game.get_node_or_null("MazeViewport/Clipper/Content")
	if content != null:
		for child in content.get_children():
			if child.name != "CombatVisuals":
				child.visible = false
	for frame in 3:
		tracked_game._render_live_semantic_floor_footprints()
		await get_tree().process_frame
	var nodes: Dictionary = tracked_game.semantic_lod_floor_outline_nodes
	for node_key in nodes:
		if String(node_key).contains("projected_canvas"):
			canvas_barrel = nodes[node_key]
			break
	if canvas_barrel == null:
		push_error("Canvas barrel lab did not create its projected Canvas node")
		return
	RenderingServer.viewport_set_measure_render_time(canvas_barrel.pixel_viewport.get_viewport_rid(), true)
	_build_panel()


func _process(_delta: float) -> void:
	if canvas_barrel == null or not is_instance_valid(canvas_barrel):
		return
	gpu_ms_sum += RenderingServer.viewport_get_measured_render_time_gpu(canvas_barrel.pixel_viewport.get_viewport_rid())
	sample_count += 1
	if sample_count % 12 == 0 and telemetry != null:
		var stats: Dictionary = canvas_barrel.get_telemetry()
		telemetry.text = "REAL RASTER TELEMETRY\nTarget: %s | barrels: %d\nActive layers: %d\nGeometry update: %d µs\nGeometry points: %d\nCanvas GPU: %.3f ms\nFPS: %.1f\nDraw calls: %d\nPrimitives: %d\nTexture memory: %.1f MB" % [str(stats["viewport_size"]), int(stats["barrel_count"]), int(stats["active_layers"]), int(stats["geometry_update_us"]), int(stats["geometry_points"]), gpu_ms_sum / float(sample_count), Performance.get_monitor(Performance.TIME_FPS), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0]
		gpu_ms_sum = 0.0
		sample_count = 0


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(660.0, 8.0)
	panel.size = Vector2(292.0, 620.0)
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	layer_panel = VBoxContainer.new()
	layer_panel.custom_minimum_size.x = 268.0
	scroll.add_child(layer_panel)
	var title := Label.new()
	title.text = "REAL CANVAS BARREL\nFollows game projection"
	layer_panel.add_child(title)
	var reveal := Button.new()
	reveal.text = "Enable all layers"
	reveal.pressed.connect(func() -> void: canvas_barrel.reveal_all_layers())
	layer_panel.add_child(reveal)
	for entry in canvas_barrel.get_layer_debug_entries():
		var check := CheckBox.new()
		check.text = String(entry["label"])
		check.button_pressed = bool(entry["visible"])
		check.toggled.connect(_set_real_layer.bind(String(entry["id"])))
		layer_panel.add_child(check)
	telemetry = Label.new()
	telemetry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer_panel.add_child(telemetry)


func _set_real_layer(is_on: bool, layer_id: String) -> void:
	canvas_barrel.set_layer_visible(layer_id, is_on)
