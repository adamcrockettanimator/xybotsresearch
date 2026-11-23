uniform int town_variant_role = 0;
uniform vec4 town_variant_bounds;
uniform vec4 town_variant_form; // Eave, rise, flat-front height, direction to street.
uniform vec4 town_variant_porch; // Front wall Y, depth, entrance X, awning at wall.
uniform vec3 town_variant_options; // Second story, balcony, framed sign.
uniform vec4 town_variant_timber : source_color;
uniform vec4 town_variant_board : source_color;
uniform vec4 town_variant_ink : source_color;
uniform vec4 town_variant_sign_rect;
uniform int town_variant_glyphs[16];
uniform int town_variant_glyph_count;
uniform bool town_variant_outside;
uniform vec2 town_variant_opening;
uniform bool town_variant_shed_roof = false;
uniform bool town_variant_generated = false;
uniform bool town_gable_blueprint = false;
uniform vec4 town_gable_outline : source_color;
uniform vec4 town_gable_roof_metal : source_color;
uniform bool town_gable_room_view = false;
uniform vec2 town_gable_joinery; // Sill height and face width of the casing.
uniform vec3 town_gable_siding_profile; // First board, pitch, and lap underside.
uniform float town_gable_lining_drop;
uniform float town_variant_door_center;
uniform vec4 town_variant_windows[2];
uniform int town_variant_window_count;
uniform int town_variant_broken_windows;
uniform float town_variant_window_trim;
uniform bool town_variant_front_view;
uniform float town_porch_awning_shadow;
uniform vec2 town_variant_support; // Corner post width and underside of floor apron.

bool town_glyph_cell(int bits, ivec2 cell) {
	if (cell.x < 0 || cell.x >= 5 || cell.y < 0 || cell.y >= 5) return false;
	return ((bits >> (24 - (cell.y * 5 + cell.x))) & 1) != 0;
}

bool town_building_ink(vec2 facade, vec2 footprint) {
	if (town_variant_glyph_count <= 0) return false;
	vec2 sign_size = town_variant_sign_rect.zw - town_variant_sign_rect.xy;
	vec2 uv = (facade - town_variant_sign_rect.xy) / sign_size;
	if (uv.x < 0.0 || uv.x >= 1.0) return false;
	float word = uv.x * float(town_variant_glyph_count);
	int bits = town_variant_glyphs[int(word)];
	float size_pixels = sign_size.y / footprint.y;
	float row = (1.0 - uv.y) * 5.2 - 0.1;
	if (size_pixels < 7.0) {
		// Pin five complete glyph rows to the shared pixel grid. This keeps the
		// bars in E, H, and T when the wall projects fewer than five texel rows.
		float horizon = horizon_y + projection_offset.y;
		float center_px = horizon + (camera_height - (town_variant_sign_rect.y + sign_size.y * 0.5)) / footprint.y;
		float top_px = floor(center_px) - 2.0;
		float screen_px = floor(horizon + (camera_height - facade.y) / footprint.y);
		row = screen_px - top_px + 0.5;
	}
	vec2 grid = vec2(fract(word) * 6.2 - 0.60, row);
	ivec2 cell = ivec2(floor(grid));
	if (!town_glyph_cell(bits, cell)) return false;
	vec2 offset = fract(grid) - 0.5;
	vec2 projected = footprint / sign_size * vec2(float(town_variant_glyph_count) * 6.2, 5.2);
	vec2 half_stroke = clamp(projected * 0.61, vec2(0.34), vec2(0.50));
	if (size_pixels < 7.0) half_stroke.x = max(half_stroke.x, 0.45);
	bool horizontal = abs(offset.x) <= half_stroke.x ||
		town_glyph_cell(bits, cell + ivec2(offset.x < 0.0 ? -1 : 1, 0));
	bool vertical = abs(offset.y) <= half_stroke.y ||
		town_glyph_cell(bits, cell + ivec2(0, offset.y < 0.0 ? -1 : 1));
	return horizontal && vertical;
}

// Rasterize each letter as a whole onto the logical screen grid. Adjacent
// projected stroke intervals must not disappear just because their world-space
// centers happen to fall between two pixel centers.
vec2 town_sign_project(vec2 world, float height) {
	vec2 relative = world - town_camera_origin;
	float depth = dot(relative, town_camera_forward);
	return vec2(canvas_size.x * 0.5 + projection_offset.x + dot(relative, town_camera_right) * focal_length / max(depth, 0.001),
		horizon_y + projection_offset.y + (camera_height - height) * focal_length / max(depth, 0.001));
}

float town_sign_world_x(float across) {
	return town_variant_form.w > 0.0 ? town_variant_bounds.x + across : town_variant_bounds.z - across;
}

float town_sign_glyph_coverage(int bits, float col, float count, float row, float rows,
		bool compact, vec2 raised, vec2 footprint) {
	float ink_columns = count >= 4.0 ? count - 1.0 : count;
	if (compact && count >= 4.0) {
		col -= floor((count - 3.0) * 0.5);
		ink_columns = 3.0;
	}
	if (col < 0.0 || col >= ink_columns) return 0.0;
	if (compact && rows >= 5.0) {
		row -= floor((rows - 5.0) * 0.5);
		rows = 5.0;
	}
	if (row < 0.0 || row >= rows) return 0.0;
	if (ink_columns < 3.0 || rows < 5.0) {
		vec2 d = footprint * 0.25;
		float coverage = float(town_building_ink(raised + vec2(-d.x, -d.y), footprint));
		coverage += float(town_building_ink(raised + vec2(d.x, -d.y), footprint));
		coverage += float(town_building_ink(raised + vec2(-d.x, d.y), footprint));
		coverage += float(town_building_ink(raised + vec2(d.x, d.y), footprint));
		return coverage * 0.25;
	}
	int columns = compact ? 3 : 5;
	int column = int(floor(col * float(columns) / ink_columns));
	int glyph_x = compact ? column * 2 : column;
	int glyph_y = int(floor(row * 5.0 / rows));
	return float(town_glyph_cell(bits, ivec2(glyph_x, glyph_y)));
}

float town_sign_raster_ink(vec2 pixel, vec2 raised, vec2 footprint) {
	vec2 sign_size = town_variant_sign_rect.zw - town_variant_sign_rect.xy;
	float letter_width = sign_size.x / float(town_variant_glyph_count);
	float plane_y = town_variant_porch.x + town_variant_form.w * 0.025;
	float start_x = town_sign_project(vec2(town_sign_world_x(town_variant_sign_rect.x), plane_y), 0.0).x;
	float end_x = town_sign_project(vec2(town_sign_world_x(town_variant_sign_rect.z), plane_y), 0.0).x;
	float next_x = town_sign_project(vec2(town_sign_world_x(town_variant_sign_rect.x + letter_width), plane_y), 0.0).x;
	float previous_x = town_sign_project(vec2(town_sign_world_x(town_variant_sign_rect.z - letter_width), plane_y), 0.0).x;
	float narrowest = min(abs(next_x - start_x), abs(end_x - previous_x));
	float room = abs(end_x - start_x);
	// Redistribute available width when perspective makes the far word too
	// narrow, keeping the sign's projected endpoints fixed.
	float rebalance = (1.0 - smoothstep(4.0, 5.5, narrowest)) * smoothstep(float(town_variant_glyph_count) * 3.75, float(town_variant_glyph_count) * 4.25, room);
	for (int index = 0; index < 16; index++) {
		if (index >= town_variant_glyph_count) break;
		int bits = town_variant_glyphs[index];
		if (bits == 0) continue;
		float left = town_variant_sign_rect.x + float(index) * letter_width;
		float right = left + letter_width;
		vec2 first = vec2(town_sign_world_x(left), plane_y);
		vec2 last = vec2(town_sign_world_x(right), plane_y);
		float sx0 = mix(town_sign_project(first, 0.0).x, mix(start_x, end_x, float(index) / float(town_variant_glyph_count)), rebalance);
		float sx1 = mix(town_sign_project(last, 0.0).x, mix(start_x, end_x, float(index + 1) / float(town_variant_glyph_count)), rebalance);
		float lo = floor(min(sx0, sx1) + 0.5);
		float hi = floor(max(sx0, sx1) + 0.5);
		float count = hi - lo;
		float screen_col = floor(pixel.x) - lo;
		if (screen_col < 0.0 || screen_col >= count) continue;
		// Reserve one column for letter spacing when at least three ink
		// columns remain. Reverse columns for a reversed projection.
		if (sx0 > sx1) screen_col = count - 1.0 - screen_col;
		vec2 at_x = vec2(town_sign_world_x(raised.x), plane_y);
		float top = floor(town_sign_project(at_x, town_variant_sign_rect.w).y + 0.5);
		float bottom = floor(town_sign_project(at_x, town_variant_sign_rect.y).y + 0.5);
		float rows = bottom - top;
		float screen_row = floor(pixel.y) - top;
		// Blend coverage based on the continuous projection, not rounded
		// cell counts, so a threshold cannot alternate on successive frames.
		float expanded = smoothstep(5.0, 8.0, abs(sx1 - sx0));
		float small = town_sign_glyph_coverage(bits, screen_col, count, screen_row, rows, true, raised, footprint);
		if (expanded <= 0.0) return small;
		float large = town_sign_glyph_coverage(bits, screen_col, count, screen_row, rows, false, raised, footprint);
		return mix(small, large, expanded);
	}
	return 0.0;
}

vec4 town_window_paint(vec2 local, vec2 half_size, float depth, float facing, bool glazed, bool broken,
		bvec2 snapped_cross) {
	vec2 edge = half_size - abs(local);
	float pixel_height = depth / focal_length;
	float trim = town_variant_window_trim;
	vec3 wood = town_weathered_wood(town_variant_timber.rgb);
	if (min(edge.x, edge.y) < trim) {
		float bevel = clamp(pixel_height * 1.05, 0.009, 0.018);
		bool lit = edge.y < bevel && local.y > 0.0 || edge.x < bevel && local.x < 0.0;
		bool recess = min(edge.x, edge.y) > trim - 0.011;
		return vec4(wood * (lit ? 1.31 : (recess ? 0.65 : 1.0)), 1.0);
	}

	vec2 aperture = half_size - vec2(trim);
	vec2 pane_uv = local / (2.0 * aperture) + 0.5;
	float projected_width = aperture.x * facing / pixel_height;
	if (broken) return storefront_broken_glass(pane_uv, min(2.0 * projected_width, 2.0 * aperture.y / pixel_height));

	// Evaluate the cross as a union. At the intersection only the edges
	// against glass carry a bevel, so neither bar reads as a separate overlay.
	vec2 bars = vec2(0.012, 0.013);
	if (!town_gable_blueprint) bars = max(bars, vec2(pixel_height * 0.55));
	vec2 from_bar = abs(local) - bars;
	if (any(snapped_cross) || min(from_bar.x, from_bar.y) < 0.0) {
		float bevel = min(0.009, pixel_height);
		bool side = !snapped_cross.x && !snapped_cross.y && from_bar.y >= 0.0 && from_bar.x > -bevel;
		bool horizontal = !snapped_cross.x && !snapped_cross.y && from_bar.x >= 0.0 && from_bar.y > -bevel;
		float tone = side ? (local.x < 0.0 ? 1.28 : 0.78) : (horizontal ? (local.y > 0.0 ? 1.28 : 0.76) : 1.0);
		return vec4(wood * tone, 1.0);
	}
	if (glazed) return storefront_glass_color(pane_uv, facing, projected_width);
	vec3 glass = mix(vec3(0.29, 0.34, 0.36), vec3(0.67, 0.71, 0.65), smoothstep(-half_size.y, half_size.y, local.y));
	float reflection = abs(local.x - local.y * 0.43);
	glass += (1.0 - smoothstep(0.018, 0.05, reflection)) * vec3(0.16, 0.17, 0.14);
	if (min(edge.x, edge.y) < trim + 0.016) glass *= 0.79;
	return vec4(glass, 1.0);
}

vec4 town_porch_paint(vec2 world, float height, vec2 uv) {
	vec3 timber = town_weathered_wood(town_variant_timber.rgb);
	if (town_variant_role == 7) return vec4(timber * 0.91, 1.0);
	if (town_variant_role == 10) {
		// Hinged edge is u=0; both leaves rise and dip toward their meeting edge.
		float curve = smoothstep(0.25, 0.95, uv.x);
		float top = 0.18 * (1.0 - curve);
		float bottom = 0.82 + 0.18 * curve;
		if (uv.y < top || uv.y > bottom) return vec4(0.0);
		vec3 wood = timber * 0.90;
		bool inset = uv.x > 0.12 && uv.x < 0.88 && uv.y > 0.25 && uv.y < 0.75;
		if (inset) {
			float slat = fract((uv.y - 0.25) * 20.0);
			wood *= mix(0.59, 1.04, smoothstep(0.07, 0.58, slat));
		} else if (uv.x < 0.05 || uv.x > 0.94 || abs(uv.y - top) < 0.035 || abs(uv.y - bottom) < 0.035) {
			wood *= 0.70;
		}
		return vec4(wood, 1.0);
	}
	if (town_variant_role == 6) {
		vec2 panel = vec2(min(uv.x, 1.0 - uv.x), min(fract(uv.y * 2.0), 1.0 - fract(uv.y * 2.0)));
		vec3 wood = timber * 0.82;
		if (panel.x > 0.15 && panel.y > 0.17) wood *= panel.y < 0.24 || panel.x < 0.21 ? 0.58 : 0.83;
		if (uv.x > 0.977) wood *= 0.57;
		if (distance(uv, vec2(0.86, 0.53)) < 0.068) wood = vec3(0.56, 0.39, 0.19);
		return vec4(wood, 1.0);
	}
	// The gable porch skirt already has depth-correct timber carriers.
	bool apron = !town_gable_blueprint && height < 0.050 && height > 0.006;
	float balcony = height - 0.695;
	bool balcony_fascia = town_variant_options.y > 0.5 && balcony < 0.0 && balcony > -0.063;
	if (!apron && !balcony_fascia) return vec4(0.0);
	float along = town_variant_role == 4 ? world.x : world.y;
	return vec4(timber * (apron ? 0.91 : (fract(along * 8.0) > 0.92 ? 0.75 : 0.91)), 1.0);
}

float town_gable_edge_distance(vec2 pixel, vec3 first, vec3 last) {
	vec2 center = vec2(canvas_size.x * 0.5, horizon_y) + projection_offset;
	return town_projected_edge_distance(pixel, first, last, vec3(town_camera_origin, camera_height),
		town_camera_forward, town_camera_right, center, focal_length);
}

float town_gable_roof_edge(vec2 world, vec2 pixel, bool end_wall, bool rear, float top) {
	vec2 first = end_wall ? vec2(town_variant_bounds.x, world.y) : vec2(world.x, town_variant_bounds.y);
	vec2 last = end_wall ? vec2(town_variant_bounds.z, world.y) : vec2(world.x, town_variant_bounds.w);
	vec2 midpoint = (first + last) * 0.5;
	vec2 corner = dot(world - midpoint, last - first) < 0.0 ? first : last;
	if (!rear) return town_gable_edge_distance(pixel, vec3(first, top), vec3(last, top));
	float eave = town_variant_form.x;
	float ridge = eave + town_variant_form.y;
	return town_gable_edge_distance(pixel, vec3(corner, eave), vec3(midpoint, ridge));
}

float town_gable_frame_contact(vec2 world, vec2 pixel, float height, bool end_wall, vec4 rect) {
	vec2 axis = end_wall ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	float along = dot(world, axis);
	bool across = along >= rect.x && along <= rect.z;
	bool within_height = height >= rect.y && height <= rect.w;
	if (across == within_height) return 1e10;
	if (across) {
		float edge_height = height < rect.y ? rect.y : rect.w;
		return town_gable_edge_distance(pixel, vec3(world + axis * (rect.x - along), edge_height),
			vec3(world + axis * (rect.z - along), edge_height));
	}
	float side = along < rect.x ? rect.x : rect.z;
	vec2 edge = world + axis * (side - along);
	return town_gable_edge_distance(pixel, vec3(edge, rect.y), vec3(edge, rect.w));
}

float town_gable_door_contact(vec2 world, vec2 pixel, float height, bool end_wall, vec4 rect, float pixel_height) {
	vec2 axis = end_wall ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	float along = dot(world, axis);
	vec2 nearest = clamp(vec2(along, height), rect.xy, rect.zw);
	bool outside_side = along != nearest.x;
	bool outside_cap = height != nearest.y;
	float cap_reach = height < rect.y ? 0.065 : 0.020;
	float reach = outside_cap ? cap_reach : 0.042;
	float distance_px = town_gable_frame_contact(world, pixel, height, end_wall, rect);
	if (outside_side && outside_cap) {
		// A rounded falloff joins the jamb to the head and threshold.
		vec2 corner_world = world + axis * (nearest.x - along);
		if (dot(corner_world - town_camera_origin, town_camera_forward) <= 0.005) return 0.0;
		vec2 offset_px = abs(pixel - town_sign_project(corner_world, nearest.y));
		distance_px = length(offset_px);
		reach = mix(0.042, cap_reach, offset_px.y / max(offset_px.x + offset_px.y, 0.0001));
	}
	float shade = mix(1.0, 0.70, smoothstep(rect.y, rect.w, height));
	return shade * town_contact_coverage(distance_px, reach / pixel_height);
}

const float TOWN_GABLE_POST_PROJECTION = 0.26;

vec2 town_gable_post_contact(vec2 world, vec2 pixel, bool end_wall, float inset_width) {
	vec2 axis = end_wall ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec2 midpoint = (town_variant_bounds.xy + town_variant_bounds.zw) * 0.5;
	vec2 corner = mix(town_variant_bounds.xy, town_variant_bounds.zw, step(midpoint, world));
	vec2 inward = sign(midpoint - corner);
	vec2 inset = corner + inward * axis * inset_width;
	if (dot(inset - town_camera_origin, town_camera_forward) <= 0.005) return vec2(1e10, 0.0);
	float inner_x = town_sign_project(inset, 0.0).x;
	float outer_x = town_sign_project(corner, 0.0).x;
	float direction = sign(inner_x - outer_x);
	if (direction == 0.0) return vec2(1e10, 0.0);
	// Compare the projected return with the join itself. A grazing view
	// can hide the core of the shadow behind the projecting timber.
	vec2 outward = -inward * (vec2(1.0) - axis);
	float post_depth = town_variant_support.x * TOWN_GABLE_POST_PROJECTION;
	vec2 return_edge = inset + outward * post_depth;
	float return_x = town_sign_project(return_edge, 0.0).x;
	float on_return = float(dot(return_edge - town_camera_origin, town_camera_forward) > 0.005 &&
		(pixel.x - inner_x) * direction >= 0.0 &&
		(return_x - pixel.x) * direction > 0.0);
	// Reserve a column for the post when its real width is subpixel.
	inner_x = outer_x + direction * max(abs(inner_x - outer_x), 1.0);
	float first_column = direction > 0.0 ? ceil(inner_x - 0.5) : floor(inner_x - 0.5);
	float offset = (floor(pixel.x) - first_column) * direction;
	return vec2(offset < 0.0 ? 1e10 : offset + 0.5, on_return);
}

float town_gable_post_ink(vec2 world, vec2 pixel, bool end_wall, float inset_width) {
	vec2 midpoint = (town_variant_bounds.xy + town_variant_bounds.zw) * 0.5;
	vec2 corner = mix(town_variant_bounds.xy, town_variant_bounds.zw, step(midpoint, world));
	float depth = dot(corner - town_camera_origin, town_camera_forward);
	if (depth <= 0.005) return 0.0;
	vec2 axis = end_wall ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec2 inward = sign(midpoint - corner);
	vec2 inset = corner + inward * axis * inset_width;
	float outer_x = town_sign_project(corner, 0.0).x;
	float inner_x = town_sign_project(inset, 0.0).x;
	float width = abs(inner_x - outer_x);
	vec2 view = (corner - town_camera_origin) * inward;
	if (min(view.x, view.y) > 0.0) {
		// Both wall carriers meet at this corner. They share the column
		// containing the corner rather than darkening one column each.
		if (floor(pixel.x) != floor(outer_x)) return 0.0;
		vec2 other = corner + inward * (vec2(1.0) - axis) * inset_width;
		width += abs(town_sign_project(other, 0.0).x - outer_x);
		return 1.0 - smoothstep(1.0, 2.3, width);
	}
	float to_edge = (pixel.x - outer_x) * sign(inner_x - outer_x);
	if (to_edge < 0.0 || to_edge >= 1.0) return 0.0;
	return 1.0 - smoothstep(1.0, 2.3, width);
}

vec3 town_gable_cladding(vec3 wood, float height, float pixel_height, float detail) {
	float course = (height - town_gable_siding_profile.x) / town_gable_siding_profile.y;
	float phase = fract(course);
	float lip = town_gable_siding_profile.z / town_gable_siding_profile.y;
	float near_detail = smoothstep(0.25, 0.80, storefront_siding_detail)
		* (1.0 - smoothstep(0.023, 0.044, pixel_height));
	float course_blocks = 1.0 - smoothstep(0.047, 0.085, pixel_height);
	float variance = fract(floor(course) * 0.618);
	float flat_tone = 0.92 * mix(storefront_siding_distant_variation.x, storefront_siding_distant_variation.y, variance);
	float flat_board = mix(0.92, flat_tone, 0.68 * course_blocks);
	float face = mix(1.13, 0.91, smoothstep(lip, 1.0, phase));
	float underside = max(lip, min(pixel_height / town_gable_siding_profile.y, 0.34));
	float beveled = phase < underside ? 0.57 : face;
	return wood * mix(0.92, mix(flat_board, mix(0.97, 1.025, variance) * beveled, near_detail), detail);
}

vec2 town_gable_frame_world(vec2 wall, vec2 axis, float along) {
	return wall + axis * (along - dot(wall, axis));
}

// The opening and outer moulding share a front face. At oblique angles
// the camera sees an outer jamb return and the opposite inner reveal.
vec3 town_gable_frame(vec2 world, vec2 pixel, float height, float depth, bool end_wall, vec4 opening, float trim, vec3 timber) {
	vec2 axis = end_wall ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	float along = dot(world, axis);
	vec2 a = town_gable_frame_world(world, axis, opening.x);
	vec2 b = town_gable_frame_world(world, axis, opening.z);
	vec2 toward_eye = normalize(town_camera_origin - (a + b) * 0.5);
	float side_view = dot(toward_eye, axis);
	float facing = abs(dot(toward_eye, axis.yx));
	float resolve = smoothstep(0.85, 2.6, trim * focal_length / depth);
	float tone = STOREFRONT_TRIM_FACE;
	bool between_jambs = along > opening.x && along < opening.z;
	if (!between_jambs && height > opening.y && height < opening.w) {
		bool low_jamb = along <= opening.x;
		float inset = low_jamb ? opening.x - along : along - opening.z;
		float view = low_jamb ? -side_view : side_view;
		float outer = storefront_jamb_return(trim - inset, trim, view, depth);
		float inner = storefront_jamb_return(inset, trim, -view, depth);
		tone = mix(tone, STOREFRONT_TRIM_RETURN, outer);
		tone = mix(tone, 0.69, inner);
	}
	// Use projected rows for the header's underside and the top of the sill.
	// Extend to the outside of both jambs so the ends never leave a gap.
	vec2 head_a = a - axis * trim;
	vec2 head_b = b + axis * trim;
	if (height >= opening.w && storefront_edge_cell(pixel, vec3(head_a, opening.w), vec3(head_b, opening.w))) {
		tone = mix(tone, 0.73, resolve);
	} else if (height <= opening.y && storefront_edge_cell(pixel, vec3(head_a, opening.y), vec3(head_b, opening.y))) {
		tone = mix(tone, 1.52, resolve);
	} else if (height >= opening.w && storefront_edge_cell(pixel, vec3(head_a, opening.w + trim), vec3(head_b, opening.w + trim))) {
		tone = mix(tone, 1.47, resolve * facing);
	}
	return timber * tone;
}

float town_gable_lining_top(vec2 world) {
	float width = town_variant_bounds.z - town_variant_bounds.x;
	float across = (world.x - town_variant_bounds.x) / width;
	float rise = town_variant_role == 3 ? 0.0 : town_variant_form.y * (1.0 - abs(2.0 * across - 1.0));
	return town_variant_form.x + rise - town_gable_lining_drop;
}

bool town_gable_room_face(vec2 world) {
	vec2 center = (town_variant_bounds.xy + town_variant_bounds.zw) * 0.5;
	int axis = town_variant_role == 3 ? 0 : 1;
	return (world[axis] - center[axis]) * (town_camera_origin[axis] - world[axis]) < 0.0;
}

vec4 town_building_paint(vec2 world, vec2 pixel, float height, float depth, float across_per_pixel,
		bool daylight, vec4 lining, out bool structural_outline, out float contact_shadow) {
	structural_outline = false;
	contact_shadow = 0.0;
	float pixel_height = depth / focal_length;
	float width = town_variant_bounds.z - town_variant_bounds.x;
	float across = town_variant_form.w > 0.0 ? world.x - town_variant_bounds.x : town_variant_bounds.z - world.x;
	float eave = town_variant_form.x;
	float rise = town_variant_form.y;
	float facade_top = town_variant_form.z;
	float gable = eave + rise * (1.0 - abs(across * 2.0 / width - 1.0));
	bool front = town_variant_role == 1;
	bool rear = town_variant_role == 2;
	bool end_wall = front || rear;
	bool balcony = town_variant_options.y > 0.5;
	bool second = town_variant_options.x > 0.5;
	float center = abs(across - width * 0.5);
	float cap = facade_top;
	if (balcony) {
		cap += 0.21 * max(0.0, 1.0 - center / (width * 0.31));
	} else if (second && center < width * 0.25) {
		cap += center < width * 0.17 ? 0.17 : 0.085;
	}
	float top = front ? max(gable, cap) : (rear ? gable : eave);
	if (town_gable_blueprint && front) top = facade_top;
	if (town_gable_blueprint && town_gable_room_view && town_gable_room_face(world)) {
		top = town_gable_lining_top(world);
	}
	if (town_variant_shed_roof) {
		float along = clamp((world.y - town_variant_bounds.y) / (town_variant_bounds.w - town_variant_bounds.y), 0.0, 1.0);
		float slope_top = eave + rise * (town_variant_form.w > 0.0 ? along : 1.0 - along);
		top = front ? max(cap, slope_top) : slope_top;
	}
	float jamb = abs((end_wall ? world.x : world.y) - town_variant_door_center);
	float gap = town_variant_opening.x;
	float lintel = town_variant_opening.y;
	bool has_door = town_variant_generated ? gap > 0.0 : end_wall;
	float sill = town_gable_blueprint ? town_gable_joinery.x : 0.0;
	if (has_door && jamb < gap && height >= sill && height < lintel) return vec4(0.0);
	vec3 timber = town_weathered_wood(town_variant_timber.rgb);
	vec3 base = timber;
	float edge = end_wall ? min(across, width - across) : min(world.y - town_variant_bounds.y, town_variant_bounds.w - world.y);
	bool interior = lining.a > 0.0;
	bool gable_exterior = town_gable_blueprint && !interior;
	bool siding_receiver = gable_exterior;
	float frame_contact = 1e10;
	float door_contact = 0.0;
	float inset_width = town_variant_support.x * (1.0 - TOWN_GABLE_POST_PROJECTION);
	float post_ink = gable_exterior ? town_gable_post_ink(world, pixel, end_wall, inset_width) : 0.0;
	vec2 post_contact = gable_exterior ? town_gable_post_contact(world, pixel, end_wall, inset_width) : vec2(1e10, 0.0);
	bool gable_post = gable_exterior && (edge < inset_width || post_ink > 0.0 || post_contact.y > 0.0);
	float middle_y = (town_variant_bounds.y + town_variant_bounds.w) * 0.5;
	bool front_corner = (world.y - middle_y) * (town_variant_porch.x - middle_y) > 0.0;
	if (height > top) {
		if (end_wall || !town_variant_outside || !front_corner || !gable_post || height > facade_top) return vec4(0.0);
	}
	float foundation_top = storefront_floor_height + storefront_trim_bands.x;
	// The raised floor rests on the corner posts. Let the ground and its
	// foundation shadow show through beneath the apron between supports.
	if (height < town_variant_support.y && !gable_post && (gable_exterior || edge >= town_variant_support.x)) return vec4(0.0);
	float from_cap = top - height;
	vec2 facade = vec2(across, height);
	vec2 p = vec2(across_per_pixel, pixel_height);
	float material_detail = town_gable_blueprint ? 1.0 - smoothstep(6.5, 12.0, depth) : 1.0;
	bool sign_face = !interior && front && town_variant_front_view && town_variant_glyph_count > 0;
	bool framed = town_variant_options.z > 0.5;
	// Dust collects on the lower courses without covering the painted sign.
	float dust = 1.0 - smoothstep(0.08, 0.39, height);
	base *= 1.0 + 0.08 * dust;
	if (sign_face && !framed && town_building_ink(facade, p)) base = town_variant_ink.rgb;
	vec3 paint = lining.rgb;
	if (!interior) {
		paint = town_gable_blueprint ? town_gable_cladding(base, height, pixel_height, material_detail)
			: storefront_lapped_siding(base, world, height, depth, false);
	}
	if (gable_post) {
		paint = storefront_corner_timber(world, pixel, depth, town_variant_bounds, inset_width, timber, true);
	} else if (!gable_exterior && !interior && edge < town_variant_support.x) {
		// A corner post is continuous through the foundation band.
		paint = timber * 1.22;
	} else if (!interior && height < (town_gable_blueprint ? foundation_top : 0.086)) {
		paint = town_gable_blueprint ? timber * 0.90
			: timber * (height > 0.070 ? 1.22 : 0.86);
	}
	if (!town_gable_blueprint && !interior && edge < town_variant_support.x) {
		vec2 midpoint = (town_variant_bounds.xy + town_variant_bounds.zw) * 0.5;
		vec2 corner = mix(town_variant_bounds.xy, town_variant_bounds.zw, step(midpoint, world));
		vec2 view = (town_camera_origin - corner) * sign(corner - midpoint);
		bool side_wall = !end_wall;
		if (view.x > 0.0 && view.y > 0.0 && side_wall == (view.x >= view.y)) {
			vec2 span = wall_world_b - wall_world_a;
			float u = dot(corner - wall_world_a, span) / dot(span, span);
			vec2 local = mix(wall_local_a, wall_local_b, u);
			vec2 inner = mix(wall_local_a, wall_local_b, u + (u < 0.5 ? 1.0 : -1.0) * town_variant_support.x / length(span));
			if (min(local.y, inner.y) > 0.005) {
				float x = canvas_size.x * 0.5 + projection_offset.x + local.x * focal_length / local.y;
				float inside_x = canvas_size.x * 0.5 + projection_offset.x + inner.x * focal_length / inner.y;
				float column = inside_x >= x ? ceil(x - 0.5) : floor(x - 0.5);
				float highlight = float(floor(pixel.x) == column) * smoothstep(1.5, 3.5, abs(inside_x - x));
				paint *= 1.0 + timber_lighting.x * highlight * (1.0 - smoothstep(1.9, 4.1, depth));
			}
		}
	}
	if (has_door && town_gable_blueprint) {
		float frame = town_gable_joinery.y;
		float reveal = max(jamb - gap, max(sill - height, height - lintel));
		float frame_pixels = frame / max(max(across_per_pixel, pixel_height), 0.0001);
		vec2 opening_offset = vec2(jamb - gap, max(sill - height, height - lintel));
		vec2 outer_px = (vec2(frame) - opening_offset) / max(p, vec2(0.0001));
		float frame_coverage = mix(smoothstep(-0.45, 0.55, min(outer_px.x, outer_px.y)),
			1.0 - step(frame, reveal), smoothstep(1.0, 2.2, frame_pixels));
		// Reserve the first logical stroke outside the opening for the solid
		// casing. The leaf and its reveal only own pixels inside that opening.
		if (frame_coverage < 1.0 && min(outer_px.x, outer_px.y) > -2.0) {
			float center = town_variant_door_center;
			vec4 opening = vec4(center - gap, sill, center + gap, lintel);
			float edge_px = town_gable_frame_contact(world, pixel, height, end_wall, opening);
			if (min(opening_offset.x, opening_offset.y) >= 0.0) {
				vec2 corner_px = opening_offset / max(p, vec2(0.0001));
				edge_px = max(corner_px.x, corner_px.y);
			}
			if (edge_px < 1.0) frame_coverage = 1.0;
		}
		if (frame_coverage > 0.0) {
			siding_receiver = frame_coverage < 1.0 && reveal >= frame;
			// One flat ring. The visible outside return runs the whole height,
			// including the header and threshold, without separate rim strokes.
			vec2 axis = end_wall ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
			float along = dot(world, axis) - town_variant_door_center;
			vec2 center = world - axis * along;
			float view = sign(along) * dot(normalize(town_camera_origin - center), axis);
			float side = storefront_jamb_return(gap + frame - jamb, frame, view, depth);
			vec3 moulding = timber * mix(STOREFRONT_TRIM_FACE, STOREFRONT_TRIM_RETURN, side * smoothstep(1.0, 2.2, frame_pixels));
			paint = mix(paint, mix(timber * 1.08, moulding, material_detail), frame_coverage);
		}
		if (gable_exterior && siding_receiver) {
			float center = town_variant_door_center;
			door_contact = town_gable_door_contact(world, pixel, height, end_wall,
				vec4(center - gap - frame, sill - frame, center + gap + frame, lintel + frame), pixel_height) * (1.0 - frame_coverage);
		}
	} else if (has_door && ((jamb < gap + 0.053 && height < lintel + 0.048) || (jamb < gap + 0.028 && height < lintel + 0.065))) {
		float from_opening = min(jamb - gap, height - lintel);
		paint = timber * (from_opening < 0.014 ? 0.65 : (from_opening > 0.033 ? 1.30 : 1.0));
	}
	float opacity = 1.0;
	if (front || !end_wall || town_variant_generated) {
		vec2 local;
		vec2 half_size;
		float window_axis = end_wall ? world.x : world.y;
		for (int i = 0; i < town_variant_window_count; i++) {
			vec4 rect = town_variant_windows[i];
			local = vec2(window_axis, height) - (rect.xy + rect.zw) * 0.5;
			half_size = (rect.zw - rect.xy) * 0.5;
			vec2 inset = half_size - abs(local);
			if (min(inset.x, inset.y) <= 0.0) {
				if (gable_exterior) {
					frame_contact = min(frame_contact, town_gable_frame_contact(world, pixel, height, end_wall, rect));
					continue;
				}
				// Cast the projecting sill down and away from the west light.
				vec2 shadow_offset = vec2(end_wall ? 0.012 : 0.0, -0.027);
				vec2 shadow_edge = half_size - abs(local - shadow_offset);
				if (min(shadow_edge.x, shadow_edge.y) > 0.0) {
					float detail = 1.0 - smoothstep(1.9, 4.1, depth);
					paint *= 1.0 - detail * timber_lighting.y * smoothstep(0.0, 0.021, shadow_edge.y);
				}
				continue;
			}
			siding_receiver = false;
			bool broken = (town_variant_broken_windows & (1 << i)) != 0;
			if (town_gable_blueprint && min(inset.x, inset.y) < town_variant_window_trim) {
				float trim = town_variant_window_trim;
				vec4 opening = rect + vec4(trim, trim, -trim, -trim);
				vec3 moulding = town_gable_frame(world, pixel, height, depth, end_wall, opening, trim, timber);
				paint = mix(paint, moulding, material_detail);
				break;
			}
			vec2 to_window = world - town_camera_origin;
			if (end_wall) to_window.x -= local.x;
			else to_window.y -= local.x;
			float facing = abs(end_wall ? to_window.y : to_window.x) / max(length(to_window), 0.0001);
			bvec2 snapped_cross = bvec2(false);
			if (town_gable_blueprint && !broken) {
				// Snap the two axes independently. The horizontal bar follows
				// the projected row at this column on an oblique wall.
				vec2 axis = end_wall ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
				vec2 bar_world = world - axis * local.x;
				float center_height = height - local.y;
				vec2 cross_pixel = vec2(town_sign_project(bar_world, height).x,
					town_sign_project(world, center_height).y);
				float bar_width = abs(town_sign_project(bar_world + axis * 0.012, height).x -
					town_sign_project(bar_world - axis * 0.012, height).x);
				vec2 bar_pixels = vec2(bar_width, 0.026 / pixel_height);
				bvec2 owns_cell = equal(floor(pixel), floor(cross_pixel));
				snapped_cross = bvec2(bar_pixels.x <= 1.0 && owns_cell.x, bar_pixels.y <= 1.0 && owns_cell.y);
			}
			vec4 window = town_window_paint(local, half_size, depth, facing, true, broken, snapped_cross);
			paint = broken || town_gable_blueprint ? window.rgb : mix(paint, window.rgb, material_detail);
			opacity = window.a;
			break;
		}
		if (front && second) {
			float bays = balcony ? 5.0 : 2.0;
			float pitch = width / bays;
			local = vec2((fract(across / pitch) - 0.5) * pitch, height - (balcony ? 0.95 : 0.99));
			half_size = vec2(pitch * (balcony ? 0.36 : 0.30), 0.155);
			if (all(lessThan(abs(local), half_size))) paint = town_window_paint(local, half_size, depth, 1.0, false, false, bvec2(false)).rgb;
		}
	}
	if (!end_wall && second && town_variant_outside && edge > 0.14) {
		float length_y = town_variant_bounds.w - town_variant_bounds.y;
		float edge_y = world.y - town_variant_bounds.y;
		float run = (fract(edge_y / (length_y * 0.5)) - 0.5) * length_y * 0.5;
		vec2 half_size = vec2(0.165, 0.14);
		vec2 local = vec2(run, height - (second ? 0.93 : 0.46));
		if (all(lessThan(abs(local), half_size))) paint = town_window_paint(local, half_size, depth, 1.0, false, false, bvec2(false)).rgb;
	}

	if (interior) return vec4(paint, opacity);
	if (front) {
		float from_awning = town_variant_porch.w - height;
		// This broad cast-shadow gradient survives the loss of fine detail.
		// Apply to the assembled facade, including frames and siding.
		float under_awning = step(0.0, from_awning);
		float rise = clamp((height - 0.05) / max(town_variant_porch.w - 0.05, 0.001), 0.0, 1.0);
		if (!gable_post) paint *= 1.0 - town_porch_awning_shadow * smoothstep(0.0, 1.0, rise) * under_awning;
		if (balcony && height < 0.695) paint *= mix(0.61, 0.96, smoothstep(0.0, 0.30, 0.695 - height));
		if (!town_gable_blueprint && from_cap < 0.131 && from_cap >= 0.075 &&
			abs(fract((across + 0.03) / 0.235) - 0.5) < 0.13) paint = timber * (from_cap < 0.10 ? 0.72 : 1.16);
	} else if (!town_gable_blueprint && height < top) {
		paint *= mix(0.72, 1.0, smoothstep(0.025, 0.12, from_cap));
	}
	float trim_height = town_gable_blueprint ? 0.05 : (front ? 0.081 : 0.033);
	if (gable_exterior) {
		float shadow_width = 0.048 / pixel_height;
		float shadow_strength = mix(0.31, 0.23, smoothstep(2.0, 7.0, depth));
		if (from_cap < trim_height && !gable_post) {
			paint = timber * (front ? 1.08 : 0.90);
		} else if (siding_receiver && !gable_post) {
			float foundation_contact = height < foundation_top ? (foundation_top - height) / pixel_height : 1e10;
			float distance_px = min(frame_contact, foundation_contact);
			contact_shadow = max(door_contact, town_contact_coverage(distance_px, shadow_width)) * shadow_strength;
			if (front) {
				// The cornice shades the siding directly below its lower edge.
				float cornice_contact = town_gable_roof_edge(world, pixel, true, false, top - trim_height);
				float cornice_shadow = town_contact_coverage(cornice_contact, 0.032 / pixel_height);
				contact_shadow = max(contact_shadow, cornice_shadow * shadow_strength);
			}
		}
		// The vertical joint continues onto the top trim beside the roof.
		if (siding_receiver && !gable_post) {
			float post_shadow = town_contact_coverage(post_contact.x, shadow_width) * shadow_strength;
			contact_shadow = max(contact_shadow, post_shadow);
		}
		// The metal casts onto the face directly below it. The storefront
		// wall meets the high edge of the porch roof below its false front.
		float metal_height = front ? town_variant_porch.w : top;
		bool under_porch_metal = front && town_variant_porch.y > 0.0;
		// The rear posts terminate under the main roof. The tall front posts
		// pass the side eave, so their exposed side does not receive this band.
		bool receives_metal_shadow = !gable_post || under_porch_metal || !front_corner;
		if (height <= metal_height && siding_receiver && receives_metal_shadow) {
			float metal_contact = town_gable_roof_edge(world, pixel, end_wall, rear, metal_height);
			// Leave a contact row below the metal lip even at distance.
			if (!front && !gable_post) metal_contact = max(0.0, metal_contact - 1.0);
			contact_shadow = max(contact_shadow, 0.32 * town_contact_coverage(metal_contact, 0.046 / pixel_height));
		}
		if (under_porch_metal && height < metal_height) {
			// Match the outer rafter's end at the wall and extend its contact
			// below the joint on the porch-facing surface of the post.
			float rafter_center = town_variant_support.x * 0.5;
			float rafter_bottom = metal_height - 0.052;
			vec2 outside = max(vec2(abs(edge - rafter_center) - rafter_center * 0.5, rafter_bottom - height), vec2(0.0));
			vec2 contact_px = outside / max(p, vec2(0.0001));
			float rafter_shadow = 0.40 * town_contact_coverage(length(contact_px), 0.034 / pixel_height);
			contact_shadow = max(contact_shadow, rafter_shadow);
		}
	} else if (from_cap < trim_height) {
		float band = from_cap / trim_height;
		float moulding = band < 0.21 ? 1.52 : (band < 0.53 ? 1.16 : (band < 0.67 ? 0.73 : 0.99));
		paint = mix(paint, timber * moulding, material_detail);
	} else if (from_cap < trim_height + 0.021) {
		paint *= 0.69;
	}
	if (sign_face && framed) {
		// Project a shallow raised board toward the viewer. Its offset shadow
		// sits on the wall, while the complete board paints above the cornice.
		float toward = clamp(0.025 / max(abs(town_camera_origin.y - world.y), 0.05), 0.0, 0.5);
		vec2 raised = vec2(across + (town_camera_origin.x - world.x) * toward * town_variant_form.w,
			height + (camera_height - height) * toward);
		vec2 shadow = min(facade - (town_variant_sign_rect.xy + vec2(0.014, -0.025)),
			(town_variant_sign_rect.zw + vec2(0.014, -0.025)) - facade);
		if (min(shadow.x, shadow.y) > -0.033) paint *= 0.57;
		vec2 sign_margin = min(raised - town_variant_sign_rect.xy, town_variant_sign_rect.zw - raised);
		float margin = min(sign_margin.x, sign_margin.y);
		if (margin >= -0.032) {
			contact_shadow = 0.0;
			bool lip = raised.y > town_variant_sign_rect.w + 0.020 || raised.x < town_variant_sign_rect.x - 0.021;
			paint = margin < -0.012 ? timber * (lip ? 1.52 : 0.86) : town_variant_board.rgb;
			paint = mix(paint, town_variant_ink.rgb, town_sign_raster_ink(pixel, raised, p));
		}
	}
	float sun = storefront_sunlight();
	float light = daylight || (front && town_variant_front_view) || (town_variant_outside && height > 0.67) ? sun : 0.72;
	if (gable_post) light = 1.0; // The same directional post tones are already applied on the porch.
	// The wall carrier owns the first row just under the metal. It still
	// shows a lip when the sheet itself is edge-on or outside the view.
	if (gable_exterior && !front && !gable_post && town_gable_roof_edge(world, pixel, end_wall, rear, top) < 1.0) {
		contact_shadow = 0.0;
		return vec4(town_gable_roof_metal.rgb * 0.73, opacity);
	}
	float roof_ink = 0.0;
	if (gable_exterior && front && !gable_post && town_gable_roof_edge(world, pixel, end_wall, rear, top) < 1.0) {
		roof_ink = 1.0 - smoothstep(1.0, 2.3, 0.05 / pixel_height);
	}
	float ink = max(post_ink, roof_ink);
	structural_outline = ink > 0.5;
	paint = mix(paint, town_gable_outline.rgb, ink);
	return vec4(paint * light, opacity);
}
