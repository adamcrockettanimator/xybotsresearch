shader_type canvas_item;

uniform float floor_logical_y = 110.0;
uniform float top_logical_y = 50.0;
uniform float floor_darkening_strength : hint_range(0.0, 1.0) = 0.32;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float safe_span = max(floor_logical_y - top_logical_y, 0.001);
	float height_t = clamp((floor_logical_y - UV.y * 120.0) / safe_span, 0.0, 1.0);
	// The multiplier is never above one: this pass only darkens the completed
	// logical raster from the floor upward, leaving its highest point unchanged.
	float multiplier = clamp(1.0 - floor_darkening_strength * (1.0 - height_t), 0.0, 1.0);
	COLOR = vec4(source.rgb * multiplier, source.a);
}
