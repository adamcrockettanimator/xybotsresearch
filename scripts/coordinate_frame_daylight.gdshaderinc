uniform bool use_daylight = false;

// The most distant ground takes on the ochre at the base of day_horizon.png.
const vec3 DAY_HORIZON_COLOR = vec3(218.0, 171.0, 109.0) / 255.0;

vec3 daylight_color(vec3 base, float depth) {
	float dust = 1.0 - exp(-max(depth - 0.85, 0.0) * 0.16);
	float luminance = dot(base, vec3(0.299, 0.587, 0.114));
	return mix(mix(base, vec3(luminance), dust * 0.14), DAY_HORIZON_COLOR, dust);
}
