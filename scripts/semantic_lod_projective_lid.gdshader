shader_type canvas_item;

// The top of a semantic box is a true projected plane, not two independently
// affine triangles. These coefficients map a logical screen pixel back into
// the crate texture's UV space through one projective transform.
uniform sampler2D lid_texture : filter_nearest;
uniform vec3 uv_u_coefficients;
uniform vec3 uv_v_coefficients;
uniform vec2 uv_denominator_coefficients;
uniform vec2 uv_min;
uniform vec2 uv_max;
uniform vec2 logical_canvas_size = vec2(160.0, 120.0);

void fragment() {
	// UV belongs to this 160x120 draw_rect inside the SubViewport. FRAGCOORD
	// is global to the composed canvas and caused the far-distance leakage.
	vec2 logical_pixel = UV * logical_canvas_size;
	float denominator = dot(uv_denominator_coefficients, logical_pixel) + 1.0;
	if (abs(denominator) < 0.00001) {
		discard;
	}
	vec2 source_uv = vec2(
		dot(uv_u_coefficients.xy, logical_pixel) + uv_u_coefficients.z,
		dot(uv_v_coefficients.xy, logical_pixel) + uv_v_coefficients.z
	) / denominator;
	if (source_uv.x < uv_min.x || source_uv.x > uv_max.x || source_uv.y < uv_min.y || source_uv.y > uv_max.y) {
		discard;
	}
	COLOR = texture(lid_texture, source_uv);
}
