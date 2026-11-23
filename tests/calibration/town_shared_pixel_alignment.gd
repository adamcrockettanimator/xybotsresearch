extends RefCounted

var player_scale_override := 0.0

# Align texture edges, including odd-sized centered frames, to logical pixels.
func _snap_center(value: float, size: float, scale: float, offset: float) -> float:
	var edge_offset := (offset - size * 0.5) * scale
	return roundf(value + edge_offset) - edge_offset


func align_player(game: Node, sprite: AnimatedSprite2D) -> void:
	if not sprite.visible or sprite.sprite_frames == null:
		return
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return
	var old_scale := sprite.scale.x
	var scale := player_scale_override if player_scale_override > 0.0 else maxf(1.0, roundf(old_scale))
	var feet_y: float = sprite.position.y - game._sprite_center_y_for_feet(sprite, 0.0, old_scale)
	var new_y: float = game._sprite_center_y_for_feet(sprite, feet_y, scale)
	sprite.scale = Vector2.ONE * scale
	var size := texture.get_size()
	sprite.position = Vector2(_snap_center(sprite.position.x, size.x, scale, sprite.offset.x), _snap_center(new_y, size.y, scale, sprite.offset.y))


func align_pickup(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return
	sprite.scale = Vector2.ONE
	var size := sprite.texture.get_size()
	sprite.position = Vector2(_snap_center(sprite.position.x, size.x, 1.0, sprite.offset.x), _snap_center(sprite.position.y, size.y, 1.0, sprite.offset.y))
