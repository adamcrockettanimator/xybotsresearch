# Semantic GPU Cage Debugging

Use debug views to answer: **which projected structure produces these final
pixels?** A debug view is successful only if an artist can map its lines to
the named paint components.

## Two separate overlays

### Cage wireframe

Shows only the projected, camera-facing construction edges: the minimal
structural lattice used to establish the prop's planes and silhouette.

This answers: “what 3D form is the semantic prop derived from?”

### Semantic geometry

Shows boundaries for the shader masks that assemble the pixel art. Examples:

- crate outer frame, inset panel, one-pixel inset/brace extrusion bands, vertical slats,
  diagonal brace, bevel/rim, bottom contact edge;
- barrel body rows, interior opening, inner rim, lid, staves, hoop shadow,
  metal band, hoop highlight, and floor-contact edge.

This answers: “what named semantic layer is responsible for this patch of
pixels?”

## Rules

- Draw debug overlays at full application resolution with thin real-pixel
  strokes, so they stay readable.
- Never draw the overlay into the logical gameplay viewport.
- Cull back-facing geometry unless the debug question specifically needs it.
- Do not use a generic mesh grid as a stand-in for semantic geometry. If a
  feature is painted from a mask, its mask boundary is the line to show.
- Label or document a stable colour key whenever there are several semantic
  stroke families. Keep labels outside the prop whenever possible.
- The overlay must not create a second carrier mesh or alter the rendered
  pixels, collision, or LOD decisions.

## Eight-corner crate colour key

The crate's cage-wireframe toggle is cyan: only the physical cube-face edges
from its eight corners are shown. It does not show a hidden raster or a
subdivision grid.

The crate's semantic-geometry toggle uses the following projected shader-mask
boundaries: orange for the outer frame, amber for the inset opening, purple
for the lid's directional recess and the side panels' top/far-edge extrusion
shadows, yellow for the side panels' always-on bottom inset highlight and
edge-highlight centreline, magenta for slats, blue for the diagonal brace, and
navy for the camera-facing L-shaped contact-shadow stroke. These lines are projected with the same
perspective-correct face coordinates used by the shader; they are diagnostic
evidence, not decorative outlines.

## Inspecting a surprising pixel

1. Enable semantic geometry, not just the cage wireframe.
2. Identify the nearest component boundary and its expected layer order.
3. Check whether the feature is changing because of distance, angle/silhouette
   suppression, a logical-pixel width transition, or mask order.
4. Fix the named component or its mask. Do not hide the symptom by adding
   unrelated geometry.
