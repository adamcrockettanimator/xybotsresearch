extends Node

@export var town_level_override: TownLevelRecipe
@export var player_sprite_scale_override := 0.0
@export var outdoor_town_music_enabled := false
@export var show_floor_grid := false
@export var separate_cowboy := false

# Ten render pixels per world pixel give the 1.3x cowboy 13 samples per art texel.
const COWBOY_TARGET_SCALE := 10

# Isolated comparison only: the shipping town scene and its default renderer
# remain untouched. F12 switches the existing player view between paths.
var game: Node
var content: Node2D
var clipper: Node
var shared_target: SubViewport
var display: Sprite2D
var shared_enabled := false
var prop_bridge: Node
var pixel_adapter: RefCounted
var mode_label: Label
var mode_label_time := 0.0
var sprite_target: SubViewport
var sprite_display: Sprite2D
var sprite_root: Node2D
var split_sprites := false
var sprite_parents := {}


func _ready() -> void:
	var town := preload("res://generated_coffee_town.tscn").instantiate()
	if town_level_override != null:
		town.town_level = town_level_override
	town.outdoor_town_music_enabled = outdoor_town_music_enabled
	add_child(town)
	await get_tree().process_frame
	await get_tree().process_frame
	game = town.get_node("CoordinateFrameGame")
	game._set_debug_option(show_floor_grid, "town_ground_grid")
	content = game.maze_content
	clipper = content.get_parent()
	shared_target = SubViewport.new()
	shared_target.name = "SharedLogicalTargetExperiment"
	shared_target.size = Vector2i(game.VIEWPORT_SIZE)
	shared_target.transparent_bg = true
	shared_target.disable_3d = true
	shared_target.gui_disable_input = true
	shared_target.render_target_update_mode = SubViewport.UPDATE_DISABLED
	clipper.add_child(shared_target)
	display = Sprite2D.new()
	display.name = "SharedLogicalTargetDisplay"
	display.centered = false
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.texture = shared_target.get_texture()
	display.visible = false
	clipper.add_child(display)
	sprite_target = SubViewport.new()
	sprite_target.name = "SpriteTargetExperiment"
	var sprite_resolution := COWBOY_TARGET_SCALE if separate_cowboy else 1
	sprite_target.size = Vector2i(game.VIEWPORT_SIZE) * sprite_resolution
	sprite_target.transparent_bg = true
	sprite_target.disable_3d = true
	sprite_target.gui_disable_input = true
	sprite_target.render_target_update_mode = SubViewport.UPDATE_DISABLED
	clipper.add_child(sprite_target)
	sprite_root = Node2D.new()
	sprite_target.add_child(sprite_root)
	sprite_display = Sprite2D.new()
	sprite_display.centered = false
	sprite_display.scale = Vector2.ONE / float(sprite_resolution)
	sprite_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_display.texture = sprite_target.get_texture()
	sprite_display.visible = false
	clipper.add_child(sprite_display)
	prop_bridge = preload("res://tests/calibration/town_shared_prop_bridge.gd").new()
	prop_bridge.game = game
	add_child(prop_bridge)
	pixel_adapter = preload("res://tests/calibration/town_shared_pixel_alignment.gd").new()
	pixel_adapter.player_scale_override = player_sprite_scale_override
	var indicator := CanvasLayer.new()
	indicator.layer = 100
	add_child(indicator)
	mode_label = Label.new()
	mode_label.position = Vector2(16, 16)
	mode_label.add_theme_font_size_override("font_size", 20)
	mode_label.add_theme_color_override("font_color", Color.WHITE)
	mode_label.add_theme_color_override("font_outline_color", Color.BLACK)
	mode_label.add_theme_constant_override("outline_size", 5)
	indicator.add_child(mode_label)
	RenderingServer.viewport_set_measure_render_time(shared_target.get_viewport_rid(), true)
	_set_shared_enabled(true)
	print("Town shared-target experiment: F12 switches between shared and original rendering.")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10 and shared_enabled:
		_set_split_sprites(not split_sprites)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12 and is_instance_valid(shared_target):
		_set_shared_enabled(not shared_enabled)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if split_sprites:
		sprite_root.transform = content.transform.scaled(Vector2.ONE / sprite_display.scale)
		_move_sprite_nodes()
	if mode_label_time > 0.0:
		mode_label_time = maxf(mode_label_time - delta, 0.0)
		if mode_label_time == 0.0 and is_instance_valid(mode_label):
			mode_label.visible = false


func _set_shared_enabled(enabled: bool) -> void:
	if enabled == shared_enabled:
		return
	shared_enabled = enabled
	if enabled:
		game.set_meta("shared_pixel_adapter", pixel_adapter)
		content.reparent(shared_target, false)
		shared_target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		display.visible = true
		prop_bridge.set_direct_enabled(true)
	else:
		_set_split_sprites(false)
		game.remove_meta("shared_pixel_adapter")
		prop_bridge.set_direct_enabled(false)
		content.reparent(clipper, false)
		display.visible = false
		shared_target.render_target_update_mode = SubViewport.UPDATE_DISABLED
	game._apply_near_camera_crop()
	if is_instance_valid(mode_label):
		mode_label.text = "F12: SHARED 160x120" if enabled else "F12: ORIGINAL RENDERER"
		mode_label.visible = true
		mode_label_time = 3.0
	if enabled and separate_cowboy:
		_set_split_sprites(true, false)
	print("Town shared-target experiment: ", "shared 160x120" if enabled else "original")


func _set_split_sprites(enabled: bool, show_label := true) -> void:
	if enabled == split_sprites:
		return
	split_sprites = enabled
	if enabled:
		sprite_root.transform = content.transform.scaled(Vector2.ONE / sprite_display.scale)
		sprite_target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sprite_display.visible = true
		_move_sprite_nodes()
	else:
		for node in sprite_parents:
			if is_instance_valid(node) and is_instance_valid(sprite_parents[node]):
				node.reparent(sprite_parents[node], false)
		sprite_parents.clear()
		sprite_display.visible = false
		sprite_target.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if show_label and is_instance_valid(mode_label):
		mode_label.text = "F10: SEPARATE SPRITES" if enabled else "F10: SHARED SPRITES"
		mode_label.visible = true
		mode_label_time = 3.0


func _move_sprite_nodes() -> void:
	var view: Dictionary = game.player_views[0]
	var nodes: Array = [view.player_sprite]
	if not separate_cowboy:
		nodes.append_array(view.opponent_sprites.values())
		for key in view.combat_nodes:
			if str(key).begins_with("coin_") or str(key).begins_with("heart_") or str(key).begins_with("machine_gun_"):
				nodes.append(view.combat_nodes[key])
	for node in nodes:
		if is_instance_valid(node) and not sprite_parents.has(node):
			sprite_parents[node] = node.get_parent()
			node.reparent(sprite_root, false)
