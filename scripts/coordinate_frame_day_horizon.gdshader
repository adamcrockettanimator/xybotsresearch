shader_type canvas_item;
render_mode unshaded;

#include "res://scripts/coordinate_frame_daylight.gdshaderinc"

uniform sampler2D horizon_strip : filter_nearest, repeat_disable;
uniform vec2 canvas_size;
uniform vec2 projection_center;
uniform float focal_length;
uniform float camera_height;
uniform float camera_turn;

void fragment() {
	vec2 pixel = floor(UV * canvas_size) + vec2(0.5);
	float angle = atan((pixel.x - projection_center.x) / focal_length);
	float panorama_u = fract(camera_turn + angle / TAU);
	float elevation = pixel.y - projection_center.y;
	float strip_y = clamp((elevation + 31.0) / 31.0, 0.0, 1.0);
	vec3 sky = texture(horizon_strip, vec2(panorama_u, strip_y)).rgb;
	// Continue the same ground plane behind the transparent fence rails.
	float ground_depth = camera_height * focal_length / max(elevation, 0.01);
	vec3 ground = daylight_color(vec3(0.74, 0.55, 0.29), ground_depth);
	COLOR = vec4(elevation <= 0.0 ? sky : ground, 1.0);
}
