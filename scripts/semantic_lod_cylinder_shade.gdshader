shader_type canvas_item;
render_mode unshaded;

uniform float left_x = 0.0;
uniform float right_x = 1.0;
uniform bool use_profile = false;
uniform vec2 side_a[5];
uniform vec2 side_b[5];
varying vec2 canvas_position;

float profile_x(vec2 points[5], float y) {
	for (int i = 0; i < 4; i++) {
		vec2 a = points[i];
		vec2 b = points[i + 1];
		if (y >= min(a.y, b.y) && y <= max(a.y, b.y) && abs(b.y - a.y) > 0.0001) {
			return mix(a.x, b.x, clamp((y - a.y) / (b.y - a.y), 0.0, 1.0));
		}
	}
	return abs(y - points[0].y) < abs(y - points[4].y) ? points[0].x : points[4].x;
}

void vertex() {
	canvas_position = VERTEX;
}

void fragment() {
	// Broad discrete bands evoke a rounded surface at the logical pixel scale.
	float left = left_x;
	float right = right_x;
	if (use_profile) {
		float a = profile_x(side_a, canvas_position.y);
		float b = profile_x(side_b, canvas_position.y);
		left = min(a, b);
		right = max(a, b);
	}
	float x = clamp((canvas_position.x - left) / max(right - left, 0.001), 0.0, 1.0);
	float light = 0.68 + 0.32 * sqrt(max(0.0, 1.0 - pow(2.0 * x - 1.0, 2.0)));
	// The body gets less light toward the floor as the bowed middle shades
	// the lower staves. Follow the projected rim heights across the barrel.
	if (use_profile) {
		bool a_is_left = side_a[2].x <= side_b[2].x;
		float top_y = a_is_left ? mix(side_a[4].y, side_b[4].y, x) : mix(side_b[4].y, side_a[4].y, x);
		float bottom_y = a_is_left ? mix(side_a[0].y, side_b[0].y, x) : mix(side_b[0].y, side_a[0].y, x);
		float height_position = clamp((canvas_position.y - top_y) / max(bottom_y - top_y, 0.001), 0.0, 1.0);
		light *= mix(1.15, 0.68, smoothstep(0.0, 1.0, height_position));
	}
	light = floor(light * 16.0 + 0.5) / 16.0;
	COLOR.rgb *= light;
}
