// Shared 8×5 barrel lattice.  VERTEX/UV describe a static local mesh; the
// vertex shader turns those into world space and then the game's 160×120 view.
shader_type canvas_item;

uniform vec2 camera_origin;
uniform vec2 camera_forward = vec2(0.0, 1.0);
uniform vec2 camera_right = vec2(1.0, 0.0);
uniform vec2 projection_offset;
uniform vec2 barrel_center;
uniform float barrel_radius = 0.08;
uniform float barrel_height = 0.20;
uniform float barrel_swell = 0.20;
uniform float upper_hoop_height = 0.30;
uniform float lower_hoop_height = 0.82;
uniform float hoop_width_logical_pixels = 2.0;
uniform float rim_width_logical_pixels = 2.0;
uniform float stave_shadow_width_logical_pixels = 1.0;
uniform float stave_highlight_width_logical_pixels = 1.0;
uniform float floor_shadow_width = 1.30;
uniform float floor_shadow_opacity = 0.55;
uniform float focal_length = 128.0;
// Must match CoordinateFrameRuntimeRenderer.HORIZON_Y.  A previous authoring
// value of 44.0 made this otherwise-correct GPU mesh project below the room's
// floor, because the floor itself meets the camera projection at y = 31.5.
uniform float horizon_y = 31.5;
uniform float virtual_camera_height = 0.5;
// 0 = outside wood, 1 = interior/lid disk, 2/3 = hoop bands, 4 = wood rim.
// These are separate MeshInstance2D children sharing the same static lattice.
uniform int surface_mode = 0;
uniform bool show_lattice_wireframe = false;
uniform vec4 wood_edge : source_color = vec4(0.12, 0.055, 0.015, 1.0);
uniform vec4 wood_centre : source_color = vec4(0.62, 0.28, 0.06, 1.0);
uniform vec4 interior_colour : source_color = vec4(0.12, 0.045, 0.012, 1.0);
uniform vec4 metal_dark : source_color = vec4(0.09, 0.10, 0.09, 1.0);
uniform vec4 metal_light : source_color = vec4(0.78, 0.82, 0.76, 1.0);
uniform vec4 rim_colour : source_color = vec4(0.78, 0.43, 0.12, 1.0);
uniform vec4 stave_shadow_colour : source_color = vec4(0.22, 0.11, 0.04, 1.0);
uniform vec4 stave_highlight_colour : source_color = vec4(0.85, 0.60, 0.33, 1.0);
uniform vec4 floor_shadow_colour : source_color = vec4(0.10, 0.06, 0.025, 0.34);

varying vec2 radial;
varying float height_fraction;
varying float face_to_camera;
varying float projection_depth;

void vertex() {
	float angle = UV.x * TAU;
	height_fraction = surface_mode == 5 ? 0.0 : UV.y;
	radial = vec2(cos(angle), sin(angle)) * COLOR.a;
	float swell = 1.0 + barrel_swell * sin(PI * height_fraction);
	float radius_scale = surface_mode == 5 ? floor_shadow_width : swell;
	vec2 world = barrel_center + radial * barrel_radius * radius_scale;
	vec2 relative = world - camera_origin;
	float depth = max(dot(relative, camera_forward), 0.02);
	projection_depth = depth;
	float side = dot(relative, camera_right);
	face_to_camera = dot(normalize(radial + vec2(0.0001)), normalize(camera_origin - barrel_center));
	VERTEX = vec2(
		80.0 + side / depth * focal_length,
		horizon_y + (virtual_camera_height - barrel_height * height_fraction) / depth * focal_length
	) + projection_offset;
	if (surface_mode == 5) {
		// A shallow floor ellipse made from the same 8-point top fan.  It is
		// deliberately its own component and never pretends to be wood shading.
		float center_depth = max(dot(barrel_center - camera_origin, camera_forward), 0.02);
		float floor_center_y = horizon_y + virtual_camera_height / center_depth * focal_length + projection_offset.y;
		VERTEX.y = mix(floor_center_y, VERTEX.y, 0.30) + 1.0;
	}
}

// This barrel is deliberately assembled from hard, named paint regions rather
// than a continuously lit 3D surface.  The shader runs in the shared 160x120
// play viewport, so these hard edges become the game's enlarged pixels.
float component_line(float distance_to_line, float width) {
	return 1.0 - step(width, distance_to_line);
}

float stepped(float value, float steps) {
	return floor(clamp(value, 0.0, 1.0) * (steps - 1.0) + 0.5) / (steps - 1.0);
}

float height_half_width_for_logical_pixels(float pixel_width) {
	// One height-fraction unit spans barrel_height / projection_depth world
	// units, or focal_length pixels on the shared 160×120 target.  This turns
	// the Inspector's screen-pixel value into the current barrel fraction.
	return max(pixel_width, 0.0) * projection_depth / max(barrel_height * focal_length, 0.001) * 0.5;
}

float turn_half_width_for_logical_pixels(float pixel_width) {
	// Approximate local circumference-to-screen conversion for stave marks.
	return max(pixel_width, 0.0) * projection_depth / max(barrel_radius * focal_length * TAU, 0.001) * 0.5;
}

float radial_half_width_for_logical_pixels(float pixel_width) {
	return max(pixel_width, 0.0) * projection_depth / max(barrel_radius * focal_length, 0.001) * 0.5;
}

void fragment() {
	if (surface_mode != 1 && surface_mode != 5 && face_to_camera <= 0.02) {
		discard;
	}
	if ((surface_mode == 2 || surface_mode == 3) && face_to_camera <= 0.18) {
		// Hoops are front arcs, not bands visible around the far half of a model.
		discard;
	}
	float radial_length = length(radial);
	float facing = clamp(face_to_camera, 0.0, 1.0);
	vec3 colour;
	if (surface_mode == 5) {
		colour = floor_shadow_colour.rgb;
	} else if (surface_mode == 1) {
		// Semantic top assembly: a dark opening bounded by a warm rim.  Both are
		// separate paint regions on one static lid fan.
		float rim_half_width = radial_half_width_for_logical_pixels(rim_width_logical_pixels);
		float rim_inner_radius = clamp(1.0 - rim_half_width * 2.0, 0.0, 1.0);
		float rim = component_line(radial_length, 1.0) - component_line(radial_length, rim_inner_radius);
		float lid_area = component_line(radial_length, rim_inner_radius);
		colour = interior_colour.rgb * 0.62;
		colour = mix(colour, wood_centre.rgb * 0.78, lid_area * 0.72);
		colour = mix(colour, rim_colour.rgb, rim);
	} else {
		// Outside wood is a deliberately stepped, broad centre-light treatment.
		// It is not per-face 3D lighting: the visible staves below carry the
		// construction information, while this reads as a single painted body.
		float vertical = stepped(mix(0.70, 1.0, height_fraction), 3.0);
		float centre_light = stepped(0.42 + 0.46 * facing, 3.0);
		colour = mix(wood_edge.rgb, wood_centre.rgb, centre_light) * vertical;
		float hoop_half_width = height_half_width_for_logical_pixels(hoop_width_logical_pixels);
		float rim_half_width = height_half_width_for_logical_pixels(rim_width_logical_pixels);
		float upper_hoop = component_line(abs(height_fraction - upper_hoop_height), hoop_half_width);
		float lower_hoop = component_line(abs(height_fraction - lower_hoop_height), hoop_half_width);
		float hoop = surface_mode == 2 ? upper_hoop : lower_hoop;
		float hoop_highlight = surface_mode == 2
			? component_line(abs(height_fraction - (upper_hoop_height + hoop_half_width * 0.72)), max(hoop_half_width * 0.50, height_half_width_for_logical_pixels(1.0)))
			: component_line(abs(height_fraction - (lower_hoop_height + hoop_half_width * 0.72)), max(hoop_half_width * 0.50, height_half_width_for_logical_pixels(1.0)));
		float rim = component_line(abs(height_fraction - 1.0), rim_half_width);
		float angle_turn = atan(radial.y, radial.x) / TAU;
		float stave_distance = abs(fract(angle_turn * 8.0 + 0.5) - 0.5);
		float stave = component_line(stave_distance, turn_half_width_for_logical_pixels(stave_shadow_width_logical_pixels));
		float stave_highlight_distance = abs(fract(angle_turn * 8.0 + 0.565) - 0.5);
		float stave_highlight = component_line(stave_highlight_distance, turn_half_width_for_logical_pixels(stave_highlight_width_logical_pixels));
		if (surface_mode == 0) {
			// Outside-wood component: staves are paint marks, not lighting facets.
			colour = mix(colour, stave_shadow_colour.rgb, stave * 0.62);
			colour = mix(colour, stave_highlight_colour.rgb, stave_highlight * 0.32);
		} else if (surface_mode == 2 || surface_mode == 3) {
			// The hoop meshes draw only their individual semantic band.
			if (hoop < 0.5) {
				discard;
			}
			colour = mix(metal_dark.rgb, metal_light.rgb, hoop_highlight);
		} else {
			// The rim is deliberately a separate final layer over the lid/body.
			if (rim < 0.5) {
				discard;
			}
			colour = rim_colour.rgb;
		}
	}
	if (show_lattice_wireframe && surface_mode == 0) {
		// Deliberately broad and bright: this is an authoring diagram, not a
		// subtle in-game treatment. The five cyan rows are the shared CPU-free
		// lattice rings; the eight spokes are its fixed columns.
		float horizontal = max(component_line(abs(height_fraction - 0.0), 0.006), max(component_line(abs(height_fraction - 0.25), 0.006), max(component_line(abs(height_fraction - 0.50), 0.006), max(component_line(abs(height_fraction - 0.75), 0.006), component_line(abs(height_fraction - 1.0), 0.006)))));
		float angle_turn = atan(radial.y, radial.x) / TAU;
		float vertical_line = component_line(abs(fract(angle_turn * 8.0 + 0.5) - 0.5), 0.006);
		colour = mix(colour, vec3(0.10, 1.0, 1.0), max(horizontal, vertical_line));
	}
	COLOR = vec4(colour, surface_mode == 5 ? floor_shadow_colour.a * floor_shadow_opacity : 1.0);
}
