shader_type canvas_item;
render_mode unshaded;

// World-only sprite pass for actors, pickups, shots, and impact art.  Unlike
// HUD sprites, these use the same deliberate distance bands as the projected
// environment: source texels are grouped into whole-size blocks and then
// nearest-sampled, so distant art reads as authored arcade LOD rather than a
// smoothly shrunk modern sprite.
uniform float texel_stride = 1.0;
uniform float depth_light = 1.0;

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec2 stride = vec2(max(texel_stride, 1.0));
	vec2 texel = floor(UV * texture_size / stride) * stride + stride * 0.5;
	texel = clamp(texel, vec2(0.5), texture_size - vec2(0.5));
	vec4 sampled = texture(TEXTURE, texel / texture_size);
	COLOR = sampled * COLOR;
	COLOR.rgb *= depth_light;
}
