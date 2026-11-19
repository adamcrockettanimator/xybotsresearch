shader_type canvas_item;
render_mode unshaded;

// One full native-resolution CanvasItem per visible wall.  Projective UVs are
// evaluated by the GPU, leaving GDScript responsible only for visibility and
// the three inverse-homography rows.  This deliberately avoids the uniform
// array that made the earlier batched shader unreliable on the Windows driver.

// Mipmaps are generated once by the runtime renderer whenever the active wall
// texture changes.  The shader selects a discrete level per output pixel so
// the GPU wall pass keeps the chunky, stable look of the CPU experiment.
uniform sampler2D base_texture : filter_nearest_mipmap;
uniform sampler2D layer1_texture : filter_nearest_mipmap;
uniform sampler2D layer2_texture : filter_nearest_mipmap;
// Artist-authored exterior window prop layers. They are deliberately separate
// textures so the frame, glass, and rear shadow can move at three depths.
uniform sampler2D window_frame_texture : filter_nearest;
uniform sampler2D window_glass_texture : filter_nearest;
uniform sampler2D window_shadow_texture : filter_nearest;
uniform bool use_layer_parallax = false;
uniform bool clamp_layer_edges = true;
uniform bool use_integer_uv_scale_snap = true;
// Width, in the game's logical pixels, below which a semantic lattice stroke
// may not shrink. Kept as a shader parameter so this LOD policy can be tuned
// independently of the wallpaper colors and repeat size.
uniform float semantic_lattice_min_logical_line_width = 0.25;
// EWA-style Gaussian footprint for the semantic wallpaper only. The lattice is
// procedural, so its low-frequency coverage is an implicit final mip level;
// no second authored image or bitmap mip chain is required.
uniform bool use_semantic_lattice_anisotropic_filter = true;
// Affects only depth-light band transitions, never the semantic wallpaper
// pattern itself. This makes it possible to inspect its visual contribution.
uniform bool use_depth_light_dither = true;
// Debug view: draw only the depth-light dither in grayscale, independent of
// wallpaper color or material pattern.
uniform bool show_depth_light_dither_debug = false;
// Opt-in experiment for the pictured wall material.  Its bands and repeated
// motifs are evaluated from wall-space coordinates, so panels reduce by one
// screen pixel at a time under projective recession instead of being averaged
// into a conventional 2x mip level.
uniform bool use_semantic_wall_material = false;
// The game view is authored at 160Ãƒâ€”120 then nearest-upscaled.  Quantizing the
// *screen-space homography lookup* to that lattice is what gives GPU walls the
// same large, intentional pixels as the CPU composited floor/ceiling pass.
uniform bool quantize_logical_pixels = true;
uniform vec3 inverse_row0 = vec3(1.0, 0.0, 0.0);
uniform vec3 inverse_row1 = vec3(0.0, 1.0, 0.0);
uniform vec3 inverse_row2 = vec3(0.0, 0.0, 1.0);
uniform vec2 base_texture_size = vec2(128.0, 88.0);
uniform vec2 layer_texture_size = vec2(128.0, 88.0);
// The renderer supplies the owning maze cell for each projected wall. This
// makes room-scale wallpaper selection independent of UV orientation.
uniform vec2 cell_world = vec2(0.0);
// Independent semantic-window depth displacement. Unlike the legacy full-wall
// layers, this remains active even while wallpaper parallax is disabled.
uniform vec2 window_parallax_offset = vec2(0.0);
uniform vec2 window_asset_size = vec2(36.0, 40.0);
uniform bool show_exterior_window = false;
#include "res://scripts/coordinate_frame_daylight.gdshaderinc"
#include "res://scripts/town_storefront_projection.gdshaderinc"
#include "res://scripts/town_rectangular_slats.gdshaderinc"
uniform vec2 layer1_offset = vec2(0.0);
uniform vec2 layer2_offset = vec2(0.0);
uniform vec2 wall_depths = vec2(1.0);
// Each fragment intersects this real camera-local wall segment. This is the
// same camera-ray projection used for the horizontal world planes; no endpoint
// is ever near-clamped or geometrically clipped for the wall renderer.
uniform vec2 wall_local_a = vec2(-0.5, 1.0);
uniform vec2 wall_local_b = vec2(0.5, 1.0);
uniform float camera_height = 0.5;
uniform vec2 face_top = vec2(0.6666667);
uniform float face_bottom = 0.0;
uniform int storefront_paint = 0;
uniform bool storefront_window = false;
uniform bool storefront_glass_broken = false;

uniform vec4 storefront_glass_tint : source_color;
uniform vec4 storefront_glass_shine : source_color;
uniform vec2 storefront_glass_shine_width;
uniform float storefront_glass_fragment_reach;
uniform vec4 storefront_window_aperture;
uniform vec2 storefront_window_mullion;
uniform float storefront_window_recess;
uniform vec4 storefront_siding : source_color;
uniform vec4 storefront_trim : source_color;
// Casing at endpoints A and B, door head height, and casing width.
uniform vec4 door_casing;
uniform vec2 door_frame_center;
uniform float door_reveal_width;
uniform float door_panel_depth;
uniform vec4 storefront_foundation : source_color;
uniform vec4 storefront_metal : source_color;
uniform float focal_length = 128.0;
uniform float horizon_y = 31.5;
uniform vec2 projection_offset = vec2(0.0);
uniform float light_dither_near_half_width_pixels = 3.0;
uniform float light_dither_far_half_width_pixels = 1.0;
uniform int light_dither_steps = 4;
// 0 = continuous gradient; 2, 4, and 8 select ordered Bayer matrices.
uniform int light_dither_matrix_size = 2;
// -1 darkens a recessed (concave) endpoint, +1 lights an exposed (convex)
// endpoint. Zero leaves a straight continuation unmarked.
uniform vec2 endpoint_corner_tones = vec2(0.0);
uniform float convex_highlight_factor = 1.12;
uniform float concave_crevice_factor = 0.58;
uniform float wall_opacity = 1.0;
uniform bool use_camera_cutaway_fade = false;
uniform vec2 wall_world_a = vec2(0.0);
uniform vec2 wall_world_b = vec2(0.0);
uniform vec2 cutaway_contact_a = vec2(0.0);
uniform vec2 cutaway_contact_b = vec2(0.0);
uniform float cutaway_inner_radius = 0.0;
uniform float cutaway_fade_width = 0.01;
uniform vec2 canvas_size = vec2(160.0, 120.0);

vec2 homography_uv(vec2 pixel) {
	vec3 homogeneous = vec3(
		dot(inverse_row0, vec3(pixel, 1.0)),
		dot(inverse_row1, vec3(pixel, 1.0)),
		dot(inverse_row2, vec3(pixel, 1.0))
	);
	return homogeneous.xy / homogeneous.z;
}

float cross2(vec2 a, vec2 b) {
	return a.x * b.y - a.y * b.x;
}

// Return the source UV and physical forward depth for the screen ray. Rays
// with no positive intersection simply do not own this wall pixel.
bool wall_ray_uv(vec2 pixel, out vec2 source_uv, out float depth) {
	vec2 ray = vec2((pixel.x - canvas_size.x * 0.5 - projection_offset.x) / focal_length, 1.0);
	vec2 segment = wall_local_b - wall_local_a;
	float denominator = cross2(ray, segment);
	if (abs(denominator) < 0.000001) return false;
	depth = cross2(wall_local_a, segment) / denominator;
	float segment_u = cross2(wall_local_a, ray) / denominator;
	if (depth <= 0.0 || segment_u < 0.0 || segment_u > 1.0) return false;
	float world_height = camera_height - (pixel.y - horizon_y - projection_offset.y) * depth / focal_length;
	float top = mix(face_top.x, face_top.y, segment_u);
	if (world_height < face_bottom || world_height > top) return false;
	source_uv = vec2(segment_u, (top - world_height) / (top - face_bottom));
	return true;
}

float bayer2(vec2 pixel) {
	float x = mod(floor(pixel.x), 2.0);
	float y = mod(floor(pixel.y), 2.0);
	return 2.0 * x + 3.0 * y - 4.0 * x * y;
}

float bayer2_threshold(vec2 pixel) {
	return (bayer2(pixel) + 0.5) / 4.0;
}

float bayer4_threshold(vec2 pixel) {
	vec2 p = mod(floor(pixel), 4.0);
	float low_digit = bayer2(mod(p, 2.0));
	float high_digit = bayer2(floor(p * 0.5));
	return (low_digit * 4.0 + high_digit + 0.5) / 16.0;
}

float bayer8_threshold(vec2 pixel) {
	vec2 p = mod(floor(pixel), 8.0);
	float low_digit = bayer2(mod(p, 2.0));
	float middle_digit = bayer2(mod(floor(p * 0.5), 2.0));
	float high_digit = bayer2(floor(p * 0.25));
	return (low_digit * 16.0 + middle_digit * 4.0 + high_digit + 0.5) / 64.0;
}

float depth_dither_threshold(vec2 pixel) {
	if (light_dither_matrix_size >= 8) return bayer8_threshold(pixel);
	if (light_dither_matrix_size >= 4) return bayer4_threshold(pixel);
	return bayer2_threshold(pixel);
}

// Match the floor's distance bands and intermediate Bayer-dithered levels.
float depth_light_dither(float depth, vec2 pixel) {
	float thresholds[5] = float[](1.35, 2.5, 3.8, 4.8, 5.2);
	float near_lights[5] = float[](1.0, 0.78, 0.56, 0.36, 0.22);
	float far_lights[5] = float[](0.78, 0.56, 0.36, 0.22, 0.10);
	float depth_per_pixel = max(depth * depth / (camera_height * focal_length), 0.0001);
	float near_weight = 1.0 - clamp((depth - 1.35) / (5.2 - 1.35), 0.0, 1.0);
	float half_band = depth_per_pixel * mix(light_dither_far_half_width_pixels, light_dither_near_half_width_pixels, near_weight);
	for (int index = 0; index < 5; index++) {
		float threshold = thresholds[index];
		if (depth < threshold - half_band) return near_lights[index];
		if (depth <= threshold + half_band) {
			float coverage = clamp((depth - (threshold - half_band)) / (half_band * 2.0), 0.0, 1.0);
			if (light_dither_matrix_size <= 0) {
				return mix(near_lights[index], far_lights[index], coverage);
			}
			float scaled_step = coverage * float(light_dither_steps);
			int lower_step = clamp(int(floor(scaled_step)), 0, light_dither_steps);
			int upper_step = min(lower_step + 1, light_dither_steps);
			int selected_step = fract(scaled_step) >= depth_dither_threshold(pixel) ? upper_step : lower_step;
			return mix(near_lights[index], far_lights[index], float(selected_step) / float(light_dither_steps));
		}
	}
	return 0.10;
}

// The exact same authored depth-light palette with hard, non-dithered band
// transitions. This is used only for the live comparison toggle above.
float depth_light(float depth) {
	float thresholds[5] = float[](1.35, 2.5, 3.8, 4.8, 5.2);
	float near_lights[5] = float[](1.0, 0.78, 0.56, 0.36, 0.22);
	for (int index = 0; index < 5; index++) {
		if (depth < thresholds[index]) return near_lights[index];
	}
	return 0.10;
}

vec4 nearest_sample(sampler2D source, vec2 source_uv, vec2 source_size, bool clamp_to_edge, float mip_level) {
	if (clamp_to_edge) {
		source_uv = clamp(source_uv, vec2(0.0), vec2(1.0));
	} else if (source_uv.x < 0.0 || source_uv.x > 1.0 || source_uv.y < 0.0 || source_uv.y > 1.0) {
		return vec4(0.0);
	}
	float level_scale = exp2(mip_level);
	vec2 mip_size = max(vec2(1.0), floor(source_size / level_scale));
	vec2 texel = floor(source_uv * mip_size) + vec2(0.5);
	texel = clamp(texel, vec2(0.5), mip_size - vec2(0.5));
	return textureLod(source, texel / mip_size, mip_level);
}

// The current 128x88 Wall_Layer1 grammar, expressed as semantic regions:
// 0-7 top trim; 8-55 wallpaper; 56-61 chair rail; 62-82 alternating panels;
// 83-87 bottom trim. The wallpaper is intentionally a separate base field plus
// a repeatable overlay. Future rooms can swap the pattern grammar (crisscross,
// flowers, birds, or none) without baking it into a complete wall bitmap.
float lattice_line_coverage(vec2 pattern_position, float half_width) {
	float rising_distance = abs(mod(pattern_position.x + pattern_position.y + 8.0, 16.0) - 8.0);
	float falling_distance = abs(mod(pattern_position.x - pattern_position.y + 8.0, 16.0) - 8.0);
	return min(rising_distance, falling_distance) <= half_width ? 1.0 : 0.0;
}

int wallpaper_quadrant() {
	// The current maze is 6x6. North-west, north-east, south-west, and
	// south-east each receive a deliberately different paper/pattern pair.
	int east = cell_world.x >= 3.0 ? 1 : 0;
	int south = cell_world.y >= 3.0 ? 1 : 0;
	return south * 2 + east;
}

vec3 wallpaper_paper_color() {
	int quadrant = wallpaper_quadrant();
	// NW blue, NE neutral gray, SW original warm gold, SE muted mauve.
	if (quadrant == 0) return vec3(133.0, 143.0, 162.0) / 255.0;
	if (quadrant == 1) return vec3(133.0, 134.0, 140.0) / 255.0;
	if (quadrant == 2) return vec3(158.0, 140.0, 106.0) / 255.0;
	return vec3(126.0, 93.0, 125.0) / 255.0;
}

vec3 wallpaper_lattice_color() {
	int quadrant = wallpaper_quadrant();
	if (quadrant == 0) return vec3(155.0, 165.0, 184.0) / 255.0;
	if (quadrant == 1) return vec3(155.0, 156.0, 164.0) / 255.0;
	if (quadrant == 2) return vec3(171.0, 156.0, 127.0) / 255.0;
	return vec3(145.0, 111.0, 144.0) / 255.0;
}

bool is_exterior_wall() {
	bool horizontal_edge = abs(wall_world_a.y - wall_world_b.y) < 0.001;
	if (horizontal_edge) return wall_world_a.y < 0.001 || wall_world_a.y > 5.999;
	return wall_world_a.x < 0.001 || wall_world_a.x > 5.999;
}

vec4 window_asset_sample(sampler2D asset, vec2 wall_texel) {
	// The supplied 36x40 prop is deliberately mounted at eye level. Its lower
	// portion continues across the chair rail and into the panels below.
	vec2 asset_texel = wall_texel - vec2(46.0, 24.0);
	if (asset_texel.x < 0.0 || asset_texel.y < 0.0 || asset_texel.x >= window_asset_size.x || asset_texel.y >= window_asset_size.y) return vec4(0.0);
	return texture(asset, (floor(asset_texel) + vec2(0.5)) / window_asset_size);
}

vec3 semantic_window_over_wall(vec3 wall_color, vec2 source_uv, vec2 source_size) {
	if (!show_exterior_window || (!use_daylight && !is_exterior_wall())) return wall_color;
	vec2 texel = source_uv * source_size;
	// Each real PNG has its own depth: frame nearest, glass mid, shadow farthest.
	vec4 shadow = window_asset_sample(window_shadow_texture, texel - window_parallax_offset * source_size * 1.10);
	vec4 glass = window_asset_sample(window_glass_texture, texel - window_parallax_offset * source_size * 0.55);
	vec4 frame = window_asset_sample(window_frame_texture, texel);
	vec3 result = mix(wall_color, shadow.rgb, shadow.a);
	result = mix(result, glass.rgb, glass.a);
	return mix(result, frame.rgb, frame.a);
}

float ewa_lattice_coverage(vec2 pattern_position, vec2 span_x, vec2 span_y, float half_width) {
	// The two screen-space UV derivatives form a parallelogram. Sample a
	// Gaussian cross-section of the matching ellipse: a heavy centre, lighter
	// axial taps, and still lighter diagonal taps near the ellipse boundary.
	float center = lattice_line_coverage(pattern_position, half_width);
	float axial = lattice_line_coverage(pattern_position + span_x * 0.5, half_width)
		+ lattice_line_coverage(pattern_position - span_x * 0.5, half_width)
		+ lattice_line_coverage(pattern_position + span_y * 0.5, half_width)
		+ lattice_line_coverage(pattern_position - span_y * 0.5, half_width);
	vec2 diagonal_a = (span_x + span_y) * 0.35;
	vec2 diagonal_b = (span_x - span_y) * 0.35;
	float diagonal = lattice_line_coverage(pattern_position + diagonal_a, half_width)
		+ lattice_line_coverage(pattern_position - diagonal_a, half_width)
		+ lattice_line_coverage(pattern_position + diagonal_b, half_width)
		+ lattice_line_coverage(pattern_position - diagonal_b, half_width);
	float gaussian_coverage = center * 0.28 + axial * 0.10 + diagonal * 0.08;
	// At very large footprints, individual phase samples cannot describe the
	// repeat. Its two thin diagonals cover one quarter of the material, which is
	// the analytic terminal level of this procedural pyramid.
	float major_footprint = max(length(span_x), length(span_y));
	float terminal_level = smoothstep(8.0, 24.0, major_footprint);
	return mix(gaussian_coverage, 0.25, terminal_level);
}

float panel_light_coverage(vec2 panel_position) {
	return mod(floor(panel_position.x / 8.0), 2.0);
}

float ewa_panel_light_coverage(vec2 panel_position, vec2 span_x, vec2 span_y) {
	// Same Gaussian footprint as the wallpaper lattice, evaluated against the
	// semantic light/dark panel field rather than a sampled bitmap.
	float center = panel_light_coverage(panel_position);
	float axial = panel_light_coverage(panel_position + span_x * 0.5)
		+ panel_light_coverage(panel_position - span_x * 0.5)
		+ panel_light_coverage(panel_position + span_y * 0.5)
		+ panel_light_coverage(panel_position - span_y * 0.5);
	vec2 diagonal_a = (span_x + span_y) * 0.35;
	vec2 diagonal_b = (span_x - span_y) * 0.35;
	float diagonal = panel_light_coverage(panel_position + diagonal_a)
		+ panel_light_coverage(panel_position - diagonal_a)
		+ panel_light_coverage(panel_position + diagonal_b)
		+ panel_light_coverage(panel_position - diagonal_b);
	float gaussian_coverage = center * 0.28 + axial * 0.10 + diagonal * 0.08;
	// Equal-width alternating panels have a 50% average at the implicit final
	// procedural pyramid level.
	float major_footprint = max(length(span_x), length(span_y));
	float terminal_level = smoothstep(8.0, 24.0, major_footprint);
	return mix(gaussian_coverage, 0.5, terminal_level);
}

float trim_detail_line_coverage(float source_texel_y, float line_center_y, float y_texels_per_logical_pixel) {
	// Xiaolin Wu coverage for a horizontal one-logical-pixel line. Convert the
	// source-space distance to the projected logical-pixel grid, then share the
	// line's intensity between the two neighboring rows. At an exact row centre
	// one row receives 100%; halfway between rows they receive 50% each.
	float logical_pixel_distance = (source_texel_y - line_center_y) / max(y_texels_per_logical_pixel, 0.0001);
	return max(0.0, 1.0 - abs(logical_pixel_distance));
}

vec4 semantic_wall_material(vec2 source_uv, vec2 source_size, float x_texels_per_logical_pixel, float y_texels_per_logical_pixel, vec2 span_x, vec2 span_y, vec2 pixel, float ray_depth) {
	vec2 texel = floor(source_uv * source_size);
	float y = texel.y;
	float source_texel_y = source_uv.y * source_size.y;
	vec3 trim = vec3(100.0, 80.0, 60.0) / 255.0;
	vec3 trim_highlight = vec3(135.0, 114.0, 86.0) / 255.0;
	// Half the previous shadow contrast against the base trim; highlights stay
	// deliberately unchanged so their crisp edge remains readable.
	vec3 trim_shadow = vec3(79.0, 63.0, 48.0) / 255.0;
	// Detail fades with the actual depth-light value.  The line is still one
	// logical pixel wide while visible, but does not stay conspicuously bright
	// in a nearly black distant corridor.
	float detail_fade = smoothstep(0.18, 0.78, depth_light_dither(ray_depth, pixel));
	if (y < 8.0) return vec4(semantic_window_over_wall(trim, source_uv, source_size), 1.0);
	if (y >= 83.0) {
		float lower_highlight = trim_detail_line_coverage(source_texel_y, 83.5, y_texels_per_logical_pixel);
		return vec4(semantic_window_over_wall(mix(trim, trim_highlight, lower_highlight * detail_fade), source_uv, source_size), 1.0);
	}
	if (y >= 56.0 && y < 62.0) {
		float chair_highlight = trim_detail_line_coverage(source_texel_y, 56.5, y_texels_per_logical_pixel);
		float chair_shadow = trim_detail_line_coverage(source_texel_y, 61.5, y_texels_per_logical_pixel);
		vec3 chair_color = mix(trim, trim_highlight, chair_highlight * detail_fade);
		chair_color = mix(chair_color, trim_shadow, chair_shadow * detail_fade);
		return vec4(semantic_window_over_wall(chair_color, source_uv, source_size), 1.0);
	}
	if (y >= 62.0) {
		// Eight authored texels per panel become 8, 7, 6... logical pixels
		// under perspective. Once a panel is sub-pixel, retain only its field
		// color rather than aliasing a rapidly alternating stripe.
		vec3 dark_panel = vec3(107.0, 86.0, 65.0) / 255.0;
		vec3 light_panel = vec3(135.0, 108.0, 81.0) / 255.0;
		float panel = mod(floor(texel.x / 8.0), 2.0);
		float panel_footprint_major = max(length(span_x), length(span_y));
		float panel_footprint_minor = max(0.001, min(length(span_x), length(span_y)));
		bool panel_needs_ewa = panel_footprint_major > 1.25 && panel_footprint_major / panel_footprint_minor > 1.5;
		if (use_semantic_lattice_anisotropic_filter && panel_needs_ewa) {
			float panel_coverage = ewa_panel_light_coverage(vec2(texel) + vec2(0.5), span_x, span_y);
			return vec4(semantic_window_over_wall(mix(dark_panel, light_panel, panel_coverage), source_uv, source_size), 1.0);
		}
		float projected_panel_width = 8.0 / max(x_texels_per_logical_pixel, 0.0001);
		if (projected_panel_width < 1.0) return vec4(semantic_window_over_wall(mix(dark_panel, light_panel, 0.5), source_uv, source_size), 1.0);
		return vec4(semantic_window_over_wall(mix(dark_panel, light_panel, panel), source_uv, source_size), 1.0);
	}
	// The wallpaper is a dark base with a separate light crisscross overlay.
	// Unlike isolated outlined diamonds, its continuous diagonals retain a
	// useful read at oblique angles without needing to enlarge each motif.
	vec3 paper = wallpaper_paper_color();
	vec3 lattice = wallpaper_lattice_color();
	vec2 pattern_position = vec2(texel.x, y - 8.0) + vec2(0.5);
	// Repeat every 16 source pixels. A two-source-pixel near line becomes one
	// stable logical pixel as distance increases instead of disappearing between
	// samples. The lines continue to converge; only their width is clamped.
	float rising_distance = abs(mod(pattern_position.x + pattern_position.y + 8.0, 16.0) - 8.0);
	float falling_distance = abs(mod(pattern_position.x - pattern_position.y + 8.0, 16.0) - 8.0);
	float nearest_line_distance = min(rising_distance, falling_distance);
	// The authored wallpaper stroke is two source pixels wide.  [ and ] are
	// deliberately *not* its width control: they only impose a screen-space
	// floor once perspective would otherwise shrink this authored stroke below
	// the selected logical-pixel minimum.  Thus a nearby wall is invariant.
	float authored_stroke_half_width = 1.0;
	float projected_minimum_half_width = x_texels_per_logical_pixel * semantic_lattice_min_logical_line_width * 0.5;
	// This is the exact no-filter baseline controlled by [ and ]. Both sides of
	// the anisotropic toggle use it; filtering must not silently choose a
	// different distant wallpaper representation.
	float literal_stroke_half_width = max(authored_stroke_half_width, projected_minimum_half_width);
	// Keep the selected small-line lattice bit-for-bit crisp nearby and when the
	// wall is face-on.  The Gaussian footprint is only useful when perspective
	// has made the projected texel footprint both wide and elliptical.
	float footprint_major = max(length(span_x), length(span_y));
	float footprint_minor = max(0.001, min(length(span_x), length(span_y)));
	bool needs_ewa = footprint_major > 1.25 && footprint_major / footprint_minor > 1.5;
	if (use_semantic_lattice_anisotropic_filter && needs_ewa) {
		// Gaussian EWA-style footprint of the same artist-tuned small-line
		// lattice. The filter changes sampling only, not the LOD grammar.
		float coverage = ewa_lattice_coverage(pattern_position, span_x, span_y, literal_stroke_half_width);
		vec3 wallpaper_color = bayer2_threshold(pixel) < coverage ? lattice : paper;
		float top_trim_shadow = trim_detail_line_coverage(source_texel_y, 8.5, y_texels_per_logical_pixel);
		wallpaper_color = semantic_window_over_wall(wallpaper_color, source_uv, source_size);
		return vec4(mix(wallpaper_color, trim_shadow, top_trim_shadow * detail_fade), 1.0);
	}
	// Direct A/B baseline: the literal minimum-width lattice the user selected
	// with [. Do not fall into any alternate coverage/symbol LOD here.
	vec3 wallpaper_color = nearest_line_distance <= literal_stroke_half_width ? lattice : paper;
	wallpaper_color = semantic_window_over_wall(wallpaper_color, source_uv, source_size);
	float top_trim_shadow = trim_detail_line_coverage(source_texel_y, 8.5, y_texels_per_logical_pixel);
	return vec4(mix(wallpaper_color, trim_shadow, top_trim_shadow * detail_fade), 1.0);
}

uniform vec2 town_camera_origin;
uniform bool use_town_fence = false;
uniform vec2 town_camera_forward;
uniform vec2 town_camera_right;
uniform vec2 fence_post;
uniform float fence_post_half_width;
uniform float fence_rail_half_width;
uniform vec4 fence_heights;

uniform bool use_town_lintel = false;
uniform vec4 storefront_awning_rect;
uniform vec2 storefront_awning_heights;
uniform bool storefront_open_leaf = false;
uniform bool storefront_awning_edge = false;
uniform bool storefront_front_door = false;
// Shared-corner endpoint, overhang height, and timber enable flag.
uniform vec3 porch_timber;
// Edge highlight, ledge contact shadow, and awning shadow strengths.
uniform vec3 timber_lighting;
uniform int storefront_occluder_count = 0;
uniform vec4 storefront_occluders[10];
uniform vec4 storefront_occluder_heights[10];
uniform float storefront_floor_height;
uniform float storefront_facade_base;
uniform bool draw_porch_cap = false;
uniform bool use_projected_wall = true;
uniform vec4 porch_cap_rect;
uniform int storefront_porch_box_count = 0;
uniform vec3 storefront_porch_box_min[6];
uniform vec3 storefront_porch_box_max[6];
uniform float storefront_face_tone = 1.0;

// Rectangular boards meet directly. Each course offsets the longitudinal cuts
// so the color blocks read like floor planks laid across the wall.
vec3 town_siding(vec3 base, float height, vec2 uv, vec2 uv_x, float depth) {
	vec2 segment = wall_world_b - wall_world_a;
	float along = abs(segment.x) > abs(segment.y) ? mix(wall_world_a.x, wall_world_b.x, uv.x) : mix(wall_world_a.y, wall_world_b.y, uv.x);
	// Eight reference pixels per course. Pick one board at the center of
	// each logical pixel, with a distance fade only on the overall contrast.
	float tone = rectangular_slat_tone(vec2(along * 1.05, height * 16.0));
	float footprint = max(16.0 * depth / focal_length, abs(uv_x.x - uv.x) * length(segment) * 1.05);
	float visible = (1.0 - smoothstep(0.57, 1.00, footprint)) * (1.0 - smoothstep(7.0, 12.0, depth));
	return base * mix(0.865, tone, visible);
}

bool storefront_clear_pane(vec2 point) {
	vec2 center = (storefront_window_aperture.xy + storefront_window_aperture.zw) * 0.5;
	return all(greaterThan(point, storefront_window_aperture.xy)) &&
		all(lessThan(point, storefront_window_aperture.zw)) &&
		(storefront_glass_broken || all(greaterThanEqual(abs(point - center), storefront_window_mullion)));
}

// Each triangle has a base on the sash and a point offset along the glass.
float glass_fragment_edge(vec2 p, vec3 triangle) {
	float sideways = (p.x - triangle.x) / triangle.y;
	float taper = max(0.0, min((sideways + 1.0) / 1.32, (1.0 - sideways) / 0.68));
	return taper * triangle.z - p.y;
}

vec4 storefront_broken_glass(float u, float height, float depth, float pane_width) {
	vec2 opening = storefront_window_aperture.zw - storefront_window_aperture.xy;
	vec2 p = (vec2(u, height) - storefront_window_aperture.xy) / opening;
	// Only the outside sash retains fragments once the inner cross has broken.
	float reach = storefront_glass_fragment_reach * 0.58;
	float bottom = glass_fragment_edge(p, vec3(0.26, 0.19, reach));
	float top = glass_fragment_edge(vec2(1.0 - p.x, 1.0 - p.y), vec3(0.16, 0.13, reach * 0.72));
	float side = glass_fragment_edge(p.yx, vec3(0.23, 0.19, reach * 0.9));
	float opposite = glass_fragment_edge(vec2(1.0 - p.y, 1.0 - p.x), vec3(0.36, 0.14, reach * 0.72));
	float edge = max(max(bottom, top), max(side, opposite));
	if (edge <= 0.0) return vec4(0.0);

	float pane_pixels = min(pane_width, opening.y * focal_length / depth);
	float visible = smoothstep(1.75, 5.5, pane_pixels);
	vec3 color = mix(storefront_glass_tint.rgb, storefront_glass_shine.rgb, edge < 0.105 ? 0.94 : 0.55);
	return vec4(color, storefront_glass_shine.a * visible);
}

vec4 storefront_glaze(vec4 wall, vec2 uv, float height, float depth) {
	if (!storefront_window || uv.x <= 0.13 || uv.x >= 0.87 || height <= 0.20 || height >= 0.49) return wall;

	vec2 point = vec2(uv.x, height);
	vec2 opening = storefront_window_aperture.zw - storefront_window_aperture.xy;
	vec2 center = storefront_window_aperture.xy + opening * 0.5;
	vec2 span = wall_world_b - wall_world_a;
	float width = length(span);
	vec2 to_window = 0.5 * (wall_world_a + wall_world_b) - town_camera_origin;
	vec2 normal = normalize(vec2(-span.y, span.x));
	float facing = abs(dot(normal, to_window)) / max(length(to_window), 0.0001);
	float pane_width = (storefront_glass_broken ? opening.x : opening.x * 0.5 - storefront_window_mullion.x) * width * facing * focal_length / depth;
	float detail = smoothstep(2.0, 6.0, pane_width);
	if (!storefront_clear_pane(point)) {
		float pixel_height = depth / focal_length;
		float top_rim = 0.49 - height;
		float sill_rim = storefront_window_aperture.y - height;
		float head_underside = height - storefront_window_aperture.w;
		float cross_rim = center.y + storefront_window_mullion.y - height;
		float cross_underside = height - (center.y - storefront_window_mullion.y);
		bool over_opening = uv.x > storefront_window_aperture.x && uv.x < storefront_window_aperture.z;
		bool rim = top_rim <= pixel_height || (over_opening && sill_rim >= 0.0 && sill_rim < pixel_height);
		bool under = over_opening && head_underside >= 0.0 && head_underside < pixel_height;
		if (!storefront_glass_broken && over_opening) {
			rim = rim || (cross_rim >= 0.0 && cross_rim < pixel_height);
			under = under || (cross_underside >= 0.0 && cross_underside < pixel_height);
		}
		float tone = 1.32 * (1.0 + detail * (timber_lighting.x * float(rim) - timber_lighting.y * float(under)));
		return vec4(storefront_trim.rgb * tone, 1.0);
	}
	if (storefront_glass_broken) return storefront_broken_glass(uv.x, height, depth, pane_width);

	float grazing = smoothstep(0.04, 0.70, 1.0 - facing);
	float half_width = mix(storefront_glass_shine_width.x, storefront_glass_shine_width.y, grazing);
	float across = (uv.x - storefront_window_aperture.x) / opening.x;
	float up = (height - storefront_window_aperture.y) / opening.y;
	float diagonal = up - across * 0.78 - 0.11;
	// Hard masks at the logical pixel center. The softer companion drops out
	// first as the projected glass gets small.
	float main_band = step(abs(diagonal), half_width);
	float companion = step(abs(diagonal + half_width + 0.125), 0.055);
	float shine = max(main_band, companion * 0.52 * smoothstep(6.0, 12.0, pane_width));
	shine *= smoothstep(1.25, 3.0, pane_width);
	vec4 glass = mix(storefront_glass_tint, storefront_glass_shine, shine);
	// Sample the sash silhouette on a plane behind the glass. Oblique rays
	// move its shadow across the pane while the front frame stays in place.
	vec2 camera_to_pane = mix(wall_world_a, wall_world_b, uv.x) - town_camera_origin;
	float normal_distance = max(abs(dot(normal, camera_to_pane)), 0.06);
	vec2 transfer = vec2(dot(camera_to_pane, span) / (width * width) - 1.05, height - camera_height + 0.22);
	vec2 shift = clamp(transfer * storefront_window_recess / normal_distance, vec2(-0.09, -0.023), vec2(0.09, 0.035));
	float shadow_alpha = storefront_clear_pane(point + shift) ? 0.0 : timber_lighting.y * detail;
	float visible_shadow = shadow_alpha * (1.0 - glass.a);
	float alpha = glass.a + visible_shadow;
	return vec4((glass.rgb * glass.a + storefront_trim.rgb * 0.53 * visible_shadow) / max(alpha, 0.0001), alpha);
}

// The two jambs and the strip across the header form one U on the wall cage.
vec4 storefront_door_casing(vec4 wall, vec2 uv, float depth) {
	if (door_casing.x + door_casing.y == 0.0) return wall;
	float height = mix(mix(face_top.x, face_top.y, uv.x), face_bottom, uv.y);
	float width = door_casing.w;
	if (height > door_casing.z + width || height < storefront_floor_height) return wall;

	const float face_tone = 1.32;
	if (door_casing.x + door_casing.y == 2.0) {
		return vec4(storefront_trim.rgb * face_tone, 1.0);
	}
	vec2 span = wall_world_b - wall_world_a;
	float direction = door_casing.x > 0.0 ? 1.0 : -1.0;
	float inset = (direction > 0.0 ? uv.x : 1.0 - uv.x) * length(span);
	if (inset > width) return wall;
	// Only the camera-facing outer return shows beside the front of the jamb.
	vec2 to_camera = normalize(town_camera_origin - door_frame_center);
	float side_view = dot(to_camera, normalize(span) * direction);
	float side_width = width * 0.60 * smoothstep(0.10, 0.82, side_view);
	float side_pixels = side_width * focal_length / depth;
	float side = step(width - inset, side_width) * smoothstep(0.45, 1.35, side_pixels);
	float bevel = mix(face_tone, 1.10, side);
	return vec4(storefront_trim.rgb * bevel, 1.0);
}

bool storefront_wall_blocks_door(vec2 ray, float eye_slope, float door_depth) {
	for (int index = 0; index < storefront_occluder_count; index++) {
		vec4 span = storefront_occluders[index];
		vec4 height_range = storefront_occluder_heights[index];
		vec2 offset = span.xy - town_camera_origin;
		vec2 edge = span.zw - span.xy;
		float denominator = cross2(ray, edge);
		if (abs(denominator) < 0.000001) continue;
		float depth = cross2(offset, edge) / denominator;
		float u = cross2(offset, ray) / denominator;
		if (depth <= 0.0 || depth >= door_depth - 0.001 || u < 0.0 || u > 1.0) continue;
		float height = camera_height - eye_slope * depth;
		if (height < height_range.z || height > mix(height_range.x, height_range.y, u)) continue;
		if (height_range.w > 0.5 && storefront_clear_pane(vec2(u, height))) continue;
		return true;
	}
	return false;
}

vec2 storefront_project_uv(vec2 uv) {
	vec2 local = mix(wall_local_a, wall_local_b, uv.x);
	float height = mix(mix(face_top.x, face_top.y, uv.x), face_bottom, uv.y);
	return vec2(canvas_size.x * 0.5, horizon_y) + projection_offset +
		vec2(local.x, camera_height - height) * focal_length / max(local.y, 0.005);
}

vec4 storefront_door_surface(vec2 uv, vec2 uv_x, vec2 pixel, float depth, out float glint) {
	float board = floor(uv.x * 5.0);
	float visible = 1.0 - smoothstep(0.4, 0.9, abs(uv_x.x - uv.x) * 5.0);
	float tone = rectangular_slat_tone(vec2(0.0, board));
	float dark_tone = rectangular_slat_tone(vec2(0.0));
	vec3 dark_wood = storefront_trim.rgb * mix(0.91, dark_tone * 1.055, visible);
	bool side_board = uv.x <= 0.14 || uv.x >= 0.86;
	bool brace = uv.y < 0.10 || abs(uv.y - 0.55) < 0.05 || uv.y > 0.90;
	vec3 leaf = side_board || brace ? dark_wood : storefront_trim.rgb * mix(0.91, tone * 1.055, visible);

	float height = face_top.x - face_bottom;
	float width = length(wall_world_b - wall_world_a);
	float pixel_v = depth / (focal_length * height);
	float detail = 1.0 - smoothstep(1.9, 3.6, depth);
	if (!side_board) {
		float rim = min(min(uv.y, uv.y < 0.50 ? 1.0 : uv.y - 0.50), uv.y < 0.90 ? 1.0 : uv.y - 0.90);
		float below_ledge = uv.y < 0.60 ? uv.y - 0.10 : uv.y - 0.60;
		float shadow = below_ledge >= 0.0 ? 1.0 - smoothstep(0.0, 0.032, below_ledge) : 0.0;
		if (!brace) {
			vec2 span = wall_world_b - wall_world_a;
			vec2 to_camera = normalize(town_camera_origin - (wall_world_a + wall_world_b) * 0.5);
			float side_view = dot(to_camera, span / width);
			float angle = smoothstep(0.08, 0.80, abs(side_view));
			float far_edge = (side_view >= 0.0 ? uv.x - 0.14 : 0.86 - uv.x) * width;
			float side_shadow = angle * (1.0 - smoothstep(0.0, max(door_panel_depth * angle, 0.0001), far_edge));
			shadow = max(shadow, side_shadow);
		}
		leaf *= 1.0 + detail * (timber_lighting.x * step(rim, pixel_v) - timber_lighting.y * shadow);
	}
	// The jambs, header, and threshold shade the stationary leaf inside the opening.
	if (!storefront_open_leaf) {
		vec2 inset = min(uv, 1.0 - uv) * vec2(width, height);
		float reveal = 1.0 - smoothstep(door_reveal_width * 0.45, door_reveal_width, min(inset.x, inset.y));
		leaf *= 1.0 - 1.35 * timber_lighting.y * reveal;
	}

	glint = 0.0;
	const vec2 knob_uv = vec2(0.85, 0.59);
	if (depth < 4.0 && all(lessThan(abs(uv - knob_uv), vec2(0.27, 0.09)))) {
		vec2 knob_local = mix(wall_local_a, wall_local_b, knob_uv.x);
		vec2 center = storefront_project_uv(knob_uv);
		float radius = 0.023 * focal_length / max(knob_local.y, 0.005);
		vec2 knob = (pixel - center) / radius;
		if (length(knob - vec2(0.32, 0.38)) <= 1.0) leaf *= 0.60;
		if (length(knob) <= 1.0) {
			float shade = 1.0 - 0.20 * smoothstep(0.10, 0.92, dot(knob, vec2(0.58, 0.81)));
			leaf = vec3(0.74, 0.55, 0.27) * shade;
			float knob_pixels = 2.0 * radius;
			vec2 sparkle = center - radius * vec2(0.34, 0.37);
			glint = float(all(equal(floor(pixel), floor(sparkle)))) * step(4.0, knob_pixels);
		}
	}
	return vec4(leaf, 1.0);
}

// Paint cladding first, then the attached trim, glazing, or moving door.
vec4 storefront_surface(vec2 uv, vec2 uv_x, vec2 pixel, float depth, out float glint) {
	glint = 0.0;
	float top = mix(face_top.x, face_top.y, uv.x);
	float height = mix(top, face_bottom, uv.y);
	if (storefront_paint == 2) return vec4(storefront_trim.rgb * storefront_face_tone, storefront_trim.a);
	if (storefront_paint == 4) {
		if (storefront_awning_edge) {
			float course = (mix(wall_world_a.x, wall_world_b.x, uv.x) - storefront_awning_rect.x) * 16.0;
			float visible = (1.0 - smoothstep(2.0, 6.5, depth)) * (1.0 - smoothstep(0.29, 0.70, abs(uv_x.x - uv.x) * 16.0));
			float tone = mix(0.865, rectangular_slat_tone(vec2(0.0, course)), visible);
			return vec4(storefront_metal.rgb * tone * 0.82, 1.0);
		}
		float rib = fract(uv.x * 13.0);
		float detail = 1.0 - smoothstep(2.0, 6.0, depth);
		return vec4(storefront_metal.rgb * mix(0.9, rib < 0.26 ? 1.23 : (uv.y > 0.69 ? 0.63 : 0.97), detail), 1.0);
	}
	if (storefront_paint == 3) {
		return storefront_door_surface(uv, uv_x, pixel, depth, glint);
	}
	vec3 color = town_siding(storefront_siding.rgb, height, uv, uv_x, depth);
	if (height < 0.065) {
		color = storefront_foundation.rgb;
		if (height > 0.052) color *= mix(0.83, 1.0, smoothstep(2.0, 5.0, depth));
	}
	if (top - height < 0.042) color = storefront_trim.rgb;
	return storefront_glaze(vec4(color, 1.0), uv, height, depth);
}

float porch_timber_tone(vec2 pixel, float height, float top, float depth) {
	float pixel_height = depth / focal_length;
	float close_detail = 1.0 - smoothstep(1.9, 4.1, depth);
	float face_pixels = (top - face_bottom) / pixel_height;
	if (porch_timber.y > 0.0) {
		// One face owns the shared corner. Leave subpixel-width faces solid.
		vec2 corner = porch_timber.x < 0.0 ? wall_local_a : wall_local_b;
		vec2 other = porch_timber.x < 0.0 ? wall_local_b : wall_local_a;
		float edge = 0.0;
		if (porch_timber.x != 0.0 && min(corner.y, other.y) > 0.005) {
			float corner_x = canvas_size.x * 0.5 + projection_offset.x + corner.x * focal_length / corner.y;
			float width = abs(corner.x / corner.y - other.x / other.y) * focal_length;
			edge = step(abs(pixel.x - corner_x), 1.0) * smoothstep(0.8, 2.4, width);
		}
		float under = 1.0 - smoothstep(0.012, 0.062, max(porch_timber.y - height, 0.0));
		return (1.0 + timber_lighting.x * edge * close_detail) * (1.0 - timber_lighting.y * under);
	}
	// The upper rim and underside must leave a row of face between them.
	float detail = close_detail * smoothstep(2.0, 4.0, face_pixels);
	float rim = step(top - height, pixel_height);
	float under = step(height - face_bottom, pixel_height);
	return 1.0 + detail * (timber_lighting.x * rim - timber_lighting.y * under);
}

float storefront_overhang_tone(vec2 uv, float height, float depth) {
	float tone = 1.0;
	bool porch_wall = storefront_paint == 1 &&
		abs(wall_world_a.y - storefront_awning_rect.w) < 0.0001 &&
		abs(wall_world_b.y - storefront_awning_rect.w) < 0.0001;
	if (town_camera_origin.y < storefront_awning_rect.w && (porch_wall || storefront_front_door)) {
		float rise = clamp((height - storefront_floor_height) /
			(storefront_awning_heights.y - storefront_floor_height), 0.0, 1.0);
		float under_awning = step(height, storefront_awning_heights.y);
		tone *= 1.0 - timber_lighting.z * rise * rise * under_awning;
	}
	if (storefront_window && porch_wall && town_camera_origin.y < storefront_awning_rect.w && height < 0.20) {
		float below_sill = 1.0 - smoothstep(0.008, 0.052, 0.20 - height);
		float across_sill = 1.0 - smoothstep(0.34, 0.38, abs(uv.x - 0.5));
		tone *= 1.0 - timber_lighting.y * below_sill * across_sill * (1.0 - smoothstep(3.0, 6.0, depth));
	}
	return tone;
}

float town_wall_opacity(vec2 wall_world_position, vec2 pixel) {
	float cutaway_opacity = wall_opacity;
	if (use_camera_cutaway_fade) {
		// The wall UV's horizontal axis follows its physical world segment. Fade
		// from the nearest camera-fan contact span so the transition continues
		// naturally over neighboring physical wall faces.
		vec2 contact_segment = cutaway_contact_b - cutaway_contact_a;
		float contact_length_squared = dot(contact_segment, contact_segment);
		float contact_amount = contact_length_squared > 0.000001 ? clamp(dot(wall_world_position - cutaway_contact_a, contact_segment) / contact_length_squared, 0.0, 1.0) : 0.0;
		float contact_distance = distance(wall_world_position, cutaway_contact_a + contact_segment * contact_amount);
		float dither_coverage = smoothstep(cutaway_inner_radius, cutaway_inner_radius + max(cutaway_fade_width, 0.0001), contact_distance);
		cutaway_opacity *= step(bayer2_threshold(pixel), dither_coverage);
	}
	return cutaway_opacity;
}

vec3 town_fence_rows(float depth) {
	float scale = focal_length / depth;
	float horizon = horizon_y + projection_offset.y;
	float upper_height = fence_heights.x + fence_heights.y + fence_heights.z * 0.5;
	// Reserve an empty row between rails even when their projected centers
	// would be less than two pixels apart. Keep the lowest rail above ground.
	float pitch = max(2.0, fence_heights.y * scale);
	float ground = horizon + camera_height * scale;
	float upper = min(horizon + (camera_height - upper_height) * scale, floor(ground) - 1.0 - pitch);
	return vec3(upper, pitch, ground);
}

vec2 town_fence_post_hit(vec2 pixel, vec3 origin, vec3 ray) {
	vec2 delta = fence_post - town_camera_origin;
	float depth = dot(delta, town_camera_forward);
	float minimum_post_scale = min(fence_heights.y * 0.5, 2.0 * fence_post_half_width) * focal_length;
	if (depth > minimum_post_scale) {
		float x = canvas_size.x * 0.5 + projection_offset.x + dot(delta, town_camera_right) * focal_length / depth;
		vec3 rows = town_fence_rows(depth);
		float top = min(floor(rows.x) - 1.0, floor(horizon_y + projection_offset.y + (camera_height - fence_heights.w) * focal_length / depth));
		if (floor(pixel.x) == floor(x) && floor(pixel.y) >= top && floor(pixel.y) <= floor(rows.z)) return vec2(depth, 1.0);
		return vec2(-1.0);
	}
	vec2 half_width = vec2(fence_post_half_width);
	vec2 hit = town_wood_box_hit(origin, ray, vec3(fence_post - half_width, 0.0), vec3(fence_post + half_width, fence_heights.w));
	if (hit.x > 0.0) {
		vec2 corner = delta - sign(delta) * half_width;
		float corner_depth = dot(corner, town_camera_forward);
		if (corner_depth > 0.005) {
			float x = canvas_size.x * 0.5 + projection_offset.x + dot(corner, town_camera_right) * focal_length / corner_depth;
			float width = 2.0 * fence_post_half_width * focal_length / hit.x;
			float edge = float(floor(pixel.x) == floor(x)) * smoothstep(1.2, 3.0, width);
			hit.y *= 1.0 + timber_lighting.x * edge;
		}
	}
	return hit;
}

vec2 town_fence_rail_interval(float depth, int rail) {
	vec3 rows = town_fence_rows(depth);
	float width = clamp(floor(fence_heights.z * focal_length / depth + 0.5), 1.0, floor(rows.y) - 1.0);
	float center = rows.x + (1.0 - float(rail)) * rows.y;
	float first_row = floor(center - (width - 1.0) * 0.5);
	return vec2(first_row, first_row + width);
}

vec2 town_fence_rail_hit(vec2 pixel, vec3 origin, vec3 ray) {
	vec2 from_a = wall_world_a - town_camera_origin;
	vec2 from_b = wall_world_b - town_camera_origin;
	vec2 a = vec2(dot(from_a, town_camera_right), dot(from_a, town_camera_forward));
	vec2 b = vec2(dot(from_b, town_camera_right), dot(from_b, town_camera_forward));
	const float near_clip = 0.005;
	if (max(a.y, b.y) <= near_clip) return vec2(-1.0);
	if (a.y < near_clip) a = mix(a, b, (near_clip - a.y) / (b.y - a.y));
	if (b.y < near_clip) b = mix(b, a, (near_clip - b.y) / (a.y - b.y));

	float screen_center = canvas_size.x * 0.5 + projection_offset.x;
	float x_a = screen_center + a.x * focal_length / a.y;
	float x_b = screen_center + b.x * focal_length / b.y;
	float column = floor(pixel.x);
	if (column < floor(min(x_a, x_b)) || column > floor(max(x_a, x_b))) return vec2(-1.0);

	float dx = x_b - x_a;
	vec2 reciprocal_depths = 1.0 / vec2(a.y, b.y);
	vec2 column_fractions = vec2(0.0, 1.0);
	if (abs(dx) > 0.00001) {
		column_fractions = clamp((vec2(column, column + 1.0) - x_a) / dx, vec2(0.0), vec2(1.0));
	}
	vec2 column_depths = 1.0 / mix(vec2(reciprocal_depths.x), vec2(reciprocal_depths.y), column_fractions);
	float fraction = abs(dx) > 0.00001 ? clamp((column + 0.5 - x_a) / dx, 0.0, 1.0) : 0.5;
	float center_depth = 1.0 / mix(reciprocal_depths.x, reciprocal_depths.y, fraction);

	for (int rail = 0; rail < 2; rail++) {
		float height = fence_heights.x + float(rail) * fence_heights.y;
		float eye_to_rail = camera_height - height - fence_heights.z * 0.5;
		vec2 rows = town_fence_rail_interval(center_depth, rail);
		float depth = center_depth;
		// On steep runs, paint the rows crossed over the entire logical column.
		// Sampling its center alone can jump multiple rows between columns.
		if (abs(eye_to_rail * focal_length * (reciprocal_depths.y - reciprocal_depths.x)) >= abs(dx)) {
			vec2 left_rows = town_fence_rail_interval(column_depths.x, rail);
			vec2 right_rows = town_fence_rail_interval(column_depths.y, rail);
			rows = vec2(min(left_rows.x, right_rows.x), max(left_rows.y, right_rows.y));
			float slope = (pixel.y - horizon_y - projection_offset.y) / focal_length;
			if (abs(slope) > 0.00001) {
				depth = clamp(eye_to_rail / slope, min(column_depths.x, column_depths.y), max(column_depths.x, column_depths.y));
			}
		}
		if (pixel.y < rows.x || pixel.y >= rows.y) continue;
		// The screen mask owns the silhouette. Use the thin timber box for
		// face shading wherever it covers those same pixels.
		vec2 along = abs(normalize(wall_world_b - wall_world_a));
		vec2 across = along.yx;
		vec2 inset = fence_post_half_width * along - fence_rail_half_width * across;
		vec2 first = min(wall_world_a, wall_world_b) + inset;
		vec2 last = max(wall_world_a, wall_world_b) - inset;
		vec2 hit = town_wood_box_hit(origin, ray, vec3(first, height), vec3(last, height + fence_heights.z));
		vec2 surface = hit.x > 0.0 ? hit : vec2(depth, 1.0);
		// Apply detail to the physical rail width, even if the continuity mask
		// occupies extra rows at a steep angle.
		float detail = smoothstep(2.0, 4.0, fence_heights.z * focal_length / surface.x);
		float rim = float(floor(pixel.y) == rows.x);
		float under = float(floor(pixel.y) == rows.y - 1.0);
		surface.y *= 1.0 + detail * (timber_lighting.x * rim - timber_lighting.y * under);
		return surface;
	}
	return vec2(-1.0);
}

vec4 town_fence_pixel(vec2 pixel) {
	float screen_x = (pixel.x - canvas_size.x * 0.5 - projection_offset.x) / focal_length;
	float screen_y = (pixel.y - horizon_y - projection_offset.y) / focal_length;
	vec2 direction = town_camera_forward + town_camera_right * screen_x;
	vec3 origin = vec3(town_camera_origin, camera_height);
	vec3 ray = vec3(direction, -screen_y);
	vec2 post = town_fence_post_hit(pixel, origin, ray);
	vec2 rail = town_fence_rail_hit(pixel, origin, ray);
	bool hit_post = post.x > 0.0 && (rail.x <= 0.0 || post.x <= rail.x);
	vec2 best = hit_post ? post : rail;
	if (best.x <= 0.0) return vec4(0.0);

	vec2 world = town_camera_origin + direction * best.x;
	float outdoor_depth = town_outdoor_depth(town_camera_origin, world, best.x);
	vec3 timber = vec3(0.32, 0.235, 0.153) * best.y * (hit_post ? 0.91 : 1.0);
	// Retain enough contrast with the ground for the one-pixel rails.
	return vec4(daylight_color(timber, min(outdoor_depth, 9.0)), town_wall_opacity(world, pixel));
}

bool porch_box_in_front(vec2 direction, float eye_slope, float face_depth) {
	vec3 origin = vec3(town_camera_origin, camera_height);
	vec3 ray = vec3(direction, -eye_slope);
	for (int index = 0; index < storefront_porch_box_count; index++) {
		vec2 hit = town_wood_box_hit(origin, ray, storefront_porch_box_min[index], storefront_porch_box_max[index]);
		if (hit.x > 0.0 && hit.x < face_depth - 0.0008) return true;
	}
	return false;
}

vec2 town_screen_ray(vec2 pixel) {
	float screen_x = (pixel.x - canvas_size.x * 0.5 - projection_offset.x) / focal_length;
	return town_camera_forward + town_camera_right * screen_x;
}

bool porch_plane_blocks(vec2 world_ray, float eye_slope, float ray_depth) {
	float awning_depth = storefront_plane_depth(town_camera_origin, world_ray, camera_height, eye_slope, storefront_awning_rect, storefront_awning_heights);
	if (awning_depth > 0.075 && awning_depth < ray_depth - 0.001) return true;
	float deck_depth = storefront_plane_depth(town_camera_origin, world_ray, camera_height, eye_slope, storefront_awning_rect, vec2(storefront_floor_height));
	return deck_depth > 0.075 && deck_depth < ray_depth - 0.001;
}

float porch_cap_depth(vec2 world_ray, float eye_slope) {
	if (eye_slope <= 0.0 || camera_height <= face_top.x) return -1.0;
	float depth = storefront_plane_depth(town_camera_origin, world_ray, camera_height, eye_slope, porch_cap_rect, vec2(face_top.x));
	if (depth <= 0.075 || porch_plane_blocks(world_ray, eye_slope, depth) ||
			porch_box_in_front(world_ray, eye_slope, depth) ||
			storefront_wall_blocks_door(world_ray, eye_slope, depth)) return -1.0;
	return depth;
}

void fragment() {
	vec2 pixel = UV * canvas_size;
	if (quantize_logical_pixels) {
		pixel = floor(pixel) + vec2(0.5);
	}
	float eye_slope = (pixel.y - horizon_y - projection_offset.y) / focal_length;
	vec2 cap_ray = vec2(0.0);
	float cap_depth = -1.0;
	if (draw_porch_cap) {
		cap_ray = town_screen_ray(pixel);
		cap_depth = porch_cap_depth(cap_ray, eye_slope);
	}
	if (use_town_fence) {
		COLOR = town_fence_pixel(pixel);
	} else if (cap_depth > 0.0) {
		vec2 world = town_camera_origin + cap_ray * cap_depth;
		vec3 timber = storefront_trim.rgb * 1.20;
		if (!use_daylight) timber *= 0.72;
		COLOR = vec4(daylight_color(timber, town_outdoor_depth(town_camera_origin, world, cap_depth)), town_wall_opacity(world, pixel));
	} else {
		vec2 source_uv;
		float ray_depth;
		if (!use_projected_wall || !wall_ray_uv(pixel, source_uv, ray_depth)) discard;
		vec2 wall_world_position = mix(wall_world_a, wall_world_b, source_uv.x);
		if (use_town_lighting) {
			vec2 world_ray = (wall_world_position - town_camera_origin) / ray_depth;
			if (porch_plane_blocks(world_ray, eye_slope, ray_depth)) discard;
			if (storefront_paint == 2 && porch_box_in_front(world_ray, eye_slope, ray_depth)) discard;
			if ((storefront_open_leaf || storefront_paint == 2) && storefront_wall_blocks_door(world_ray, eye_slope, ray_depth)) discard;
		}
		float outdoor_depth = use_town_lighting ? town_outdoor_depth(town_camera_origin, wall_world_position, ray_depth) : 0.0;
		float indoor_depth = max(ray_depth - outdoor_depth, 0.0);
		float mip_level = 0.0;
		// Semantic features need the physical horizontal footprint even when the
		// bitmap mip diagnostic is off, so derive these neighbors unconditionally.
		vec2 uv_x;
		vec2 uv_y;
		float ignored_depth;
		if (!wall_ray_uv(pixel + vec2(1.0, 0.0), uv_x, ignored_depth)) uv_x = source_uv;
		if (!wall_ray_uv(pixel + vec2(0.0, 1.0), uv_y, ignored_depth)) uv_y = source_uv;
		vec2 span_x = (uv_x - source_uv) * base_texture_size;
		vec2 span_y = (uv_y - source_uv) * base_texture_size;
		if (use_integer_uv_scale_snap) {
			float minor_footprint = max(1.0, min(length(span_x), length(span_y)));
			// Match the CPU diagnostic path: footprint is quantized before choosing
			// a whole mip level, rather than blending between levels.
			minor_footprint = max(1.0, floor(minor_footprint + 0.5));
			mip_level = clamp(floor(log2(minor_footprint)), 0.0, 7.0);
		}
		vec4 result;
		float glint = 0.0;
		float wall_top = mix(face_top.x, face_top.y, source_uv.x);
		float world_height = mix(wall_top, face_bottom, source_uv.y);
		// Above the main roof the back of the false front is exposed siding too.
		bool exposed_facade = storefront_paint == 1 && world_height >= storefront_facade_base &&
			abs(wall_world_a.y - storefront_awning_rect.w) < 0.0001 &&
			abs(wall_world_b.y - storefront_awning_rect.w) < 0.0001;
		bool exterior_light = use_daylight || exposed_facade;
		if (use_town_lintel) {
			if (source_uv.y > 0.17) discard;
			result = vec4(0.34, 0.23, 0.14, 1.0);
		} else if (storefront_paint == 1 && !exterior_light && use_semantic_wall_material) {
			vec2 segment = wall_world_b - wall_world_a;
			float width = length(segment);
			float along = dot(wall_world_position, segment / width);
			vec2 interior_uv = vec2(along, clamp(1.0 - (world_height - storefront_floor_height) / 0.6666667, 0.0, 1.0));
			float face_height = mix(face_top.x, face_top.y, source_uv.x) - face_bottom;
			vec2 material_scale = vec2(width, face_height / 0.6666667);
			vec2 material_span_x = span_x * material_scale;
			vec2 material_span_y = span_y * material_scale;
			result = semantic_wall_material(interior_uv, base_texture_size, abs(material_span_x.x), abs(material_span_y.y), material_span_x, material_span_y, pixel, indoor_depth);
			result = storefront_glaze(result, source_uv, world_height, ray_depth);
		} else if (storefront_paint != 0) {
			result = storefront_surface(source_uv, uv_x, pixel, ray_depth, glint);
			result.rgb *= exterior_light ? 1.0 : 0.72;
		} else if (use_daylight) {
			float height = mix(mix(face_top.x, face_top.y, source_uv.x), face_bottom, source_uv.y);
			vec3 wood = town_siding(vec3(0.49, 0.34, 0.20), height, source_uv, uv_x, ray_depth);
			if (source_uv.y < 0.09 || source_uv.y > 0.94) wood = vec3(0.30, 0.20, 0.12);
			result = vec4(semantic_window_over_wall(wood, source_uv, base_texture_size), 1.0);
		} else if (use_semantic_wall_material) {
			// Horizontal texel coverage is the relevant projected measure for the
			// wallpaper repeat and the vertical wooden panels.
			float x_texels_per_logical_pixel = max(abs(uv_x.x - source_uv.x) * base_texture_size.x, 0.0001);
			float y_texels_per_logical_pixel = max(abs(uv_y.y - source_uv.y) * base_texture_size.y, 0.0001);
			result = semantic_wall_material(source_uv, base_texture_size, x_texels_per_logical_pixel, y_texels_per_logical_pixel, span_x, span_y, pixel, indoor_depth);
		} else if (use_layer_parallax) {
			vec4 bottom = nearest_sample(layer1_texture, source_uv + layer1_offset, layer_texture_size, clamp_layer_edges, mip_level);
			vec4 top = nearest_sample(layer2_texture, source_uv + layer2_offset, layer_texture_size, clamp_layer_edges, mip_level);
			result.rgb = top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a);
			result.a = top.a + bottom.a * (1.0 - top.a);
		} else {
			result = nearest_sample(base_texture, source_uv, base_texture_size, false, mip_level);
		}
		if (storefront_paint == 1) result = storefront_door_casing(result, source_uv, ray_depth);
		if (storefront_paint != 0) {
			if (porch_timber.z > 0.0) {
				result.rgb *= porch_timber_tone(pixel, world_height, wall_top, ray_depth);
			} else {
				result.rgb *= storefront_overhang_tone(source_uv, world_height, ray_depth);
			}
		}
		if (result.a <= 0.0) {
			discard;
		}
		// Derive the stroke thickness from the projected UV footprint, rather than
		// from a source texel. This keeps a corner line one 160x120 logical pixel at
		// every distance and viewing angle.
		vec2 corner_uv_x;
		float ignored_corner_depth;
		if (!wall_ray_uv(pixel + vec2(1.0, 0.0), corner_uv_x, ignored_corner_depth)) corner_uv_x = source_uv;
		// Wall endpoints are vertical under the yaw-only projector, so only the
		// horizontal neighboring sample measures the perpendicular one-pixel width.
		// Including the vertical UV derivative made oblique faces produce broad,
		// flickering bands instead of a single logical-pixel line.
		float endpoint_width = max(abs(corner_uv_x.x - source_uv.x), 0.000001);
		float corner_tone = source_uv.x <= endpoint_width ? endpoint_corner_tones.x : (source_uv.x >= 1.0 - endpoint_width ? endpoint_corner_tones.y : 0.0);
		// Town corners use a broad bevel tone nearby and fade before the bevel
		// collapses to a one-pixel flicker. The indoor maze keeps its line treatment.
		if (use_town_lighting && !use_town_fence && !use_town_lintel && storefront_paint <= 1) {
			float bevel = min(0.022 / length(wall_world_b - wall_world_a), 0.16);
			float detail = (1.0 - smoothstep(3.0, 7.0, ray_depth)) *
				(1.0 - smoothstep(bevel * 0.5, bevel, endpoint_width));
			float edge = face_bottom > 0.0 ? 0.0 : source_uv.x < bevel ? endpoint_corner_tones.x : (source_uv.x > 1.0 - bevel ? endpoint_corner_tones.y : 0.0);
			result.rgb *= 1.0 + detail * (edge > 0.0 ? edge * 0.13 : edge * 0.23);
			if (use_daylight && storefront_paint == 0) {
				float height = mix(face_top.x, face_top.y, source_uv.x) * (1.0 - source_uv.y);
				result.rgb *= mix(vec3(0.65, 0.56, 0.48), vec3(1.0), smoothstep(0.0, 0.065, height));
			}
		} else if (!use_town_lighting) {
			if (!use_town_fence && !use_town_lintel && storefront_paint == 0 && corner_tone > 0.0) {
				// Preserve the brighter exposed-edge read without allowing a light wall
				// texel to bloom into a white accidental line.
				result.rgb = min(result.rgb * convex_highlight_factor, vec3(0.82));
			} else if (!use_town_fence && !use_town_lintel && storefront_paint == 0 && corner_tone < 0.0) {
				// AO is a dark mark, never a multiply of an already-bright wallpaper texel.
				result.rgb = min(result.rgb * 0.82, vec3(0.46));
			}
		}
		float cutaway_opacity = town_wall_opacity(wall_world_position, pixel);
		float dither_light = depth_light_dither(indoor_depth, pixel);
		float wall_light = use_depth_light_dither ? dither_light : depth_light(indoor_depth);
		if (show_depth_light_dither_debug) {
			COLOR = vec4(vec3(dither_light), result.a * cutaway_opacity);
		} else {
			vec3 shaded = result.rgb * (exterior_light ? 1.0 : wall_light);
			if (use_town_lighting) shaded = daylight_color(shaded, outdoor_depth);
			COLOR = vec4(mix(shaded, vec3(1.0), glint), result.a * cutaway_opacity);
		}
	}
}
