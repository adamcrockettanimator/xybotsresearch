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
uniform vec2 wall_depths = vec2(1.0);
// Each fragment intersects this real camera-local wall segment. This is the
// same camera-ray projection used for the horizontal world planes; no endpoint
// is ever near-clamped or geometrically clipped for the wall renderer.
uniform vec2 wall_local_a = vec2(-0.5, 1.0);
uniform vec2 wall_local_b = vec2(0.5, 1.0);
uniform float camera_height = 0.5;
uniform float wall_height = 0.6666667;
uniform float focal_length = 128.0;
uniform float horizon_y = 31.5;
uniform vec2 projection_offset = vec2(0.0);
uniform float light_dither_near_half_width_pixels = 3.0;
uniform float light_dither_far_half_width_pixels = 1.0;
uniform int light_dither_steps = 4;
// -1 darkens a recessed (concave) endpoint, +1 lights an exposed (convex)
// endpoint. Zero leaves a straight continuation unmarked.
uniform vec2 endpoint_corner_tones = vec2(0.0);
uniform float convex_highlight_factor = 1.12;
uniform float concave_crevice_factor = 0.58;
uniform float wall_opacity = 1.0;
uniform bool use_camera_cutaway_fade = false;
uniform vec2 wall_world_a = vec2(0.0);
uniform vec2 wall_world_b = vec2(0.0);
uniform vec2 cutaway_contact_a = vec2(0.0);
uniform vec2 cutaway_contact_b = vec2(0.0);
uniform float cutaway_inner_radius = 0.0;
uniform float cutaway_fade_width = 0.01;
uniform vec2 canvas_size = vec2(160.0, 120.0);

vec2 homography_uv(vec2 pixel) {
	vec3 homogeneous = vec3(
		dot(inverse_row0, vec3(pixel, 1.0)),
		dot(inverse_row1, vec3(pixel, 1.0)),
		dot(inverse_row2, vec3(pixel, 1.0))
	);
	return homogeneous.xy / homogeneous.z;
}

float cross2(vec2 a, vec2 b) {
	return a.x * b.y - a.y * b.x;
}

// Return the source UV and physical forward depth for the screen ray. Rays
// with no positive intersection simply do not own this wall pixel.
bool wall_ray_uv(vec2 pixel, out vec2 source_uv, out float depth) {
	vec2 ray = vec2((pixel.x - canvas_size.x * 0.5 - projection_offset.x) / focal_length, 1.0);
	vec2 segment = wall_local_b - wall_local_a;
	float denominator = cross2(ray, segment);
	if (abs(denominator) < 0.000001) return false;
	depth = cross2(wall_local_a, segment) / denominator;
	float segment_u = cross2(wall_local_a, ray) / denominator;
	if (depth <= 0.0 || segment_u < 0.0 || segment_u > 1.0) return false;
	float world_height = camera_height - (pixel.y - horizon_y - projection_offset.y) * depth / focal_length;
	if (world_height < 0.0 || world_height > wall_height) return false;
	source_uv = vec2(segment_u, 1.0 - world_height / wall_height);
	return true;
}

float bayer2(vec2 pixel) {
	float x = mod(floor(pixel.x), 2.0);
	float y = mod(floor(pixel.y), 2.0);
	return 2.0 * x + 3.0 * y - 4.0 * x * y;
}

float bayer2_threshold(vec2 pixel) {
	return (bayer2(pixel) + 0.5) / 4.0;
}

// Match the floor's distance bands and intermediate Bayer-dithered levels.
float depth_light_dither(float depth, vec2 pixel) {
	float thresholds[5] = float[](1.35, 2.5, 3.8, 4.8, 5.2);
	float near_lights[5] = float[](1.0, 0.78, 0.56, 0.36, 0.22);
	float far_lights[5] = float[](0.78, 0.56, 0.36, 0.22, 0.10);
	float depth_per_pixel = max(depth * depth / (camera_height * focal_length), 0.0001);
	float near_weight = 1.0 - clamp((depth - 1.35) / (5.2 - 1.35), 0.0, 1.0);
	float half_band = depth_per_pixel * mix(light_dither_far_half_width_pixels, light_dither_near_half_width_pixels, near_weight);
	for (int index = 0; index < 5; index++) {
		float threshold = thresholds[index];
		if (depth < threshold - half_band) return near_lights[index];
		if (depth <= threshold + half_band) {
			float coverage = clamp((depth - (threshold - half_band)) / (half_band * 2.0), 0.0, 1.0);
			float scaled_step = coverage * float(light_dither_steps);
			int lower_step = clamp(int(floor(scaled_step)), 0, light_dither_steps);
			int upper_step = min(lower_step + 1, light_dither_steps);
			int selected_step = fract(scaled_step) >= bayer2_threshold(pixel) ? upper_step : lower_step;
			return mix(near_lights[index], far_lights[index], float(selected_step) / float(light_dither_steps));
		}
	}
	return 0.10;
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
	vec2 source_uv;
	float ray_depth;
	if (!wall_ray_uv(pixel, source_uv, ray_depth)) discard;
	float mip_level = 0.0;
	if (use_integer_uv_scale_snap) {
		vec2 uv_x;
		vec2 uv_y;
		float ignored_depth;
		if (!wall_ray_uv(pixel + vec2(1.0, 0.0), uv_x, ignored_depth) || !wall_ray_uv(pixel + vec2(0.0, 1.0), uv_y, ignored_depth)) {
			uv_x = source_uv;
			uv_y = source_uv;
		}
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
	// Derive the stroke thickness from the projected UV footprint, rather than
	// from a source texel. This keeps a corner line one 160x120 logical pixel at
	// every distance and viewing angle.
	vec2 corner_uv_x;
	float ignored_corner_depth;
	if (!wall_ray_uv(pixel + vec2(1.0, 0.0), corner_uv_x, ignored_corner_depth)) corner_uv_x = source_uv;
	// Wall endpoints are vertical under the yaw-only projector, so only the
	// horizontal neighboring sample measures the perpendicular one-pixel width.
	// Including the vertical UV derivative made oblique faces produce broad,
	// flickering bands instead of a single logical-pixel line.
	float endpoint_width = max(abs(corner_uv_x.x - source_uv.x), 0.000001);
	float corner_tone = source_uv.x <= endpoint_width ? endpoint_corner_tones.x : (source_uv.x >= 1.0 - endpoint_width ? endpoint_corner_tones.y : 0.0);
	if (corner_tone > 0.0) {
		// Preserve the brighter exposed-edge read without allowing a light wall
		// texel to bloom into a white accidental line.
		result.rgb = min(result.rgb * convex_highlight_factor, vec3(0.82));
	} else if (corner_tone < 0.0) {
		// AO is a dark mark, never a multiply of an already-bright wallpaper texel.
		result.rgb = min(result.rgb * 0.82, vec3(0.46));
	}
	float cutaway_opacity = wall_opacity;
	if (use_camera_cutaway_fade) {
		// The wall UV's horizontal axis follows its physical world segment. Fade
		// from the nearest camera-fan contact span so the transition continues
		// naturally over neighboring physical wall faces.
		vec2 wall_world_position = mix(wall_world_a, wall_world_b, source_uv.x);
		vec2 contact_segment = cutaway_contact_b - cutaway_contact_a;
		float contact_length_squared = dot(contact_segment, contact_segment);
		float contact_amount = contact_length_squared > 0.000001 ? clamp(dot(wall_world_position - cutaway_contact_a, contact_segment) / contact_length_squared, 0.0, 1.0) : 0.0;
		float contact_distance = distance(wall_world_position, cutaway_contact_a + contact_segment * contact_amount);
		float dither_coverage = smoothstep(cutaway_inner_radius, cutaway_inner_radius + max(cutaway_fade_width, 0.0001), contact_distance);
		cutaway_opacity *= step(bayer2_threshold(pixel), dither_coverage);
	}
	float wall_light = depth_light_dither(ray_depth, pixel);
	COLOR = vec4(result.rgb * wall_light, result.a * cutaway_opacity);
}
