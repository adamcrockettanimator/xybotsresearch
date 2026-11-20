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

float town_plane_depth(vec2 origin, vec2 ray, float eye_height, float screen_slope, vec4 rect, vec2 heights, bool along_x) {
	if (along_x) return storefront_plane_depth(origin.yx, ray.yx, eye_height, screen_slope, rect.yxwz, heights);
	return storefront_plane_depth(origin, ray, eye_height, screen_slope, rect, heights);
}

// Match the standard ground-floor ceiling pass before drawing any surface
// behind it. The first roof bound is Coffee, whose shed roof is exposed.
bool town_ceiling_precedes(vec2 origin, vec2 ray, float eye_height, float screen_slope, float hit_depth, vec4 rooms[4], float ceiling_height) {
	if (screen_slope >= 0.0) return false;
	float ceiling_depth = (eye_height - ceiling_height) / screen_slope;
	if (ceiling_depth <= 0.075 || ceiling_depth >= hit_depth - 0.001) return false;
	vec2 hit = origin + ray * ceiling_depth;
	for (int i = 1; i < 4; i++) {
		if (all(greaterThanEqual(hit, rooms[i].xy)) && all(lessThan(hit, rooms[i].zw))) return true;
	}
	return false;
}

// World axes are street X, street Y, and height. Return forward depth
// and the signed face axis. The sign is positive on the upper bounds.
vec2 town_wood_box_surface(vec3 origin, vec3 ray, vec3 lower, vec3 upper) {
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
	float side = sign(ray[face]) * (enter >= 0.005 ? -1.0 : 1.0);
	return vec2(enter >= 0.005 ? enter : exit, side * float(face + 1));
}

vec2 town_wood_box_hit(vec3 origin, vec3 ray, vec3 lower, vec3 upper) {
	vec2 hit = town_wood_box_surface(origin, ray, lower, upper);
	float axis = abs(hit.y);
	return vec2(hit.x, axis == 3.0 ? 1.20 : (axis == 1.0 ? 0.89 : 1.05));
}
