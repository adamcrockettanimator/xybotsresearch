shader_type spatial;
// This is a solid prop, not a double-sided card.  Rendering only outward
// faces prevents the barrel's rear/interior shell from showing through it in
// the 3D authoring scene and the offscreen source viewport.
render_mode unshaded, cull_back;

// Functional port of BARREL_FOUR_TONE_TOON.001 in the Blender rig. Its final
// Mix is a constant normal-Z color ramp; its image nodes do not feed the
// final output. Godot's upright barrel uses NORMAL.y instead.
uniform float lower_band : hint_range(0.0, 1.0) = 0.45;
uniform float middle_band : hint_range(0.0, 1.0) = 0.66;
uniform float lid_band : hint_range(0.0, 1.0) = 0.851963;
// The Blender graph begins with this palette texture, then applies a constant
// greyscale Color Ramp driven by normal Z. Keep the source art intact and
// multiply it by that stepped light value rather than replacing its colors.
uniform sampler2D base_texture : source_color, filter_nearest;
uniform float underside_value : hint_range(0.0, 1.0) = 0.32;
uniform float lower_side_value : hint_range(0.0, 1.0) = 0.52;
uniform float upper_side_value : hint_range(0.0, 1.0) = 0.72;
uniform float lid_value : hint_range(0.0, 1.0) = 1.0;

// Fragment NORMAL is in Godot's camera/view space. Preserve the barrel mesh's
// original normal instead, just as Blender's Geometry node supplies it.
varying vec3 barrel_local_normal;

void vertex() {
	barrel_local_normal = NORMAL;
}

void fragment() {
	// Blender maps the normal's vertical axis from -1..1 to 0..1, then feeds
	// it through a CONSTANT colour ramp. These branches preserve its four
	// discontinuous bands, including the small bright upward-facing lid band.
	// The imported barrel mesh is rotated +90° around X; its local -Z points
	// upward in Godot. This stays stable while the camera moves around it.
	float vertical_normal = clamp(-barrel_local_normal.z * 0.5 + 0.5, 0.0, 1.0);
	float stepped_light = underside_value;
	if (vertical_normal >= lower_band && vertical_normal < middle_band) {
		stepped_light = lower_side_value;
	} else if (vertical_normal >= middle_band && vertical_normal < lid_band) {
		stepped_light = upper_side_value;
	} else if (vertical_normal >= lid_band) {
		stepped_light = lid_value;
	}

	vec3 palette_color = texture(base_texture, UV).rgb;
	ALBEDO = palette_color * stepped_light;
	// Do not assign ALPHA here. In Godot, even ALPHA = 1.0 moves the material
	// into the transparent pass, where separate parts of this barrel can sort
	// through one another. Leaving it untouched keeps an opaque depth buffer.
}
