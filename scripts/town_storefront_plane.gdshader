shader_type canvas_item;
render_mode unshaded;

#include "res://scripts/coordinate_frame_daylight.gdshaderinc"
#include "res://scripts/town_storefront_projection.gdshaderinc"
#include "res://scripts/coordinate_frame_plane_depth_light.gdshaderinc"

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
uniform bool show_town_ground_grid = false;
uniform bool slope_along_x = false;
uniform float floor_inward = 1.0;
uniform vec4 town_variant_plane_bounds[24];
uniform vec4 town_variant_plane_heights[24];
uniform int town_variant_plane_count = 0;
uniform bool use_coffee_plane_occlusion = false;
uniform int town_variant_plane_index = -1;
uniform float town_ceiling_height;
uniform vec4 coffee_plane_bounds[3];
uniform vec2 coffee_plane_heights[3];
uniform vec4 deck_rails[4];
uniform int deck_rail_count = 0;
uniform float deck_rail_rise;
uniform bool deck_rail_shadow_plumb = false;
uniform vec4 deck_feet[8];
uniform int deck_foot_count = 0;
uniform float porch_deck_depth;
uniform float porch_deck_shadow;
uniform sampler2D floor_texture : filter_nearest_mipmap, repeat_enable;
uniform vec2 floor_texture_size = vec2(1.0);
uniform bool use_floor_mips;
uniform bool use_semantic_floor_material;
uniform float facade_y;
uniform vec2 floor_door_opening;
uniform float floor_door_open_fraction = 0.0;
uniform float roof_rib_count = 18.0;
uniform float roof_rib_contrast = 0.25;
uniform float roof_top_light = 1.0;
uniform bool ink_gable_awning = false;
uniform bool gable_porch_behind_wall = false;
uniform vec4 gable_porch_wall;
uniform vec4 gable_roof_ink : source_color;
uniform vec4 gable_room_bounds;
uniform bool gable_room_view = false;
uniform vec2 gable_ceiling_heights;
uniform vec3 gable_rafter_positions;
uniform vec2 gable_rafter_section;
uniform vec4 gable_ceiling_wood : source_color;
uniform vec4 gable_ceiling_timber : source_color;
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

bool roof_edge_cell(vec2 pixel, vec3 first, vec3 last) {
	return town_projected_edge_cell(pixel, first, last, vec3(camera_origin, camera_height),
		camera_forward, camera_right, projection_center, focal_length);
}

void gable_ceiling_timber_hit(vec3 eye, vec3 ray, vec3 lower, vec3 upper, float side_light,
		inout float depth, inout vec3 paint) {
	vec2 hit = town_wood_box_surface(eye, ray, lower, upper);
	if (hit.x > 0.005 && hit.x < depth) {
		depth = hit.x;
		float underside = abs(hit.y) == 3.0 ? 0.77 : 1.10;
		paint = gable_ceiling_timber.rgb * underside * side_light;
	}
}

vec4 gable_ceiling_paint(vec2 pixel, float screen_y, vec2 direction) {
	vec3 eye = vec3(camera_origin, camera_height);
	vec3 ray = vec3(direction, -screen_y);
	float ridge_x = (gable_room_bounds.x + gable_room_bounds.z) * 0.5;
	float half_width = gable_rafter_section.x * 0.5;
	float drop = gable_rafter_section.y;
	float peak = gable_ceiling_heights.y;
	float depth = 1e10;
	vec3 paint = gable_ceiling_wood.rgb;
	for (int side = 0; side < 2; side++) {
		bool east = side == 1;
		vec4 half_room = gable_room_bounds;
		if (east) half_room.x = ridge_x;
		else half_room.z = ridge_x;
		vec2 heights = east ? gable_ceiling_heights.yx : gable_ceiling_heights;
		float lining = town_plane_depth(camera_origin, direction, camera_height, screen_y, half_room, heights, true);
		if (lining > 0.005 && lining < depth) {
			depth = lining;
			paint = gable_ceiling_wood.rgb * (east ? 0.87 : 1.0);
		}
		float slope = (heights.y - heights.x) / (half_room.z - half_room.x);
		vec3 flat_eye = vec3(eye.xy, eye.z - heights.x - slope * (eye.x - half_room.x));
		vec3 flat_ray = vec3(ray.xy, ray.z - slope * ray.x);
		float side_light = east ? 0.90 : 1.0;
		for (int index = 0; index < 5; index++) {
			// The end rafters close the junction with the two gable walls.
			float y = index == 0 ? half_room.y + half_width : half_room.w - half_width;
			if (index > 0 && index < 4) y = mix(half_room.y, half_room.w, gable_rafter_positions[index - 1]);
			gable_ceiling_timber_hit(flat_eye, flat_ray, vec3(half_room.x, y - half_width, -drop),
				vec3(half_room.z, y + half_width, 0.0), side_light, depth, paint);
		}
		// A continuous eave plate joins each set of rafter feet to the wall.
		float eave_x = east ? half_room.z : half_room.x;
		float inner_x = eave_x + (east ? -1.0 : 1.0) * gable_rafter_section.x;
		gable_ceiling_timber_hit(flat_eye, flat_ray, vec3(min(eave_x, inner_x), half_room.y, -drop),
			vec3(max(eave_x, inner_x), half_room.w, 0.0), side_light * 0.90, depth, paint);
	}
	vec2 ridge = town_wood_box_surface(eye, ray, vec3(ridge_x - half_width, gable_room_bounds.y, peak - drop),
		vec3(ridge_x + half_width, gable_room_bounds.w, peak));
	if (ridge.x > 0.005 && ridge.x < depth) {
		depth = ridge.x;
		paint = gable_ceiling_timber.rgb * (abs(ridge.y) == 3.0 ? 0.61 : 0.84);
	}
	if (depth > far_depth) return vec4(0.0);
	float light = depth_light_dither(depth, pixel, peak - camera_height, focal_length);
	return vec4(use_town_room_shading ? town_room_color(paint, light) : paint * mix(0.72, 1.0, light), 1.0);
}

vec4 storefront_plane_paint(vec2 pixel, vec2 screen, vec2 direction) {
	int axis = slope_along_x ? 0 : 1;
	float slope = (edge_heights.y - edge_heights.x) / (bounds[axis + 2] - bounds[axis]);
	float origin_plane_height = edge_heights.x + slope * (camera_origin[axis] - bounds[axis]);
	float depth = town_plane_depth(camera_origin, direction, camera_height, screen.y, bounds, edge_heights, slope_along_x);
	if (depth <= 0.075 || depth > far_depth) discard;
	if (gable_porch_behind_wall && town_gable_front_wall_precedes(
			vec3(camera_origin, camera_height), vec3(direction, -screen.y), depth, gable_porch_wall)) discard;
	if (!metal && town_support_precedes(vec3(camera_origin, camera_height), vec3(direction, -screen.y), depth)) discard;
	if (town_ceiling_precedes(camera_origin, direction, camera_height, screen.y, depth,
			town_roof_bounds, town_ceiling_height, town_ceiling_mask)) discard;
	for (int i = 0; i < town_variant_plane_count; i++) {
		if (i == town_variant_plane_index) continue;
		vec4 height = town_variant_plane_heights[i];
		float other = town_plane_depth(camera_origin, direction, camera_height, screen.y,
			town_variant_plane_bounds[i], height.xy, height.z > 0.5);
		if (other > 0.075 && other < depth - 0.001) discard;
	}
	if (town_variant_plane_index >= 0 || use_coffee_plane_occlusion) {
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
	float outdoor_depth = town_outdoor_depth(camera_origin, world, depth);
	float band = 1.0;
	float room_light = 1.0;
	float foot_shadow = 0.0;
	bool room_surface = false;
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
		if (!inside && deck_foot_count > 0) {
			// Measure the outside of each foot in logical pixels on the deck.
			vec2 pixel_span = max(max(abs(delta_x), abs(delta_y)), vec2(0.0001));
			for (int i = 0; i < deck_foot_count; i++) {
				vec4 foot = deck_feet[i];
				vec2 outside = max(foot.xy - world, world - foot.zw) / pixel_span;
				float distance_to_foot = max(outside.x, outside.y);
				if (distance_to_foot > 0.0) {
					float width_px = 0.032 * focal_length / depth;
					foot_shadow = max(foot_shadow, town_contact_coverage(distance_to_foot, width_px));
				}
			}
			band *= 1.0 - foot_shadow * 0.23;
		}
		if (!inside && deck_rail_count > 0) {
			// Broad wall-to-street illumination is structural, not fine LOD.
			float toward_wall = 1.0 - clamp(-inward / max(porch_deck_depth, 0.001), 0.0, 1.0);
			float broad_shadow = porch_deck_shadow * mix(1.0, 0.55, smoothstep(1.8, 5.0, depth));
			band *= 1.0 - broad_shadow * toward_wall * toward_wall;
		}
		if (!inside && deck_rail_count > 0 && depth < 3.8) {
			// The gable rail shades the boards directly below it.
			vec2 at_rail = deck_rail_shadow_plumb ? world : world + TOWN_SUN_DIRECTION * deck_rail_rise * 0.82;
			float cast_shadow = 0.0;
			for (int i = 0; i < deck_rail_count; i++) {
				vec4 rail = deck_rails[i];
				if (all(greaterThanEqual(at_rail, rail.xy)) && all(lessThanEqual(at_rail, rail.zw))) cast_shadow = 1.0;
			}
			band *= 1.0 - ledge_shadow * cast_shadow * (1.0 - smoothstep(1.9, 3.8, depth));
		}
		if (inside) {
			float spill = 1.0 - smoothstep(0.0, 0.38, inward);
			if (use_town_room_shading) {
				float doorway_width = 1.0 - smoothstep(0.0, 0.34, max(-from_jamb, 0.0));
				float doorway_depth = 1.0 - smoothstep(0.10, 1.55, inward);
				band *= 1.0 + 0.24 * doorway_width * doorway_depth * floor_door_open_fraction;
			} else {
				band *= mix(0.79, 0.88, spill);
			}
			float indoor_depth = max(depth - outdoor_depth, 0.0);
			room_light = depth_light_dither(indoor_depth, pixel, camera_height - edge_heights.x, focal_length);
			room_surface = use_town_room_shading;
			if (!room_surface) band *= room_light;
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
	if (use_town_room_shading && metal && camera_height < origin_plane_height && town_point_is_inside(world)) {
		room_surface = true;
		room_light = depth_light_dither(max(depth - outdoor_depth, 0.0), pixel, camera_height - origin_plane_height, focal_length);
	}
	if (room_surface) paint = town_room_color(paint, room_light);
	bool ink_edge = false;
	if (ink_gable_awning) {
		float outer_y = slope > 0.0 ? bounds.y : bounds.w;
		float outer_z = min(edge_heights.x, edge_heights.y);
		float side = local.x < 0.5 ? bounds.x : bounds.z;
		ink_edge = roof_edge_cell(pixel, vec3(bounds.x, outer_y, outer_z), vec3(bounds.z, outer_y, outer_z))
			|| roof_edge_cell(pixel, vec3(side, bounds.y, edge_heights.x), vec3(side, bounds.w, edge_heights.y));
	}
	if (ink_edge) {
		float ink = 1.0 - smoothstep(1.0, 2.3, 0.05 * focal_length / depth);
		paint = mix(paint, gable_roof_ink.rgb, ink);
		outdoor_depth = mix(outdoor_depth, town_outline_haze_depth(outdoor_depth), ink);
	}
	vec3 final_color = daylight_color(paint, outdoor_depth);
	// Use the same world-cell boundaries on raised wooden floors and porches.
	if (show_town_ground_grid && !metal &&
		(any(notEqual(floor(world), floor(world + delta_x))) ||
		 any(notEqual(floor(world), floor(world + delta_y))))) {
		final_color = mix(final_color, vec3(0.0), 0.10);
	}
	return vec4(final_color, 1.0);
}

void fragment() {
	vec2 pixel = floor(UV * canvas_size) + vec2(0.5);
	vec2 screen = (pixel - projection_center) / focal_length;
	vec2 direction = camera_forward + screen.x * camera_right;
	bool camera_inside = all(greaterThanEqual(camera_origin, gable_room_bounds.xy))
		&& all(lessThan(camera_origin, gable_room_bounds.zw));
	bool east_slope = edge_heights.x > edge_heights.y;
	if (camera_inside && east_slope) discard;
	vec4 lining = gable_room_view ? gable_ceiling_paint(pixel, screen.y, direction) : vec4(0.0);
	if (lining.a > 0.0) {
		// The west roof carrier paints both slopes and their shared ridge.
		if (east_slope) discard;
		COLOR = lining;
	} else {
		if (camera_inside) discard;
		COLOR = storefront_plane_paint(pixel, screen, direction);
	}
}
