extends Node2D

const DIR_N := "N"
const DIR_E := "E"
const DIR_S := "S"
const DIR_W := "W"

@export var move_speed: float = 80.0
@export var sprite_scale: float = 2.0
@export var start_centered: bool = true

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var status_label: Label = $CanvasLayer/StatusLabel

var run_dir: String = DIR_S
var aim_dir: String = DIR_S
var last_animation: StringName = &""
var available_animations: Dictionary = {}


func _ready() -> void:
	sprite.scale = Vector2.ONE * sprite_scale
	_cache_animations()
	if start_centered:
		sprite.position = get_viewport_rect().size * 0.5
	_play_best_animation()
	_update_status(Vector2.ZERO)


func _physics_process(delta: float) -> void:
	var movement := _read_movement()
	var aim := _read_aim()

	if movement != Vector2.ZERO:
		run_dir = _vector_to_cardinal(movement)
		sprite.position += movement.normalized() * move_speed * delta

	if aim != Vector2.ZERO:
		aim_dir = _vector_to_cardinal(aim)
	elif movement != Vector2.ZERO:
		aim_dir = run_dir

	_clamp_to_viewport()
	_play_best_animation()
	_update_status(movement)


func _cache_animations() -> void:
	available_animations.clear()
	if sprite.sprite_frames == null:
		push_error("AnimatedSprite2D has no SpriteFrames resource.")
		return

	for animation in sprite.sprite_frames.get_animation_names():
		available_animations[String(animation)] = true


func _read_movement() -> Vector2:
	var movement := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		movement.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		movement.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		movement.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		movement.y += 1.0
	return movement


func _read_aim() -> Vector2:
	var aim := Vector2.ZERO
	if Input.is_key_pressed(KEY_J):
		aim.x -= 1.0
	if Input.is_key_pressed(KEY_L):
		aim.x += 1.0
	if Input.is_key_pressed(KEY_I):
		aim.y -= 1.0
	if Input.is_key_pressed(KEY_K):
		aim.y += 1.0
	return aim


func _vector_to_cardinal(vector: Vector2) -> String:
	if absf(vector.x) > absf(vector.y):
		return DIR_E if vector.x > 0.0 else DIR_W
	return DIR_S if vector.y > 0.0 else DIR_N


func _play_best_animation() -> void:
	var animation := _best_animation_for(run_dir, aim_dir)
	if animation == &"":
		return
	if animation == last_animation and sprite.is_playing():
		return

	last_animation = animation
	sprite.play(animation)


func _best_animation_for(run: String, aim: String) -> StringName:
	var exact := "Run%s_Aim%s" % [run, aim]
	if available_animations.has(exact):
		return StringName(exact)

	var same_run := _first_animation_with_prefix("Run%s_Aim" % run)
	if same_run != &"":
		return same_run

	var same_aim_suffix := "_Aim%s" % aim
	for animation in available_animations.keys():
		if String(animation).ends_with(same_aim_suffix):
			return StringName(animation)

	if available_animations.has("Death"):
		return &"Death"

	return &""


func _first_animation_with_prefix(prefix: String) -> StringName:
	var names := available_animations.keys()
	names.sort()
	for animation in names:
		if String(animation).begins_with(prefix):
			return StringName(animation)
	return &""


func _clamp_to_viewport() -> void:
	var bounds := get_viewport_rect().size
	sprite.position.x = clampf(sprite.position.x, 0.0, bounds.x)
	sprite.position.y = clampf(sprite.position.y, 0.0, bounds.y)


func _update_status(movement: Vector2) -> void:
	var animation := String(sprite.animation)
	var movement_text := "idle" if movement == Vector2.ZERO else run_dir
	status_label.text = (
		"Move: %s  Aim: %s  Anim: %s\n"
		+ "WASD/arrows move. IJKL aim. Missing exact run/aim clips fall back."
	) % [movement_text, aim_dir, animation]
