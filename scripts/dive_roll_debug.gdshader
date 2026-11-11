shader_type canvas_item;

uniform vec4 debug_color : source_color = vec4(1.0, 0.85, 0.0, 0.72);

void fragment() {
	float alpha = texture(TEXTURE, UV).a;
	COLOR = vec4(debug_color.rgb, alpha * debug_color.a);
}
