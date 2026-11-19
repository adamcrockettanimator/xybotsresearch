shader_type canvas_item;
render_mode unshaded;

#include "res://scripts/coordinate_frame_daylight.gdshaderinc"
#include "res://scripts/town_storefront_projection.gdshaderinc"
#include "res://scripts/town_rectangular_slats.gdshaderinc"

uniform vec4 bounds;
uniform vec2 edge_heights;
uniform vec2 camera_origin;
uniform vec2 camera_forward;
uniform vec2 camera_right;
uniform vec2 projection_center;
uniform vec2 canvas_size;
uniform float focal_length;
uniform float camera_height;
uniform float far_depth;
uniform bool metal;
uniform bool porch_slats;
uniform float ledge_shadow;
uniform vec4 surface_color : source_color;

void fragment() {
	vec2 pixel = floor(UV * canvas_size) + vec2(0.5);
	vec2 screen = (pixel - projection_center) / focal_length;
	vec2 direction = camera_forward + screen.x * camera_right;
	float slope = (edge_heights.y - edge_heights.x) / (bounds.w - bounds.y);
	float origin_plane_height = edge_heights.x + slope * (camera_origin.y - bounds.y);
	float depth = storefront_plane_depth(camera_origin, direction, camera_height, screen.y, bounds, edge_heights);
	if (depth <= 0.075 || depth > far_depth) discard;
	vec2 world = camera_origin + direction * depth;
	vec2 local = (world - bounds.xy) / (bounds.zw - bounds.xy);
	float repeat = metal ? 13.0 : 9.0;
	float profile = fract(local.x * repeat);
	float detail = 1.0 - smoothstep(2.0, 6.5, depth);
	float band = mix(0.92, profile < 0.16 ? 0.68 : (profile < 0.30 ? 1.19 : 0.98), detail);
	if (porch_slats) {
		// Long boards/sheets run from the wall toward the porch edge.
		vec2 plank = vec2(0.0, local.x * 16.0);
		// Estimate the footprint from neighboring logical camera rays. Screen
		// derivatives of the snapped UV would instead measure upscale pixels.
		float denominator = screen.y + slope * direction.y;
		vec2 depth_steps = denominator + vec2(slope * camera_right.y, 1.0) / focal_length;
		float footprint = 1.0;
		if (min(abs(depth_steps.x), abs(depth_steps.y)) > 0.0001) {
			vec2 delta_x = (direction + camera_right / focal_length) * (depth * denominator / depth_steps.x) - direction * depth;
			vec2 delta_y = direction * (depth * denominator / depth_steps.y - depth);
			footprint = max(abs(delta_x.x), abs(delta_y.x)) * 16.0;
		}
		float visible = detail * (1.0 - smoothstep(0.29, 0.70, footprint));
		band = mix(0.865, rectangular_slat_tone(plank), visible);
		// A contact strip anchors the porch deck to the wall beneath the awning.
		if (!metal) band *= 1.0 - 0.55 * ledge_shadow * smoothstep(0.68, 1.0, local.y);
	}
	float side_light = metal && camera_height < origin_plane_height ? 0.65 : 1.0;
	vec3 paint = surface_color.rgb * band * side_light;
	float outdoor_depth = town_outdoor_depth(camera_origin, world, depth);
	COLOR = vec4(daylight_color(paint, outdoor_depth), 1.0);
}
