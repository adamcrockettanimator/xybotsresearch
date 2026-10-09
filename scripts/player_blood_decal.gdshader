shader_type canvas_item;
render_mode unshaded;

uniform sampler2D blood_mask : source_color, filter_nearest;
uniform vec2 blood_center = vec2(0.5);
uniform vec2 blood_size = vec2(0.1);
uniform vec4 blood_color : source_color = vec4(0.70, 0.01, 0.01, 0.8);

void fragment() {
	vec2 blood_uv = (UV - blood_center) / blood_size + vec2(0.5);
	float inside_blood_card = step(0.0, blood_uv.x) * step(blood_uv.x, 1.0) * step(0.0, blood_uv.y) * step(blood_uv.y, 1.0);
	float character_alpha = texture(TEXTURE, UV).a;
	float blob_alpha = texture(blood_mask, blood_uv).a * inside_blood_card;
	COLOR = vec4(blood_color.rgb, blood_color.a * blob_alpha * character_alpha);
}
