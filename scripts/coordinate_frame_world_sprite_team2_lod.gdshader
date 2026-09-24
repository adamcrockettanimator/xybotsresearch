shader_type canvas_item;
render_mode unshaded;

// Team 2 variant of the world-sprite pass. Keeping this as a separate shader
// resource makes the team selection independent of per-instance uniforms.
uniform float texel_stride = 1.0;

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec2 stride = vec2(max(texel_stride, 1.0));
	vec2 texel = floor(UV * texture_size / stride) * stride + stride * 0.5;
	texel = clamp(texel, vec2(0.5), texture_size - vec2(0.5));
	vec4 sampled = texture(TEXTURE, texel / texture_size);
	float brightest = max(sampled.r, max(sampled.g, sampled.b));
	bool preserve_face_shading = UV.y < 0.23;
	bool blue_costume = sampled.b > sampled.r * 1.45 && sampled.b > sampled.g * 1.45 && brightest > 0.08;
	bool magenta_costume = !preserve_face_shading && sampled.r > sampled.g * 1.8 && sampled.b > sampled.g * 1.8 && sampled.b > sampled.r * 0.48;
	bool burgundy_costume = !preserve_face_shading && sampled.r > sampled.g * 1.8 && sampled.r > sampled.b * 1.8 && sampled.g < 0.48 && sampled.r < 0.80;
	if (blue_costume) {
		// Preserve the source costume's dark, midtone, and highlight bands.
		if (brightest < 0.30) {
			sampled.rgb = vec3(0.0, 0.19608, 0.03529);
		} else if (brightest < 0.42) {
			sampled.rgb = vec3(0.12941, 0.39608, 0.07059);
		} else {
			sampled.rgb = vec3(0.21961, 0.69020, 0.21961);
		}
	} else if (magenta_costume) {
		// Brown receives the same three-band treatment instead of a flat tint.
		if (brightest < 0.16) {
			sampled.rgb = vec3(0.32941, 0.19608, 0.19608);
		} else if (brightest < 0.30) {
			sampled.rgb = vec3(0.50196, 0.29412, 0.11765);
		} else {
			sampled.rgb = vec3(0.72549, 0.45490, 0.19216);
		}
	} else if (burgundy_costume) {
		// Preserve the vest/boot shading bands too; these were previously one flat brown.
		if (brightest < 0.24) {
			sampled.rgb = vec3(0.27059, 0.14902, 0.10196);
		} else if (brightest < 0.48) {
			sampled.rgb = vec3(0.47059, 0.27843, 0.12549);
		} else {
			sampled.rgb = vec3(0.70588, 0.45490, 0.20392);
		}
	}
	COLOR = sampled;
}
