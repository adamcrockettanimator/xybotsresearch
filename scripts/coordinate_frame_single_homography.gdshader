shader_type canvas_item;
render_mode unshaded;

// One visible wall per CanvasItem.  This deliberately avoids the large uniform
// arrays used by the first batching pass: the coordinate-frame experiment is
// only 160×120, so reliability and inspectability are worth more than batching.
uniform vec3 inverse_row0 = vec3(1.0, 0.0, 0.0);
uniform vec3 inverse_row1 = vec3(0.0, 1.0, 0.0);
uniform vec3 inverse_row2 = vec3(0.0, 0.0, 1.0);
uniform float wall_light = 1.0;
uniform vec2 wall_texture_size = vec2(128.0, 88.0);

void fragment() {
	vec2 pixel = UV * vec2(160.0, 120.0);
	vec3 h = vec3(
		dot(inverse_row0, vec3(pixel, 1.0)),
		dot(inverse_row1, vec3(pixel, 1.0)),
		dot(inverse_row2, vec3(pixel, 1.0))
	);
	if (abs(h.z) < 0.00001) {
		discard;
	}
	vec2 source_uv = h.xy / h.z;
	if (source_uv.x < 0.0 || source_uv.x > 1.0 || source_uv.y < 0.0 || source_uv.y > 1.0) {
		discard;
	}
	vec2 texel = floor(source_uv * wall_texture_size) + vec2(0.5);
	texel = clamp(texel, vec2(0.5), wall_texture_size - vec2(0.5));
	vec4 sampled = texture(TEXTURE, texel / wall_texture_size);
	COLOR = vec4(sampled.rgb * wall_light, sampled.a);
}
