shader_type canvas_item;
render_mode unshaded;

// A full logical-screen carrier for one projected floor or ceiling cell.  The
// inverse homography reconstructs its cell UV on the GPU, replacing the CPU
// Image.set_pixel raster loop and subsequent ImageTexture upload.
uniform sampler2D base_texture : filter_nearest;
uniform sampler2D layer1_texture : filter_nearest;
uniform sampler2D layer2_texture : filter_nearest;
uniform bool use_layers = false;
uniform vec3 inverse_row0 = vec3(1.0, 0.0, 0.0);
uniform vec3 inverse_row1 = vec3(0.0, 1.0, 0.0);
uniform vec3 inverse_row2 = vec3(0.0, 0.0, 1.0);
uniform vec2 layer1_offset = vec2(0.0);
uniform vec2 layer2_offset = vec2(0.0);
uniform float plane_height_delta = 0.5;
uniform float focal_length = 128.0;
uniform float horizon_y = 31.5;
uniform vec2 canvas_size = vec2(160.0, 120.0);

float depth_light(float depth) {
	if (depth < 1.35) return 1.0;
	if (depth < 2.5) return 0.78;
	if (depth < 3.8) return 0.56;
	if (depth < 4.8) return 0.36;
	if (depth < 5.2) return 0.22;
	return 0.10;
}

vec4 nearest_sample(sampler2D source, vec2 source_uv) {
	vec2 texture_size = vec2(textureSize(source, 0));
	vec2 texel = floor(clamp(source_uv, vec2(0.0), vec2(1.0)) * texture_size) + vec2(0.5);
	texel = clamp(texel, vec2(0.5), texture_size - vec2(0.5));
	return texture(source, texel / texture_size);
}

void fragment() {
	vec2 pixel = floor(UV * canvas_size) + vec2(0.5);
	vec3 h = vec3(dot(inverse_row0, vec3(pixel, 1.0)), dot(inverse_row1, vec3(pixel, 1.0)), dot(inverse_row2, vec3(pixel, 1.0)));
	if (abs(h.z) < 0.00001) discard;
	vec2 source_uv = h.xy / h.z;
	if (source_uv.x < 0.0 || source_uv.x > 1.0 || source_uv.y < 0.0 || source_uv.y > 1.0) discard;
	float screen_delta = pixel.y - horizon_y;
	if (abs(screen_delta) < 0.00001) discard;
	float depth = plane_height_delta * focal_length / screen_delta;
	if (depth <= 0.0 || depth > 5.5) discard;
	vec4 result = nearest_sample(base_texture, source_uv);
	if (use_layers) {
		vec4 bottom = nearest_sample(layer1_texture, source_uv + layer1_offset);
		vec4 top = nearest_sample(layer2_texture, source_uv + layer2_offset);
		result.rgb = top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a);
		result.a = top.a + bottom.a * (1.0 - top.a);
	}
	if (result.a <= 0.0) discard;
	COLOR = vec4(result.rgb * depth_light(depth), result.a);
}
