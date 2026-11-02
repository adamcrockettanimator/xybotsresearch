// Paint a convex projected quad as whole logical cells. The carrier is only a
// bounding rectangle; the fragment stage owns the mosaic coverage decision.
shader_type canvas_item;

uniform vec2 corner_0;
uniform vec2 corner_1;
uniform vec2 corner_2;
uniform vec2 corner_3;
uniform vec4 face_colour : source_color;
varying vec2 projected_pixel;

void vertex() {
	projected_pixel = VERTEX;
}

float cross_2d(vec2 a, vec2 b) {
	return a.x * b.y - a.y * b.x;
}

bool inside_convex_quad(vec2 point) {
	vec2 corners[4] = vec2[](corner_0, corner_1, corner_2, corner_3);
	float first_sign = 0.0;
	for (int index = 0; index < 4; index++) {
		float side = cross_2d(corners[(index + 1) % 4] - corners[index], point - corners[index]);
		if (abs(side) < 0.0001) continue;
		if (first_sign == 0.0) first_sign = sign(side);
		else if (side * first_sign < 0.0) return false;
	}
	return true;
}

void fragment() {
	vec2 cell = floor(projected_pixel) + vec2(0.5);
	if (!inside_convex_quad(cell)) discard;
	COLOR = face_colour;
}
