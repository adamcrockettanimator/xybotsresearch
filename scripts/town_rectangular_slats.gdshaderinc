// Adjacent courses keep a light/dark rhythm. The repeating four-course
// stagger breaks vertical joints, with small tone changes at each joint.
float rectangular_slat_tone(vec2 plank) {
	float course = floor(plank.y + 0.00001);
	float stagger = mod(course, 2.0) * 0.5 + floor(mod(course, 4.0) / 2.0) * 0.12;
	float board = floor(plank.x + stagger);
	float variation = fract(sin(dot(vec2(board, course), vec2(8.31, 13.57))) * 217.9);
	return mix(0.805, 0.925, mod(course, 2.0)) + (variation - 0.5) * 0.045;
}
