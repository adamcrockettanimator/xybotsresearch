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
// Procedural reconstructions of the current WoodFloor2 and two-layer ceiling.
uniform bool use_semantic_floor_material = false;
uniform bool use_semantic_ceiling_material = false;
uniform bool use_semantic_plane_anisotropic_filter = true;
uniform float floor_light_dither_near_half_width_pixels = 3.0;
uniform float floor_light_dither_far_half_width_pixels = 1.0;
uniform int floor_light_dither_steps = 4;
// 0 = continuous gradient; 2, 4, and 8 select ordered Bayer matrices.
uniform int floor_light_dither_matrix_size = 2;
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

float bayer2_value(vec2 pixel) {
	float x = mod(floor(pixel.x), 2.0);
	float y = mod(floor(pixel.y), 2.0);
	return 2.0 * x + 3.0 * y - 4.0 * x * y;
}

float bayer4_threshold(vec2 pixel) {
	vec2 p = mod(floor(pixel), 4.0);
	return (bayer2_value(mod(p, 2.0)) * 4.0 + bayer2_value(floor(p * 0.5)) + 0.5) / 16.0;
}

float bayer8_threshold(vec2 pixel) {
	vec2 p = mod(floor(pixel), 8.0);
	float low_digit = bayer2_value(mod(p, 2.0));
	float middle_digit = bayer2_value(mod(floor(p * 0.5), 2.0));
	float high_digit = bayer2_value(floor(p * 0.25));
	return (low_digit * 16.0 + middle_digit * 4.0 + high_digit + 0.5) / 64.0;
}

float depth_dither_threshold(vec2 pixel) {
	if (floor_light_dither_matrix_size >= 8) return bayer8_threshold(pixel);
	if (floor_light_dither_matrix_size >= 4) return bayer4_threshold(pixel);
	return bayer2_threshold(pixel);
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
			if (floor_light_dither_matrix_size <= 0) {
				return mix(near_lights[index], far_lights[index], coverage);
			}
			float scaled_step = coverage * float(floor_light_dither_steps);
			int lower_step = clamp(int(floor(scaled_step)), 0, floor_light_dither_steps);
			int upper_step = min(lower_step + 1, floor_light_dither_steps);
			int selected_step = fract(scaled_step) >= depth_dither_threshold(pixel) ? upper_step : lower_step;
			return mix(near_lights[index], far_lights[index], float(selected_step) / float(floor_light_dither_steps));
		}
	}
	return 0.10;
}

float semantic_hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.11369));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

vec3 semantic_floor_board_color(vec2 source_uv) {
	// One source texel wide, lengthwise strips. Every lane has its own cycle
	// length, phase, and split point. Avoiding a shared 12-texel cycle prevents
	// separated lanes from reconverging into a visible cross-floor seam.
	vec2 floor_texel = (cell_world + source_uv) * base_texture_size;
	float lane = floor(floor_texel.x);
	float cycle_length = 11.0 + floor(semantic_hash(vec2(lane, 19.0)) * 5.0);
	float lane_phase = floor(semantic_hash(vec2(lane, 71.0)) * cycle_length);
	float staggered_y = floor(floor_texel.y) + lane_phase;
	float block = floor(staggered_y / cycle_length);
	float within_block = mod(staggered_y, cycle_length);
	float first_board_length = 5.0 + floor(semantic_hash(vec2(lane, block + 313.0)) * 3.0);
	first_board_length = min(first_board_length, cycle_length - 4.0);
	float segment = block * 2.0 + (within_block >= first_board_length ? 1.0 : 0.0);
	float distribution = semantic_hash(vec2(lane * 1.37, segment * 3.19));
	vec3 dark = vec3(101.0, 81.0, 60.0) / 255.0;
	vec3 middle = vec3(118.0, 94.0, 71.0) / 255.0;
	vec3 light = vec3(135.0, 108.0, 81.0) / 255.0;
	return distribution < 0.333333 ? dark : (distribution < 0.666667 ? middle : light);
}

vec3 ewa_floor_material(vec2 source_uv, vec2 span_x, vec2 span_y) {
	// Gaussian footprint in the procedural board field. The 9 samples mirror
	// the wall EWA layout and are evaluated only once perspective is elongated.
	vec3 center = semantic_floor_board_color(source_uv) * 0.28;
	vec3 axial = semantic_floor_board_color(source_uv + span_x * 0.5)
		+ semantic_floor_board_color(source_uv - span_x * 0.5)
		+ semantic_floor_board_color(source_uv + span_y * 0.5)
		+ semantic_floor_board_color(source_uv - span_y * 0.5);
	vec2 diagonal_a = (span_x + span_y) * 0.35;
	vec2 diagonal_b = (span_x - span_y) * 0.35;
	vec3 diagonal = semantic_floor_board_color(source_uv + diagonal_a)
		+ semantic_floor_board_color(source_uv - diagonal_a)
		+ semantic_floor_board_color(source_uv + diagonal_b)
		+ semantic_floor_board_color(source_uv - diagonal_b);
	vec3 gaussian_color = center + axial * 0.10 + diagonal * 0.08;
	float major_footprint = max(length(span_x), length(span_y));
	vec3 average = vec3(118.0, 94.0, 71.0) / 255.0;
	return mix(gaussian_color, average, smoothstep(8.0, 24.0, major_footprint));
}

vec3 semantic_floor_material(vec2 source_uv, vec2 span_x, vec2 span_y) {
	float major_footprint = max(length(span_x), length(span_y));
	float minor_footprint = max(0.001, min(length(span_x), length(span_y)));
	bool needs_ewa = major_footprint > 1.25 && major_footprint / minor_footprint > 1.5;
	if (use_semantic_plane_anisotropic_filter && needs_ewa) return ewa_floor_material(source_uv, span_x, span_y);
	return semantic_floor_board_color(source_uv);
}

float ceiling_beam_coverage(vec2 ceiling_texel) {
	// The source beam is 14 pixels wide, centered on every 64-pixel repeat.
	float local_x = mod(ceiling_texel.x + 0.5, 64.0);
	float distance_to_beam = min(local_x, 64.0 - local_x);
	return distance_to_beam < 7.0 ? 1.0 : 0.0;
}

vec3 semantic_ceiling_material_unfiltered(vec2 source_uv) {
	vec2 base_texel = source_uv * base_texture_size;
	float board_band = mod(floor(base_texel.y / 8.0), 2.0);
	vec3 dark_board = vec3(107.0, 86.0, 65.0) / 255.0;
	vec3 light_board = vec3(135.0, 108.0, 81.0) / 255.0;
	vec3 ceiling_color = mix(light_board, dark_board, board_band);
	// Match the prior transparent beam layer's independently shifted parallax.
	vec2 beam_texel = base_texel + layer2_offset * layer_texture_size;
	float beam = ceiling_beam_coverage(beam_texel);
	// Project the drop shadow toward the camera-facing side of each beam. If
	// the camera looks along the beam, its cross-beam component approaches zero
	// and the shadow naturally disappears instead of forming a false side band.
	vec2 to_camera = camera_origin - (cell_world + source_uv);
	float camera_distance = max(length(to_camera), 0.0001);
	to_camera /= camera_distance;
	float cross_beam_view = abs(to_camera.x);
	float shadow_beam = ceiling_beam_coverage(beam_texel - to_camera * (6.0 * cross_beam_view));
	float shadow = shadow_beam * (1.0 - beam) * cross_beam_view;
	ceiling_color = mix(ceiling_color, ceiling_color * 0.58, shadow);
	vec3 beam_color = vec3(100.0, 80.0, 60.0) / 255.0;
	return mix(ceiling_color, beam_color, beam);
}

vec3 ewa_ceiling_material(vec2 source_uv, vec2 span_x, vec2 span_y) {
	vec3 center = semantic_ceiling_material_unfiltered(source_uv) * 0.28;
	vec3 axial = semantic_ceiling_material_unfiltered(source_uv + span_x * 0.5)
		+ semantic_ceiling_material_unfiltered(source_uv - span_x * 0.5)
		+ semantic_ceiling_material_unfiltered(source_uv + span_y * 0.5)
		+ semantic_ceiling_material_unfiltered(source_uv - span_y * 0.5);
	vec2 diagonal_a = (span_x + span_y) * 0.35;
	vec2 diagonal_b = (span_x - span_y) * 0.35;
	vec3 diagonal = semantic_ceiling_material_unfiltered(source_uv + diagonal_a)
		+ semantic_ceiling_material_unfiltered(source_uv - diagonal_a)
		+ semantic_ceiling_material_unfiltered(source_uv + diagonal_b)
		+ semantic_ceiling_material_unfiltered(source_uv - diagonal_b);
	vec3 gaussian_color = center + axial * 0.10 + diagonal * 0.08;
	float major_footprint = max(length(span_x), length(span_y));
	vec3 average = vec3(116.0, 93.0, 70.0) / 255.0;
	// Do not begin collapsing the structure until a beam itself is sub-pixel.
	// This is deliberately later than the floor: a ceiling beam is a readable
	// architectural feature, rather than surface grain.
	return mix(gaussian_color, average, smoothstep(24.0, 48.0, major_footprint));
}

vec3 semantic_ceiling_material(vec2 source_uv, vec2 span_x, vec2 span_y) {
	float major_footprint = max(length(span_x), length(span_y));
	float minor_footprint = max(0.001, min(length(span_x), length(span_y)));
	// Preserve the 14-texel beam and its directional shadow until the footprint
	// is genuinely too broad to represent either. Farther away EWA still removes
	// the moire rather than turning those distinct shapes into close-range noise.
	bool needs_ewa = major_footprint > 12.0 && major_footprint / minor_footprint > 1.5;
	if (use_semantic_plane_anisotropic_filter && needs_ewa) return ewa_ceiling_material(source_uv, span_x, span_y);
	return semantic_ceiling_material_unfiltered(source_uv);
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
	// Semantic floor boards need their footprint even without bitmap mipmaps.
	vec2 uv_x = plane_uv(pixel + vec2(1.0, 0.0));
	vec2 uv_y = plane_uv(pixel + vec2(0.0, 1.0));
	vec2 span_x = (uv_x - source_uv) * base_texture_size;
	vec2 span_y = (uv_y - source_uv) * base_texture_size;
	float mip_level = 0.0;
	if (use_integer_uv_scale_snap || use_anisotropic_bottom_filter) {
		float minor_footprint = max(1.0, min(length(span_x), length(span_y)));
		if (use_integer_uv_scale_snap) {
			minor_footprint = max(1.0, floor(minor_footprint + 0.5));
			mip_level = clamp(floor(log2(minor_footprint)), 0.0, 7.0);
		}
	}
	vec4 result;
	if (use_semantic_floor_material) {
		result = vec4(semantic_floor_material(source_uv, span_x, span_y), 1.0);
	} else if (use_semantic_ceiling_material) {
		result = vec4(semantic_ceiling_material(source_uv, span_x, span_y), 1.0);
	} else if (use_layers) {
		vec4 bottom = use_anisotropic_bottom_filter ? anisotropic_nearest_sample(layer1_texture, source_uv + layer1_offset, layer_texture_size, mip_level, uv_x + layer1_offset, uv_y + layer1_offset) : nearest_sample(layer1_texture, source_uv + layer1_offset, layer_texture_size, mip_level);
		vec4 top = nearest_sample(layer2_texture, source_uv + layer2_offset, layer_texture_size, mip_level);
		result.rgb = top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a);
		result.a = top.a + bottom.a * (1.0 - top.a);
	} else {
		result = use_anisotropic_bottom_filter ? anisotropic_nearest_sample(base_texture, source_uv, base_texture_size, mip_level, uv_x, uv_y) : nearest_sample(base_texture, source_uv, base_texture_size, mip_level);
	}
	if (result.a <= 0.0) discard;
	// Mark a plane pixel only when one of its immediate screen neighbors crosses
	// a real wall boundary. This is a true one-logical-pixel contour; a UV
	// footprint threshold widened into a heavy band at oblique angles.
	vec2 uv_left = plane_uv(pixel + vec2(-1.0, 0.0));
	vec2 uv_right = plane_uv(pixel + vec2(1.0, 0.0));
	vec2 uv_up = plane_uv(pixel + vec2(0.0, -1.0));
	vec2 uv_down = plane_uv(pixel + vec2(0.0, 1.0));
	bool crosses_north = (uv_left.y < 0.0 && uv_left.x >= 0.0 && uv_left.x <= 1.0) || (uv_right.y < 0.0 && uv_right.x >= 0.0 && uv_right.x <= 1.0) || (uv_up.y < 0.0 && uv_up.x >= 0.0 && uv_up.x <= 1.0) || (uv_down.y < 0.0 && uv_down.x >= 0.0 && uv_down.x <= 1.0);
	bool crosses_east = (uv_left.x > 1.0 && uv_left.y >= 0.0 && uv_left.y <= 1.0) || (uv_right.x > 1.0 && uv_right.y >= 0.0 && uv_right.y <= 1.0) || (uv_up.x > 1.0 && uv_up.y >= 0.0 && uv_up.y <= 1.0) || (uv_down.x > 1.0 && uv_down.y >= 0.0 && uv_down.y <= 1.0);
	bool crosses_south = (uv_left.y > 1.0 && uv_left.x >= 0.0 && uv_left.x <= 1.0) || (uv_right.y > 1.0 && uv_right.x >= 0.0 && uv_right.x <= 1.0) || (uv_up.y > 1.0 && uv_up.x >= 0.0 && uv_up.x <= 1.0) || (uv_down.y > 1.0 && uv_down.x >= 0.0 && uv_down.x <= 1.0);
	bool crosses_west = (uv_left.x < 0.0 && uv_left.y >= 0.0 && uv_left.y <= 1.0) || (uv_right.x < 0.0 && uv_right.y >= 0.0 && uv_right.y <= 1.0) || (uv_up.x < 0.0 && uv_up.y >= 0.0 && uv_up.y <= 1.0) || (uv_down.x < 0.0 && uv_down.y >= 0.0 && uv_down.y <= 1.0);
	bool at_wall_plane_corner =
		(wall_edge_mask.x > 0.5 && crosses_north) ||
		(wall_edge_mask.y > 0.5 && crosses_east) ||
		(wall_edge_mask.z > 0.5 && crosses_south) ||
		(wall_edge_mask.w > 0.5 && crosses_west);
	// Clamp the contact seam itself to a dark value: AO must not turn into a
	// bright texture-colored stripe when the underlying floor/ceiling texel is pale.
	if (at_wall_plane_corner) result.rgb = min(result.rgb * 0.82, vec3(0.46));
	float light = use_depth_light_dither ? depth_light_dither(depth, pixel) : depth_light(depth);
	COLOR = vec4(result.rgb * light, result.a);
}
