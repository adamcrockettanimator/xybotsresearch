extends Node2D

@export var frames_folder: String = "res://assets/frames/renamed_trimmed_sequence"
@export var playback_fps: float = 24.0
@export var sprite_scale: float = 2.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	if sprite.sprite_frames == null or sprite.sprite_frames.get_frame_count("capture") == 0:
		_build_animation()
	_center_sprite()
	_update_status()


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
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("capture"):
		frame_count = sprite.sprite_frames.get_frame_count("capture")
	status_label.text = "Loaded %d frames from %s" % [frame_count, frames_folder]
