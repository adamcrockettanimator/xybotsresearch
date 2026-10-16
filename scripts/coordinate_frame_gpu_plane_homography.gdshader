shader_type canvas_item;
render_mode unshaded;

// A full logical-screen carrier for one floor or ceiling cell. Each fragment
// follows its live camera ray onto the horizontal plane, then derives its cell
// UV from that world point. This stays correct when a cell crosses the camera:
// projecting behind-camera corners into a near-clamped quad does not.
// Match the wall pass: choose a whole mip level from the projective texture
// footprint, then nearest-sample it so the authored pixel look stays intact.
uniform sampler2D base_texture : filter_nearest_mipmap;
uniform sampler2D layer1_texture : filter_nearest_mipmap;
uniform sampler2D layer2_texture : filter_nearest_mipmap;
uniform bool use_layers = false;
uniform bool use_integer_uv_scale_snap = true;
// Ceiling Layer 1 is the dense opaque stripe surface. Filter only that layer
// along its stretched projected axis; the simpler transparent Layer 2 remains
// a single nearest sample so its authored pixels stay literal.
uniform bool use_anisotropic_bottom_filter = false;
uniform bool use_depth_light_dither = false;
uniform float floor_light_dither_near_half_width_pixels = 3.0;
uniform float floor_light_dither_far_half_width_pixels = 1.0;
uniform int floor_light_dither_steps = 4;
uniform vec2 base_texture_size = vec2(128.0, 88.0);
uniform vec2 layer_texture_size = vec2(128.0, 88.0);
uniform vec2 layer1_offset = vec2(0.0);
uniform vec2 layer2_offset = vec2(0.0);
uniform vec2 camera_origin = vec2(0.0);
uniform vec2 camera_forward = vec2(0.0, -1.0);
uniform vec2 camera_right = vec2(1.0, 0.0);
uniform vec2 cell_world = vec2(0.0);
uniform vec2 projection_offset = vec2(0.0);
uniform float plane_height_delta = 0.5;
// N, E, S, W real wall contacts around the owning cell. These are the only
// plane borders that receive ambient occlusion; open cell joins stay clean.
uniform vec4 wall_edge_mask = vec4(0.0);
uniform float plane_corner_ao_factor = 0.60;
uniform float focal_length = 128.0;
uniform float horizon_y = 31.5;
uniform vec2 canvas_size = vec2(160.0, 120.0);

float depth_light(float depth) {
	if (depth < 1.35) return 1.0;
	if (depth < 2.5) return 0.78;
	if (depth < 3.8) return 0.56;
	if (depth < 4.8) return 0.36;
	if (depth < 5.2) return 0.22;
	return 0.10;
}

vec2 plane_uv(vec2 pixel) {
	float screen_delta = pixel.y - horizon_y - projection_offset.y;
	float depth = plane_height_delta * focal_length / screen_delta;
	float side = (pixel.x - canvas_size.x * 0.5 - projection_offset.x) * depth / focal_length;
	return camera_origin + camera_right * side + camera_forward * depth - cell_world;
}

vec4 nearest_sample(sampler2D source, vec2 source_uv, vec2 source_size, float mip_level) {
	float level_scale = exp2(mip_level);
	vec2 mip_size = max(vec2(1.0), floor(source_size / level_scale));
	vec2 texel = floor(clamp(source_uv, vec2(0.0), vec2(1.0)) * mip_size) + vec2(0.5);
	texel = clamp(texel, vec2(0.5), mip_size - vec2(0.5));
	return textureLod(source, texel / mip_size, mip_level);
}

vec4 anisotropic_nearest_sample(sampler2D source, vec2 source_uv, vec2 source_size, float mip_level, vec2 source_uv_x, vec2 source_uv_y) {
	vec2 span_x = (source_uv_x - source_uv) * source_size;
	vec2 span_y = (source_uv_y - source_uv) * source_size;
	float length_x = length(span_x);
	float length_y = length(span_y);
	float minor_footprint = max(1.0, min(length_x, length_y));
	float major_length = max(length_x, length_y);
	int sample_count = clamp(int(ceil(major_length / minor_footprint)), 1, 8);
	if (sample_count == 1) return nearest_sample(source, source_uv, source_size, mip_level);
	vec2 major_uv = length_x >= length_y ? source_uv_x - source_uv : source_uv_y - source_uv;
	vec4 accumulated = vec4(0.0);
	float total_weight = 0.0;
	for (int index = 0; index < 8; index++) {
		if (index >= sample_count) continue;
		float t = (float(index) + 0.5) / float(sample_count) - 0.5;
		float weight = 1.0 - abs(t) * 1.5;
		accumulated += nearest_sample(source, source_uv + major_uv * t, source_size, mip_level) * weight;
		total_weight += weight;
	}
	return total_weight > 0.0 ? accumulated / total_weight : nearest_sample(source, source_uv, source_size, mip_level);
}

float bayer2_threshold(vec2 pixel) {
	float x = mod(floor(pixel.x), 2.0);
	float y = mod(floor(pixel.y), 2.0);
	return (2.0 * x + 3.0 * y - 4.0 * x * y + 0.5) / 4.0;
}

float depth_light_dither(float depth, vec2 pixel) {
	float thresholds[5] = float[](1.35, 2.5, 3.8, 4.8, 5.2);
	float near_lights[5] = float[](1.0, 0.78, 0.56, 0.36, 0.22);
	float far_lights[5] = float[](0.78, 0.56, 0.36, 0.22, 0.10);
	// Ceiling height delta is negative while its visible screen delta is also
	// negative. Use magnitude here so both horizontal planes receive the same
	// pixel-width Bayer transition rather than a collapsed ceiling band.
	float depth_per_pixel = max(depth * depth / (abs(plane_height_delta) * focal_length), 0.0001);
	float near_weight = 1.0 - clamp((depth - 1.35) / (5.2 - 1.35), 0.0, 1.0);
	float half_band = depth_per_pixel * mix(floor_light_dither_far_half_width_pixels, floor_light_dither_near_half_width_pixels, near_weight);
	for (int index = 0; index < 5; index++) {
		float threshold = thresholds[index];
		if (depth < threshold - half_band) return near_lights[index];
		if (depth <= threshold + half_band) {
			float coverage = clamp((depth - (threshold - half_band)) / (half_band * 2.0), 0.0, 1.0);
			float scaled_step = coverage * float(floor_light_dither_steps);
			int lower_step = clamp(int(floor(scaled_step)), 0, floor_light_dither_steps);
			int upper_step = min(lower_step + 1, floor_light_dither_steps);
			int selected_step = fract(scaled_step) >= bayer2_threshold(pixel) ? upper_step : lower_step;
			return mix(near_lights[index], far_lights[index], float(selected_step) / float(floor_light_dither_steps));
		}
	}
	return 0.10;
}

void fragment() {
	vec2 pixel = floor(UV * canvas_size) + vec2(0.5);
	float screen_delta = pixel.y - horizon_y - projection_offset.y;
	if (abs(screen_delta) < 0.00001) discard;
	float depth = plane_height_delta * focal_length / screen_delta;
	if (depth <= 0.0 || depth > 5.5) discard;
	vec2 source_uv = plane_uv(pixel);
	// The world-to-cell test is exact: only one plane cell owns a screen pixel.
	// Do not overdraw and clamp neighboring floor cells here; that old CPU seam
	// workaround produces a moving border when independent GPU passes overlap.
	if (source_uv.x < 0.0 || source_uv.x > 1.0 || source_uv.y < 0.0 || source_uv.y > 1.0) discard;
	float mip_level = 0.0;
	vec2 uv_x = source_uv;
	vec2 uv_y = source_uv;
	if (use_integer_uv_scale_snap || use_anisotropic_bottom_filter) {
		uv_x = plane_uv(pixel + vec2(1.0, 0.0));
		uv_y = plane_uv(pixel + vec2(0.0, 1.0));
		vec2 span_x = (uv_x - source_uv) * base_texture_size;
		vec2 span_y = (uv_y - source_uv) * base_texture_size;
		float minor_footprint = max(1.0, min(length(span_x), length(span_y)));
		if (use_integer_uv_scale_snap) {
			minor_footprint = max(1.0, floor(minor_footprint + 0.5));
			mip_level = clamp(floor(log2(minor_footprint)), 0.0, 7.0);
		}
	}
	vec4 result;
	if (use_layers) {
		vec4 bottom = use_anisotropic_bottom_filter ? anisotropic_nearest_sample(layer1_texture, source_uv + layer1_offset, layer_texture_size, mip_level, uv_x + layer1_offset, uv_y + layer1_offset) : nearest_sample(layer1_texture, source_uv + layer1_offset, layer_texture_size, mip_level);
		vec4 top = nearest_sample(layer2_texture, source_uv + layer2_offset, layer_texture_size, mip_level);
		result.rgb = top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a);
		result.a = top.a + bottom.a * (1.0 - top.a);
	} else {
		result = use_anisotropic_bottom_filter ? anisotropic_nearest_sample(base_texture, source_uv, base_texture_size, mip_level, uv_x, uv_y) : nearest_sample(base_texture, source_uv, base_texture_size, mip_level);
	}
	if (result.a <= 0.0) discard;
	// The floor/ceiling side of a wall-plane corner gets exactly one logical
	// pixel of ambient occlusion. Derive its width from the live ray footprint,
	// so it remains a line rather than becoming a broad textured band nearby.
	vec2 corner_uv_x = plane_uv(pixel + vec2(1.0, 0.0));
	vec2 corner_uv_y = plane_uv(pixel + vec2(0.0, 1.0));
	vec2 corner_width = max(abs(corner_uv_x - source_uv), abs(corner_uv_y - source_uv));
	bool at_wall_plane_corner =
		(wall_edge_mask.x > 0.5 && source_uv.y <= corner_width.y) ||
		(wall_edge_mask.y > 0.5 && source_uv.x >= 1.0 - corner_width.x) ||
		(wall_edge_mask.z > 0.5 && source_uv.y >= 1.0 - corner_width.y) ||
		(wall_edge_mask.w > 0.5 && source_uv.x <= corner_width.x);
	// Clamp the contact seam itself to a dark value: AO must not turn into a
	// bright texture-colored stripe when the underlying floor/ceiling texel is pale.
	if (at_wall_plane_corner) result.rgb = min(result.rgb * plane_corner_ao_factor, vec3(0.22));
	float light = use_depth_light_dither ? depth_light_dither(depth, pixel) : depth_light(depth);
	COLOR = vec4(result.rgb * light, result.a);
}
