shader_type canvas_item;
render_mode unshaded;

// The template has 13 independently editable visible planes. Each plane uses
// three rows of an inverse homography: screen pixel -> source UV.
const int MAX_PLANES = 16;
uniform int plane_count = 0;
uniform vec4 inverse_homography_rows[48];
uniform sampler2D source_texture : source_color, filter_nearest, repeat_disable;
uniform vec2 source_size = vec2(160.0, 120.0);
uniform float arcade_pixel_step = 2.0;
uniform float arcade_uv_step = 2.0;
uniform float plane_brightness[16];
uniform bool coverage_debug = false;
uniform bool force_clean_edges = false;


vec4 debug_plane_color(int plane_index) {
	// Alternate colors by depth band and plane orientation so adjacent quads
	// remain easy to distinguish without sampling the source texture.
	int orientation = plane_index % 4;
	int depth_band = plane_index / 4;
	float shade = 1.0 - float(depth_band) * 0.17;
	if (orientation == 0) {
		return vec4(0.25, 0.70, 1.0, 1.0) * shade; // ceiling
	}
	if (orientation == 1) {
		return vec4(1.0, 0.45, 0.25, 1.0) * shade; // right wall
	}
	if (orientation == 2) {
		return vec4(0.32, 0.95, 0.45, 1.0) * shade; // floor
	}
	return vec4(0.72, 0.38, 1.0, 1.0) * shade; // left wall / back wall
}

void fragment() {
	// SCREEN_UV remains 0..1 after Godot stretches the 160x120 viewport into
	// the game window. Convert it back to native template coordinates, then
	// snap it onto an intentionally chunky arcade raster.
	vec2 native_pixel = SCREEN_UV * vec2(160.0, 120.0);
	vec2 pixel = floor(native_pixel / arcade_pixel_step) * arcade_pixel_step + vec2(arcade_pixel_step * 0.5);
	vec4 output_color = vec4(0.0);
	vec4 debug_color = vec4(0.0);
	int coverage_count = 0;
	float edge_epsilon = force_clean_edges ? 0.004 : 0.0;
	for (int index = 0; index < MAX_PLANES; index++) {
		if (index >= plane_count) {
			break;
		}
		int row = index * 3;
		vec3 homogeneous_uv = vec3(
			dot(inverse_homography_rows[row].xyz, vec3(pixel, 1.0)),
			dot(inverse_homography_rows[row + 1].xyz, vec3(pixel, 1.0)),
			dot(inverse_homography_rows[row + 2].xyz, vec3(pixel, 1.0))
		);
		if (abs(homogeneous_uv.z) < 0.00001) {
			continue;
		}
		vec2 uv = homogeneous_uv.xy / homogeneous_uv.z;
		if (uv.x >= -edge_epsilon && uv.x <= 1.0 + edge_epsilon && uv.y >= -edge_epsilon && uv.y <= 1.0 + edge_epsilon) {
			coverage_count += 1;
			debug_color = debug_plane_color(index);
			// Quantize texture lookup separately from screen rasterization. This
			// intentionally breaks smooth projective sampling into sprite-like
			// blocks while retaining the template's exact quad boundaries.
			vec2 source_pixel = floor(uv * source_size / arcade_uv_step) * arcade_uv_step + vec2(arcade_uv_step * 0.5);
			source_pixel = clamp(source_pixel, vec2(0.5), source_size - vec2(0.5));
			output_color = texture(source_texture, source_pixel / source_size);
			output_color.rgb *= plane_brightness[index];
		}
	}
	if (coverage_debug) {
		if (coverage_count > 1) {
			output_color = vec4(1.0, 0.95, 0.0, 1.0); // Multiple planes claim this pixel.
		} else if (coverage_count == 1) {
			output_color = debug_color;
		} else {
			// The fixed authoring template fills every native row from y=4 through
			// y=111. Magenta here means a genuine interior coverage hole.
			output_color = native_pixel.y >= 4.0 && native_pixel.y <= 111.0 ? vec4(1.0, 0.0, 0.75, 1.0) : vec4(0.0);
		}
	}
	COLOR = output_color;
}
