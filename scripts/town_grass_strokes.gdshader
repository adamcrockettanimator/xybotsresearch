shader_type canvas_item;
render_mode unshaded;

uniform vec4 blades[8];
uniform vec4 bends[8];
uniform int blade_count;
uniform vec4 pixel_rect;

void fragment() {
	vec2 pixel = floor(pixel_rect.xy + UV * pixel_rect.zw);
	float rise = 0.0;
	float opacity = 0.0;
	for (int blade = 0; blade < blade_count; blade++) {
		vec2 foot = blades[blade].xy;
		vec2 tip = blades[blade].zw;
		if (pixel.y < floor(tip.y) || pixel.y > floor(foot.y)) continue;
		vec2 bend = bends[blade].xy;
		float row_center = clamp(pixel.y + 0.5, tip.y, foot.y);
		vec2 lower = row_center >= bend.y ? foot : bend;
		vec2 upper = row_center >= bend.y ? bend : tip;
		float t = (lower.y - row_center) / (lower.y - upper.y);
		// Each stalk owns exactly one column on each logical row, bend included.
		if (pixel.x != floor(mix(lower.x, upper.x, t)) || bends[blade].z <= opacity) continue;
		rise = (foot.y - row_center) / (foot.y - tip.y);
		opacity = bends[blade].z;
	}
	if (opacity <= 0.0) discard;
	float band = floor(rise * 3.99) / 3.0;
	vec3 straw = mix(vec3(0.50, 0.38, 0.23), vec3(0.70, 0.57, 0.36), band);
	COLOR = vec4(straw, opacity);
}
