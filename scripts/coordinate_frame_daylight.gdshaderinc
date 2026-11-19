uniform bool use_daylight = false;

// A warm, low-contrast air color becomes dominant with travel distance.
vec3 daylight_color(vec3 base, float depth) {
	float dust = 1.0 - exp(-max(depth - 0.85, 0.0) * 0.19);
	float luminance = dot(base, vec3(0.299, 0.587, 0.114));
	return mix(mix(base, vec3(luminance), dust * 0.56), vec3(0.89, 0.75, 0.55), dust);
}
