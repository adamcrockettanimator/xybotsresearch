shader_type canvas_item;
render_mode unshaded;

// A single full-frame canvas item evaluates every visible grid-edge quad.
// Each wall supplies an inverse homography, so the same master texture is
// sampled projectively instead of being pre-rendered for every slot/angle.
// Three vec4 rows per wall; keep this below portable CanvasItem uniform limits.
// The coordinate-frame view only admits 32 useful visible edges.
const int MAX_WALLS = 28;

uniform int wall_count = 0;
uniform vec4 inverse_rows[84];
uniform vec2 wall_depths[28];
uniform float wall_light[28];
uniform vec2 wall_texture_size = vec2(128.0, 88.0);

void fragment() {
	vec2 pixel = UV * vec2(160.0, 120.0);
	vec4 result = vec4(0.0);
	float closest_depth = 100000.0;
	for (int wall = 0; wall < MAX_WALLS; wall++) {
		if (wall >= wall_count) {
			break;
		}
		int row = wall * 3;
		vec3 homogeneous = vec3(
			dot(inverse_rows[row].xyz, vec3(pixel, 1.0)),
			dot(inverse_rows[row + 1].xyz, vec3(pixel, 1.0)),
			dot(inverse_rows[row + 2].xyz, vec3(pixel, 1.0))
		);
		if (abs(homogeneous.z) < 0.00001) {
			continue;
		}
		vec2 source_uv = homogeneous.xy / homogeneous.z;
		if (source_uv.x < 0.0 || source_uv.x > 1.0 || source_uv.y < 0.0 || source_uv.y > 1.0) {
			continue;
		}
		float depth = mix(wall_depths[wall].x, wall_depths[wall].y, source_uv.x);
		if (depth < closest_depth) {
			closest_depth = depth;
			// Deliberately coarse, nearest source sampling retains an arcade-like
			// pixel texture while the quad itself can remain continuously projected.
			vec2 snapped_texel = floor(source_uv * wall_texture_size) + vec2(0.5);
			snapped_texel = clamp(snapped_texel, vec2(0.5), wall_texture_size - vec2(0.5));
			// Sample the Polygon2D's own assigned texture rather than a secondary
			// material sampler.  This keeps the coordinate compositor on Godot's
			// guaranteed CanvasItem texture path.
			result = texture(TEXTURE, snapped_texel / wall_texture_size);
			result.rgb *= wall_light[wall];
		}
	}
	COLOR = result;
}
