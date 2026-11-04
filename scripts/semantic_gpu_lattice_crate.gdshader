// Static semantic-lattice crate. There is no texture sampler or UV attribute:
// the fixed mesh carries only local lattice coordinates in VERTEX.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 camera_origin;
uniform vec2 camera_forward = vec2(0.0, 1.0);
uniform vec2 camera_right = vec2(1.0, 0.0);
uniform vec2 projection_offset;
uniform vec2 crate_center;
uniform vec2 crate_half_size = vec2(0.10);
uniform float crate_height = 0.20;
uniform float ground_lift = 0.0;
uniform int face_index = 0;
// 0 frame strips, 1 board field, 2 slat strips, 3 brace, 5 floor shadow.
// 0 base planes, 1 frame, 2 panel/inset, 3 slats, 4 brace, 5 floor shadow.
uniform int surface_layer = 0;
uniform int authoring_lod_stage = -1;
uniform vec2 diagonal_start_pixel;
uniform vec2 diagonal_end_pixel;
uniform vec2 crate_center_pixel;
uniform vec2 face_bl_pixel;
uniform vec2 face_br_pixel;
uniform vec2 face_tr_pixel;
uniform vec2 face_tl_pixel;
uniform vec2 panel_bl_pixel;
uniform vec2 panel_br_pixel;
uniform vec2 panel_tr_pixel;
uniform vec2 panel_tl_pixel;
uniform vec2 edge_y_start_pixel;
uniform vec2 edge_y_u_end_pixel;
uniform vec2 edge_y_v_end_pixel;
uniform vec2 edge_y_vertical_start_pixel;
uniform vec2 edge_y_vertical_end_pixel;
uniform vec2 slat_start_0;
uniform vec2 slat_end_0;
uniform vec2 slat_start_1;
uniform vec2 slat_end_1;
uniform vec2 slat_start_2;
uniform vec2 slat_end_2;
uniform vec2 slat_start_3;
uniform vec2 slat_end_3;
uniform vec2 slat_start_4;
uniform vec2 slat_end_4;
uniform vec2 slat_start_5;
uniform vec2 slat_end_5;
uniform vec2 slat_start_6;
uniform vec2 slat_end_6;
uniform vec2 slat_start_7;
uniform vec2 slat_end_7;
uniform vec4 top_color : source_color;
uniform vec4 side_x_color : source_color;
uniform vec4 side_y_color : source_color;
uniform float side_bottom_light = 0.65;
uniform float side_top_light = 1.10;
uniform vec4 panel_top_color : source_color;
uniform vec4 panel_color : source_color;
uniform vec4 panel_dark_color : source_color;
uniform vec4 shadow_color : source_color;
uniform vec4 inset_shadow_color : source_color;
uniform vec4 slat_color : source_color;
uniform vec4 frame_color : source_color;
uniform vec4 floor_shadow_color : source_color;
uniform vec4 edge_highlight_color : source_color;
uniform bool panel_enabled = true;
uniform bool lid_enabled = true;
uniform bool slats_enabled = true;
uniform bool diagonal_enabled = false;
uniform bool floor_shadow_enabled = true;
uniform bool edge_highlight_enabled = true;
// Comparison path: when true every one-pixel effect is selected per logical
// fragment. The CPU/Bresenham reference keeps this false and paints its own
// overlay after the structural GPU layers.
uniform bool fragment_raster_lines_enabled = false;
uniform bool final_edge_overlay_enabled = false;
uniform float frame_inset = 0.14;
uniform int slat_count = 4;
uniform float panel_max_distance = 1000.0;
uniform float panel_full_distance = 4.0;
uniform float panel_hidden_distance = 6.0;
uniform float inset_full_distance = 2.0;
uniform float inset_hidden_distance = 3.5;
uniform float diagonal_width = 1.0;
uniform float floor_shadow_opacity = 0.45;
uniform float inset_shadow_depth = 0.035;
uniform float inset_shadow_strength = 0.55;
uniform float edge_highlight_width_logical_pixels = 1.0;
uniform float edge_highlight_end_fade = 0.30;
uniform float edge_highlight_angle_fade = 0.28;
uniform float edge_highlight_full_distance = 1.5;
uniform float edge_highlight_hidden_distance = 3.0;
uniform float inset_side_highlight_full_distance = 0.60;
uniform float inset_side_highlight_hidden_distance = 1.20;
uniform float detail_full_distance = 2.0;
uniform float detail_hidden_distance = 4.5;
uniform float diagonal_full_distance = 2.5;
uniform float diagonal_hidden_distance = 5.0;
uniform float diagonal_highlight_full_distance = 1.5;
uniform float diagonal_highlight_hidden_distance = 3.0;
uniform float minimum_face_ratio = 0.10;

varying vec3 local_corner;
// Perspective-correct face coordinates let one quad describe each cube face
// without the hidden 5×5 subdivision that warped the inset boundaries.
varying vec2 lattice_coord_over_depth;
varying float inverse_projection_depth;
varying vec2 projected_pixel;
varying float camera_distance;
varying float visible_face;
varying float face_angle;
varying vec2 camera_direction;
// Signed horizontal view direction within a side-panel's local coordinates.
// Zero is front-on; +/-1 means the viewer is at either end of the panel.
varying float inset_side_view;
varying vec2 lid_inset_shadow_direction;

vec3 normal_for_face() {
	if (face_index == 0) return vec3(0.0, 0.0, -1.0);
	if (face_index == 1) return vec3(1.0, 0.0, 0.0);
	if (face_index == 2) return vec3(0.0, 0.0, 1.0);
	if (face_index == 3) return vec3(-1.0, 0.0, 0.0);
	return vec3(0.0, 1.0, 0.0);
}

void vertex() {
	if (face_index == 0) local_corner = vec3(VERTEX.x, VERTEX.y, -1.0);
	else if (face_index == 1) local_corner = vec3(1.0, VERTEX.y, VERTEX.x);
	else if (face_index == 2) local_corner = vec3(VERTEX.x, VERTEX.y, 1.0);
	else if (face_index == 3) local_corner = vec3(-1.0, VERTEX.y, VERTEX.x);
	else local_corner = vec3(VERTEX.x, face_index == 4 ? 1.0 : 0.0, VERTEX.y);
	// A carrier just beyond the face boundaries lets the Y highlight paint the
	// exact shared rim pixel. It has no body colour of its own (layer 5 only
	// emits the requested highlight), so it cannot add a second silhouette.
	if (surface_layer == 5 && face_index < 5) {
		if (face_index == 0 || face_index == 2) local_corner.x *= 1.02;
		else if (face_index == 1 || face_index == 3) local_corner.z *= 1.02;
		else { local_corner.x *= 1.02; local_corner.z *= 1.02; }
		if (face_index < 4) local_corner.y = (local_corner.y - 0.5) * 1.04 + 0.5;
	}
	vec2 relative = crate_center + vec2(local_corner.x * crate_half_size.x, local_corner.z * crate_half_size.y) - camera_origin;
	float projection_depth = max(dot(relative, camera_forward), 0.02);
	camera_distance = length(crate_center - camera_origin);
	float raised = face_index == 5 ? 0.0 : ground_lift + local_corner.y * crate_height;
	// Keep the four-corner cage projection continuous. The shared low-resolution
	// viewport performs the one intended pixel quantization during rasterization.
	VERTEX = vec2(80.0 + dot(relative, camera_right) / projection_depth * 128.0, 31.5 + (0.5 - raised) / projection_depth * 128.0) + projection_offset;
	// The floor carrier is geometry only. Expand it by two *logical screen*
	// pixels so every cell of the footprint stroke receives a fragment, even
	// when that cell center lies just beyond the original floor-face triangle.
	// The fragment mask below still discards everything except the true contact
	// segment, so this cannot widen or float the visible shadow.
	if (face_index == 5 || surface_layer == 5) {
		vec2 outward = VERTEX - crate_center_pixel;
		VERTEX += outward / max(length(outward), 0.001) * 2.0;
	}
	projected_pixel = VERTEX;
	vec3 normal = normal_for_face();
	camera_direction = normalize(camera_origin - crate_center);
	float facing = face_index >= 4 ? 1.0 : dot(normal.xz, camera_direction);
	visible_face = face_index >= 4 ? 1.0 : step(0.001, facing);
	face_angle = face_index >= 4 ? 1.0 : clamp(facing, 0.0, 1.0);
	vec2 face_coord;
	if (face_index >= 4) face_coord = (local_corner.xz + 1.0) * 0.5;
	else if (abs(normal.x) > 0.5) face_coord = vec2(local_corner.z * 0.5 + 0.5, local_corner.y);
	else face_coord = vec2(local_corner.x * 0.5 + 0.5, local_corner.y);
	inverse_projection_depth = 1.0 / projection_depth;
	lattice_coord_over_depth = face_coord * inverse_projection_depth;
	if (face_index == 4) {
		lid_inset_shadow_direction = normalize(camera_direction);
		inset_side_view = 0.0;
	} else if (abs(normal.x) > 0.5) {
		lid_inset_shadow_direction = vec2(0.0);
		inset_side_view = clamp(camera_direction.y, -1.0, 1.0);
	} else {
		lid_inset_shadow_direction = vec2(0.0);
		inset_side_view = clamp(camera_direction.x, -1.0, 1.0);
	}
}

float logical_pixel(float amount) {
	float projection_depth = 1.0 / max(inverse_projection_depth, 0.001);
	float across = projection_depth / max(crate_half_size.x * 2.0 * 128.0, 0.001);
	float high = projection_depth / max(crate_height * 128.0, 0.001);
	return max(across, high) * amount;
}

vec2 face_uv() {
	return lattice_coord_over_depth / max(inverse_projection_depth, 0.001);
}

// A logical-grid segment: one selected pixel cell per dominant-axis step.
// Endpoints are snapped before stepping, so this uses the same cell ownership
// rule as the stable diagonal rather than sampling a moving fractional line.
float raster_segment(vec2 pixel, vec2 start_pixel, vec2 end_pixel, float width) {
	vec2 start_cell = floor(start_pixel) + vec2(0.5);
	vec2 end_cell = floor(end_pixel) + vec2(0.5);
	vec2 delta = end_cell - start_cell;
	if (max(abs(delta.x), abs(delta.y)) < 0.001) return 0.0;
	float step_index;
	float step_count;
	float minor_coordinate;
	float pixel_minor_coordinate;
	if (abs(delta.x) >= abs(delta.y)) {
		step_index = pixel.x - start_cell.x;
		step_count = delta.x;
		minor_coordinate = start_cell.y + (step_index / delta.x) * delta.y;
		pixel_minor_coordinate = pixel.y;
	} else {
		step_index = pixel.y - start_cell.y;
		step_count = delta.y;
		minor_coordinate = start_cell.x + (step_index / delta.y) * delta.x;
		pixel_minor_coordinate = pixel.x;
	}
	// `step_index / step_count` is in [0, 1] for either travel direction.
	if (step_index / step_count < 0.0 || step_index / step_count > 1.0) return 0.0;
	float chosen_cell = floor(minor_coordinate) + 0.5;
	// All requested effect lines are one logical pixel. Keeping the test at an
	// exact cell centre prevents a neighbouring pink/base cell from sharing the
	// stroke due to a half-pixel threshold.
	if (width <= 1.01) return step(abs(pixel_minor_coordinate - chosen_cell), 0.01);
	return step(abs(pixel_minor_coordinate - chosen_cell), floor(width * 0.5) + 0.01);
}

float raster_slat_mask(vec2 pixel, int count) {
	float mask = 0.0;
	if (count >= 1) mask = max(mask, raster_segment(pixel, slat_start_0, slat_end_0, 1.0));
	if (count >= 2) mask = max(mask, raster_segment(pixel, slat_start_1, slat_end_1, 1.0));
	if (count >= 3) mask = max(mask, raster_segment(pixel, slat_start_2, slat_end_2, 1.0));
	if (count >= 4) mask = max(mask, raster_segment(pixel, slat_start_3, slat_end_3, 1.0));
	if (count >= 5) mask = max(mask, raster_segment(pixel, slat_start_4, slat_end_4, 1.0));
	if (count >= 6) mask = max(mask, raster_segment(pixel, slat_start_5, slat_end_5, 1.0));
	if (count >= 7) mask = max(mask, raster_segment(pixel, slat_start_6, slat_end_6, 1.0));
	if (count >= 8) mask = max(mask, raster_segment(pixel, slat_start_7, slat_end_7, 1.0));
	return mask;
}

vec2 logical_screen_pixel() {
	// CanvasItem shaders expose neither FRAGCOORD nor SCREEN_UV without a screen
	// texture. The projected canvas vertex coordinate is affine across this quad,
	// so at a fragment it is the logical SubViewport pixel coordinate we need.
	return floor(projected_pixel) + vec2(0.5);
}

float fade_between(float full_distance, float hidden_distance) {
	return 1.0 - smoothstep(min(full_distance, hidden_distance - 0.01), max(hidden_distance, full_distance + 0.01), camera_distance);
}

float visible_detail() {
	float angle_fade = smoothstep(minimum_face_ratio, min(1.0, minimum_face_ratio + 0.18), face_angle);
	return fade_between(detail_full_distance, detail_hidden_distance) * angle_fade * step(minimum_face_ratio, visible_face);
}

// One interior Y only: the nearest shared vertical edge and the two lid edges
// leaving its closest corner. The frame is still painted below it, so fading
// ends return to frame colour rather than leaking over the silhouette.
float edge_highlight_strength() {
	if (authoring_lod_stage >= 0 && authoring_lod_stage < 4) return 0.0;
	if (!fragment_raster_lines_enabled || !edge_highlight_enabled || final_edge_overlay_enabled) return 0.0;
	vec2 pixel = logical_screen_pixel();
	float mask = 0.0;
	if (face_index == 4) {
		// Each lid arm inherits the facing fade of the side plane sharing it.
		// Exact projected endpoints preserve a single logical-pixel arm.
		float x_facing = smoothstep(0.0, max(edge_highlight_angle_fade, 0.01), abs(camera_direction.x));
		float z_facing = smoothstep(0.0, max(edge_highlight_angle_fade, 0.01), abs(camera_direction.y));
		float x_arm = raster_segment(pixel, edge_y_start_pixel, edge_y_u_end_pixel, edge_highlight_width_logical_pixels);
		float z_arm = raster_segment(pixel, edge_y_start_pixel, edge_y_v_end_pixel, edge_highlight_width_logical_pixels);
		mask = max(x_arm * x_facing, z_arm * z_facing);
	} else {
		// One stable, most-front-facing side owns the shared vertical arm.  Having
		// both face carriers compete here made its presence depend on their
		// raster-boundary coverage as the crate turned.
		int vertical_owner;
		if (abs(camera_direction.x) >= abs(camera_direction.y)) {
			vertical_owner = camera_direction.x >= 0.0 ? 1 : 3;
		} else {
			vertical_owner = camera_direction.y >= 0.0 ? 2 : 0;
		}
		if (face_index != vertical_owner) return 0.0;
		mask = raster_segment(pixel, edge_y_vertical_start_pixel, edge_y_vertical_end_pixel, edge_highlight_width_logical_pixels);
	}
	float angle = face_index == 4 ? 1.0 : smoothstep(0.0, max(edge_highlight_angle_fade, 0.01), face_angle);
	if (authoring_lod_stage == 4) return mask * angle;
	return mask * angle * fade_between(edge_highlight_full_distance, edge_highlight_hidden_distance);
}

// GPU panel-effects pass, above slats and beneath the diagonal brace.
// Panel lighting owns its seam pixels without painting over the brace.
// Each candidate logical cell evaluates its own segment membership; no CPU
// Bresenham cells or freehand Canvas strokes are involved on this path.
vec4 fragment_raster_effect_colour() {
	if (!fragment_raster_lines_enabled) return vec4(0.0);
	vec2 pixel = logical_screen_pixel();
	// The close-only front Y has its own LOD controls. It must not inherit the
	// inset-panel fade, because it describes the large cube form rather than a
	// panel detail.
	float y_highlight = edge_highlight_strength();
	if (y_highlight > 0.001) return vec4(edge_highlight_color.rgb, y_highlight);
	if (!panel_enabled) return vec4(0.0);
	float inset_alpha = authoring_lod_stage >= 3 ? 1.0 : fade_between(inset_full_distance, inset_hidden_distance);
	if (authoring_lod_stage >= 0 && authoring_lod_stage < 3) inset_alpha = 0.0;
	if (inset_alpha <= 0.001) return vec4(0.0);
	// Contact shadow is deliberately below the front-edge Y in the named paint
	// stack.  At their shared bottom cell the camera-facing edge keeps its
	// authored highlight colour; every other bottom silhouette cell is shadow.
	if (face_index < 4 && floor_shadow_enabled) {
		float floor_alpha = authoring_lod_stage >= 3 ? 1.0 : fade_between(inset_full_distance, inset_hidden_distance);
		float bottom_contact = raster_segment(pixel, face_bl_pixel, face_br_pixel, 1.0);
		if (floor_alpha > 0.001 && bottom_contact > 0.5) {
			return vec4(floor_shadow_color.rgb, floor_shadow_color.a * floor_shadow_opacity * floor_alpha);
		}
	}
	if (face_index == 4) {
		float left_rim = raster_segment(pixel, panel_bl_pixel, panel_tl_pixel, 1.0);
		float right_rim = raster_segment(pixel, panel_br_pixel, panel_tr_pixel, 1.0);
		float bottom_rim = raster_segment(pixel, panel_bl_pixel, panel_br_pixel, 1.0);
		float top_rim = raster_segment(pixel, panel_tl_pixel, panel_tr_pixel, 1.0);
		float rim_u = camera_direction.x >= 0.0 ? left_rim : right_rim;
		float rim_v = camera_direction.y >= 0.0 ? bottom_rim : top_rim;
		float rim = max(rim_u, rim_v) * inset_alpha;
		return rim > 0.001 ? vec4(edge_highlight_color.rgb, rim) : vec4(0.0);
	}
	float bottom_highlight = raster_segment(pixel, panel_bl_pixel, panel_br_pixel, 1.0);
	float top_shadow = raster_segment(pixel, panel_tl_pixel, panel_tr_pixel, 1.0);
	float left_edge = raster_segment(pixel, panel_bl_pixel, panel_tl_pixel, 1.0);
	float right_edge = raster_segment(pixel, panel_br_pixel, panel_tr_pixel, 1.0);
	// Match the CPU reference: positive local view means the right panel edge
	// faces the viewer, so the left edge is the recessed, far-side shadow.
	float far_shadow = max(left_edge * max(inset_side_view, 0.0), right_edge * max(-inset_side_view, 0.0));
	if (bottom_highlight > 0.5) return vec4(edge_highlight_color.rgb, inset_alpha);
	float shadow = max(top_shadow, far_shadow) * inset_alpha;
	return shadow > 0.001 ? vec4(inset_shadow_color.rgb, shadow) : vec4(0.0);
}

void fragment() {
	vec2 lattice_coord = face_uv();
	if (face_index == 5) {
		if (!floor_shadow_enabled) discard;
		if (authoring_lod_stage >= 0 && authoring_lod_stage < 3) discard;
		float floor_alpha = authoring_lod_stage >= 3 ? 1.0 : fade_between(inset_full_distance, inset_hidden_distance);
		if (floor_alpha <= 0.0) discard;
		// Preserve only the camera-facing floor contact as exact logical-grid
		// strokes; the floor quad itself never contributes a blurred outline.
		vec2 pixel = logical_screen_pixel();
		float contact_u = camera_direction.x >= 0.0
			? raster_segment(pixel, face_br_pixel, face_tr_pixel, 1.0)
			: raster_segment(pixel, face_bl_pixel, face_tl_pixel, 1.0);
		float contact_v = camera_direction.y >= 0.0
			? raster_segment(pixel, face_tl_pixel, face_tr_pixel, 1.0)
			: raster_segment(pixel, face_bl_pixel, face_br_pixel, 1.0);
		if (max(contact_u, contact_v) < 0.5) discard;
		COLOR = vec4(floor_shadow_color.rgb, floor_shadow_color.a * floor_shadow_opacity * floor_alpha);
	} else {
		if (visible_face < 0.5 || (face_index == 4 && !lid_enabled)) discard;
		float inset = clamp(frame_inset, 0.06, 0.28);
		float border = min(min(lattice_coord.x, 1.0-lattice_coord.x), min(lattice_coord.y, 1.0-lattice_coord.y));
		float panel_alpha = authoring_lod_stage >= 1 ? 1.0 : fade_between(panel_full_distance, panel_hidden_distance);
		bool inside = panel_enabled && panel_alpha > 0.0 && border >= inset && camera_distance <= panel_max_distance;
		float detail_alpha = authoring_lod_stage >= 2 ? 1.0 : visible_detail();
		bool lid = face_index == 4;
		// Like the barrel staves, every side semantic layer shares a local-height
		// light ramp. The lid keeps its authored top colour unchanged.
		float side_vertical_light = lid ? 1.0 : mix(side_bottom_light, side_top_light, clamp(lattice_coord.y, 0.0, 1.0));
		vec3 axis_tone = (lid ? top_color.rgb : (abs(normal_for_face().x) > 0.5 ? side_x_color.rgb : side_y_color.rgb)) * side_vertical_light;
		if (surface_layer == 0) {
			// A: the three uninterrupted top/side colour planes.
			COLOR = vec4(axis_tone, 1.0);
		} else if (surface_layer == 1) {
			if (authoring_lod_stage >= 0 && authoring_lod_stage < 1) discard;
			// B: frame appears over the base plane when the panel LOD is supported.
			if (!panel_enabled || panel_alpha <= 0.0 || border >= inset) discard;
			// The frame is the surviving border of the A-stage plane, so its colour
			// must remain face-specific rather than repainting every side orange.
			COLOR = vec4(axis_tone, panel_alpha);
		} else if (surface_layer == 5) {
			vec4 effect_colour = fragment_raster_effect_colour();
			if (effect_colour.a <= 0.001) discard;
			COLOR = effect_colour;
		} else {
			// The brace owns its rasterized endpoints; continuous panel UV clipping
			// would drop its boundary cells as the projected panel moves.
			if (!inside && surface_layer != 4) discard;
			vec3 panel_tone = (lid ? panel_top_color.rgb : (abs(normal_for_face().x) > 0.5 ? panel_color.rgb : panel_dark_color.rgb)) * side_vertical_light;
			vec3 panel = mix(axis_tone, panel_tone, 0.65);
			// All panel details use this 0..1 space, never the cube-face UVs.
			// Therefore changing Frame Inset resizes and redistributes them with
			// the central panel rather than leaving them tied to the outer cube.
			float panel_span = max(1.0 - 2.0 * inset, 0.01);
			float u = (lattice_coord.x - inset) / panel_span;
			float v = (lattice_coord.y - inset) / panel_span;
			if (surface_layer == 2) {
				if (authoring_lod_stage >= 0 && authoring_lod_stage < 1) discard;
				vec2 pixel = logical_screen_pixel();
				float inset_detail_alpha = authoring_lod_stage >= 3 ? 1.0 : fade_between(inset_full_distance, inset_hidden_distance);
				if (authoring_lod_stage >= 0 && authoring_lod_stage < 3) inset_detail_alpha = 0.0;
				// Raster strokes centered exactly on a panel boundary lose samples to the
				// neighbouring mask. Shift every effect line half a logical pixel into
				// its owning panel so a one-pixel stroke stays continuous rather than
				// collapsing into isolated corner dots.
				// One full logical pixel clears the panel clipping boundary. This is
				// especially important on the lid, where its two projected rim edges
				// are shallow diagonals and half-pixel placement can skip samples.
				float stroke_inset = 1.0;
				vec2 bottom_left_stroke = panel_bl_pixel + normalize(panel_tl_pixel - panel_bl_pixel) * stroke_inset;
				vec2 bottom_right_stroke = panel_br_pixel + normalize(panel_tr_pixel - panel_br_pixel) * stroke_inset;
				vec2 top_left_stroke = panel_tl_pixel + normalize(panel_bl_pixel - panel_tl_pixel) * stroke_inset;
				vec2 top_right_stroke = panel_tr_pixel + normalize(panel_br_pixel - panel_tr_pixel) * stroke_inset;
				vec2 left_bottom_stroke = panel_bl_pixel + normalize(panel_br_pixel - panel_bl_pixel) * stroke_inset;
				vec2 left_top_stroke = panel_tl_pixel + normalize(panel_tr_pixel - panel_tl_pixel) * stroke_inset;
				vec2 right_bottom_stroke = panel_br_pixel + normalize(panel_bl_pixel - panel_br_pixel) * stroke_inset;
				vec2 right_top_stroke = panel_tr_pixel + normalize(panel_tl_pixel - panel_tr_pixel) * stroke_inset;
				if (lid) {
					// Highlight-only lid rim. Its two far panel edges are exact one-pixel
					// raster strokes; no shadow is painted around the lid inset.
					float lid_u_rim = camera_direction.x >= 0.0
						? raster_segment(pixel, left_bottom_stroke, left_top_stroke, 1.0)
						: raster_segment(pixel, right_bottom_stroke, right_top_stroke, 1.0);
					float lid_v_rim = camera_direction.y >= 0.0
						? raster_segment(pixel, bottom_left_stroke, bottom_right_stroke, 1.0)
						: raster_segment(pixel, top_left_stroke, top_right_stroke, 1.0);
					// The comparison path evaluates the two far lid-rim segments on
					// every logical fragment. No CPU cell list is generated.
					float lid_rim = max(lid_u_rim, lid_v_rim) * inset_detail_alpha;
					// Lighting is painted only by the final raster carrier (layer 5).
					// Keeping this base layer flat prevents an offset duplicate pixel.
					COLOR = vec4(panel, panel_alpha);
				} else {
				// All inset edges are exact one-logical-pixel raster segments.
				float bottom_highlight = raster_segment(pixel, bottom_left_stroke, bottom_right_stroke, 1.0);
				float top_shadow = raster_segment(pixel, top_left_stroke, top_right_stroke, 1.0);
				float left_edge_band = raster_segment(pixel, left_bottom_stroke, left_top_stroke, 1.0);
				float right_edge_band = raster_segment(pixel, right_bottom_stroke, right_top_stroke, 1.0);
				// The near panel edge is hidden behind the physical extrusion. Only the
				// far edge may receive a line, and it fades in as the face turns.
				float left_far_weight = max(-inset_side_view, 0.0);
				float right_far_weight = max(inset_side_view, 0.0);
				float far_edge_band = max(left_edge_band * left_far_weight, right_edge_band * right_far_weight);
				// Side extrusion is shadow-only: highlights belong to the lid rim/Y.
				// Keep panels flat except for the authored one-pixel inset bands.
				vec3 paint = panel;
				float inset_alpha = inset_detail_alpha;
				// Lighting is painted only by the final raster carrier (layer 5).
				// This layer remains the flat recessed panel beneath it.
				// Axis colour remains at every distance; only the inset treatment is LOD detail.
				COLOR = vec4(paint, panel_alpha);
				}
			} else if (surface_layer == 3) {
				if (authoring_lod_stage >= 0 && authoring_lod_stage < 2) discard;
				if (!slats_enabled || detail_alpha <= 0.0) discard;
				// The CPU supplies each seam's perspective-exact endpoints. This keeps
				// slats evenly distributed within the inset panel while their raster
				// width remains exactly one logical pixel.
				vec2 pixel = logical_screen_pixel();
				if (raster_slat_mask(pixel, slat_count) < 0.5) discard;
				COLOR = vec4(slat_color.rgb * side_vertical_light, detail_alpha);
			} else if (surface_layer == 4) {
				if (authoring_lod_stage >= 0 && authoring_lod_stage < 1) discard;
				if (!diagonal_enabled || !panel_enabled || panel_alpha <= 0.0 || camera_distance > panel_max_distance || lid || camera_distance >= diagonal_hidden_distance) discard;
				// Rasterize directly in the 160x120 logical grid. The brace is a
				// deliberately wide structural mask; its lighting remains a one-pixel
				// raster stroke on only the camera-facing edge.
				vec2 pixel = logical_screen_pixel();
				vec2 brace_start = floor(diagonal_start_pixel) + vec2(0.5);
				vec2 brace_end = floor(diagonal_end_pixel) + vec2(0.5);
				vec2 delta = brace_end - brace_start;
				if (max(abs(delta.x), abs(delta.y)) < 0.001) discard;
				float line_coordinate;
				float pixel_coordinate;
				float line_t;
				if (abs(delta.x) >= abs(delta.y)) {
					line_t = (pixel.x - brace_start.x) / delta.x;
					line_coordinate = brace_start.y + line_t * delta.y;
					pixel_coordinate = pixel.y;
				} else {
					line_t = (pixel.y - brace_start.y) / delta.y;
					line_coordinate = brace_start.x + line_t * delta.x;
					pixel_coordinate = pixel.x;
				}
				float signed_distance = pixel_coordinate - line_coordinate;
				float brace_width = max(diagonal_width, 1.0);
				if (line_t < 0.0 || line_t > 1.0 || abs(signed_distance) >= brace_width * 0.5) discard;
				float brace_alpha = authoring_lod_stage >= 1 ? 1.0 : fade_between(diagonal_full_distance, diagonal_hidden_distance);
				// The brace is part of the side's structural frame, so it starts from
				// that face's base colour instead of the darker recessed-panel colour.
				vec3 brace_paint = axis_tone;
				// The screen-right panel is viewed from the crate's left and exposes
				// the support's upper edge; the screen-left panel is viewed from its
				// right and exposes the lower edge. This maps to the actual visible
				// top/bottom instead of flipping from a tangential camera sign.
				float directional_light = smoothstep(0.0, max(edge_highlight_angle_fade, 0.01), face_angle);
				float panel_is_left = step(0.5 * (diagonal_start_pixel.x + diagonal_end_pixel.x), crate_center_pixel.x);
				// Classify the brace's edge with a perpendicular line normal. A simple
				// screen-Y offset swaps perceived top/bottom whenever the diagonal slope
				// reverses; the normal stays attached to the physical support.
				vec2 closest_point = brace_start + line_t * delta;
				vec2 line_normal = normalize(vec2(-delta.y, delta.x));
				float normal_side = dot(pixel - closest_point, line_normal);
				float top_sign = line_normal.y < 0.0 ? 1.0 : -1.0;
				float edge_threshold = max((brace_width * 0.5 - 1.0) * abs(line_normal.y), 0.0);
				float upper_edge = step(edge_threshold, top_sign * normal_side);
				float lower_edge = step(edge_threshold, -top_sign * normal_side);
				if (brace_width >= 2.0 && panel_is_left < 0.5 && upper_edge > 0.5) {
					float highlight_fade = authoring_lod_stage >= 1 ? 1.0 : fade_between(diagonal_highlight_full_distance, diagonal_highlight_hidden_distance);
					brace_paint = mix(brace_paint, edge_highlight_color.rgb, directional_light * highlight_fade);
				} else if (brace_width >= 2.0 && panel_is_left > 0.5 && lower_edge > 0.5) {
					brace_paint = mix(brace_paint, inset_shadow_color.rgb, directional_light);
				}
				COLOR = vec4(brace_paint, brace_alpha);
			} else discard;
		}
	}
}
