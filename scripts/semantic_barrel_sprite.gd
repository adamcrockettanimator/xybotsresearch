class_name SemanticBarrelSprite
extends RefCounted

# SemanticBarrelSprite is intentionally an authored recipe, rather than a
# reduced copy of the Blender barrel. Each pixel comes from a named barrel
# feature so later tuning can change a hoop, stave, cap, or scratch without
# redrawing sixteen complete sprites.

const OUTLINE := Color("2b2119")
const WOOD_DARK := Color("54331f")
const WOOD_SHADOW := Color("714526")
const WOOD_MID := Color("95603a")
const WOOD_LIGHT := Color("bb8552")
const WOOD_HIGHLIGHT := Color("d9b77d")
const HOOP_DARK := Color("34332c")
const HOOP_LIGHT := Color("8b8066")
const CORK_DARK := Color("4a2e1c")


# texture_for: Bakes one small semantic source image. This is a deliberately
# tiny CPU authoring step; the resulting ImageTexture is cached by the world
# renderer and drawn through the existing GPU prop shader.
static func texture_for(size: int, direction_index: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var detail_tier := _detail_tier(size)
	var rotation_phase := float(posmod(direction_index, 16)) / 16.0
	for y in range(size):
		for x in range(size):
			var color := _pixel_color(Vector2i(x, y), size, rotation_phase, detail_tier)
			if color.a > 0.0:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func _detail_tier(size: int) -> int:
	if size >= 24:
		return 3 # Full barrel: cap, staves, stepped hoops, and minor marks.
	if size >= 15:
		return 2 # Cylinder, alternating staves, and single-pixel hoops.
	if size >= 8:
		return 1 # Cylinder read, cap highlight, and one broad band.
	return 0 # Symbol read: a lit cap over a short wooden body.


static func _pixel_color(pixel: Vector2i, size: int, rotation_phase: float, detail_tier: int) -> Color:
	var uv := (Vector2(pixel) + Vector2(0.5, 0.5)) / float(size)
	var top := 0.13
	var bottom := 0.90
	if uv.y < top or uv.y > bottom:
		return Color.TRANSPARENT
	var height_t := (uv.y - top) / (bottom - top)
	# The wide central sine is the barrel's bulge. As the semantic tier drops,
	# it deliberately gives way to a straight cylinder rather than a noisy
	# scaled-down outline.
	var bulge_amount := 0.092 if detail_tier >= 2 else (0.052 if detail_tier == 1 else 0.0)
	var half_width := 0.245 + sin(height_t * PI) * bulge_amount
	var local_x := (uv.x - 0.5) / maxf(half_width, 0.001)
	if absf(local_x) > 1.0:
		return Color.TRANSPARENT
	var edge_distance := 1.0 - absf(local_x)
	if edge_distance < 1.0 / float(size) * (1.35 if detail_tier >= 2 else 0.8):
		return OUTLINE

	# Three tonal regions make every stave read as a piece of a round form:
	# dark turning away, midtone through the center, and a narrow lit side.
	var body := WOOD_MID
	if local_x < -0.42:
		body = WOOD_SHADOW
	elif local_x > 0.48:
		body = WOOD_LIGHT
	elif local_x > 0.18:
		body = WOOD_LIGHT.lerp(WOOD_MID, 0.35)

	if detail_tier >= 2:
		var phase_value: float = (local_x * 0.5 + 0.5 + rotation_phase) * 6.0
		var stave_phase: float = phase_value - floorf(phase_value)
		if stave_phase < 0.075:
			body = body.lerp(WOOD_DARK, 0.54)
		elif stave_phase > 0.87 and local_x > -0.05:
			body = body.lerp(WOOD_HIGHLIGHT, 0.24)

	# The top is an oval cap. The recess survives only in the fuller tiers;
	# at a distance it becomes the one light cap pixel that keeps barrel readable.
	if height_t < (0.16 if detail_tier >= 2 else 0.12):
		var cap_width := 0.78 - height_t * 1.8
		if absf(local_x) < cap_width:
			if detail_tier >= 2 and height_t > 0.055 and absf(local_x) < cap_width * 0.72:
				body = WOOD_DARK
			else:
				body = WOOD_HIGHLIGHT if local_x > -0.35 else WOOD_LIGHT

	# Hoops fall from a shaded two-pixel strip to a one-pixel dark read, then
	# disappear before the four-pixel symbol.
	var hoop_center_a := 0.36
	var hoop_center_b := 0.72
	var hoop_half_width := 1.15 / float(size) if detail_tier >= 3 else 0.60 / float(size)
	if detail_tier >= 1 and (absf(height_t - hoop_center_a) <= hoop_half_width or absf(height_t - hoop_center_b) <= hoop_half_width):
		body = HOOP_DARK
		if detail_tier >= 3 and height_t < hoop_center_a + hoop_half_width * 0.1:
			body = HOOP_LIGHT

	if detail_tier >= 3:
		# A cork/nick pair adds rotation-specific high-frequency detail which
		# intentionally disappears below the full-detail tier.
		var cork_x := 0.5 + sin(rotation_phase * TAU) * 0.10
		if absf(uv.x - cork_x) < 0.035 and height_t < 0.055:
			body = CORK_DARK
		if absf(local_x + 0.08) < 0.035 and absf(height_t - 0.55) < 0.028:
			body = WOOD_HIGHLIGHT
	return body
