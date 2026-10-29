shader_type canvas_item;
render_mode unshaded;

// Sample once per logical playfield pixel, even when the prop is scaled down.
// The origin keeps the grid aligned to the playfield as the camera moves.
uniform float sprite_scale = 1.0;
uniform vec2 grid_origin = vec2(0.0);
uniform float depth_light = 1.0;
uniform bool quantize_scale_pixels = true;

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	float scale = quantize_scale_pixels ? max(sprite_scale, 0.0001) : 1.0;
	vec2 texel = (floor(UV * texture_size * scale + grid_origin) + vec2(0.5) - grid_origin) / scale;
	texel = clamp(texel, vec2(0.5), texture_size - vec2(0.5));
	vec4 sampled = texture(TEXTURE, texel / texture_size);
	COLOR = vec4(sampled.rgb * depth_light, sampled.a);
}
