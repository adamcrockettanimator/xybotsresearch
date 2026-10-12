@tool
class_name MuzzleAnchorLibrary
extends Resource

## Pixel-space muzzle anchors authored with the Muzzle Anchor Editor.
## Keys are SpriteFrames animation names. Each entry can contain `right` and/or
## `left` Vector2i values. Future per-frame data can live in `frames` without
## changing callers that ask for the animation default.

@export var sprite_frames_path: String = ""
@export var anchors: Dictionary = {}


func get_anchor(animation_name: StringName, hand: StringName) -> Variant:
	var animation: Variant = anchors.get(String(animation_name), {})
	if not animation is Dictionary:
		return null
	var result: Variant = animation.get(String(hand), null)
	return result if result is Vector2i else null


func set_anchor(animation_name: StringName, hand: StringName, pixel: Vector2i) -> void:
	var animation: Dictionary = anchors.get(String(animation_name), {})
	animation[String(hand)] = pixel
	anchors[String(animation_name)] = animation
	emit_changed()


func clear_anchor(animation_name: StringName, hand: StringName) -> void:
	var animation: Variant = anchors.get(String(animation_name), {})
	if not animation is Dictionary:
		return
	(animation as Dictionary).erase(String(hand))
	if (animation as Dictionary).is_empty():
		anchors.erase(String(animation_name))
	emit_changed()
