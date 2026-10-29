shader_type canvas_item;

// Components are actual static meshes. Fragment code chooses colour only;
// there is no height/angle paint-mask that fabricates hoops or staves.
uniform int component = 0;
uniform vec2 camera_origin;
uniform vec2 camera_forward;
uniform vec2 camera_right;
uniform vec2 projection_offset;
uniform vec2 barrel_center;
uniform float barrel_radius;
uniform float barrel_height;
uniform float barrel_swell;
uniform float interior_radius_fraction;
uniform float lower_hoop_height;
uniform float upper_hoop_height;
uniform float hoop_width_pixels;
uniform float rim_highlight_width_pixels;
uniform float interior_rim_width_pixels;
uniform float stave_shadow_width_pixels;
uniform float stave_highlight_width_pixels;
uniform float stave_silhouette_cutoff;
uniform float lid_stave_width_pixels;
uniform float floor_shadow_radius;
uniform float floor_shadow_opacity;
uniform float stave_bottom_light;
uniform float stave_top_light;
uniform float camera_distance;
uniform float interior_full_opening_pixels;
uniform float interior_hidden_opening_pixels;
uniform float stave_detail_full_distance;
uniform float stave_detail_hidden_distance;
uniform float hoop_accent_full_distance;
uniform float hoop_accent_hidden_distance;
uniform float hoop_highlight_full_distance;
uniform float hoop_highlight_hidden_distance;
uniform float hoop_shadow_full_distance;
uniform float hoop_shadow_hidden_distance;
uniform float rim_highlight_full_distance;
uniform float rim_highlight_hidden_distance;
uniform float rim_width_full_distance;
uniform float rim_one_pixel_distance;
uniform float floor_shadow_full_distance;
uniform float floor_shadow_hidden_distance;
uniform vec4 wood_edge : source_color;
uniform vec4 wood_centre : source_color;
uniform vec4 interior_colour : source_color;
uniform vec4 interior_shadow_colour : source_color;
uniform vec4 interior_highlight_colour : source_color;
uniform vec4 lid_colour : source_color;
uniform vec4 lid_stave_colour : source_color;
uniform vec4 lid_stave_highlight_colour : source_color;
uniform float lid_radius_fraction;
uniform float lid_height_fraction;
uniform vec4 rim_colour : source_color;
uniform vec4 rim_highlight_colour : source_color;
uniform vec4 metal_dark : source_color;
uniform vec4 metal_light : source_color;
uniform vec4 hoop_shadow_colour : source_color;
uniform vec4 hoop_highlight_colour : source_color;
uniform vec4 stave_shadow_colour : source_color;
uniform vec4 stave_highlight_colour : source_color;
uniform vec4 floor_shadow_colour : source_color;

varying float cage_facing;
varying float cage_height;
// Used only by the side-stave groove. It lets the fragment stage select one
// logical pixel from the projected seam rather than trusting a narrow quad's
// fractional coverage, which can otherwise paint two adjacent pixels.
varying vec2 seam_centre;
varying vec2 seam_near_direction;
varying float rim_current_width;

float distance_visibility(float full_distance, float hidden_distance) {
	return 1.0 - smoothstep(full_distance, hidden_distance, camera_distance);
}

float top_opening_logical_pixels() {
	// The two extrema are the near and far points of the top ring along the
	// viewing direction. Their projected separation is the apparent thickness
	// of the opening, calculated entirely in the shader from existing uniforms.
	vec2 centre_relative = barrel_center - camera_origin;
	float centre_depth = max(dot(centre_relative, camera_forward), 0.02);
	float near_depth = max(centre_depth - barrel_radius, 0.02);
	float far_depth = max(centre_depth + barrel_radius, 0.02);
	float top_y = 0.5 - barrel_height;
	return abs(top_y / near_depth * 128.0 - top_y / far_depth * 128.0);
}

// Returns logical screen position plus camera depth for one ordinary cage
// point. Stave bevels use the neighboring points to decide which side of a
// vertical edge belongs to the nearer panel and which belongs to the farther.
vec3 project_outer_cage(float side, float height_fraction) {
	float angle = side * TAU / 8.0;
	vec2 radial = vec2(cos(angle), sin(angle));
	float swell = 1.0 + barrel_swell * sin(PI * height_fraction);
	vec2 world = barrel_center + radial * barrel_radius * swell;
	vec2 relative = world - camera_origin;
	float depth = max(dot(relative, camera_forward), 0.02);
	return vec3(vec2(80.0 + dot(relative, camera_right) / depth * 128.0, 31.5 + (0.5 - barrel_height * height_fraction) / depth * 128.0) + projection_offset, depth);
}

vec2 project_lid_point(float side, float radial_fraction) {
	float angle = side * TAU / 8.0;
	vec2 radial = vec2(cos(angle), sin(angle));
	float swell = 1.0 + barrel_swell * sin(PI * lid_height_fraction);
	vec2 world = barrel_center + radial * barrel_radius * swell * lid_radius_fraction * radial_fraction;
	vec2 relative = world - camera_origin;
	float depth = max(dot(relative, camera_forward), 0.02);
	return vec2(80.0 + dot(relative, camera_right) / depth * 128.0, 31.5 + (0.5 - barrel_height * lid_height_fraction) / depth * 128.0) + projection_offset;
}

vec2 project_lid_local_point(vec2 local_point) {
	float swell = 1.0 + barrel_swell * sin(PI * lid_height_fraction);
	vec2 world = barrel_center + local_point * barrel_radius * swell * lid_radius_fraction;
	vec2 relative = world - camera_origin;
	float depth = max(dot(relative, camera_forward), 0.02);
	return vec2(80.0 + dot(relative, camera_right) / depth * 128.0, 31.5 + (0.5 - barrel_height * lid_height_fraction) / depth * 128.0) + projection_offset;
}

vec2 top_rim_parallel_inset(float side, vec2 current_projected, vec2 top_centre, float inset_width_pixels) {
	// Offset the adjacent screen-space polygon edges inward and use their
	// shared corner direction. Unlike a radial pull, this preserves a parallel
	// inner octagon at large widths instead of shearing the apparent rim.
	vec2 previous = project_outer_cage(mod(side + 7.0, 8.0), 1.0).xy;
	vec2 next = project_outer_cage(mod(side + 1.0, 8.0), 1.0).xy;
	vec2 toward_centre = normalize(top_centre - current_projected);
	vec2 previous_edge = normalize(current_projected - previous);
	vec2 next_edge = normalize(next - current_projected);
	vec2 normal_a = vec2(-previous_edge.y, previous_edge.x);
	vec2 normal_b = vec2(-next_edge.y, next_edge.x);
	if (dot(normal_a, toward_centre) < 0.0) normal_a = -normal_a;
	if (dot(normal_b, toward_centre) < 0.0) normal_b = -normal_b;
	vec2 bisector = normalize(normal_a + normal_b);
	float corner_scale = inset_width_pixels / max(dot(bisector, normal_a), 0.10);
	return bisector * min(corner_scale, length(top_centre - current_projected) * 0.98);
}

void vertex() {
	float side = VERTEX.x;
	float height_fraction = VERTEX.y;
	bool band = component >= 5 && component <= 10;
	if (component >= 5 && component <= 7) height_fraction = lower_hoop_height;
	if (component >= 8 && component <= 10) height_fraction = upper_hoop_height;
	if (component == 11 || component == 12) height_fraction = 1.0;
	if (component == 14 || component == 15) height_fraction = lid_height_fraction;
	if (component == 2) height_fraction = 0.0;
	float angle = side * TAU / 8.0;
	vec2 radial = vec2(cos(angle), sin(angle));
	float radial_scale = 1.0;
	if (component == 1) radial_scale = interior_radius_fraction;
	if (component == 14 || component == 15) radial_scale = VERTEX.y * lid_radius_fraction;
	float swell = 1.0 + barrel_swell * sin(PI * height_fraction);
	vec2 world = barrel_center + radial * barrel_radius * swell * radial_scale;
	vec2 relative = world - camera_origin;
	float depth = max(dot(relative, camera_forward), 0.02);
	vec2 projected = vec2(80.0 + dot(relative, camera_right) / depth * 128.0, 31.5 + (0.5 - barrel_height * height_fraction) / depth * 128.0) + projection_offset;
	float vertical_offset = 0.0;
	seam_centre = projected;
	seam_near_direction = vec2(1.0, 0.0);
	rim_current_width = interior_rim_width_pixels;
	if (component == 3 || component == 4 || component == 13) {
		float previous_side = mod(side + 7.0, 8.0);
		float next_side = mod(side + 1.0, 8.0);
		vec3 previous_point = project_outer_cage(previous_side, height_fraction);
		vec3 next_point = project_outer_cage(next_side, height_fraction);
		// The direction from this seam toward its nearer adjacent panel. This
		// makes the shadow and highlight land on opposite sides of the seam,
		// instead of being two competing centred lines.
		vec2 nearer_panel = previous_point.z < next_point.z ? previous_point.xy : next_point.xy;
		vec2 near_direction = normalize(nearer_panel - projected);
		seam_centre = projected;
		seam_near_direction = near_direction;
		if (component == 13) {
			// Cover enough area for the fragment test below, then choose exactly one
			// logical pixel on the centreline. A nominal one-pixel geometry strip can
			// otherwise straddle two pixel centres after projection.
			projected += near_direction * (UV.x * 2.0 - 1.0) * 1.25;
		} else {
			float width = component == 3 ? stave_shadow_width_pixels : stave_highlight_width_pixels;
			// Start each optional bevel at the edge of the one-pixel groove. The
			// previous 0.15 offset made it overlap the core, so z-order decided
			// which colour won on a given logical pixel.
			float side_distance = 0.5 + UV.x * width;
			projected += near_direction * side_distance * (component == 3 ? 1.0 : -1.0);
		}
	}
	if (band) {
		float hoop_span = max(hoop_accent_hidden_distance - hoop_accent_full_distance, 0.01);
		// One artist-facing near/far range, with three ordered events inside it:
		// bright edge fades first, the structural band narrows second, and the
		// dark contact shadow is the last optional detail to disappear.
		float core_start = hoop_accent_full_distance + hoop_span * 0.35;
		float core_end = hoop_accent_full_distance + hoop_span * 0.70;
		float hoop_core_width_visibility = distance_visibility(core_start, core_end);
		// Hoops are structural: near view uses the artist's logical-pixel width;
		// distance reduces them to one pixel but never removes the metal band.
		float core_width = max(1.0, mix(1.0, hoop_width_pixels, hoop_core_width_visibility));
		float width = core_width;
		if (component == 5 || component == 8 || component == 7 || component == 10) {
			// Accent meshes are deliberately one logical pixel regardless of the
			// metal core's width. Put them immediately outside the core, rather
			// than overlapping it as a second thick stripe.
			width = 1.0;
			float accent_centre = component == 5 || component == 8 ? core_width * 0.5 + 0.5 : -core_width * 0.5 - 0.5;
			vertical_offset = accent_centre + (UV.x * 2.0 - 1.0) * width * 0.5;
		} else {
			vertical_offset = (UV.x * 2.0 - 1.0) * width * 0.5;
		}
	}
	if (component == 2) {
		// A fixed one-logical-pixel lower-rim edge. Unlike the old floor fan,
		// this follows the barrel's projected bottom ring rather than extending
		// onto the floor.
		vertical_offset = (UV.x * 2.0 - 1.0) * 0.5;
	}
	if (component == 11 || component == 12) {
		// The actual annulus geometry narrows over its own artist-controlled
		// distance range. The rim highlight has independent timing.
		float rim_width_visibility = distance_visibility(rim_width_full_distance, rim_one_pixel_distance);
		rim_current_width = max(1.0, mix(1.0, interior_rim_width_pixels, rim_width_visibility));
		// A top-plane annulus: UV.x=0 is the outer rim, UV.x=1 is the
		// inward edge. Clamping makes even a very wide rim stop at centre.
		vec2 centre_relative = barrel_center - camera_origin;
		float centre_depth = max(dot(centre_relative, camera_forward), 0.02);
		vec2 top_centre = vec2(80.0 + dot(centre_relative, camera_right) / centre_depth * 128.0, 31.5 + (0.5 - barrel_height) / centre_depth * 128.0) + projection_offset;
		projected += top_rim_parallel_inset(side, projected, top_centre, rim_current_width) * UV.x;
	}
	if (component == 15) {
		projected = project_lid_local_point(VERTEX);
		// Use one canonical bottom-to-top chord direction for every vertex in the
		// seam. Deriving it from the opposite endpoint reversed the vector at the
		// far end, flipped the bevel normal, and literally crossed the ribbon.
		vec2 chord_bottom = project_lid_local_point(vec2(VERTEX.x, -1.0));
		vec2 chord_top = project_lid_local_point(vec2(VERTEX.x, 1.0));
		vec2 line_direction = normalize(chord_top - chord_bottom);
		// Shadow and highlight are two halves of this *one* ribbon. Keeping them
		// in a single projected primitive prevents independent raster edges from
		// drifting, crossing, or z-overwriting each other.
		float total_bevel_width = max(1.0, lid_stave_width_pixels * 2.0);
		projected += vec2(-line_direction.y, line_direction.x) * (UV.x * 2.0 - 1.0) * total_bevel_width * 0.5;
	}
	VERTEX = projected + vec2(0.0, vertical_offset);
	cage_facing = dot(radial, normalize(camera_origin - barrel_center));
	cage_height = height_fraction;
}

void fragment() {
	float stave_visibility = distance_visibility(stave_detail_full_distance, stave_detail_hidden_distance);
	float hoop_span = max(hoop_accent_hidden_distance - hoop_accent_full_distance, 0.01);
	float hoop_highlight_visibility = distance_visibility(hoop_highlight_full_distance, hoop_highlight_hidden_distance);
	float hoop_shadow_visibility = distance_visibility(hoop_shadow_full_distance, hoop_shadow_hidden_distance);
	float rim_span = max(rim_highlight_hidden_distance - rim_highlight_full_distance, 0.01);
	float rim_highlight_end = rim_highlight_full_distance + rim_span * 0.35;
	float rim_highlight_visibility = distance_visibility(rim_highlight_full_distance, rim_highlight_end);
	float floor_shadow_visibility = distance_visibility(floor_shadow_full_distance, floor_shadow_hidden_distance);
	// The artist chooses where a stave seam has fully disappeared at the side
	// silhouette. It retains a small inward fade so the end does not pop.
	float stave_silhouette_visibility = smoothstep(stave_silhouette_cutoff, min(stave_silhouette_cutoff + 0.26, 0.99), cage_facing);
	// Lid seams cannot describe boards once the lid is only a few logical
	// pixels tall. Remove them before their endpoints alias into a crown above
	// the barrel silhouette at distance.
	float lid_seam_visibility = stave_visibility * smoothstep(3.0, 5.0, top_opening_logical_pixels());
	if (component == 13) {
		vec2 logical_pixel_centre = floor(FRAGCOORD.xy) + vec2(0.5);
		float seam_side = dot(logical_pixel_centre - seam_centre, seam_near_direction);
		// The half-open interval deterministically selects one side when a seam
		// happens to land exactly on a logical-pixel boundary.
		if (seam_side < -0.5 || seam_side >= 0.5) discard;
	}
	// CanvasItem has no depth buffer between these projected cage faces.  The
	// rear half must therefore be rejected here, just as a 3D back-face pass
	// would reject it before rasterization.  This is visibility culling, not a
	// decorative paint mask: the surviving pixels still come from real panels.
	if (component == 0 && cage_facing < -0.05) discard;
	// The inner surface is seen on the opposite half of the same cylinder. Its
	// normal is reversed, so the far/back cage panels are the camera-facing
	// interior wall, while the near/front panels are hidden by the outer wood.
	if (component == 1 && cage_facing > 0.05) discard;
	if ((component == 2 || (component >= 5 && component <= 10)) && cage_facing < -0.12) discard;
	if (component == 11 && cage_facing < -0.12) discard;
	// Indentation marks stop before the silhouette. At grazing angles a stave
	// would hide its own groove, and allowing it through made lines poke over
	// the hoop ends.
	if ((component == 3 || component == 4 || component == 13) && cage_facing < stave_silhouette_cutoff) discard;
	// Fine light/shadow accents disappear before the body. This keeps distant
	// barrels legible instead of turning their few pixels into noisy stripes.
	if (component == 2 && floor_shadow_visibility <= 0.01) discard;
	if ((component == 3 || component == 4 || component == 13) && stave_visibility <= 0.01) discard;
	if (component == 15 && lid_seam_visibility <= 0.01) discard;
	// At a one-pixel bevel width there is no room for a second dark strip without
	// making the crack read two pixels wide. Keep the centre groove as the dark
	// side, but retain the far-side highlight: it is the readable board edge.
	if (component == 3 && stave_shadow_width_pixels < 2.0) discard;
	if ((component == 5 || component == 8) && hoop_shadow_visibility <= 0.01) discard;
	if ((component == 7 || component == 10) && hoop_highlight_visibility <= 0.01) discard;
	if (component == 11 && rim_highlight_visibility <= 0.01) discard;
	if (component == 0) {
		float centre_light = clamp(0.28 + max(cage_facing, 0.0) * 0.72, 0.0, 1.0);
		// The outside wood panels are the staves. These two artist controls make
		// their shared bottom-to-top gradient explicit, rather than burying it in
		// fixed shader constants.
		float vertical_light = mix(stave_bottom_light, stave_top_light, cage_height);
		COLOR = vec4(mix(wood_edge.rgb, wood_centre.rgb, centre_light) * vertical_light, 1.0);
	} else if (component == 1) {
		float opening_visibility = smoothstep(interior_hidden_opening_pixels, interior_full_opening_pixels, top_opening_logical_pixels());
		if (opening_visibility <= 0.01) discard;
		// This is the same reverse-facing cage as the outer body.  On the inner
		// surface, -cage_facing is greatest at the far-centre wall and height is
		// greatest near the rim: together they make the opening read as round and
		// deep without sampling a painted texture.
		float far_centre = clamp(-cage_facing, 0.0, 1.0);
		float top_light = mix(0.18, 1.0, cage_height);
		float interior_light = clamp(far_centre * top_light, 0.0, 1.0);
		vec3 dark_interior = mix(interior_shadow_colour.rgb, interior_colour.rgb, 0.32);
		COLOR = vec4(mix(dark_interior, interior_highlight_colour.rgb, interior_light), opening_visibility);
	} else if (component == 2) {
		// Fade to transparent at the side silhouette, just like the top rim
		// highlight. This makes the dark edge describe roundness instead of a
		// flat outline traced around the entire octagon.
		float bottom_rim_arc = pow(clamp(cage_facing, 0.0, 1.0), 1.5);
		COLOR = vec4(floor_shadow_colour.rgb, floor_shadow_colour.a * floor_shadow_opacity * floor_shadow_visibility * bottom_rim_arc);
	} else if (component == 13) {
		COLOR = vec4(stave_shadow_colour.rgb * mix(stave_bottom_light, stave_top_light, cage_height), stave_shadow_colour.a * stave_silhouette_visibility * stave_visibility);
	} else if (component == 3) {
		COLOR = vec4(stave_shadow_colour.rgb * mix(stave_bottom_light, stave_top_light, cage_height), stave_shadow_colour.a * stave_silhouette_visibility * stave_visibility);
	} else if (component == 4) {
		COLOR = vec4(stave_highlight_colour.rgb * mix(stave_bottom_light, stave_top_light, cage_height), stave_highlight_colour.a * stave_silhouette_visibility * stave_visibility);
	} else if (component == 11) {
		// The highlight is a narrow outer slice of the same annulus as the
		// rim—not a separate vertically-offset ribbon—so its seams stay locked.
		if (UV.x > min(rim_highlight_width_pixels / max(rim_current_width, 0.01), 1.0)) discard;
		float rim_arc_highlight = pow(clamp(cage_facing, 0.0, 1.0), 1.5);
		COLOR = vec4(rim_highlight_colour.rgb, rim_highlight_colour.a * rim_arc_highlight * rim_highlight_visibility);
	} else if (component == 12) {
		COLOR = rim_colour;
	} else if (component == 14) {
		COLOR = lid_colour;
	} else if (component == 15) {
		// UV.x selects a stable dark and light half within the same seam ribbon.
		vec4 lid_bevel_colour = mix(lid_stave_colour, lid_stave_highlight_colour, step(0.5, UV.x));
		COLOR = vec4(lid_bevel_colour.rgb, lid_bevel_colour.a * lid_seam_visibility);
	} else if (component == 5 || component == 8) {
		COLOR = vec4(hoop_shadow_colour.rgb, hoop_shadow_colour.a * hoop_shadow_visibility);
	} else if (component == 7 || component == 10) {
		float hoop_arc_highlight = pow(clamp(cage_facing, 0.0, 1.0), 1.5);
		COLOR = vec4(hoop_highlight_colour.rgb, hoop_highlight_colour.a * hoop_arc_highlight * hoop_highlight_visibility);
	} else {
		// One side-to-side metal gradient follows the visible barrel arc: the
		// left/right silhouette stays dark while the camera-facing middle shines.
		// Do not use UV.x here: it runs top-to-bottom across a hoop's thickness.
		// A linear facing value made the wide, visible arc read almost uniformly
		// light.  Bias it toward the dark endpoint so only the small directly
		// camera-facing centre catches the bright metal colour.
		float side_to_side_light = pow(clamp(cage_facing, 0.0, 1.0), 3.0);
		COLOR = mix(metal_dark, metal_light, side_to_side_light);
	}
}
