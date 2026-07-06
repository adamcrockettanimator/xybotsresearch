extends Node2D

@export var frames_folder: String = "res://assets/frames/renamed_trimmed_sequence"
@export var sprite_frames_path: String = "res://assets/frames/renamed_trimmed_sequence/capture_frames.tres"
@export var animation_name: String = "capture"
@export var playback_fps: float = 24.0
@export var sprite_scale: float = 2.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	if not _load_baked_animation():
		_build_animation()
	_center_sprite()
	_update_status()


func _load_baked_animation() -> bool:
	if sprite_frames_path.is_empty():
		return false
	if not ResourceLoader.exists(sprite_frames_path):
		return false
	var resource := load(sprite_frames_path)
	if resource is not SpriteFrames:
		return false
	sprite.sprite_frames = resource
	if sprite.sprite_frames.has_animation(animation_name):
		sprite.animation = animation_name
	elif sprite.sprite_frames.get_animation_names().size() > 0:
		sprite.animation = sprite.sprite_frames.get_animation_names()[0]
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.play()
	return true


func _process(_delta: float) -> void:
	_center_sprite()


func _build_animation() -> void:
	var dir := DirAccess.open(frames_folder)
	if dir == null:
		push_error("Unable to open frame folder: %s" % frames_folder)
		return

	var file_names: PackedStringArray = []
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if file_name.to_lower().ends_with(".png"):
			file_names.append(file_name)
	dir.list_dir_end()

	file_names.sort()

	var frames := SpriteFrames.new()
	frames.add_animation("capture")
	frames.set_animation_loop("capture", true)
	frames.set_animation_speed("capture", playback_fps)

	for file_name in file_names:
		var image_path := ProjectSettings.globalize_path(frames_folder.path_join(file_name))
		var image := Image.load_from_file(image_path)
		if image and not image.is_empty():
			var texture := ImageTexture.create_from_image(image)
			frames.add_frame("capture", texture)

	sprite.sprite_frames = frames
	sprite.animation = "capture"
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.play()


func _center_sprite() -> void:
	sprite.position = get_viewport_rect().size * 0.5


func _update_status() -> void:
	var frame_count := 0
	var current_animation := animation_name
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(current_animation):
		frame_count = sprite.sprite_frames.get_frame_count(current_animation)
	elif sprite.sprite_frames != null and sprite.sprite_frames.get_animation_names().size() > 0:
		current_animation = sprite.sprite_frames.get_animation_names()[0]
		frame_count = sprite.sprite_frames.get_frame_count(current_animation)
	status_label.text = "Loaded %d frames for %s from %s" % [frame_count, current_animation, frames_folder]
