shader_type canvas_item;
render_mode unshaded;

#include "res://scripts/coordinate_frame_daylight.gdshaderinc"
#include "res://scripts/town_storefront_projection.gdshaderinc"

uniform vec4 bounds;
uniform vec2 edge_heights;
uniform vec2 camera_origin;
uniform vec2 camera_forward;
uniform vec2 camera_right;
uniform vec2 projection_center;
uniform vec2 canvas_size;
uniform float focal_length;
uniform float camera_height;
uniform float far_depth;
uniform bool metal;
uniform bool slope_along_x = false;
uniform float floor_inward = 1.0;
uniform vec4 town_variant_plane_bounds[16];
uniform vec4 town_variant_plane_heights[16];
uniform int town_variant_plane_count = 0;
uniform int town_variant_plane_index = -1;
uniform float town_ceiling_height;
uniform vec4 coffee_plane_bounds[3];
uniform vec2 coffee_plane_heights[3];
uniform vec4 deck_rails[4];
uniform int deck_rail_count = 0;
uniform float deck_rail_rise;
uniform sampler2D floor_texture : filter_nearest_mipmap, repeat_enable;
uniform vec2 floor_texture_size = vec2(1.0);
uniform bool use_floor_mips;
uniform bool use_semantic_floor_material;
uniform float facade_y;
uniform vec2 floor_door_opening;
uniform float roof_rib_count = 18.0;
uniform float roof_rib_contrast = 0.25;
uniform float roof_top_light = 1.0;
uniform vec4 roof_rust_color : source_color;
uniform float ledge_shadow;
uniform vec4 surface_color : source_color;

#include "res://scripts/coordinate_frame_semantic_floor.gdshaderinc"

float roof_rust_coverage(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(uv));
	float near_edge = mix(semantic_hash(cell), semantic_hash(cell + vec2(1.0, 0.0)), blend.x);
	float far_edge = mix(semantic_hash(cell + vec2(0.0, 1.0)), semantic_hash(cell + vec2(1.0)), blend.x);
	return smoothstep(0.48, 0.76, mix(near_edge, far_edge, blend.y));
}

void fragment() {
	vec2 pixel = floor(UV * canvas_size) + vec2(0.5);
	vec2 screen = (pixel - projection_center) / focal_length;
	vec2 direction = camera_forward + screen.x * camera_right;
	int axis = slope_along_x ? 0 : 1;
	float slope = (edge_heights.y - edge_heights.x) / (bounds[axis + 2] - bounds[axis]);
	float origin_plane_height = edge_heights.x + slope * (camera_origin[axis] - bounds[axis]);
	float depth = town_plane_depth(camera_origin, direction, camera_height, screen.y, bounds, edge_heights, slope_along_x);
	if (depth <= 0.075 || depth > far_depth) discard;
	if (town_ceiling_precedes(camera_origin, direction, camera_height, screen.y, depth,
			town_roof_bounds, town_ceiling_height)) discard;
	for (int i = 0; i < town_variant_plane_count; i++) {
		if (i == town_variant_plane_index) continue;
		vec4 height = town_variant_plane_heights[i];
		float other = town_plane_depth(camera_origin, direction, camera_height, screen.y,
			town_variant_plane_bounds[i], height.xy, height.z > 0.5);
		if (other > 0.075 && other < depth - 0.001) discard;
	}
	if (town_variant_plane_index >= 0) {
		for (int i = 0; i < 3; i++) {
			float other = town_plane_depth(camera_origin, direction, camera_height, screen.y,
				coffee_plane_bounds[i], coffee_plane_heights[i], false);
			if (other > 0.075 && other < depth - 0.001) discard;
		}
	}
	vec2 world = camera_origin + direction * depth;
	vec2 local = (world - bounds.xy) / (bounds.zw - bounds.xy);
	// Measure the horizontal roof/floor pattern over a logical pixel before
	// snapping its paint. This keeps peaks and crevices from flashing at grazing angles.
	float denominator = screen.y + slope * direction[axis];
	vec2 depth_steps = denominator + vec2(slope * camera_right[axis], 1.0) / focal_length;
	vec2 delta_x = vec2(1.0);
	vec2 delta_y = vec2(1.0);
	if (min(abs(depth_steps.x), abs(depth_steps.y)) > 0.0001) {
		delta_x = (direction + camera_right / focal_length) * (depth * denominator / depth_steps.x) - direction * depth;
		delta_y = direction * (depth * denominator / depth_steps.y - depth);
	}
	float detail = 1.0 - smoothstep(2.0, 6.5, depth);
	float band = 1.0;
	vec3 material_color = surface_color.rgb;
	if (!metal) {
		vec2 span_x = delta_x * floor_texture_size;
		vec2 span_y = delta_y * floor_texture_size;
		if (use_semantic_floor_material) {
			material_color = semantic_floor_material(world * floor_texture_size, span_x, span_y, vec2(1.0));
		} else {
			float mip = 0.0;
			if (use_floor_mips) {
				float footprint = min(length(span_x), length(span_y));
				mip = clamp(floor(log2(max(1.0, floor(footprint + 0.5)))), 0.0, 7.0);
			}
			material_color = textureLod(floor_texture, world, mip).rgb;
		}
		material_color = town_weathered_wood(material_color);
		float from_jamb = min(world.x - floor_door_opening.x, floor_door_opening.y - world.x);
		float contact = (1.0 - smoothstep(0.0, 0.15, abs(world.y - facade_y))) * (1.0 - smoothstep(0.0, 0.055, from_jamb));
		band *= 1.0 - 0.55 * ledge_shadow * contact;
		float inward = (world.y - facade_y) * floor_inward;
		bool inside = inward >= 0.0;
		if (!inside && deck_rail_count > 0 && depth < 3.8) {
			// The upper guard projects westward toward the sun from the
			// receiver. Shade the boards once even at intersecting rails.
			vec2 at_rail = world + TOWN_SUN_DIRECTION * deck_rail_rise * 0.82;
			float cast_shadow = 0.0;
			for (int i = 0; i < deck_rail_count; i++) {
				vec4 rail = deck_rails[i];
				if (all(greaterThanEqual(at_rail, rail.xy)) && all(lessThanEqual(at_rail, rail.zw))) cast_shadow = 1.0;
			}
			band *= 1.0 - ledge_shadow * cast_shadow * (1.0 - smoothstep(1.9, 3.8, depth));
		}
		if (inside) {
			float spill = 1.0 - smoothstep(0.0, 0.38, inward);
			band *= mix(0.79, 0.88, spill);
		}
	} else {
		int cross_axis = 1 - axis;
		float rib = local[cross_axis] * roof_rib_count;
		float phase = fract(rib);
		float footprint = max(abs(delta_x[cross_axis]), abs(delta_y[cross_axis])) * roof_rib_count / (bounds[cross_axis + 2] - bounds[cross_axis]);
		float rib_detail = detail * (1.0 - smoothstep(0.36, 0.60, footprint));
		float rise = 1.0 - abs(2.0 * phase - 1.0);
		// From the porch, lower world X is the right-hand slope.
		// Bias the middle of each linear ramp while sharing the crest and crevice tones.
		float face_bias = phase < 0.5 ? 0.32 : -0.32;
		float mid_slope = 1.0 - abs(2.0 * rise - 1.0);
		float rib_tone = mix(-0.68, 0.70, rise) + face_bias * mid_slope;

		// Draw a hard one-logical-pixel stroke at each crest and crevice.
		// Fade the strokes before the broader rib shading loses contrast.
		float accent_detail = (1.0 - smoothstep(2.0, 4.0, depth))
			* (1.0 - smoothstep(0.18, 0.32, footprint));
		float half_pixel = 0.5 * footprint;
		float crest = 1.0 - step(footprint, fract(phase - 0.5 + half_pixel));
		float crevice = 1.0 - step(footprint, fract(phase + half_pixel));
		float accents = accent_detail * (0.55 * crest - 0.52 * crevice);
		// At a distance, let a wider light/dark pair stand in for two ribs.
		// Every other crest stays in place as the fine corrugation fades.
		float distant_phase = fract(rib * 0.5 + 0.25);
		float distant_rise = 1.0 - abs(2.0 * distant_phase - 1.0);
		float distant_tone = mix(-0.74, 0.74, smoothstep(0.26, 0.74, distant_rise));
		float distant_contrast = 0.86 * (1.0 - smoothstep(3.3, 9.0, depth))
			* (1.0 - smoothstep(0.42, 0.88, footprint * 0.5));
		float corrugation = mix(distant_tone * distant_contrast, rib_tone + accents, rib_detail);
		band = 0.94 + roof_rib_contrast * corrugation;

		// Oxide follows the length of the sheet. As the streaks become too
		// small to resolve, keep a slight warm cast in the galvanized base.
		vec2 rust_scale = slope_along_x ? vec2(7.0, 22.5 / (bounds.w - bounds.y)) : vec2(22.5 / (bounds.z - bounds.x), 7.0);
		vec2 rust_span = max(abs(delta_x), abs(delta_y)) * rust_scale;
		float rust_detail = detail * (1.0 - smoothstep(0.55, 1.20, max(rust_span.x, rust_span.y)));
		float rust = mix(0.24, roof_rust_coverage((world - vec2(bounds.x, 0.0)) * rust_scale), rust_detail);
		material_color = mix(material_color, roof_rust_color.rgb, rust);
	}
	float side_light = metal ? (camera_height < origin_plane_height ? 0.65 : roof_top_light) : 1.0;
	vec3 paint = material_color * band * side_light;
	float outdoor_depth = town_outdoor_depth(camera_origin, world, depth);
	COLOR = vec4(daylight_color(paint, outdoor_depth), 1.0);
}
