shader_type canvas_item;
render_mode unshaded;

// World-only sprite pass for actors, pickups, shots, and impact art. Source
// texels are grouped into whole-size blocks, then nearest-sampled. Combined
// with whole-logical-pixel sprite placement and LOD height, this produces an
// arcade-style reduction from one sprite sheet rather than fractional pixels.
uniform float texel_stride = 1.0;
uniform float team_palette = 0.0;
uniform sampler2D wall_occlusion_texture : filter_nearest;
uniform float wall_occlusion_depth_range = 6.25;
uniform float world_view_depth = 0.0;
uniform bool use_wall_occlusion = false;

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec2 stride = vec2(max(texel_stride, 1.0));
	vec2 texel = floor(UV * texture_size / stride) * stride + stride * 0.5;
	texel = clamp(texel, vec2(0.5), texture_size - vec2(0.5));
	vec4 sampled = texture(TEXTURE, texel / texture_size);
	if (use_wall_occlusion && sampled.a > 0.0) {
		vec4 wall_mask = texture(wall_occlusion_texture, SCREEN_UV);
		if (wall_mask.a > 0.5 && wall_mask.r * wall_occlusion_depth_range + 0.01 < world_view_depth) {
			discard;
		}
	}
	// Team 1 is the authored palette. Team 2 remaps only the costume swatches
	// shown in the supplied reference: blue becomes green and magenta becomes
	// orange/brown, while skin, weapon, outlines, and neutral pixels stay intact.
	if (team_palette > 0.5) {
		float brightest = max(sampled.r, max(sampled.g, sampled.b));
		bool blue_costume = sampled.b > sampled.r * 1.45 && sampled.b > sampled.g * 1.45 && brightest > 0.08;
		bool magenta_costume = sampled.r > sampled.g * 1.8 && sampled.b > sampled.g * 1.8 && sampled.b > sampled.r * 0.48;
		if (blue_costume) {
			if (brightest < 0.32) sampled.rgb = vec3(0.0, 0.19608, 0.0);
			else if (brightest < 0.62) sampled.rgb = vec3(0.12941, 0.39608, 0.0);
			else sampled.rgb = vec3(0.0, 0.59608, 0.31765);
		} else if (magenta_costume) {
			if (brightest < 0.55) sampled.rgb = vec3(0.32941, 0.19608, 0.19608);
			else sampled.rgb = vec3(0.66275, 0.30980, 0.0);
		}
	}
	// COLOR already contains the canvas texture sample at this stage. Multiplying
	// it by sampled a second time squares every source color and darkens sprites.
	// Output the deliberately snapped authored sample directly instead.
	COLOR = sampled;
}
