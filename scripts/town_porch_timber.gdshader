shader_type canvas_item;
render_mode unshaded;

#include "res://scripts/coordinate_frame_daylight.gdshaderinc"
#include "res://scripts/town_storefront_projection.gdshaderinc"

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
uniform float baluster_rail_shadow;
uniform int run_index;
uniform vec3 group_lower[4];
uniform vec3 group_upper[4];
uniform ivec4 member_count;
uniform vec4 member_lower[192]; // Four runs of 48. X/Z slope is in W.
uniform vec4 member_upper[192]; // Y/Z slope is in W.
uniform int occluding_runs;
uniform vec4 cutaway_contacts[4];
uniform vec2 cutaway_ranges[4];
uniform vec4 plane_bounds[24];
uniform vec4 plane_heights[24];
uniform int plane_count;
uniform bool gable_porch_outline = false;
uniform bool gable_porch_behind_wall = false;
uniform vec4 gable_porch_wall;
uniform vec4 outline_color : source_color;

float timber_screen_x(vec2 world) {
	vec2 offset = world - camera_origin;
	return projection_center.x + dot(offset, camera_right) * focal_length / max(dot(offset, camera_forward), 0.005);
}

bool timber_is_gable_post(vec3 lower, vec3 upper) {
	vec3 size = upper - lower;
	return gable_porch_outline && size.z > 0.4 && max(size.x, size.y) < 0.08;
}

bool timber_is_gable_apron(vec3 lower, vec3 upper) {
	return gable_porch_outline && lower.z < 0.04 && upper.z <= 0.051;
}

bool timber_is_gable_brace(vec2 slope) {
	return gable_porch_outline && abs(slope.x) > 0.1;
}

float timber_post_width(vec2 lower, vec2 upper) {
	float a = timber_screen_x(lower);
	float b = timber_screen_x(vec2(lower.x, upper.y));
	float c = timber_screen_x(upper);
	float d = timber_screen_x(vec2(upper.x, lower.y));
	return max(max(a, b), max(c, d)) - min(min(a, b), min(c, d));
}

vec2 timber_hit(int index, vec3 eye, vec3 ray, out vec3 local) {
	vec4 lower = member_lower[index];
	vec4 upper = member_upper[index];
	vec2 slope = vec2(lower.w, upper.w);
	float world_eye_height = eye.z;
	float world_ray_rise = ray.z;
	// Flatten the rise of a brace before the slab test. Ray depth remains
	// in world units, so the hit can still be compared against other runs.
	eye.z -= dot(eye.xy - lower.xy, slope);
	ray.z -= dot(ray.xy, slope);
	vec2 hit = town_wood_box_surface(eye, ray, lower.xyz, upper.xyz);
	local = eye + ray * hit.x;
	float header_bottom = eave_height - 0.037;
	if (hit.x > 0.0 && timber_is_gable_brace(slope) &&
		world_eye_height + world_ray_rise * hit.x > header_bottom) {
		if (world_ray_rise >= -0.0001) return vec2(-1.0);
		float cut = (header_bottom - world_eye_height) / world_ray_rise;
		local = eye + ray * cut;
		if (any(lessThan(local, lower.xyz)) || any(greaterThan(local, upper.xyz))) return vec2(-1.0);
		hit = vec2(cut, 3.0);
	}
	// The deck plane owns the full walkable top. The fascia ends at it.
	if (hit.y == 3.0 && timber_is_gable_apron(lower.xyz, upper.xyz)) return vec2(-1.0);
	return hit;
}

bool timber_is_gable_header(vec3 lower, vec3 upper) {
	vec3 size = upper - lower;
	return size.x > 0.18 && size.y < 0.04 && abs(upper.z - eave_height) < 0.004;
}

bool timber_is_gable_rafter(vec3 lower, vec3 upper) {
	vec3 size = upper - lower;
	return size.x < 0.04 && size.y > 0.18 && lower.z > 0.55;
}

float timber_joint_shadow(vec3 point, int receiver, float face, bool header, float pixel_world) {
	float reach = clamp(pixel_world, 0.024, 0.042);
	float nearest = reach;
	int axis = int(abs(face)) - 1;
	vec3 receiver_center = (member_lower[receiver].xyz + member_upper[receiver].xyz) * 0.5;
	for (int run = 0; run < 4; run++) {
		if (any(lessThan(point, group_lower[run] - reach)) ||
				any(greaterThan(point, group_upper[run] + reach))) continue;
		for (int i = 0; i < member_count[run]; i++) {
			int index = run * 48 + i;
			if (index == receiver) continue;
			vec4 lower = member_lower[index];
			vec4 upper = member_upper[index];
			vec2 slope = vec2(lower.w, upper.w);
			bool brace = timber_is_gable_brace(slope);
			bool rafter = timber_is_gable_rafter(lower.xyz, upper.xyz);
			bool rail = abs(upper.z - 0.30) < 0.001 && upper.x - lower.x > 0.18;
			// An attachment only shades its receiving face. The brace meets
			// the header underside, the rafters meet its back, and the
			// post receives each member on the side it projects from.
			bool attaches = header ? (face == -3.0 && brace || axis == 1 && rafter)
				: (axis == 0 && (brace || rail || timber_is_gable_header(lower.xyz, upper.xyz)) ||
					axis == 1 && rafter);
			if (!attaches) continue;
			vec3 center = (lower.xyz + upper.xyz) * 0.5;
			if (axis < 2 && (center[axis] - receiver_center[axis]) * sign(face) <= 0.0) continue;
			vec3 local = vec3(point.xy, point.z - dot(point.xy - lower.xy, slope));
			vec3 clearance = max(max(lower.xyz - local, local - upper.xyz), vec3(0.0));
			if (brace) clearance.z = max(clearance.z, point.z - (eave_height - 0.037));
			if (axis < 2 && clearance[axis] > 0.002) continue;
			nearest = min(nearest, length(clearance));
		}
	}
	return 0.36 * (1.0 - smoothstep(reach * 0.20, reach, nearest));
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

// Sprite offsets keep the carrier's vertices in logical canvas coordinates.
varying vec2 logical_position;

void vertex() {
	logical_position = VERTEX;
}

void fragment() {
	vec2 pixel = floor(logical_position) + vec2(0.5);
	vec2 screen = (pixel - projection_center) / focal_length;
	vec3 eye = vec3(camera_origin, eye_height);
	vec3 ray = vec3(camera_forward + screen.x * camera_right, -screen.y);
	if (!gable_porch_outline && town_wood_box_hit(eye, ray, group_lower[run_index], group_upper[run_index]).x < 0.0) discard;
	float depth = 1e10;
	float face = 0.0;
	int member_index = -1;
	vec3 from_lower;
	vec3 from_upper;
	vec2 member_to_eye;
	vec3 member_lower_bound;
	vec3 member_upper_bound;
	vec2 member_slope;
	float post_ink = 0.0;
	for (int i = 0; i < member_count[run_index]; i++) {
		int index = run_index * 48 + i;
		vec3 lower = member_lower[index].xyz;
		vec3 upper = member_upper[index].xyz;
		vec3 local;
		vec2 hit = timber_hit(index, eye, ray, local);
		float ink = 0.0;
		if (timber_is_gable_post(lower, upper)) {
			vec2 center = (lower.xy + upper.xy) * 0.5;
			float screen_x = timber_screen_x(center);
			float post_depth = dot(center - camera_origin, camera_forward);
			float projected_width = timber_post_width(lower.xy, upper.xy);
			ink = 1.0 - smoothstep(1.0, 2.3, projected_width);
			// A subpixel support still owns the logical column containing its axis.
			if (post_depth > 0.075 && projected_width < 1.0) {
				if (floor(screen_x) == floor(pixel.x)) {
					vec3 post_ray = vec3(camera_forward + (screen_x - projection_center.x) * camera_right / focal_length, ray.z);
					hit = timber_hit(index, eye, post_ray, local);
				} else {
					hit = vec2(-1.0);
				}
			}
		}
		if (hit.x >= 0.075 && hit.x < depth) {
			depth = hit.x;
			face = hit.y;
			member_index = index;
			from_lower = local - lower;
			from_upper = upper - local;
			member_to_eye = eye.xy - (lower.xy + upper.xy) * 0.5;
			member_lower_bound = lower;
			member_upper_bound = upper;
			member_slope = vec2(member_lower[index].w, member_upper[index].w);
			post_ink = ink;
		}
	}
	if (depth > 1e9) discard;
	if (gable_porch_behind_wall && town_gable_front_wall_precedes(eye, ray, depth, gable_porch_wall)) discard;
	if (town_ceiling_precedes(camera_origin, ray.xy, eye_height, screen.y, depth, town_roof_bounds, ceiling_height, town_ceiling_mask)) discard;
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
	bool gable_header = gable_porch_outline && timber_is_gable_header(member_lower_bound, member_upper_bound);
	bool gable_rafter = gable_porch_outline && timber_is_gable_rafter(member_lower_bound, member_upper_bound);
	bool gable_post = timber_is_gable_post(member_lower_bound, member_upper_bound);
	if (gable_post && axis < 2) tone = town_post_face_tone(axis == 0, face < 0.0);
	bool below_metal = gable_header || gable_rafter || gable_post;
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
			// Project the corner and pick the first pixel centre inside this face.
			// A world-width strip can otherwise fall between adjacent columns.
			vec2 corner = point.xy;
			corner[across] = toward_eye[across] > 0.0 ? member_upper_bound[across] : member_lower_bound[across];
			vec2 inner = corner;
			inner[across] = toward_eye[across] > 0.0 ? member_lower_bound[across] : member_upper_bound[across];
			vec2 corner_delta = corner - camera_origin;
			vec2 inner_delta = inner - camera_origin;
			float corner_depth = dot(corner_delta, camera_forward);
			float inner_depth = dot(inner_delta, camera_forward);
			float edge_x = projection_center.x + dot(corner_delta, camera_right) * focal_length / max(corner_depth, 0.0001);
			float inner_x = projection_center.x + dot(inner_delta, camera_right) * focal_length / max(inner_depth, 0.0001);
			float edge_column = inner_x >= edge_x ? ceil(edge_x - 0.5) : floor(edge_x - 0.5);
			rim = float(floor(pixel.x) == edge_column) * ownership *
				smoothstep(0.05, 0.26, abs(toward_eye[across])) *
				smoothstep(1.5, 3.5, apparent_width / pixel_world);
		} else if (size[across] >= size[axis]) {
			// Select a logical row on the face at each column, including
			// sloped braces, rather than sampling a subpixel world band.
			float edge_y = pixel.y - from_upper.z / pixel_world;
			rim = float(floor(pixel.y) == ceil(edge_y - 0.5)) * height_detail;
		}
		float bottom_y = pixel.y + from_lower.z / pixel_world;
		under = float(floor(pixel.y) == floor(bottom_y - 0.5)) * height_detail;
	}
	if (below_metal) {
		if (gable_rafter || gable_header) {
			rim = 0.0;
			under = 0.0;
		}
		else rim *= smoothstep(0.0, 0.040, from_upper.z);
	}
	if (timber_is_gable_brace(member_slope)) {
		vec3 top_normal = normalize(vec3(-member_slope, 1.0));
		float view_top = dot(normalize(eye - point), top_normal);
		float lit_slope = dot(top_normal.xy, TOWN_SUN_DIRECTION);
		tone = axis == 2 ? (face > 0.0 ? 1.03 + 0.25 * lit_slope : 0.80 - 0.12 * lit_slope) : tone;
		// Accent the corner next to the slope face the camera can see.
		// Looking squarely at the side leaves a single flat timber tone.
		float view_detail = smoothstep(0.08, 0.42, abs(view_top));
		rim *= axis == 1 && view_top > 0.0 ? view_detail * smoothstep(-0.45, 0.20, lit_slope) : 0.0;
		under *= axis == 1 && view_top < 0.0 ? view_detail : 0.0;
	}
	tone *= 1.0 + detail * (timber_lighting.x * rim - timber_lighting.y * under);
	// Slender vertical balusters receive the handrail's contact shadow.
	// Keep this broad shadow independent of the close-only edge accents.
	bool baluster = size.z > 0.12 && size.z < 0.24 && max(size.x, size.y) < 0.035;
	if (baluster) {
		float shadow = baluster_rail_shadow * mix(1.0, 0.55, smoothstep(1.8, 5.0, depth));
		tone *= 1.0 - shadow * (1.0 - smoothstep(0.0, 0.075, from_upper.z));
	}
	float shade = mix(0.72, 1.0, smoothstep(0.02, 0.15, eave_height - point.z));
	if (gable_header || gable_rafter) shade = 0.82;
	if (gable_header) tone = axis == 2 ? (face < 0.0 ? 0.72 : 0.91) : (axis == 0 ? 0.87 : 1.04);
	vec3 paint = town_weathered_wood(timber_color.rgb) * tone * shade;
	if (timber_is_gable_apron(member_lower_bound, member_upper_bound)) {
		paint = town_weathered_wood(timber_color.rgb) * (axis == 0 ? 0.85 : 0.93);
	}
	float contact_shadow = 0.0;
	if ((gable_header && face != 3.0) || (gable_post && axis < 2)) {
		contact_shadow = timber_joint_shadow(point, member_index, face, gable_header, pixel_world);
	}
	if (below_metal) {
		// Shade the receiver beneath the sheet, including a top face seen
		// through an oblique gap. Use the member's sloped coordinates.
		float metal_contact = face == 3.0 ? 1.0 : town_contact_coverage(from_upper.z / pixel_world, 0.020 / pixel_world);
		contact_shadow = max(contact_shadow, 0.32 * metal_contact);
	}
	float haze_depth = town_outdoor_depth(camera_origin, point.xy, depth);
	COLOR = vec4(daylight_color(mix(paint * (1.0 - contact_shadow), outline_color.rgb, post_ink),
		mix(haze_depth, town_outline_haze_depth(haze_depth), post_ink)), 1.0);
}
