shader_type canvas_item;
render_mode unshaded;

#include "res://scripts/coordinate_frame_daylight.gdshaderinc"
#include "res://scripts/town_storefront_projection.gdshaderinc"

uniform vec2 canvas_size;
uniform vec2 projection_center;
uniform vec2 camera_origin;
uniform vec2 camera_forward;
uniform vec2 camera_right;
uniform float eye_height;
uniform float ceiling_height;
uniform float focal_length;
uniform vec4 timber_color : source_color;
uniform float eave_height;
uniform vec2 timber_lighting;
uniform int run_index;
uniform vec3 group_lower[4];
uniform vec3 group_upper[4];
uniform ivec4 member_count;
uniform vec4 member_lower[192]; // Four runs of 48. X/Z slope is in W.
uniform vec4 member_upper[192]; // Y/Z slope is in W.
uniform int occluding_runs;
uniform vec4 cutaway_contacts[4];
uniform vec2 cutaway_ranges[4];
uniform vec4 plane_bounds[16];
uniform vec4 plane_heights[16];
uniform int plane_count;
vec2 timber_hit(int index, vec3 eye, vec3 ray, out vec3 local) {
	vec4 lower = member_lower[index];
	vec4 upper = member_upper[index];
	vec2 slope = vec2(lower.w, upper.w);
	// Flatten the rise of a brace before the slab test. Ray depth remains
	// in world units, so the hit can still be compared against other runs.
	eye.z -= dot(eye.xy - lower.xy, slope);
	ray.z -= dot(ray.xy, slope);
	vec2 hit = town_wood_box_surface(eye, ray, lower.xyz, upper.xyz);
	local = eye + ray * hit.x;
	return hit;
}

bool timber_visible(int run, vec2 world, vec2 pixel) {
	vec2 range = cutaway_ranges[run];
	if (range.y <= 0.0) return true;
	vec4 contact = cutaway_contacts[run];
	vec2 edge = contact.zw - contact.xy;
	float along = clamp(dot(world - contact.xy, edge) / max(dot(edge, edge), 0.000001), 0.0, 1.0);
	float coverage = smoothstep(range.x, range.x + range.y, length(world - contact.xy - edge * along));
	float threshold = mod(floor(pixel.x) + floor(pixel.y) * 2.0, 4.0) * 0.25 + 0.125;
	return coverage >= threshold;
}

void fragment() {
	vec2 pixel = floor(UV * canvas_size) + vec2(0.5);
	vec2 screen = (pixel - projection_center) / focal_length;
	vec3 eye = vec3(camera_origin, eye_height);
	vec3 ray = vec3(camera_forward + screen.x * camera_right, -screen.y);
	if (town_wood_box_hit(eye, ray, group_lower[run_index], group_upper[run_index]).x < 0.0) discard;
	float depth = 1e10;
	float face = 0.0;
	vec3 from_lower;
	vec3 from_upper;
	vec2 member_to_eye;
	for (int i = 0; i < member_count[run_index]; i++) {
		int index = run_index * 48 + i;
		vec3 local;
		vec2 hit = timber_hit(index, eye, ray, local);
		if (hit.x >= 0.075 && hit.x < depth) {
			depth = hit.x;
			face = hit.y;
			vec3 lower = member_lower[index].xyz;
			vec3 upper = member_upper[index].xyz;
			from_lower = local - lower;
			from_upper = upper - local;
			member_to_eye = eye.xy - (lower.xy + upper.xy) * 0.5;
		}
	}
	if (depth > 1e9) discard;
	if (town_ceiling_precedes(camera_origin, ray.xy, eye_height, screen.y, depth, town_roof_bounds, ceiling_height)) discard;
	for (int i = 0; i < plane_count; i++) {
		vec4 heights = plane_heights[i];
		float hit = town_plane_depth(camera_origin, ray.xy, eye_height, screen.y,
			plane_bounds[i], heights.xy, heights.z > 0.5);
		if (hit > 0.075 && hit < depth - 0.001) discard;
	}
	vec3 point = eye + ray * depth;
	if (!timber_visible(run_index, point.xy, pixel)) discard;
	// A rail in an earlier canvas layer can still be physically behind a
	// corner post on one ray and in front on the next. Compare actual hits.
	for (int run = 0; run < 4; run++) {
		if ((occluding_runs & (1 << run)) == 0) continue;
		if (town_wood_box_hit(eye, ray, group_lower[run], group_upper[run]).x < 0.0) continue;
		for (int i = 0; i < member_count[run]; i++) {
			vec3 local;
			float other = timber_hit(run * 48 + i, eye, ray, local).x;
			if (other >= 0.075 && other < depth - 0.0008 &&
				timber_visible(run, camera_origin + ray.xy * other, pixel)) discard;
		}
	}
	int axis = int(abs(face)) - 1;
	float tone = axis == 2 ? (face > 0.0 ? 1.20 : 0.77) :
		(axis == 0 ? (face < 0.0 ? 1.17 : 0.89) : 1.05);
	float pixel_world = depth / focal_length;
	float detail = 1.0 - smoothstep(1.9, 4.1, depth);
	// The top plane keeps its broad face tone. Put the rim just under the
	// top on the long visible face of rails and braces, never on the far lip.
	vec3 size = from_lower + from_upper;
	float rim = 0.0;
	float under = 0.0;
	if (axis < 2) {
		int across = 1 - axis;
		float height_detail = smoothstep(2.0, 4.0, size.z / pixel_world);
		if (size.z > 2.0 * max(size.x, size.y)) {
			// A post's leading corner belongs to just one face. Transfer its
			// highlight between faces as the view turns around the corner.
			vec2 toward_eye = normalize(member_to_eye);
			float apparent_width = abs(toward_eye[axis]) * size[across];
			float other_width = abs(toward_eye[across]) * size[axis];
			float ownership = smoothstep(0.42, 0.58, apparent_width / max(apparent_width + other_width, 0.0001));
			float near_edge = toward_eye[across] > 0.0 ? from_upper[across] : from_lower[across];
			rim = step(near_edge, pixel_world) * ownership *
				smoothstep(0.05, 0.26, abs(toward_eye[across])) *
				smoothstep(1.5, 3.5, apparent_width / pixel_world);
		} else if (size[across] >= size[axis]) {
			rim = step(from_upper.z, pixel_world) * height_detail;
		}
		under = step(from_lower.z, pixel_world) * height_detail;
	}
	tone *= 1.0 + detail * (timber_lighting.x * rim - timber_lighting.y * under);
	float shade = mix(0.72, 1.0, smoothstep(0.02, 0.15, eave_height - point.z));
	COLOR = vec4(daylight_color(town_weathered_wood(timber_color.rgb) * tone * shade, town_outdoor_depth(camera_origin, point.xy, depth)), 1.0);
}
