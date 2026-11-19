// Plane heights are sampled at its minimum and maximum world Y.
float storefront_plane_depth(vec2 origin, vec2 ray, float eye_height, float screen_slope, vec4 rect, vec2 heights) {
	float slope = (heights.y - heights.x) / (rect.w - rect.y);
	float denominator = screen_slope + slope * ray.y;
	if (abs(denominator) < 0.0001) return -1.0;
	float depth = (eye_height - heights.x - slope * (origin.y - rect.y)) / denominator;
	vec2 hit = origin + ray * depth;
	if (any(lessThan(hit, rect.xy)) || any(greaterThan(hit, rect.zw))) return -1.0;
	return depth;
}

// World axes are street X, street Y, and height. Return forward depth
// and a fixed face tone so the solids keep their shape as the camera turns.
vec2 town_wood_box_hit(vec3 origin, vec3 ray, vec3 lower, vec3 upper) {
	float enter = -1e10;
	float exit = 1e10;
	int enter_axis = 0;
	int exit_axis = 0;
	for (int axis = 0; axis < 3; axis++) {
		if (abs(ray[axis]) < 0.000001) {
			if (origin[axis] < lower[axis] || origin[axis] > upper[axis]) return vec2(-1.0);
			continue;
		}
		float a = (lower[axis] - origin[axis]) / ray[axis];
		float b = (upper[axis] - origin[axis]) / ray[axis];
		if (min(a, b) > enter) {
			enter = min(a, b);
			enter_axis = axis;
		}
		if (max(a, b) < exit) {
			exit = max(a, b);
			exit_axis = axis;
		}
	}
	if (exit < max(enter, 0.005)) return vec2(-1.0);
	int face = enter >= 0.005 ? enter_axis : exit_axis;
	return vec2(enter >= 0.005 ? enter : exit, face == 2 ? 1.20 : (face == 0 ? 0.89 : 1.05));
}
