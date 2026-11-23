shader_type canvas_item;

// The original stool applies this gradient to its completed viewport texture.
// In the shared-target experiment, paint the same gradient on its raster node.
uniform float floor_logical_y = 110.0;
uniform float top_logical_y = 50.0;
uniform float floor_darkening_strength : hint_range(0.0, 1.0) = 0.32;
varying float logical_y;

void vertex() {
	logical_y = VERTEX.y;
}

void fragment() {
	float safe_span = max(floor_logical_y - top_logical_y, 0.001);
	float height_t = clamp((floor_logical_y - logical_y) / safe_span, 0.0, 1.0);
	float multiplier = clamp(1.0 - floor_darkening_strength * (1.0 - height_t), 0.0, 1.0);
	COLOR.rgb *= multiplier;
}
