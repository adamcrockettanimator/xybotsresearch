shader_type canvas_item;
render_mode unshaded;

// The four corners arrive already snapped by the semantic-footprint node.
// Every fragment chooses one *logical* pixel coordinate, then uses the same
// major-axis Bresenham rule as the CPU reference path.  This is deliberately
// hard edged: no alpha coverage, derivatives, or vector-stroke smoothing.
uniform vec2 logical_canvas_size = vec2(160.0, 120.0);
uniform vec2 corner_a = vec2(0.0);
uniform vec2 corner_b = vec2(0.0);
uniform vec2 corner_c = vec2(0.0);
uniform vec2 corner_d = vec2(0.0);
uniform vec4 line_color : source_color = vec4(1.0);
uniform vec4 point_color : source_color = vec4(1.0, 0.08, 0.08, 1.0);


bool is_bresenham_pixel(vec2 pixel, vec2 from, vec2 to) {
	vec2 delta = to - from;
	float delta_x = abs(delta.x);
	float delta_y = abs(delta.y);
	if (delta_x < 0.5 && delta_y < 0.5) {
		return false;
	}
	if (delta_x >= delta_y) {
		float step_x = sign(delta.x);
		float step_index = (pixel.x - from.x) * step_x;
		if (step_index < 0.0 || step_index > delta_x || abs(pixel.x - (from.x + step_index * step_x)) > 0.1) {
			return false;
		}
		float expected_y = from.y + sign(delta.y) * floor((delta_y * step_index + delta_x * 0.5) / delta_x);
		return abs(pixel.y - expected_y) < 0.1;
	}
	float step_y = sign(delta.y);
	float step_index = (pixel.y - from.y) * step_y;
	if (step_index < 0.0 || step_index > delta_y || abs(pixel.y - (from.y + step_index * step_y)) > 0.1) {
		return false;
	}
	float expected_x = from.x + sign(delta.x) * floor((delta_x * step_index + delta_y * 0.5) / delta_y);
	return abs(pixel.x - expected_x) < 0.1;
}


bool is_corner(vec2 pixel, vec2 corner) {
	return all(equal(pixel, corner));
}


void fragment() {
	vec2 pixel = floor(UV * logical_canvas_size);
	vec2 minimum_corner = min(min(corner_a, corner_b), min(corner_c, corner_d)) - vec2(1.0);
	vec2 maximum_corner = max(max(corner_a, corner_b), max(corner_c, corner_d)) + vec2(1.0);
	if (any(lessThan(pixel, minimum_corner)) || any(greaterThan(pixel, maximum_corner))) {
		discard;
	}
	bool at_corner = is_corner(pixel, corner_a) || is_corner(pixel, corner_b) || is_corner(pixel, corner_c) || is_corner(pixel, corner_d);
	if (at_corner) {
		COLOR = point_color;
	} else {
		bool on_edge = is_bresenham_pixel(pixel, corner_a, corner_b)
			|| is_bresenham_pixel(pixel, corner_b, corner_c)
			|| is_bresenham_pixel(pixel, corner_c, corner_d)
			|| is_bresenham_pixel(pixel, corner_d, corner_a);
		if (on_edge) {
			COLOR = line_color;
		} else {
			discard;
		}
	}
}
