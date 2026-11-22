uniform bool use_daylight = false;
uniform bool use_town_lighting = false;
uniform vec4 town_roof_bounds[4];

// Horizontal direction toward the west sun in the town grid.
const vec2 TOWN_SUN_DIRECTION = vec2(-1.0, 0.0);

// Clip the camera-to-surface segment to each building's floor plan. The
// covered fraction subtracts from the forward depth used by the dust painter.
// Keep room_bounds distinct from the storefront plane's bounds uniform.
float town_outdoor_depth(vec2 origin, vec2 target, float depth) {
	vec2 delta = target - origin;
	float covered = 0.0;
	for (int room = 0; room < 4; room++) {
		vec4 room_bounds = town_roof_bounds[room];
		float enter = 0.0;
		float exit = 1.0;
		for (int axis = 0; axis < 2; axis++) {
			if (abs(delta[axis]) < 0.00001) {
				if (origin[axis] <= room_bounds[axis] || origin[axis] >= room_bounds[axis + 2]) exit = 0.0;
			} else {
				float a = (room_bounds[axis] - origin[axis]) / delta[axis];
				float b = (room_bounds[axis + 2] - origin[axis]) / delta[axis];
				enter = max(enter, min(a, b));
				exit = min(exit, max(a, b));
			}
		}
		covered += max(exit - enter, 0.0);
	}
	return depth * clamp(1.0 - covered, 0.0, 1.0);
}

// The most distant ground takes on the ochre at the base of day_horizon.png.
const vec3 DAY_HORIZON_COLOR = vec3(218.0, 171.0, 109.0) / 255.0;

// Mineral dust shifts the red-brown wood toward ochre. The shift scales
// with existing wood chroma so recesses and pale highlights keep their depth.
vec3 town_weathered_wood(vec3 wood) {
	float chroma = max(wood.r - wood.b, 0.0);
	return (wood + chroma * vec3(-0.035, 0.065, -0.0225)) * 0.85;
}

vec3 daylight_color(vec3 base, float depth) {
	float dust = 1.0 - exp(-max(depth - 0.85, 0.0) * 0.16);
	float luminance = dot(base, vec3(0.299, 0.587, 0.114));
	return mix(mix(base, vec3(luminance), dust * 0.14), DAY_HORIZON_COLOR, dust);
}
