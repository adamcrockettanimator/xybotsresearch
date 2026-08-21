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
	// Blue costume ramp -> green ramp.
	if (sampled.b > sampled.r * 1.45 && sampled.b > sampled.g * 1.45 && brightest > 0.08) {
		if (brightest < 0.15) {
			sampled.rgb = vec3(0.0, 0.19608, 0.0);
		} else if (brightest < 0.62) {
			sampled.rgb = vec3(0.12941, 0.39608, 0.0);
		} else {
			sampled.rgb = vec3(0.0, 0.59608, 0.31765);
		}
	// Magenta costume ramp -> brown/orange ramp, leaving red accents alone.
	} else if (!preserve_face_shading && sampled.r > sampled.g * 1.8 && sampled.b > sampled.g * 1.8 && sampled.b > sampled.r * 0.48) {
		if (brightest < 0.55) {
			sampled.rgb = vec3(0.32941, 0.19608, 0.19608);
		} else {
			sampled.rgb = vec3(0.66275, 0.30980, 0.0);
		}
	// The authored red/burgundy body shading is also part of the costume, not
	// skin or the orange hair. Shift it into the reference's dark brown ramp.
	} else if (!preserve_face_shading && sampled.r > sampled.g * 1.8 && sampled.r > sampled.b * 1.8 && sampled.g < 0.48 && sampled.r < 0.80) {
		sampled.rgb = vec3(0.32941, 0.19608, 0.19608);
	}
	// Do not multiply by COLOR here: it already includes the original texture
	// sample, which would square and severely darken Team 2's palette.
	COLOR = sampled;
}
