// Shared indoor distance lighting for cell planes and continuous wooden floors.
uniform float floor_light_dither_near_half_width_pixels = 3.0;
uniform float floor_light_dither_far_half_width_pixels = 1.0;
uniform int floor_light_dither_steps = 4;
// 0 = continuous gradient; 2, 4, and 8 select ordered Bayer matrices.
uniform int floor_light_dither_matrix_size = 2;

float depth_light(float depth) {
	if (depth < 1.35) return 1.0;
	if (depth < 2.5) return 0.78;
	if (depth < 3.8) return 0.56;
	if (depth < 4.8) return 0.36;
	if (depth < 5.2) return 0.22;
	return 0.10;
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

float depth_light_dither(float depth, vec2 pixel, float height_delta, float projector_focal_length) {
	float thresholds[5] = float[](1.35, 2.5, 3.8, 4.8, 5.2);
	float near_lights[5] = float[](1.0, 0.78, 0.56, 0.36, 0.22);
	float far_lights[5] = float[](0.78, 0.56, 0.36, 0.22, 0.10);
	// Ceiling height delta is negative while its visible screen delta is also
	// negative. Use magnitude here so both horizontal planes receive the same
	// pixel-width Bayer transition rather than a collapsed ceiling band.
	float depth_per_pixel = max(depth * depth / (abs(height_delta) * projector_focal_length), 0.0001);
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
