shader_type canvas_item;
render_mode unshaded;

// One full native-resolution CanvasItem per visible wall.  Projective UVs are
// evaluated by the GPU, leaving GDScript responsible only for visibility and
// the three inverse-homography rows.  This deliberately avoids the uniform
// array that made the earlier batched shader unreliable on the Windows driver.

uniform sampler2D base_texture : filter_nearest;
uniform sampler2D layer1_texture : filter_nearest;
uniform sampler2D layer2_texture : filter_nearest;
uniform bool use_layer_parallax = false;
uniform bool clamp_layer_edges = true;
uniform vec3 inverse_row0 = vec3(1.0, 0.0, 0.0);
uniform vec3 inverse_row1 = vec3(0.0, 1.0, 0.0);
uniform vec3 inverse_row2 = vec3(0.0, 0.0, 1.0);
uniform vec2 base_texture_size = vec2(128.0, 88.0);
uniform vec2 layer_texture_size = vec2(128.0, 88.0);
uniform vec2 layer1_offset = vec2(0.0);
uniform vec2 layer2_offset = vec2(0.0);
uniform float wall_light = 1.0;
uniform vec2 canvas_size = vec2(160.0, 120.0);

vec4 nearest_sample(sampler2D source, vec2 source_uv, vec2 source_size, bool clamp_to_edge) {
	if (clamp_to_edge) {
		source_uv = clamp(source_uv, vec2(0.0), vec2(1.0));
	} else if (source_uv.x < 0.0 || source_uv.x > 1.0 || source_uv.y < 0.0 || source_uv.y > 1.0) {
		return vec4(0.0);
	}
	vec2 texel = floor(source_uv * source_size) + vec2(0.5);
	texel = clamp(texel, vec2(0.5), source_size - vec2(0.5));
	return texture(source, texel / source_size);
}

void fragment() {
	vec2 pixel = UV * canvas_size;
	vec3 homogeneous = vec3(
		dot(inverse_row0, vec3(pixel, 1.0)),
		dot(inverse_row1, vec3(pixel, 1.0)),
		dot(inverse_row2, vec3(pixel, 1.0))
	);
	if (abs(homogeneous.z) < 0.00001) {
		discard;
	}
	vec2 source_uv = homogeneous.xy / homogeneous.z;
	if (source_uv.x < 0.0 || source_uv.x > 1.0 || source_uv.y < 0.0 || source_uv.y > 1.0) {
		discard;
	}
	vec4 result;
	if (use_layer_parallax) {
		vec4 bottom = nearest_sample(layer1_texture, source_uv + layer1_offset, layer_texture_size, clamp_layer_edges);
		vec4 top = nearest_sample(layer2_texture, source_uv + layer2_offset, layer_texture_size, clamp_layer_edges);
		result.rgb = top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a);
		result.a = top.a + bottom.a * (1.0 - top.a);
	} else {
		result = nearest_sample(base_texture, source_uv, base_texture_size, false);
	}
	if (result.a <= 0.0) {
		discard;
	}
	COLOR = vec4(result.rgb * wall_light, result.a);
}
