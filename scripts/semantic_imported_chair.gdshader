shader_type canvas_item;
uniform vec2 start_pixel;
uniform vec2 end_pixel;
uniform vec4 line_colour : source_color;
uniform float line_width = 1.0;
// Signed offset along the fragment walk's minor axis.  Multiple material
// lanes share the exact same projected endpoints, so they form one contiguous
// logical-pixel ribbon instead of independently shifted, gapped lines.
uniform float line_lane = 0.0;
varying vec2 projected_pixel;
void vertex() { projected_pixel = VERTEX; }
// Same signed dominant-axis logical-cell walk used by the GPU lattice crate.
// The endpoints are projected in 3D on the CPU, then the fragment shader owns
// exactly one grid cell per step between them.
float raster_segment(vec2 pixel, vec2 start_value, vec2 end_value, float width) {
	vec2 start_cell = floor(start_value) + vec2(0.5);
	vec2 end_cell = floor(end_value) + vec2(0.5);
	vec2 delta = end_cell - start_cell;
	if (max(abs(delta.x), abs(delta.y)) < 0.001) return step(length(pixel - start_cell), 0.01);
	float step_index;
	float step_count;
	float minor_coordinate;
	float pixel_minor_coordinate;
	if (abs(delta.x) >= abs(delta.y)) {
		step_index = pixel.x - start_cell.x;
		step_count = delta.x;
		minor_coordinate = start_cell.y + (step_index / delta.x) * delta.y;
		pixel_minor_coordinate = pixel.y;
	} else {
		step_index = pixel.y - start_cell.y;
		step_count = delta.y;
		minor_coordinate = start_cell.x + (step_index / delta.y) * delta.x;
		pixel_minor_coordinate = pixel.x;
	}
	float t = step_index / step_count;
	if (t < 0.0 || t > 1.0) return 0.0;
	float chosen_cell = floor(minor_coordinate) + 0.5 + line_lane;
	if (width <= 1.01) return step(abs(pixel_minor_coordinate - chosen_cell), 0.01);
	return step(abs(pixel_minor_coordinate - chosen_cell), floor(width * 0.5) + 0.01);
}
void fragment() { if (raster_segment(floor(projected_pixel) + vec2(0.5), start_pixel, end_pixel, line_width) < 0.5) discard; COLOR = line_colour; }
