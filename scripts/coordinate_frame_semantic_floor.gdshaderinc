uniform bool use_semantic_plane_anisotropic_filter = true;
uniform float semantic_floor_ewa_min_major_footprint = 1.25;
uniform float semantic_floor_ewa_min_anisotropy = 1.50;
uniform float semantic_floor_ewa_flat_start_footprint = 8.0;
uniform float semantic_floor_ewa_flat_end_footprint = 24.0;
uniform float semantic_plane_ewa_blend_footprint = 3.0;
uniform float semantic_plane_ewa_blend_anisotropy = 0.50;

float semantic_hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.11369));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

vec3 semantic_floor_board_color(vec2 floor_texel) {
	// One source texel wide, lengthwise strips. Every lane has its own cycle
	// length, phase, and split point. Avoiding a shared 12-texel cycle prevents
	// separated lanes from reconverging into a visible cross-floor seam.
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

vec3 ewa_floor_material(vec2 floor_texel, vec2 span_x, vec2 span_y, float major_footprint) {
	// Gaussian footprint in the procedural board field. The 9 samples mirror
	// the wall EWA layout and are evaluated only once perspective is elongated.
	vec3 center = semantic_floor_board_color(floor_texel) * 0.28;
	vec3 axial = semantic_floor_board_color(floor_texel + span_x * 0.5)
		+ semantic_floor_board_color(floor_texel - span_x * 0.5)
		+ semantic_floor_board_color(floor_texel + span_y * 0.5)
		+ semantic_floor_board_color(floor_texel - span_y * 0.5);
	vec2 diagonal_a = (span_x + span_y) * 0.35;
	vec2 diagonal_b = (span_x - span_y) * 0.35;
	vec3 diagonal = semantic_floor_board_color(floor_texel + diagonal_a)
		+ semantic_floor_board_color(floor_texel - diagonal_a)
		+ semantic_floor_board_color(floor_texel + diagonal_b)
		+ semantic_floor_board_color(floor_texel - diagonal_b);
	vec3 gaussian_color = center + axial * 0.10 + diagonal * 0.08;
	vec3 average = vec3(118.0, 94.0, 71.0) / 255.0;
	return mix(gaussian_color, average, smoothstep(semantic_floor_ewa_flat_start_footprint, max(semantic_floor_ewa_flat_end_footprint, semantic_floor_ewa_flat_start_footprint + 0.01), major_footprint));
}

vec3 semantic_floor_material(vec2 floor_texel, vec2 span_x, vec2 span_y, vec2 sample_scale) {
	float major_footprint = max(length(span_x), length(span_y));
	float minor_footprint = max(0.001, min(length(span_x), length(span_y)));
	vec3 unfiltered = semantic_floor_board_color(floor_texel);
	if (!use_semantic_plane_anisotropic_filter) return unfiltered;
	float footprint_coverage = smoothstep(semantic_floor_ewa_min_major_footprint, semantic_floor_ewa_min_major_footprint + max(semantic_plane_ewa_blend_footprint, 0.01), major_footprint);
	float anisotropy = major_footprint / minor_footprint;
	float anisotropy_coverage = smoothstep(semantic_floor_ewa_min_anisotropy, semantic_floor_ewa_min_anisotropy + max(semantic_plane_ewa_blend_anisotropy, 0.01), anisotropy);
	float ewa_coverage = footprint_coverage * anisotropy_coverage;
	if (ewa_coverage <= 0.0) return unfiltered;
	return mix(unfiltered, ewa_floor_material(floor_texel, span_x * sample_scale, span_y * sample_scale, major_footprint), ewa_coverage);
}
