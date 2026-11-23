shader_type canvas_item;
render_mode unshaded;

#include "res://scripts/town_storefront_projection.gdshaderinc"

uniform vec4 blades[8];
uniform vec4 bends[8];
uniform vec2 inverse_depths[8];
uniform int blade_count;
uniform vec4 pixel_rect;
uniform vec4 floor_bounds;
uniform vec4 all_floor_bounds[6];
uniform int all_floor_count;
uniform float floor_height;
uniform vec2 camera_origin;
uniform vec2 camera_forward;
uniform vec2 camera_right;
uniform vec4 projection; // Projection center, focal length, eye height.

void fragment() {
	vec2 pixel = floor(pixel_rect.xy + UV * pixel_rect.zw);
	vec2 screen = (pixel + 0.5 - projection.xy) / projection.z;
	vec2 ray = camera_forward + screen.x * camera_right;
	float floor_depth = -1.0;
	for (int i = 0; i < all_floor_count; i++) {
		float hit = storefront_plane_depth(camera_origin, ray, projection.w, screen.y, all_floor_bounds[i], vec2(floor_height));
		if (hit > 0.075 && (floor_depth < 0.0 || hit < floor_depth)) floor_depth = hit;
	}
	float rise = 0.0;
	float opacity = 0.0;
	for (int blade = 0; blade < blade_count; blade++) {
		vec2 foot = blades[blade].xy;
		vec2 tip = blades[blade].zw;
		if (pixel.y < floor(tip.y) || pixel.y > floor(foot.y)) continue;
		vec2 bend = bends[blade].xy;
		float row_center = clamp(pixel.y + 0.5, tip.y, foot.y);
		bool below_bend = row_center >= bend.y;
		vec2 lower = below_bend ? foot : bend;
		vec2 upper = below_bend ? bend : tip;
		float t = (lower.y - row_center) / (lower.y - upper.y);
		// Each stalk owns exactly one column on each logical row, bend included.
		if (pixel.x != floor(mix(lower.x, upper.x, t)) || bends[blade].z <= opacity) continue;
		// Compare the stroke to the same raised floor drawn across the porch and room.
		float lower_depth = below_bend ? inverse_depths[blade].x : bends[blade].w;
		float upper_depth = below_bend ? bends[blade].w : inverse_depths[blade].y;
		if (floor_depth > 0.075 && floor_depth * mix(lower_depth, upper_depth, t) < 1.0) continue;
		rise = (foot.y - row_center) / (foot.y - tip.y);
		opacity = bends[blade].z;
	}
	if (opacity <= 0.0) discard;
	float band = floor(rise * 3.99) / 3.0;
	vec3 straw = mix(vec3(0.50, 0.38, 0.23), vec3(0.70, 0.57, 0.36), band);
	COLOR = vec4(straw, opacity);
}
