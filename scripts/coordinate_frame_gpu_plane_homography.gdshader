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
uniform float semantic_ceiling_ewa_min_major_footprint = 12.0;
uniform float semantic_ceiling_ewa_min_anisotropy = 1.50;
uniform float semantic_ceiling_ewa_flat_start_footprint = 24.0;
uniform float semantic_ceiling_ewa_flat_end_footprint = 48.0;
// Fade the procedural palette's deviation from its material mean by world
// depth. This is intentionally independent of the EWA footprint: a distant
// plane can become calm even where its projected texels happen to be sharp.
uniform float semantic_plane_contrast_full_depth = 1.10;
uniform float semantic_plane_contrast_flat_depth = 4.75;
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

#include "res://scripts/coordinate_frame_plane_depth_light.gdshaderinc"

#include "res://scripts/coordinate_frame_semantic_floor.gdshaderinc"

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
	return mix(gaussian_color, average, smoothstep(semantic_ceiling_ewa_flat_start_footprint, max(semantic_ceiling_ewa_flat_end_footprint, semantic_ceiling_ewa_flat_start_footprint + 0.01), major_footprint));
}

vec3 semantic_ceiling_material(vec2 source_uv, vec2 span_x, vec2 span_y) {
	float major_footprint = max(length(span_x), length(span_y));
	float minor_footprint = max(0.001, min(length(span_x), length(span_y)));
	// Preserve the 14-texel beam and its directional shadow until the footprint
	// is genuinely too broad to represent either. Farther away EWA still removes
	// the moire rather than turning those distinct shapes into close-range noise.
	vec3 unfiltered = semantic_ceiling_material_unfiltered(source_uv);
	if (!use_semantic_plane_anisotropic_filter) return unfiltered;
	float footprint_coverage = smoothstep(semantic_ceiling_ewa_min_major_footprint, semantic_ceiling_ewa_min_major_footprint + max(semantic_plane_ewa_blend_footprint, 0.01), major_footprint);
	float anisotropy = major_footprint / minor_footprint;
	float anisotropy_coverage = smoothstep(semantic_ceiling_ewa_min_anisotropy, semantic_ceiling_ewa_min_anisotropy + max(semantic_plane_ewa_blend_anisotropy, 0.01), anisotropy);
	float ewa_coverage = footprint_coverage * anisotropy_coverage;
	if (ewa_coverage <= 0.0) return unfiltered;
	return mix(unfiltered, ewa_ceiling_material(source_uv, span_x, span_y), ewa_coverage);
}

vec3 semantic_plane_distance_contrast(vec3 material_color, vec3 material_average, float depth) {
	// Preserve every near board/beam color, then smoothly remove only its
	// contrast around the authored material mean. At the flat depth the output
	// is exactly one stable palette color before depth lighting is applied.
	float contrast = 1.0 - smoothstep(semantic_plane_contrast_full_depth, semantic_plane_contrast_flat_depth, depth);
	return mix(material_average, material_color, contrast);
}

#include "res://scripts/coordinate_frame_daylight.gdshaderinc"

uniform float far_depth = 5.5;
uniform bool use_town_dirt = false;
uniform bool storefront_shadow_enabled = false;
uniform vec4 storefront_shadow_rect;
uniform vec4 town_cast_shadow_length;
uniform float town_street_y;
uniform vec2 storefront_shadow_tuning;

void fragment() {
	vec2 pixel = floor(UV * canvas_size) + vec2(0.5);
	float screen_delta = pixel.y - horizon_y - projection_offset.y;
	if (abs(screen_delta) < 0.00001) discard;
	float depth = plane_height_delta * focal_length / screen_delta;
	if (depth <= 0.0 || depth > far_depth) discard;
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
	float outdoor_depth = use_town_lighting ? town_outdoor_depth(camera_origin, cell_world + source_uv, depth) : 0.0;
	float indoor_depth = max(depth - outdoor_depth, 0.0);
	vec4 result;
	bool in_foundation_shadow = false;
	if (use_town_dirt) {
		vec2 texel = floor((cell_world + source_uv) * 64.0);
		float fleck = fract(sin(dot(texel, vec2(127.1, 311.7))) * 43758.5453);
		float grain = (floor(fleck * 4.0) - 1.5) * 0.014 / (1.0 + depth * 0.25);
		result = vec4(vec3(0.74, 0.55, 0.29) + grain, 1.0);
		vec2 ground_point = cell_world + source_uv;
		// Compacted dirt through the middle, with rougher shoulders near the lots.
		float shoulder = abs(ground_point.y - town_street_y) + fleck * 0.28;
		float worn = 1.0 - smoothstep(1.05, 2.40, shoulder);
		result.rgb = mix(result.rgb, result.rgb * vec3(0.95, 0.94, 0.90), worn);
		float shade = 0.0;
		for (int i = 0; i < 4; i++) {
			vec4 body = town_roof_bounds[i];
			float length = town_cast_shadow_length[i];
			vec2 end_shadow = body.zw - TOWN_SUN_DIRECTION * length;
			if (length > 0.0 && ground_point.x >= body.z && ground_point.x <= end_shadow.x &&
				ground_point.y >= body.y && ground_point.y <= body.w) shade = 0.19;
		}
		result.rgb *= 1.0 - shade;
		if (storefront_shadow_enabled) {
			float reach = storefront_shadow_tuning.x;
			// Stretch the contact shadow a little farther away from the west sun.
			vec2 cast = ground_point + (TOWN_SUN_DIRECTION * 0.22 + vec2(0.0, 0.29)) * reach;
			vec2 outside = max(max(storefront_shadow_rect.xy - cast, cast - storefront_shadow_rect.zw), vec2(0.0));
			// Sample a single hard shadow at the logical pixel center.
			vec2 normalized_edge = outside / vec2(0.28, 0.50);
			in_foundation_shadow = dot(normalized_edge, normalized_edge) <= reach * reach;
			if (in_foundation_shadow) {
				result.rgb *= mix(vec3(1.0), vec3(0.36, 0.29, 0.23), storefront_shadow_tuning.y);
			}
		}
	} else if (use_semantic_floor_material) {
		// Preserve the original cell renderer's wider filter tap spacing.
		vec3 floor_color = semantic_floor_material((cell_world + source_uv) * base_texture_size, span_x, span_y, base_texture_size);
		vec3 floor_average = vec3(118.0, 94.0, 71.0) / 255.0;
		result = vec4(semantic_plane_distance_contrast(floor_color, floor_average, indoor_depth), 1.0);
	} else if (use_semantic_ceiling_material) {
		vec3 ceiling_color = semantic_ceiling_material(source_uv, span_x, span_y);
		vec3 ceiling_average = vec3(116.0, 93.0, 70.0) / 255.0;
		result = vec4(semantic_plane_distance_contrast(ceiling_color, ceiling_average, indoor_depth), 1.0);
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
	// The footprint already shades this contact. A second grid-edge mark
	// would draw a dark stripe through the cast shadow.
	if (at_wall_plane_corner && !in_foundation_shadow) {
		if (use_town_dirt) {
			// Multiply the ochre rather than clamping its brightest channel.
			// The old neutral cap shifted the ground contact toward olive.
			float contact = 1.0 - smoothstep(3.5, 8.0, depth);
			result.rgb *= mix(vec3(1.0), vec3(0.66, 0.59, 0.51), contact);
		} else {
			result.rgb = min(result.rgb * 0.82, vec3(0.46));
		}
	}
	float light = use_depth_light_dither ? depth_light_dither(indoor_depth, pixel, plane_height_delta, focal_length) : depth_light(indoor_depth);
	vec3 shaded = result.rgb * (use_town_dirt ? 1.0 : light);
	COLOR = vec4(use_town_lighting ? daylight_color(shaded, outdoor_depth) : shaded, result.a);
}
