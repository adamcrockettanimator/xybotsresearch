shader_type canvas_item;
render_mode unshaded;

// A full logical-screen carrier for one projected floor or ceiling cell.  The
// inverse homography reconstructs its cell UV on the GPU, replacing the CPU
// Image.set_pixel raster loop and subsequent ImageTexture upload.
uniform sampler2D base_texture : filter_nearest;
uniform sampler2D layer1_texture : filter_nearest;
uniform sampler2D layer2_texture : filter_nearest;
uniform bool use_layers = false;
uniform bool use_floor_depth_dither = false;
uniform float floor_light_dither_near_half_width_pixels = 3.0;
uniform float floor_light_dither_far_half_width_pixels = 1.0;
uniform int floor_light_dither_steps = 4;
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

float bayer2_threshold(vec2 pixel) {
	float x = mod(floor(pixel.x), 2.0);
	float y = mod(floor(pixel.y), 2.0);
	return (2.0 * x + 3.0 * y - 4.0 * x * y + 0.5) / 4.0;
}

float floor_depth_light(float depth, vec2 pixel) {
	float thresholds[5] = float[](1.35, 2.5, 3.8, 4.8, 5.2);
	float near_lights[5] = float[](1.0, 0.78, 0.56, 0.36, 0.22);
	float far_lights[5] = float[](0.78, 0.56, 0.36, 0.22, 0.10);
	float depth_per_pixel = max(depth * depth / (plane_height_delta * focal_length), 0.0001);
	float near_weight = 1.0 - clamp((depth - 1.35) / (5.2 - 1.35), 0.0, 1.0);
	float half_band = depth_per_pixel * mix(floor_light_dither_far_half_width_pixels, floor_light_dither_near_half_width_pixels, near_weight);
	for (int index = 0; index < 5; index++) {
		float threshold = thresholds[index];
		if (depth < threshold - half_band) return near_lights[index];
		if (depth <= threshold + half_band) {
			float coverage = clamp((depth - (threshold - half_band)) / (half_band * 2.0), 0.0, 1.0);
			float scaled_step = coverage * float(floor_light_dither_steps);
			int lower_step = clamp(int(floor(scaled_step)), 0, floor_light_dither_steps);
			int upper_step = min(lower_step + 1, floor_light_dither_steps);
			int selected_step = fract(scaled_step) >= bayer2_threshold(pixel) ? upper_step : lower_step;
			return mix(near_lights[index], far_lights[index], float(selected_step) / float(floor_light_dither_steps));
		}
	}
	return 0.10;
}

void fragment() {
	vec2 pixel = floor(UV * canvas_size) + vec2(0.5);
	vec3 h = vec3(dot(inverse_row0, vec3(pixel, 1.0)), dot(inverse_row1, vec3(pixel, 1.0)), dot(inverse_row2, vec3(pixel, 1.0)));
	if (abs(h.z) < 0.00001) discard;
	vec2 source_uv = h.xy / h.z;
	float screen_delta = pixel.y - horizon_y;
	if (abs(screen_delta) < 0.00001) discard;
	float depth = plane_height_delta * focal_length / screen_delta;
	if (depth <= 0.0 || depth > 5.5) discard;
	if (source_uv.x < 0.0 || source_uv.x > 1.0 || source_uv.y < 0.0 || source_uv.y > 1.0) discard;
	vec4 result = nearest_sample(base_texture, source_uv);
	if (use_layers) {
		vec4 bottom = nearest_sample(layer1_texture, source_uv + layer1_offset);
		vec4 top = nearest_sample(layer2_texture, source_uv + layer2_offset);
		result.rgb = top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a);
		result.a = top.a + bottom.a * (1.0 - top.a);
	}
	if (result.a <= 0.0) discard;
	float light = use_floor_depth_dither ? floor_depth_light(depth, pixel) : depth_light(depth);
	COLOR = vec4(result.rgb * light, result.a);
}
