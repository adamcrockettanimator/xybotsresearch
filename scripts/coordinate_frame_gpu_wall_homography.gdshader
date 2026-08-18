shader_type canvas_item;
render_mode unshaded;

// One full native-resolution CanvasItem per visible wall.  Projective UVs are
// evaluated by the GPU, leaving GDScript responsible only for visibility and
// the three inverse-homography rows.  This deliberately avoids the uniform
// array that made the earlier batched shader unreliable on the Windows driver.

// Mipmaps are generated once by the runtime renderer whenever the active wall
// texture changes.  The shader selects a discrete level per output pixel so
// the GPU wall pass keeps the chunky, stable look of the CPU experiment.
uniform sampler2D base_texture : filter_nearest_mipmap;
uniform sampler2D layer1_texture : filter_nearest_mipmap;
uniform sampler2D layer2_texture : filter_nearest_mipmap;
uniform bool use_layer_parallax = false;
uniform bool clamp_layer_edges = true;
uniform bool use_integer_uv_scale_snap = true;
// The game view is authored at 160×120 then nearest-upscaled.  Quantizing the
// *screen-space homography lookup* to that lattice is what gives GPU walls the
// same large, intentional pixels as the CPU composited floor/ceiling pass.
uniform bool quantize_logical_pixels = true;
uniform vec3 inverse_row0 = vec3(1.0, 0.0, 0.0);
uniform vec3 inverse_row1 = vec3(0.0, 1.0, 0.0);
uniform vec3 inverse_row2 = vec3(0.0, 0.0, 1.0);
uniform vec2 base_texture_size = vec2(128.0, 88.0);
uniform vec2 layer_texture_size = vec2(128.0, 88.0);
uniform vec2 layer1_offset = vec2(0.0);
uniform vec2 layer2_offset = vec2(0.0);
uniform float wall_light = 1.0;
uniform vec2 canvas_size = vec2(160.0, 120.0);

vec2 homography_uv(vec2 pixel) {
	vec3 homogeneous = vec3(
		dot(inverse_row0, vec3(pixel, 1.0)),
		dot(inverse_row1, vec3(pixel, 1.0)),
		dot(inverse_row2, vec3(pixel, 1.0))
	);
	return homogeneous.xy / homogeneous.z;
}

vec4 nearest_sample(sampler2D source, vec2 source_uv, vec2 source_size, bool clamp_to_edge, float mip_level) {
	if (clamp_to_edge) {
		source_uv = clamp(source_uv, vec2(0.0), vec2(1.0));
	} else if (source_uv.x < 0.0 || source_uv.x > 1.0 || source_uv.y < 0.0 || source_uv.y > 1.0) {
		return vec4(0.0);
	}
	float level_scale = exp2(mip_level);
	vec2 mip_size = max(vec2(1.0), floor(source_size / level_scale));
	vec2 texel = floor(source_uv * mip_size) + vec2(0.5);
	texel = clamp(texel, vec2(0.5), mip_size - vec2(0.5));
	return textureLod(source, texel / mip_size, mip_level);
}

void fragment() {
	vec2 pixel = UV * canvas_size;
	if (quantize_logical_pixels) {
		pixel = floor(pixel) + vec2(0.5);
	}
	vec3 homogeneous = vec3(
		dot(inverse_row0, vec3(pixel, 1.0)),
		dot(inverse_row1, vec3(pixel, 1.0)),
		dot(inverse_row2, vec3(pixel, 1.0))
	);
	if (abs(homogeneous.z) < 0.00001) {
		discard;
	}
	vec2 source_uv = homogeneous.xy / homogeneous.z;
	if (source_uv.x < 0.0 || source_uv.x > 1.0 || source_uv.y < 0.0 || source_uv.y > 1.0) {
		discard;
	}
	float mip_level = 0.0;
	if (use_integer_uv_scale_snap) {
		vec2 uv_x = homography_uv(pixel + vec2(1.0, 0.0));
		vec2 uv_y = homography_uv(pixel + vec2(0.0, 1.0));
		vec2 span_x = (uv_x - source_uv) * base_texture_size;
		vec2 span_y = (uv_y - source_uv) * base_texture_size;
		float minor_footprint = max(1.0, min(length(span_x), length(span_y)));
		// Match the CPU diagnostic path: footprint is quantized before choosing
		// a whole mip level, rather than blending between levels.
		minor_footprint = max(1.0, floor(minor_footprint + 0.5));
		mip_level = clamp(floor(log2(minor_footprint)), 0.0, 7.0);
	}
	vec4 result;
	if (use_layer_parallax) {
		vec4 bottom = nearest_sample(layer1_texture, source_uv + layer1_offset, layer_texture_size, clamp_layer_edges, mip_level);
		vec4 top = nearest_sample(layer2_texture, source_uv + layer2_offset, layer_texture_size, clamp_layer_edges, mip_level);
		result.rgb = top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a);
		result.a = top.a + bottom.a * (1.0 - top.a);
	} else {
		result = nearest_sample(base_texture, source_uv, base_texture_size, false, mip_level);
	}
	if (result.a <= 0.0) {
		discard;
	}
	COLOR = vec4(result.rgb * wall_light, result.a);
}
