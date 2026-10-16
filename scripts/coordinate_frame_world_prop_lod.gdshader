shader_type canvas_item;
render_mode unshaded;

// Neutral world-prop pass. It shares the actor/pickup texel-grid reduction but
// applies the environment renderer's depth lighting without any team palette.
uniform float texel_stride = 1.0;
uniform float depth_light = 1.0;

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec2 stride = vec2(max(texel_stride, 1.0));
	vec2 texel = floor(UV * texture_size / stride) * stride + stride * 0.5;
	texel = clamp(texel, vec2(0.5), texture_size - vec2(0.5));
	vec4 sampled = texture(TEXTURE, texel / texture_size);
	COLOR = vec4(sampled.rgb * depth_light, sampled.a);
}
