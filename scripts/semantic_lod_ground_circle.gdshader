shader_type canvas_item;
render_mode unshaded;

// Screen-to-ground homography, fitted to four projected square corners.
uniform vec3 uv_u_coefficients;
uniform vec3 uv_v_coefficients;
uniform vec2 uv_denominator_coefficients;
uniform vec2 bounds_min;
uniform vec2 bounds_max;
uniform vec2 logical_canvas_size = vec2(160.0, 120.0);
uniform bool clip_back = false;
uniform bool highlight_front = false;
uniform bool highlight_only = false;
uniform vec2 camera_direction = vec2(1.0, 0.0);
uniform float tangent_ratio = 0.0;
uniform vec4 outline_color : source_color = vec4(0.263, 0.188, 0.129, 1.0);

void fragment() {
	vec2 pixel = UV * logical_canvas_size;
	float denominator = dot(uv_denominator_coefficients, pixel) + 1.0;
	// Avoid a projective singularity and keep the experiment confined to its
	// floor quad, even when a corner approaches the horizon.
	if (any(lessThan(pixel, bounds_min)) || any(greaterThan(pixel, bounds_max)) || abs(denominator) < 0.00001) {
		discard;
	}
	vec2 ground = vec2(dot(uv_u_coefficients.xy, pixel) + uv_u_coefficients.z, dot(uv_v_coefficients.xy, pixel) + uv_v_coefficients.z) / denominator;
	float circle = length(ground - vec2(0.5)) - 0.5;
	float pixel_width = max(fwidth(circle), 0.00001);
	if (abs(circle) > pixel_width * 0.5 || (clip_back && dot(ground - vec2(0.5), camera_direction) < 0.5 * tangent_ratio)) {
		discard;
	}
	if (highlight_front && dot(ground - vec2(0.5), camera_direction) >= 0.5 * tangent_ratio) {
		COLOR = vec4(0.745, 0.635, 0.502, 1.0);
	} else {
		if (highlight_only) {
			discard;
		}
		COLOR = outline_color;
	}
}
