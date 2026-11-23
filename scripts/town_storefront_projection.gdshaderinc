// Plane heights are sampled at its minimum and maximum world Y.
float storefront_plane_depth(vec2 origin, vec2 ray, float eye_height, float screen_slope, vec4 rect, vec2 heights) {
	if (any(lessThanEqual(rect.zw, rect.xy))) return -1.0;
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

// The caller already owns the surface hit. Ink the one-cell inset along
// its projected edge, using the major axis to keep diagonals connected.
float town_projected_edge_distance(vec2 pixel, vec3 first, vec3 last, vec3 eye,
		vec2 forward, vec2 right, vec2 center, float focal) {
	vec3 from_a = first - eye;
	vec3 from_b = last - eye;
	vec3 a = vec3(dot(from_a.xy, right), -from_a.z, dot(from_a.xy, forward));
	vec3 b = vec3(dot(from_b.xy, right), -from_b.z, dot(from_b.xy, forward));
	const float near_depth = 0.005;
	if (max(a.z, b.z) < near_depth) return 1e10;
	if (a.z < near_depth) a = mix(a, b, (near_depth - a.z) / (b.z - a.z));
	if (b.z < near_depth) b = mix(b, a, (near_depth - b.z) / (a.z - b.z));
	vec2 start = a.xy * focal / a.z;
	vec2 span = b.xy * focal / b.z - start;
	vec2 offset = pixel - center - start;
	float scale = max(abs(span.x), abs(span.y));
	if (scale < 0.0001) return 1e10;
	return abs(span.x * offset.y - span.y * offset.x) / scale;
}

bool town_projected_edge_cell(vec2 pixel, vec3 first, vec3 last, vec3 eye,
		vec2 forward, vec2 right, vec2 center, float focal) {
	return town_projected_edge_distance(pixel, first, last, eye, forward, right, center, focal) < 1.0;
}

// Keep a full cell against the joint. The wider close shadow softens
// outwards and collapses before the core as the joint recedes.
float town_contact_coverage(float distance_px, float width_px) {
	float penumbra = 0.75 * (1.0 - smoothstep(0.65, max(1.01, width_px), distance_px));
	return max(1.0 - step(1.0, distance_px), penumbra * smoothstep(1.0, 1.6, width_px));
}

bool town_gable_front_wall_precedes(vec3 eye, vec3 ray, float depth, vec4 wall) {
	if (abs(ray.y) <= 0.0001) return false;
	float wall_depth = (wall.x - eye.y) / ray.y;
	float wall_x = eye.x + ray.x * wall_depth;
	return wall_depth > 0.005 && wall_depth <= depth + 0.001 &&
		wall_x >= wall.z && wall_x <= wall.w && eye.z + ray.z * wall_depth > wall.y;
}

// Match the standard ground-floor ceiling pass before drawing any surface
// behind it. Shed roofs with visible undersides have no flat ceiling bit.
bool town_ceiling_precedes(vec2 origin, vec2 ray, float eye_height, float screen_slope, float hit_depth, vec4 rooms[8], float ceiling_height, int ceiling_mask) {
	if (screen_slope >= 0.0) return false;
	float ceiling_depth = (eye_height - ceiling_height) / screen_slope;
	if (ceiling_depth <= 0.075 || ceiling_depth >= hit_depth - 0.001) return false;
	vec2 hit = origin + ray * ceiling_depth;
	for (int i = 0; i < 8; i++) {
		if ((ceiling_mask & (1 << i)) == 0) continue;
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

// The deck and fascia have independent canvas layers. Reject only pixels
// whose camera ray reaches a porch post before the receiving surface.
uniform vec4 town_support_boxes[8];
uniform int town_support_count = 0;
uniform float town_support_top = 0.0;
bool town_support_precedes(vec3 eye, vec3 ray, float surface_depth) {
	for (int i = 0; i < town_support_count; i++) {
		vec4 box = town_support_boxes[i];
		float hit = town_wood_box_hit(eye, ray, vec3(box.xy, 0.0), vec3(box.zw, town_support_top)).x;
		if (hit > 0.075 && hit < surface_depth - 0.0001) return true;
	}
	return false;
}
