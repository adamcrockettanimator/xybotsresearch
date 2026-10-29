# Semantic GPU Barrel — annotated reading guide

This is a teaching copy of `scripts/semantic_gpu_barrel.gdshader`, not a second shader.  The **left column** is the real code.  The comment to its right explains that exact line in ordinary language.  Read the sections in order; each one prepares words used by the next.

## 1. Tell Godot what kind of drawing program this is

```glsl
shader_type canvas_item;                 // This shader paints a flat 2D canvas item, not a Godot 3D mesh.
render_mode unshaded;                    // Godot's built-in lights do not affect it; we choose every color ourselves.

uniform vec2 camera_origin;              // CPU sends the camera's world-space floor position: its x/y map location.
uniform vec2 camera_forward;             // CPU sends the direction the camera faces on the floor plane.
uniform vec2 camera_right;               // CPU sends the sideways direction: screen-right on that same floor plane.
uniform vec2 barrel_center;              // CPU sends this barrel's world-space floor position.
uniform vec2 projection_offset;          // CPU sends the camera's screen-space overscan adjustment.
uniform float radius = 0.08;             // The barrel's radius in game-world units; 0.08 is the default.
uniform float barrel_height = 0.20;      // The barrel's height in game-world units; 0.20 is the default.
uniform vec2 rect_origin;                // The upper-left logical pixel of this barrel's small drawing rectangle.
uniform vec2 rect_size;                  // The width and height of that drawing rectangle in logical pixels.
```

`uniform` means: “a value the CPU hands to every pixel before the shader starts.”  `vec2` is simply a pair of numbers, like an x/y point or arrow.  A `float` is one ordinary number.

## 2. Describe the barrel's outward bow

```glsl
float barrel_radius(float h) {                                                            // Make a helper named barrel_radius; h means height from 0 at bottom to 1 at top.
	return radius * (1.0 + 0.20 * sin(3.14159265 * clamp(h, 0.0, 1.0)));                  // Start at the rim radius, swell 20% at the middle, then return to rim radius.
}                                                                                         // Finish the helper.
```

`sin` makes a smooth hill: zero at the bottom, highest halfway up, and zero again at the top.  `clamp` refuses heights below 0 or above 1 before they reach that hill.

## 3. Start one pixel's barrel calculation

```glsl
vec4 shade_barrel(vec2 pixel) {                                                          // Make a helper that receives one logical screen pixel and returns its RGBA color.
	float side = (pixel.x - 80.0 - projection_offset.x) / 128.0;                         // Convert this pixel's horizontal position into “how far left/right from screen centre.”
	float rise = -(pixel.y - 31.5 - projection_offset.y) / 128.0;                        // Convert vertical position into the ray's upward/downward slope; screen y grows downward, hence the minus sign.
	vec2 ray = camera_forward + camera_right * side;                                       // Build the floor-plane direction from camera through this pixel.
	vec2 relative = camera_origin - barrel_center;                                        // Express camera position relative to this barrel, so this barrel becomes local zero.
```

A **ray** is an imaginary straight line fired from the camera through one screen pixel.  This shader asks: “if I follow this ray, do I run into the barrel, and where?”

## 4. Calculate the floor shadow before deciding whether the ray hits wood

```glsl
	float floor_t = -0.5 / (abs(rise) < 0.000001 ? -0.000001 : rise);                     // Find how far along the ray it reaches floor height; substitute a tiny safe number for a perfectly level ray.
	vec2 floor_point = relative + ray * floor_t;                                           // Turn that travel distance into an actual floor point beside the barrel.
	float shadow_radius = length(floor_point) / (radius * 1.12);                          // Measure that point's distance from barrel centre in “barrel radii.”
	float shadow_alpha = floor_t > 0.0 ? (1.0 - smoothstep(0.82, 1.0, shadow_radius)) * 0.38 : 0.0; // Make a soft black shadow inside a slightly widened barrel footprint, otherwise make it invisible.
```

`t` means travel distance along a ray.  `length` means distance.  `smoothstep(a,b,x)` gently changes from 0 to 1 between `a` and `b`, instead of making a harsh edge.  The `? :` form is a compact “if this is true, use this; otherwise use that.”

## 5. Work out the lid and its rim before the body search

```glsl
	float safe_rise = abs(rise) < 0.000001 ? (rise < 0.0 ? -0.000001 : 0.000001) : rise;  // Keep a safe non-zero vertical slope for division.
	float top_t = (barrel_height - 0.5) / safe_rise;                                       // Find where this ray reaches the barrel's top height.
	vec2 top_point = relative + ray * top_t;                                               // Find the floor-plane position directly below that possible lid hit.
	float top_r = length(top_point) / radius;                                              // Express its distance from lid centre as 0=center and 1=outer rim.
	float rim_width = max(fwidth(top_r) * 1.05, 0.10);                                     // Estimate one screen pixel's width in lid-distance units, with a minimum readable rim thickness.
```

`fwidth` asks the GPU how quickly a value changes from one nearby pixel to the next.  Here that lets “one-pixel-wide rim” remain one logical pixel despite perspective.

## 6. Quickly reject rays that cannot reach the barrel's outer envelope

```glsl
	float a = dot(ray, ray);                                                               // First ingredient for the ray/circle intersection calculation.
	float b = dot(relative, ray);                                                          // Second ingredient: how much camera-to-barrel direction points along this ray.
	float max_radius = radius * 1.20;                                                      // Use the barrel's widest possible bulge as a simple outer safety circle.
	float disc = b * b - a * (dot(relative, relative) - max_radius * max_radius);          // The discriminant tells whether this ray reaches that circle at all.
	if (disc <= 0.0 || abs(rise) < 0.000001) {                                              // If it misses the outer circle, or is level enough to be unsafe, stop body work.
		return vec4(0.0, 0.0, 0.0, shadow_alpha);                                            // Return transparent black plus only the floor-shadow opacity.
	}                                                                                       // Finish the miss case.
	float root = sqrt(disc);                                                                // Take the square root required by the circle-intersection formula.
	float near_t = max(0.001, (-b - root) / a);                                            // Find the nearer crossing of the outer circle, never allowing exactly zero distance.
	float far_t = (-b + root) / a;                                                         // Find the farther crossing of the outer circle.
	if (far_t <= near_t) { return vec4(0.0, 0.0, 0.0, shadow_alpha); }                      // Reject an invalid or backwards interval.
```

`dot` compares two arrows: it reports how much they point in the same direction.  The circle is not yet the real barrel; it is only a cheap “could this ray possibly touch the barrel?” test.

## 7. Prefer a valid lid hit, then prepare to search the curved body

```glsl
	float hit_t = -1.0;                                                                     // -1 is our sign meaning “no barrel hit has been found yet.”
	bool lid = false;                                                                       // Remember whether the eventual hit belongs to the lid.
	if (top_t > 0.0 && top_r <= 1.0) {                                                      // If the ray reaches the top in front of the camera and inside the lid circle...
		hit_t = top_t;                                                                        // ...tentatively accept the lid.
		lid = true;                                                                            // Mark that tentative hit as lid material.
	}                                                                                       // Finish the lid test.
	float previous = 1.0;                                                                   // Keep the previous “outside/inside” result for the body search.
	float previous_t = near_t;                                                              // Keep the ray distance belonging to that previous result.
	float previous_h = -1.0;                                                                // Keep its height; -1 means no valid barrel height yet.
```

`bool` is a true/false value.  The lid is checked first because a top-down ray may hit it before it reaches the curved wall.

## 8. Search along the ray for the curved wooden body

```glsl
	for (int i = 0; i <= 48; i++) {                                                        // Try 49 evenly spaced positions from outer-circle entrance to exit.
		float t = mix(near_t, far_t, float(i) / 48.0);                                        // Choose this step's travel distance; mix makes an in-between value.
		float h = (0.5 + rise * t) / barrel_height;                                           // Convert this ray position into barrel-relative height.
		float d = length(relative + ray * t) - barrel_radius(h);                              // Distance from centre minus allowed radius: positive=outside, zero=edge, negative=inside wood.
		if (h >= 0.0 && h <= 1.0 && d <= 0.0) {                                               // If this point is between barrel bottom/top and has entered the wood...
			float lo = previous_t;                                                               // ...begin with the last outside position as the low edge of a small bracket.
			float hi = t;                                                                        // Use the current inside position as the high edge of that bracket.
			if (i > 0 && previous > 0.0 && previous_h >= 0.0 && previous_h <= 1.0) {             // Refine only when the previous sample really was a valid outside point.
				for (int j = 0; j < 5; j++) {                                                     // Repeat five times to narrow the outside/inside bracket.
					float mid = (lo + hi) * 0.5;                                                     // Test exactly halfway between its current two ends.
					float mh = (0.5 + rise * mid) / barrel_height;                                   // Find the midpoint's barrel-relative height.
					if (length(relative + ray * mid) - barrel_radius(mh) <= 0.0) { hi = mid; } else { lo = mid; } // Keep the half that still brackets the surface.
				}                                                                                  // Finish five midpoint refinements.
			}                                                                                   // Finish the optional refinement.
			if (hit_t < 0.0 || hi < hit_t) { hit_t = hi; lid = false; }                          // Replace no hit, or a farther lid hit, with this nearer body hit.
			break;                                                                               // Stop searching; the first valid body entry is enough.
		}                                                                                       // Finish “entered the wood” case.
		previous = d;                                                                          // Save this outside/inside measurement for the next step.
		previous_t = t;                                                                        // Save this ray distance for the next step.
		previous_h = h;                                                                        // Save this height for the next step.
	}                                                                                         // Finish the 49-step body search.
	if (hit_t < 0.0) { return vec4(0.0, 0.0, 0.0, shadow_alpha); }                           // If neither lid nor body was reached, draw only the shadow.
```

This is the expensive section.  It is a **march**: sample forward, sample forward, and stop when a sample moves from outside to inside.  The five-step inner loop is a **binary search**: it repeatedly cuts the uncertain gap in half to find the surface more precisely.

## 9. Set up shared colour controls at the confirmed surface point

```glsl
	vec2 point = relative + ray * hit_t;                                                     // Turn the accepted ray distance into the barrel-surface point.
	float distance_fade = 1.0 - smoothstep(1.4, 4.2, length(relative));                      // Fade dark stave details with camera distance.
	float highlight_fade = 1.0 - smoothstep(1.1, 3.2, length(relative));                     // Fade bright wood-detail highlights with camera distance.
	vec3 color;                                                                               // Reserve a three-number RGB colour before choosing lid or side material.
```

`vec3` is a three-number colour: red, green, blue.  These fades affect decoration, not whether the barrel itself exists.

## 10. Shade the lid

```glsl
	if (lid) {                                                                                // Use this whole block only when the ray's nearest hit belongs to the top.
		float inset_t = (barrel_height * 0.92 - 0.5) / rise;                                   // Find a slightly lower plane: the recessed lid panel.
		vec2 inset_point = relative + ray * inset_t;                                            // Find where this ray crosses that lower panel plane.
		float inset_r = length(inset_point) / radius;                                           // Measure distance from lid centre in rim-radius units.
		color = vec3(0.35, 0.24, 0.15);                                                        // Start with the dark outer/lip wood colour.
		if (inset_t > 0.0 && inset_r < 0.80) {                                                  // If the ray reaches the recessed inner 80% of the lid...
			color = vec3(0.53, 0.40, 0.28);                                                      // ...use the lighter inset-board wood colour.
			float board = inset_point.x / radius;                                                // Describe position across the lid in barrel-radius units.
			float board_width = max(fwidth(board), 0.01);                                        // Estimate one logical pixel's width across the lid.
			float seam = abs(abs(board) - 0.27);                                                  // Measure closeness to either of the two lid-board seam positions.
			float seam_neighbor = abs(abs(board - dFdx(board)) - 0.27);                          // Look one pixel sideways to detect the bright edge beside a seam.
			if (seam < board_width * 0.5) { color *= mix(1.0, 0.62, distance_fade); }             // Darken a seam, weakening that darkness far away.
			else if (seam_neighbor < board_width * 0.5) { color *= mix(1.0, 1.20, highlight_fade); } // Lighten the adjacent board edge, fading at distance.
		}                                                                                       // Finish inset-panel test.
	} else {                                                                                  // Otherwise, this hit belongs to the curved wooden side.
```

`dFdx` means “how much did this value change one screen pixel to the right?”  Here it lets a highlight occupy the pixel next to a dark seam rather than replacing the seam itself.

## 11. Shade curved side wood and its stave seams

```glsl
		float h = clamp((0.5 + rise * hit_t) / barrel_height, 0.0, 1.0);                       // Recalculate the confirmed surface height from 0 bottom to 1 top.
		vec2 n = normalize(point);                                                              // Turn centre-to-surface direction into a unit arrow: direction without distance.
		float across = dot(n, camera_right);                                                    // Measure whether this surface faces sideways relative to the camera.
		float light = (0.68 + 0.32 * sqrt(max(0.0, 1.0 - across * across))) * mix(0.68, 1.15, h); // Make middle-facing wood brighter and upper wood brighter than lower wood.
		light = floor(light * 16.0 + 0.5) / 16.0;                                               // Restrict lighting to 16 deliberate pixel-art brightness steps.
		color = vec3(0.52, 0.36, 0.22) * light;                                                // Apply that stepped light to the base wood colour.
		float stave_position = (atan(n.y, n.x) / 6.2831853) * 8.0;                             // Turn around-the-barrel direction into eight repeating stave positions.
		float seam = abs(fract(stave_position + 0.5) - 0.5);                                    // Make 0 at each stave seam and rise toward each stave centre.
		float seam_width = clamp(fwidth(stave_position), 0.015, 0.25);                         // Estimate a readable one-pixel seam width, with safe limits.
		float neighbor = abs(fract(stave_position - dFdx(stave_position) + 0.5) - 0.5);        // Detect whether the pixel to the side sits on a seam.
		if (seam < seam_width * 0.5) { color *= mix(1.0, 0.68, distance_fade); }                // Darken an actual stave seam, less strongly in the distance.
		else if (neighbor < seam_width * 0.5) { color *= mix(1.0, 1.28, highlight_fade); }     // Lighten the wood immediately beside a seam, less strongly in the distance.
```

`normalize` keeps only direction.  `atan` converts a direction into “where around a circle?”  `fract` keeps the repeating decimal part, which is how the shader repeats the seam pattern eight times around the barrel.

## 12. Draw hoops, their highlight, and shadow

```glsl
		float hoop_delta = h - (h < 0.5 ? 0.25 : 0.75);                                        // Measure vertical distance from the nearer hoop: one at 25%, one at 75% height.
		float hoop_vertical_pixel = clamp(hit_t / (128.0 * barrel_height), 0.001, 0.25);        // Estimate one screen pixel's height in barrel-height units, safely even at an edge.
		float hoop_pixel = clamp(fwidth(h), hoop_vertical_pixel, hoop_vertical_pixel * 2.0);    // Use the real local pixel size but prevent edge derivatives from becoming absurdly wide or narrow.
		float hoop_highlight = 1.0 - smoothstep(0.9, 2.7, length(relative));                    // Fade hoop highlight as the camera moves away.
		float distant_hoop = smoothstep(0.9, 1.8, length(relative));                            // Blend toward the compact one-pixel far-hoop treatment.
		float hoop_half_width = mix(0.75, 0.5, distant_hoop);                                  // Make the central metal band thinner in the distance.
		float highlight_outer = mix(1.75, 0.5, distant_hoop);                                  // Collapse the separate highlight row into the metal row in the distance.
		vec3 metal = vec3(0.29, 0.27, 0.24);                                                    // Choose dark grey-brown metal rather than pure grey.
		vec3 lit_metal = metal * mix(1.0, 1.45, hoop_highlight);                                // Make a lighter version of that same metal colour.
		if (abs(hoop_delta) < hoop_pixel * hoop_half_width) { color = mix(metal, lit_metal, distant_hoop * 0.5); } // Paint the main metal hoop.
		else if (hoop_delta >= hoop_pixel * hoop_half_width && hoop_delta < hoop_pixel * highlight_outer) { color = lit_metal; } // Paint the near-only upper highlight row.
		else if (hoop_delta <= -hoop_pixel * hoop_half_width && hoop_delta > -hoop_pixel * (hoop_half_width + 1.0)) { color *= 0.70; } // Darken the wood directly below the hoop.
	}                                                                                         // Finish curved-side shading.
```

The hoop is not a line drawn over the wood.  Each pixel decides whether its *surface point* falls in a hoop-height band, so the hoop curves correctly around the barrel.

## 13. Put the rim above every lid detail, then send the colour back

```glsl
	if (top_t > 0.0 && top_r <= 1.0 && top_r >= 1.0 - rim_width) {                           // If this pixel is in the thin outer ring of the valid lid...
		bool front_rim = dot(top_point, relative) > 0.0;                                        // ...decide whether it is the camera-facing half of that ring.
		vec3 rim_wood = vec3(0.52, 0.36, 0.22);                                                 // Use the same basic family as the side wood.
		color = rim_wood * (front_rim ? 1.30 : 1.12);                                           // Make the front rim brighter than the rear rim.
	}                                                                                         // Finish the final, deliberately topmost rim pass.
	return vec4(color, 1.0);                                                                  // Return opaque red/green/blue plus alpha 1 for the barrel itself.
}                                                                                           // Finish shade_barrel.

void fragment() {                                                                           // Godot calls this once for every pixel covered by the barrel drawing rectangle.
	COLOR = shade_barrel(rect_origin + UV * rect_size);                                       // Convert the rectangle's local UV coordinate into a logical screen pixel, then shade it.
}                                                                                           // Finish the actual shader entry point.
```

`UV` is a built-in pair that runs from 0 to 1 across the rectangle.  The final line turns that local position into the game’s logical screen coordinate, then calls everything above.

## Read this before optimizing it

The 49-step `for` loop in section 8 is the major per-pixel cost.  It exists because the curved side uses a sine-wave profile rather than one simple mathematical cylinder.  The important visual invariant is not “49 samples”; it is: *a ray finds the nearest accurate body surface, then every decorative mark is derived from that same surface point.*
