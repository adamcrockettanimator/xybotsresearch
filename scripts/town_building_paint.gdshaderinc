uniform int town_variant_role = 0;
uniform vec4 town_variant_bounds;
uniform vec4 town_variant_form; // Eave, rise, flat-front height, direction to street.
uniform vec4 town_variant_porch; // Front wall Y, depth, entrance X, awning at wall.
uniform vec3 town_variant_options; // Second story, balcony, framed sign.
uniform vec4 town_variant_timber : source_color;
uniform vec4 town_variant_board : source_color;
uniform vec4 town_variant_ink : source_color;
uniform vec4 town_variant_sign_rect;
uniform int town_variant_glyphs[8];
uniform int town_variant_glyph_count;
uniform bool town_variant_outside;
uniform vec2 town_variant_opening;
uniform vec4 town_variant_windows[2];
uniform int town_variant_window_count;
uniform int town_variant_broken_windows;
uniform float town_variant_window_trim;
uniform bool town_variant_front_view;

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

vec4 town_window_paint(vec2 local, vec2 half_size, float depth, float facing, bool glazed, bool broken) {
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
	vec2 bars = max(vec2(0.012, 0.013), vec2(pixel_height * 0.55));
	vec2 from_bar = abs(local) - bars;
	if (min(from_bar.x, from_bar.y) < 0.0) {
		float bevel = min(0.009, pixel_height);
		bool side = from_bar.y >= 0.0 && from_bar.x > -bevel;
		bool horizontal = from_bar.x >= 0.0 && from_bar.y > -bevel;
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
	if (town_variant_role == 6) {
		vec2 panel = vec2(min(uv.x, 1.0 - uv.x), min(fract(uv.y * 2.0), 1.0 - fract(uv.y * 2.0)));
		vec3 wood = timber * 0.82;
		if (panel.x > 0.15 && panel.y > 0.17) wood *= panel.y < 0.24 || panel.x < 0.21 ? 0.58 : 0.83;
		if (uv.x > 0.977) wood *= 0.57;
		if (distance(uv, vec2(0.86, 0.53)) < 0.068) wood = vec3(0.56, 0.39, 0.19);
		return vec4(wood, 1.0);
	}
	bool apron = height < 0.050 && height > 0.006;
	float balcony = height - 0.695;
	bool balcony_fascia = town_variant_options.y > 0.5 && balcony < 0.0 && balcony > -0.063;
	if (!apron && !balcony_fascia) return vec4(0.0);
	float along = town_variant_role == 4 ? world.x : world.y;
	return vec4(timber * (fract(along * 8.0) > 0.92 ? 0.75 : 0.91), 1.0);
}

vec4 town_building_paint(vec2 world, float height, float depth, float across_per_pixel, bool daylight, vec4 lining) {
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
	float jamb = abs(world.x - town_variant_porch.z);
	float gap = town_variant_opening.x;
	float lintel = town_variant_opening.y;
	if (height > top || (end_wall && jamb < gap && height < lintel)) return vec4(0.0);
	vec3 timber = town_weathered_wood(town_variant_timber.rgb);
	vec3 base = timber;
	float edge = end_wall ? min(across, width - across) : min(world.y - town_variant_bounds.y, town_variant_bounds.w - world.y);
	float from_cap = top - height;
	bool interior = lining.a > 0.0;
	vec2 facade = vec2(across, height);
	vec2 p = vec2(across_per_pixel, pixel_height);
	bool sign_face = !interior && front && town_variant_front_view && town_variant_glyph_count > 0;
	bool framed = town_variant_options.z > 0.5;
	// Dust collects on the lower courses without covering the painted sign.
	float dust = 1.0 - smoothstep(0.08, 0.39, height);
	base *= 1.0 + 0.08 * dust;
	if (sign_face && !framed && town_building_ink(facade, p)) base = town_variant_ink.rgb;
	vec3 paint = interior ? lining.rgb : storefront_lapped_siding(base, world, height, depth, false);
	if (!interior && (height < 0.086 || edge < 0.045)) {
		paint = timber * (edge < 0.012 || height > 0.070 ? 1.22 : 0.86);
	}
	if (end_wall && ((jamb < gap + 0.053 && height < lintel + 0.048) || (jamb < gap + 0.028 && height < lintel + 0.065))) {
		float from_opening = min(jamb - gap, height - lintel);
		paint = timber * (from_opening < 0.014 ? 0.65 : (from_opening > 0.033 ? 1.30 : 1.0));
	}
	float opacity = 1.0;
	if (front || !end_wall) {
		vec2 local;
		vec2 half_size;
		float window_axis = front ? world.x : world.y;
		for (int i = 0; i < town_variant_window_count; i++) {
			vec4 rect = town_variant_windows[i];
			local = vec2(window_axis, height) - (rect.xy + rect.zw) * 0.5;
			half_size = (rect.zw - rect.xy) * 0.5;
			vec2 inset = half_size - abs(local);
			if (min(inset.x, inset.y) <= 0.0) {
				// Cast the projecting sill down and away from the west light.
				vec2 shadow_offset = vec2(front ? 0.012 : 0.0, -0.027);
				vec2 shadow_edge = half_size - abs(local - shadow_offset);
				if (min(shadow_edge.x, shadow_edge.y) > 0.0) {
					float detail = 1.0 - smoothstep(1.9, 4.1, depth);
					paint *= 1.0 - detail * timber_lighting.y * smoothstep(0.0, 0.021, shadow_edge.y);
				}
				continue;
			}
			bool broken = (town_variant_broken_windows & (1 << i)) != 0;
			vec2 to_window = world - town_camera_origin;
			if (front) to_window.x -= local.x;
			else to_window.y -= local.x;
			float facing = abs(front ? to_window.y : to_window.x) / max(length(to_window), 0.0001);
			vec4 window = town_window_paint(local, half_size, depth, facing, true, broken);
			paint = window.rgb;
			opacity = window.a;
			break;
		}
		if (front && second) {
			float bays = balcony ? 5.0 : 2.0;
			float pitch = width / bays;
			local = vec2((fract(across / pitch) - 0.5) * pitch, height - (balcony ? 0.95 : 0.99));
			half_size = vec2(pitch * (balcony ? 0.36 : 0.30), 0.155);
			if (all(lessThan(abs(local), half_size))) paint = town_window_paint(local, half_size, depth, 1.0, false, false).rgb;
		}
	}
	if (!end_wall && second && town_variant_outside && edge > 0.14) {
		float length_y = town_variant_bounds.w - town_variant_bounds.y;
		float edge_y = world.y - town_variant_bounds.y;
		float run = (fract(edge_y / (length_y * 0.5)) - 0.5) * length_y * 0.5;
		vec2 half_size = vec2(0.165, 0.14);
		vec2 local = vec2(run, height - (second ? 0.93 : 0.46));
		if (all(lessThan(abs(local), half_size))) paint = town_window_paint(local, half_size, depth, 1.0, false, false).rgb;
	}
	if (sign_face && framed) {
		vec2 sign_margin = min(facade - town_variant_sign_rect.xy, town_variant_sign_rect.zw - facade);
		float margin = min(sign_margin.x, sign_margin.y);
		if (margin > -0.052) {
			if (margin < -0.032 && facade.y < town_variant_sign_rect.y) paint *= 0.68;
			if (margin >= -0.032) {
				bool lip = facade.y > town_variant_sign_rect.w + 0.020 ||
					facade.x < town_variant_sign_rect.x - 0.021;
				paint = margin < -0.012 ? timber * (lip ? 1.52 : 0.86) : town_variant_board.rgb;
				if (town_building_ink(facade, p)) paint = town_variant_ink.rgb;
			}
		}
	}
	if (interior) return vec4(paint, opacity);
	if (front) {
		float from_awning = town_variant_porch.w - height;
		paint *= 1.0 - 0.31 * (1.0 - smoothstep(0.02, 0.14, from_awning)) * step(0.0, from_awning);
		if (balcony && height < 0.695) paint *= mix(0.61, 0.96, smoothstep(0.0, 0.30, 0.695 - height));
		if (from_cap < 0.131 && from_cap >= 0.075 &&
			abs(fract((across + 0.03) / 0.235) - 0.5) < 0.13) paint = timber * (from_cap < 0.10 ? 0.72 : 1.16);
	} else if (height < top) {
		paint *= mix(0.72, 1.0, smoothstep(0.025, 0.12, from_cap));
	}
	float trim_height = front ? 0.081 : 0.033;
	if (from_cap < trim_height) {
		float band = from_cap / trim_height;
		float moulding = band < 0.21 ? 1.52 : (band < 0.53 ? 1.16 : (band < 0.67 ? 0.73 : 0.99));
		paint = timber * moulding;
	} else if (from_cap < trim_height + 0.021) {
		paint *= 0.69;
	}
	float sun = storefront_sunlight();
	float light = daylight || (front && town_variant_front_view) || (town_variant_outside && height > 0.67) ? sun : 0.72;
	return vec4(paint * light, opacity);
}
