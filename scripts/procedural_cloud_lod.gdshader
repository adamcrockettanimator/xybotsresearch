shader_type canvas_item;
render_mode unshaded;

// Match the world-sprite depth bands while preserving the caller's material tint.
uniform float texel_stride = 1.0;
uniform vec4 tint_color : source_color = vec4(1.0);

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec2 stride = vec2(max(texel_stride, 1.0));
	vec2 texel = floor(UV * texture_size / stride) * stride + stride * 0.5;
	texel = clamp(texel, vec2(0.5), texture_size - vec2(0.5));
	vec4 cloud = texture(TEXTURE, texel / texture_size);
	COLOR = vec4(tint_color.rgb, tint_color.a * cloud.a);
}
