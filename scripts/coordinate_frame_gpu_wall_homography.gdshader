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
// The game view is authored at 160×120 then nearest-upscaled.  Quantizing the
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
uniform vec2 layer1_offset = vec2(0.0);
uniform vec2 layer2_offset = vec2(0.0);
uniform vec2 wall_depths = vec2(1.0);
// Each fragment intersects this real camera-local wall segment. This is the
// same camera-ray projection used for the horizontal world planes; no endpoint
// is ever near-clamped or geometrically clipped for the wall renderer.
uniform vec2 wall_local_a = vec2(-0.5, 1.0);
uniform vec2 wall_local_b = vec2(0.5, 1.0);
uniform float camera_height = 0.5;
uniform float wall_height = 0.6666667;
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
	if (world_height < 0.0 || world_height > wall_height) return false;
	source_uv = vec2(segment_u, 1.0 - world_height / wall_height);
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
	if (!show_exterior_window || !is_exterior_wall()) return wall_color;
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

void fragment() {
	vec2 pixel = UV * canvas_size;
	if (quantize_logical_pixels) {
		pixel = floor(pixel) + vec2(0.5);
	}
	vec2 source_uv;
	float ray_depth;
	if (!wall_ray_uv(pixel, source_uv, ray_depth)) discard;
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
	if (use_semantic_wall_material) {
		// Horizontal texel coverage is the relevant projected measure for the
		// wallpaper repeat and the vertical wooden panels.
		float x_texels_per_logical_pixel = max(abs(uv_x.x - source_uv.x) * base_texture_size.x, 0.0001);
		float y_texels_per_logical_pixel = max(abs(uv_y.y - source_uv.y) * base_texture_size.y, 0.0001);
		result = semantic_wall_material(source_uv, base_texture_size, x_texels_per_logical_pixel, y_texels_per_logical_pixel, span_x, span_y, pixel, ray_depth);
	} else if (use_layer_parallax) {
		vec4 bottom = nearest_sample(layer1_texture, source_uv + layer1_offset, layer_texture_size, clamp_layer_edges, mip_level);
		vec4 top = nearest_sample(layer2_texture, source_uv + layer2_offset, layer_texture_size, clamp_layer_edges, mip_level);
		result.rgb = top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a);
		result.a = top.a + bottom.a * (1.0 - top.a);
	} else {
		result = nearest_sample(base_texture, source_uv, base_texture_size, false, mip_level);
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
	if (corner_tone > 0.0) {
		// Preserve the brighter exposed-edge read without allowing a light wall
		// texel to bloom into a white accidental line.
		result.rgb = min(result.rgb * convex_highlight_factor, vec3(0.82));
	} else if (corner_tone < 0.0) {
		// AO is a dark mark, never a multiply of an already-bright wallpaper texel.
		result.rgb = min(result.rgb * 0.82, vec3(0.46));
	}
	float cutaway_opacity = wall_opacity;
	if (use_camera_cutaway_fade) {
		// The wall UV's horizontal axis follows its physical world segment. Fade
		// from the nearest camera-fan contact span so the transition continues
		// naturally over neighboring physical wall faces.
		vec2 wall_world_position = mix(wall_world_a, wall_world_b, source_uv.x);
		vec2 contact_segment = cutaway_contact_b - cutaway_contact_a;
		float contact_length_squared = dot(contact_segment, contact_segment);
		float contact_amount = contact_length_squared > 0.000001 ? clamp(dot(wall_world_position - cutaway_contact_a, contact_segment) / contact_length_squared, 0.0, 1.0) : 0.0;
		float contact_distance = distance(wall_world_position, cutaway_contact_a + contact_segment * contact_amount);
		float dither_coverage = smoothstep(cutaway_inner_radius, cutaway_inner_radius + max(cutaway_fade_width, 0.0001), contact_distance);
		cutaway_opacity *= step(bayer2_threshold(pixel), dither_coverage);
	}
	float dither_light = depth_light_dither(ray_depth, pixel);
	float wall_light = use_depth_light_dither ? dither_light : depth_light(ray_depth);
	if (show_depth_light_dither_debug) {
		COLOR = vec4(vec3(dither_light), result.a * cutaway_opacity);
	} else {
		COLOR = vec4(result.rgb * wall_light, result.a * cutaway_opacity);
	}
}
