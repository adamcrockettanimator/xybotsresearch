shader_type canvas_item;
render_mode unshaded;

// Team 2 variant of the world-sprite pass. Keeping this as a separate shader
// resource makes the team selection independent of per-instance uniforms.
uniform float texel_stride = 1.0;
uniform bool apply_green_costume_remap = false;

// This hue is intentionally not full-bright green. Its scale is calculated
// from the source pixel luminance, preserving the readable dark, mid, and
// light bands in the purple shirt and vest without making them glow.
const vec3 GREEN_COSTUME_HUE = vec3(0.15, 0.80, 0.28);
const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec2 stride = vec2(max(texel_stride, 1.0));
	vec2 texel = floor(UV * texture_size / stride) * stride + stride * 0.5;
	texel = clamp(texel, vec2(0.5), texture_size - vec2(0.5));
	vec4 sampled = texture(TEXTURE, texel / texture_size);
	if (apply_green_costume_remap) {
		float brightest = max(sampled.r, max(sampled.g, sampled.b));
		// Limit the remap to purple/magenta fabric. Match the dark purple vest
		// swatches too, so the costume has no artificial horizontal cutoff at
		// the neck. The blue component guard keeps brown belt, holster, boots,
		// and skin in their authored colors without needing a UV position test.
		bool purple_costume = brightest > 0.02
			&& sampled.r > sampled.g * 1.50
			&& sampled.b > sampled.g * 1.40
			&& sampled.b > sampled.r * 0.45;
		if (purple_costume) {
			float source_luma = dot(sampled.rgb, LUMA_WEIGHTS);
			float green_luma = dot(GREEN_COSTUME_HUE, LUMA_WEIGHTS);
			sampled.rgb = GREEN_COSTUME_HUE * clamp(source_luma / green_luma, 0.0, 1.0);
		}
	}
	COLOR = sampled;
}
