// ====================================================================================================================================================================
// SEMANTIC GPU BARREL
// Read top to bottom. This shader asks every screen pixel: "does my camera ray
// hit this barrel, and if so, what material detail belongs at that surface?"
// ====================================================================================================================================================================

// --------------------------------------------------------------------------------------------------------------------------------------------------------------------
// 1. SHADER IDENTITY — tell Godot how this program draws.
// Summary: this is a self-lit 2D pixel painter. We choose all its colours.
// --------------------------------------------------------------------------------------------------------------------------------------------------------------------
shader_type canvas_item;                                                            // This shader paints a flat 2D CanvasItem, not a Godot 3D mesh.
render_mode unshaded;                                                               // We choose every colour ourselves; Godot's automatic lights do not alter it.

// --------------------------------------------------------------------------------------------------------------------------------------------------------------------
// 2. CPU-TO-GPU INPUTS — values prepared once per barrel, before pixels run.
// Summary: the CPU supplies camera, barrel, and screen-rectangle facts. The
// shader uses those facts to do its per-pixel surface calculation.
// --------------------------------------------------------------------------------------------------------------------------------------------------------------------
uniform vec2 camera_origin;                                                        // CPU supplies the camera's x/y floor position in world space.
uniform vec2 camera_forward;                                                       // CPU supplies the direction the camera faces along the floor.
uniform vec2 camera_right;                                                         // CPU supplies the screen-right direction along the floor.
uniform vec2 barrel_center;                                                        // CPU supplies this barrel's x/y floor position in world space.
uniform vec2 projection_offset;                                                    // CPU supplies the camera's logical-screen overscan adjustment.
uniform float radius = 0.08;                                                       // The barrel rim radius in game-world units.
uniform float barrel_height = 0.20;                                                // The barrel height in game-world units.
uniform vec2 rect_origin;                                                          // Upper-left logical-screen pixel of this barrel's drawing rectangle.
uniform vec2 rect_size;                                                            // Width and height of that drawing rectangle in logical pixels.

// --------------------------------------------------------------------------------------------------------------------------------------------------------------------
// 3. BARREL SHAPE — the simple mathematical rule behind the outward bow.
// Summary: barrel is narrow at its rims and 20% wider around its middle.
// --------------------------------------------------------------------------------------------------------------------------------------------------------------------
float barrel_radius(float h) {                                                     // Helper: tell us how far the curved side reaches at a given height.
	return radius * (1.0 + 0.20 * sin(3.14159265 * clamp(h, 0.0, 1.0)));             // Swell 20% at middle height, while bottom and top stay at rim radius.
}                                                                                   // End of barrel_radius helper.

// ====================================================================================================================================================================
// PER-PIXEL WORK
// Everything below runs once for every pixel in the barrel's drawing rectangle.
// ====================================================================================================================================================================

vec4 shade_barrel(vec2 pixel) {                                                    // Helper: calculate RGBA colour for one logical screen pixel.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	// 4. MAKE A CAMERA RAY
	// Summary: turn this screen pixel into an imaginary line from the camera.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	float side = (pixel.x - 80.0 - projection_offset.x) / 128.0;                     // Turn horizontal pixel position into left/right distance from camera centre.
	float rise = -(pixel.y - 31.5 - projection_offset.y) / 128.0;                   // Turn vertical pixel position into the ray's vertical slope; screen y points down, hence minus.

	vec2 ray = camera_forward + camera_right * side;                                  // Build this pixel's floor-plane ray direction from forward plus sideways amount.
	vec2 relative = camera_origin - barrel_center;                                   // Move the coordinate system so this barrel centre is local zero.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	// 5. FLOOR SHADOW
	// Summary: even pixels outside the wooden silhouette can darken the floor.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	// A small translucent ground footprint remains visible outside the body.       // This comment labels the floor-shadow calculation below.
	float floor_t = -0.5 / (abs(rise) < 0.000001 ? -0.000001 : rise);                // Find travel distance where this ray reaches floor height; avoid dividing by zero.
	vec2 floor_point = relative + ray * floor_t;                                     // Convert that travel distance into a floor point relative to barrel centre.
	float shadow_radius = length(floor_point) / (radius * 1.12);                     // Measure floor-point distance in slightly widened barrel-radius units.
	float shadow_alpha = floor_t > 0.0 ? (1.0 - smoothstep(0.82, 1.0, shadow_radius)) * 0.38 : 0.0; // Make a soft, 38%-opaque shadow only in front of camera.

	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	// 6. LID RIM PREPARATION
	// Summary: calculate the lid's circular footprint before branches split pixels.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	// Evaluate the top-plane footprint before divergent hit tests so the rim's     // Calculate lid/rim quantities before branches make nearby pixels disagree.
	// logical-pixel width is stable even at the edge of the barrel.                 // That keeps the rim a stable logical-pixel thickness at silhouette edges.
	float safe_rise = abs(rise) < 0.000001 ? (rise < 0.0 ? -0.000001 : 0.000001) : rise; // Make a safe nonzero version of the vertical ray slope.
	float top_t = (barrel_height - 0.5) / safe_rise;                                  // Find where this ray reaches the barrel top plane.
	vec2 top_point = relative + ray * top_t;                                          // Find the floor-plane location directly below that possible lid hit.
	float top_r = length(top_point) / radius;                                         // Convert lid-centre distance to 0 at centre and 1 at rim.
	float rim_width = max(fwidth(top_r) * 1.05, 0.10);                                // Estimate one pixel's lid-distance width, never thinner than readable minimum.

	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	// 7. CHEAP OUTER-CIRCLE TEST
	// Summary: reject pixels that cannot possibly reach the widest part of barrel.
	// This is only a fast gate; it is not yet the precise curved wood surface.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	float a = dot(ray, ray);                                                          // First ingredient for the quick ray-versus-circle calculation.
	float b = dot(relative, ray);                                                     // Second ingredient: how camera-to-barrel direction lines up with this ray.
	float max_radius = radius * 1.20;                                                 // Use widest possible barrel bulge as a simple outer safety circle.
	float disc = b * b - a * (dot(relative, relative) - max_radius * max_radius);    // Discriminant: negative means the ray never reaches that outer circle.

	if (disc <= 0.0 || abs(rise) < 0.000001) {                                        // If it misses, or is too level to calculate safely...
		return vec4(0.0, 0.0, 0.0, shadow_alpha);                                       // ...draw no barrel, but retain any floor-shadow alpha.
	}                                                                                   // End quick-rejection case.
	float root = sqrt(disc);                                                           // Square root needed by the circle-intersection formula.
	float near_t = max(0.001, (-b - root) / a);                                       // Nearer entrance to outer circle, never exactly at camera.
	float far_t = (-b + root) / a;                                                    // Farther exit from outer circle.

	if (far_t <= near_t) { return vec4(0.0, 0.0, 0.0, shadow_alpha); }                // Reject an invalid or backwards ray interval.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	// 8. CHOOSE LID OR SEARCH BODY
	// Summary: accept a valid lid tentatively, then march through curved body to
	// find whichever surface is closer. The march is the expensive part.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	float hit_t = -1.0;                                                                // -1 means we have not found an actual barrel surface yet.
	bool lid = false;                                                                  // Remember whether the eventual hit is top lid rather than curved side.
	if (top_t > 0.0 && top_r <= 1.0) {                                                // If lid plane is in front and hit is inside lid circle...
		hit_t = top_t;                                                                   // ...accept it as a tentative nearest surface.
		lid = true;                                                                       // Record that tentative surface as lid material.
	}                                                                                   // End lid test.

	float previous = 1.0;                                                              // Store prior outside/inside measurement for body-surface refinement.
	float previous_t = near_t;                                                         // Store ray distance of that prior measurement.
	float previous_h = -1.0;                                                           // Store its barrel height; -1 means not valid yet.
	for (int i = 0; i <= 48; i++) {                                                   // March through 49 evenly spaced positions across outer-circle interval.
		float t = mix(near_t, far_t, float(i) / 48.0);                                   // Pick this step's ray distance; mix makes a value between endpoints.
		float h = (0.5 + rise * t) / barrel_height;                                      // Convert ray distance into barrel-relative height: 0 bottom, 1 top.
		float d = length(relative + ray * t) - barrel_radius(h);                         // Positive means outside wood; zero=edge; negative means inside wood.

		if (h >= 0.0 && h <= 1.0 && d <= 0.0) {                                          // If position is within barrel's height and has entered wooden body...
			float lo = previous_t;                                                         // ...start bracket at preceding outside sample.
			float hi = t;                                                                  // Current inside sample becomes other end of surface bracket.
			if (i > 0 && previous > 0.0 && previous_h >= 0.0 && previous_h <= 1.0) {      // Refine only when previous sample was a real valid outside point.
				for (int j = 0; j < 5; j++) {                                               // Narrow the surface bracket five times.
					float mid = (lo + hi) * 0.5;                                               // Test exactly halfway through current bracket.
					float mh = (0.5 + rise * mid) / barrel_height;                             // Find barrel-relative height at that midpoint.
					if (length(relative + ray * mid) - barrel_radius(mh) <= 0.0) { hi = mid; } else { lo = mid; } // Keep half containing outside-to-inside crossing.
				}                                                                             // End five midpoint refinements.
			}                                                                               // End optional refinement.
			if (hit_t < 0.0 || hi < hit_t) { hit_t = hi; lid = false; }                     // Use body if it is the first or nearer than tentative lid.
			break;                                                                          // First valid body entry is enough; stop marching.
		}                                                                                   // End body-entry case.
		previous = d;                                                                      // Save this outside measurement for next march step.
		previous_t = t;                                                                    // Save this ray distance for next march step.
		previous_h = h;                                                                    // Save this height for next march step.
	}                                                                                     // End 49-step curved-body search.

	if (hit_t < 0.0) { return vec4(0.0, 0.0, 0.0, shadow_alpha); }                      // No body/lid hit: return transparent pixel plus possible floor shadow.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	// 9. CONFIRMED SURFACE — common detail fades used by both materials.
	// Summary: now we know the exact wood/lid point, so decoration can attach to it.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	vec2 point = relative + ray * hit_t;                                                 // Convert winning ray distance into exact barrel-surface point.
	float distance_fade = 1.0 - smoothstep(1.4, 4.2, length(relative));                 // Fade dark decorative seams as barrel gets farther from camera.
	float highlight_fade = 1.0 - smoothstep(1.1, 3.2, length(relative));                // Fade bright decorative wood highlights with distance.

	vec3 color;                                                                          // Reserve RGB colour variable; lid and side choose its value next.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	// 10. MATERIAL BRANCH — lid versus curved side wood.
	// Summary: both come from the same hit test, but each needs different details.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	if (lid) {                                                                           // Use this block only for a lid-surface hit.
		// LID: recessed boards, seams, and their tiny neighbouring highlights.
		// Test the recessed panel at its lower world height. The complete      // Lid inset is a lower plane inside the outer rim.
		// outer rim is composited last, above both the inset and barrel body.  // Rim will overwrite everything later so it cannot be eaten by inset shadow.
		float inset_t = (barrel_height * 0.92 - 0.5) / rise;                               // Find ray distance to lid's slightly lower recessed plane.
		vec2 inset_point = relative + ray * inset_t;                                      // Find floor-plane point below that recessed-plane hit.
		float inset_r = length(inset_point) / radius;                                     // Measure inset point distance from lid centre in rim-radius units.

		color = vec3(0.35, 0.24, 0.15);                                                   // Begin with dark wood for the outer lip.
		if (inset_t > 0.0 && inset_r < 0.80) {                                            // Inside the lid's inner 80%, use recessed boards.
			color = vec3(0.53, 0.40, 0.28);                                                 // Choose base RGB colour for those inset boards.
			float board = inset_point.x / radius;                                           // Describe position across lid in barrel-radius units.
			float board_width = max(fwidth(board), 0.01);                                   // Estimate one logical pixel's board-coordinate width.
			float seam = abs(abs(board) - 0.27);                                            // Distance to either of the two lid-board seam positions.
			float seam_neighbor = abs(abs(board - dFdx(board)) - 0.27);                     // Ask whether the pixel immediately left/right is on a seam.
			if (seam < board_width * 0.5) { color *= mix(1.0, 0.62, distance_fade); }       // Darken actual seam, but fade that contrast in distance.
			else if (seam_neighbor < board_width * 0.5) { color *= mix(1.0, 1.20, highlight_fade); } // Lighten wood immediately beside seam, fading in distance.
		}                                                                                   // End recessed-panel test.
	} else {                                                                              // Every non-lid hit is curved side wood.
		// SIDE WOOD: round lighting first, then repeating vertical stave seams.
		float h = clamp((0.5 + rise * hit_t) / barrel_height, 0.0, 1.0);                  // Recalculate confirmed side-hit height from 0 bottom to 1 top.
		vec2 n = normalize(point);                                                         // Keep surface direction from centre, but remove its distance.
		float across = dot(n, camera_right);                                               // Measure how sideways this surface faces relative to camera.

		float light = (0.68 + 0.32 * sqrt(max(0.0, 1.0 - across * across))) * mix(0.68, 1.15, h); // Combine round-side lighting with darker bottom and brighter upper body.
		light = floor(light * 16.0 + 0.5) / 16.0;                                          // Restrict lighting to 16 deliberate pixel-art brightness steps.
		color = vec3(0.52, 0.36, 0.22) * light;                                           // Apply stepped light to base wood RGB colour.

		float stave_position = (atan(n.y, n.x) / 6.2831853) * 8.0;                        // Turn direction around barrel into eight repeating stave positions.
		float seam = abs(fract(stave_position + 0.5) - 0.5);                               // Make zero exactly at every stave seam, increasing toward each stave centre.
		float seam_width = clamp(fwidth(stave_position), 0.015, 0.25);                    // Estimate readable one-pixel seam width, held within safe limits.
		float neighbor = abs(fract(stave_position - dFdx(stave_position) + 0.5) - 0.5);   // Detect whether neighbouring pixel sits on a seam.
		if (seam < seam_width * 0.5) { color *= mix(1.0, 0.68, distance_fade); }           // Darken actual stave seam, fading detail with distance.
		else if (neighbor < seam_width * 0.5) { color *= mix(1.0, 1.28, highlight_fade); } // Lighten wood immediately next to a seam, also fading with distance.
		// ------------------------------------------------------------------------------------------------------------------------------------------------------------
		// 11. METAL HOOPS
		// Summary: hoops are height bands on the same curved surface, with a
		// highlight above and wood shadow below. Far hoops collapse to one pixel.
		// ------------------------------------------------------------------------------------------------------------------------------------------------------------
		// Bands are one logical pixel thick; their upper-edge highlight fades  // Hoops are height bands on the same curved body, not painted flat lines.
		// independently, while a shadow sits directly below the metal.       // Their highlight and lower wood shadow are separate layers.
		float hoop_delta = h - (h < 0.5 ? 0.25 : 0.75);                                   // Height distance to nearer hoop: one at 25%, one at 75%.
		// The vertical height change of a ray is known even when adjacent      // Use a stable vertical pixel-size estimate near silhouette edges.
		// pixels miss the body. Use it as a stable minimum so a hoop cannot   // This prevents a hoop from vanishing because neighbour missed barrel.
		// disappear at the silhouette; bound the horizontal contribution so a // Also prevent noisy sideways derivative from making a vertical edge streak.
		// bad edge derivative cannot make the hoop run down the silhouette.   // This finishes the edge-protection explanation.
		float hoop_vertical_pixel = clamp(hit_t / (128.0 * barrel_height), 0.001, 0.25);   // Estimate one screen row's size in barrel-height units.
		float hoop_pixel = clamp(fwidth(h), hoop_vertical_pixel, hoop_vertical_pixel * 2.0); // Use local pixel size, constrained by safe vertical estimate.
		float hoop_highlight = 1.0 - smoothstep(0.9, 2.7, length(relative));               // Fade hoop brightness with camera distance.

		// At distance the highlight shares the metal pixel instead of adding  // Keep distant hoop one logical pixel rather than stacked rows.
		// another row; the only extra row is the shadow on the wood below.    // Preserve only the shadow row below it.
		float distant_hoop = smoothstep(0.9, 1.8, length(relative));                        // Blend progressively into compact far-distance hoop treatment.
		float hoop_half_width = mix(0.75, 0.5, distant_hoop);                               // Narrow central metal band at distance.
		float highlight_outer = mix(1.75, 0.5, distant_hoop);                               // Collapse separate upper highlight row into metal at distance.
		vec3 metal = vec3(0.29, 0.27, 0.24);                                                 // Choose dark grey-brown metal RGB colour.
		vec3 lit_metal = metal * mix(1.0, 1.45, hoop_highlight);                             // Make a lighter version of same metal instead of unrelated bright grey.

		if (abs(hoop_delta) < hoop_pixel * hoop_half_width) { color = mix(metal, lit_metal, distant_hoop * 0.5); } // Paint main hoop band.
		else if (hoop_delta >= hoop_pixel * hoop_half_width && hoop_delta < hoop_pixel * highlight_outer) { color = lit_metal; } // Paint near-only upper highlight band.
		else if (hoop_delta <= -hoop_pixel * hoop_half_width && hoop_delta > -hoop_pixel * (hoop_half_width + 1.0)) { color *= 0.70; } // Darken wood directly under hoop.
	}                                                                                     // End curved-side shading branch.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	// 12. FINAL LID RIM — deliberately last, so the inset cannot cover it.
	// ----------------------------------------------------------------------------------------------------------------------------------------------------------------
	if (top_t > 0.0 && top_r <= 1.0 && top_r >= 1.0 - rim_width) {                       // If pixel belongs to thin outer ring of a valid lid...
		bool front_rim = dot(top_point, relative) > 0.0;                                    // ...decide whether it is camera-facing half of rim.
		vec3 rim_wood = vec3(0.52, 0.36, 0.22);                                             // Use wood in same colour family as barrel side.
		color = rim_wood * (front_rim ? 1.30 : 1.12);                                       // Make front rim lighter than rear rim.
	}                                                                                     // End final rim pass; this happens after inset, so rim stays on top.

	return vec4(color, 1.0);                                                              // Return barrel RGB with fully opaque alpha.
}                                                                                       // End per-pixel shade_barrel helper.

// ====================================================================================================================================================================
// GODOT ENTRY POINT
// This is the one function Godot calls. It hands work to our readable helper.
// ====================================================================================================================================================================
void fragment() {                                                                       // Godot calls this once for every pixel in the barrel drawing rectangle.
	COLOR = shade_barrel(rect_origin + UV * rect_size);                                   // Convert local 0-to-1 UV into logical screen pixel, then calculate its colour.
}                                                                                       // End shader entry point.
