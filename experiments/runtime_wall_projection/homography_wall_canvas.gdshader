shader_type canvas_item;
render_mode unshaded;

// Three inverse-homography rows per wall.  The .w member of row 0 is that
// wall's already-quantized distance shade.  A small fixed limit is sufficient
// for the diagnostic maze and keeps this deliberately simple first GPU test.
const int MAX_WALLS = 64;
uniform int wall_count = 0;
uniform vec4 inverse_homography_rows[192];
// Camera-local segment endpoints: side_a, depth_a, side_b, depth_b. They let
// the shader resolve actual nearest depth per pixel instead of trusting a
// whole-quad average sort.
uniform vec4 wall_view_segments[64];
// screen-space X center and focal length in pixels for this frame.
uniform vec2 projection_x = vec2(0.0, 1.0);
uniform sampler2D wall_texture : source_color, filter_nearest, repeat_disable;

void fragment() {
	vec2 pixel = FRAGCOORD.xy;
	vec4 output_color = vec4(0.0);
	float nearest_depth = 1000000.0;
	for (int index = 0; index < MAX_WALLS; index++) {
		if (index >= wall_count) {
			break;
		}
		int row = index * 3;
		vec4 r0 = inverse_homography_rows[row];
		vec4 r1 = inverse_homography_rows[row + 1];
		vec4 r2 = inverse_homography_rows[row + 2];
		vec3 homogeneous_uv = vec3(dot(r0.xyz, vec3(pixel, 1.0)), dot(r1.xyz, vec3(pixel, 1.0)), dot(r2.xyz, vec3(pixel, 1.0)));
		if (abs(homogeneous_uv.z) < 0.00001) {
			continue;
		}
		vec2 uv = homogeneous_uv.xy / homogeneous_uv.z;
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			vec4 segment = wall_view_segments[index];
			// A screen X identifies a yaw-only view ray. Intersect that ray with
			// this wall's ground-plane segment to obtain its true local depth.
			float ray_side = (pixel.x - projection_x.x) / max(0.001, projection_x.y);
			float segment_side = segment.z - segment.x;
			float segment_depth = segment.w - segment.y;
			float denominator = ray_side * segment_depth - segment_side;
			if (abs(denominator) < 0.00001) {
				continue;
			}
			float depth = (segment.x * segment_depth - segment.y * segment_side) / denominator;
			if (depth > 0.0 && depth < nearest_depth) {
				vec4 wall_sample = texture(wall_texture, uv);
				output_color = vec4(wall_sample.rgb * r0.w, wall_sample.a);
				nearest_depth = depth;
			}
		}
	}
	COLOR = output_color;
}
