shader_type canvas_item;
render_mode unshaded;

// World-only sprite pass for actors, pickups, shots, and impact art. Source
// texels are grouped into whole-size blocks, then nearest-sampled. Combined
// with whole-logical-pixel sprite placement and LOD height, this produces an
// arcade-style reduction from one sprite sheet rather than fractional pixels.
uniform float texel_stride = 1.0;
// Kept on both team shader resources so the controller can use one material
// setup path. Team 1 deliberately leaves its Cowboy PNG colors untouched.
uniform bool apply_green_costume_remap = false;

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec2 stride = vec2(max(texel_stride, 1.0));
	vec2 texel = floor(UV * texture_size / stride) * stride + stride * 0.5;
	texel = clamp(texel, vec2(0.5), texture_size - vec2(0.5));
	vec4 sampled = texture(TEXTURE, texel / texture_size);
	COLOR = sampled;
}
