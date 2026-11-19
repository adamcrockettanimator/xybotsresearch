shader_type canvas_item;
render_mode unshaded;

#include "res://scripts/coordinate_frame_daylight.gdshaderinc"

uniform sampler2D horizon_strip : filter_nearest, repeat_disable;
uniform vec2 canvas_size;
uniform vec2 projection_center;
uniform float focal_length;
uniform float camera_height;
uniform float camera_turn;
uniform vec2 camera_origin;
uniform vec2 camera_forward;
uniform vec2 camera_right;

void fragment() {
	vec2 pixel = floor(UV * canvas_size) + vec2(0.5);
	float angle = atan((pixel.x - projection_center.x) / focal_length);
	float panorama_u = fract(camera_turn + angle / TAU);
	float elevation = pixel.y - projection_center.y;
	float strip_y = clamp((elevation + 31.0) / 31.0, 0.0, 1.0);
	if (elevation <= 0.0) {
		COLOR = texture(horizon_strip, vec2(panorama_u, strip_y));
	} else {
		// Continue the same ground plane behind the transparent fence rails.
		float depth = camera_height * focal_length / elevation;
		float side = (pixel.x - projection_center.x) * depth / focal_length;
		vec2 world = camera_origin + camera_right * side + camera_forward * depth;
		float outdoor_depth = town_outdoor_depth(camera_origin, world, depth);
		COLOR = vec4(daylight_color(vec3(0.74, 0.55, 0.29), outdoor_depth), 1.0);
	}
}
