---
name: xybots-semantic-prop-authoring
description: Build or refine Grudge County/Xybots semantic pixel-art props, characters, environment pieces, or effects using the shared logical viewport and GPU-cage paint-mask method. Use for creating or refining procedural pixel-art forms, surface treatments, lighting, distance legibility, or occlusion in the game.
---

# Xybots Semantic Prop Authoring

Use this skill to create or refine a **semantic** game element: one whose low-resolution
pixels are assembled from named visual parts rather than painted as a normal
textured low-poly model.

The default technique is a small static 3D cage projected into the shared
logical viewport. The GPU paints named masks from that projection; the CPU
keeps world placement, collision, destruction, and network-relevant state.

## Start here

1. Use the active gameplay worktree. Check the branch and scene before editing.
   The default checkout is `D:\Godot\xybotsResearch\Project\xybots-research`.
2. Read `PROJECT_STATUS.md`, then read the appropriate sections of:
   - `docs/semantic_gpu_cage/authoring.md`
   - `docs/semantic_gpu_cage/debugging.md` when a visual explanation is requested
   - `docs/semantic_gpu_cage/prop_brief_template.md` when the brief is incomplete
3. Inspect the closest live examples before changing code:
   - crate: `scripts/semantic_gpu_lattice_crate.gd`,
     `scripts/semantic_gpu_lattice_crate.gdshader`, and
     `scripts/semantic_gpu_lattice_crate_style.gd`
   - barrel: `scripts/semantic_gpu_cage_barrel.gd`,
     `scripts/semantic_gpu_cage_barrel.gdshader`, and
     `scripts/semantic_gpu_cage_barrel_style.gd`
4. Inspect the current `run/main_scene` before assuming whether the user wants
   a calibration scene or the title-menu gameplay path.

## Working contract

- Preserve the shared low-resolution gameplay viewport. Do not substitute a
  normal textured 3D mesh or a full-resolution prop render when the target is
  semantic pixel art.
- Make the cage small, static, and reusable. It defines form and projection;
  it is not the final visual. Prefer a small set of corners/rows/columns that
  explain the prop's major planes.
- Paint semantic parts in a documented back-to-front order. Typical parts are
  a contact shadow, recessed/interior region, body planes, frames or seams,
  metal/trim, and close-only highlights. The order must be intentional.
- Keep pixel widths in **logical pixels** whenever an artist expects a
  one-pixel edge, seam, highlight, or far-distance reduction.
- Give artist-facing values inspector controls backed by a dedicated `Resource`
  (`.tres`). Persist Remote Inspector changes only when their values change;
  never save runtime world placement or projected screen coordinates.
- Treat world location, facing, collision, damage, destruction, loot, and
  network state as gameplay data. Do not replicate projected points, masks, or
  debug geometry.
- Add layer-specific LOD rather than uniformly fading the whole prop. A useful
  pattern is: highlight fades, feature narrows to one logical pixel, then
  optional shadow/detail fades. Keep identity-defining features visible if the
  brief requires it.
- Use fragment-selected logical cells for normal GPU semantic paint. If a tiny
  shared-corner accent must unconditionally draw after every face-local
  carrier, use a final logical raster overlay only for that accent (for example,
  a crate's three-segment front Y). Keep it to a few projected strokes; do not
  move general panel or silhouette paint back to CPU. Cross-fade alternate
  camera-relative candidates instead of switching them at a direction sign.
- For a side material height ramp, expose persisted bottom/top light controls
  and apply the same local-height multiplier to the side plane, inset panel,
  slats, and brace. Preserve a separately authored top-plane colour.

## Debugging contract

When the user asks how a prop is assembled, add two independently toggled,
full-resolution-only views:

- **Cage wireframe:** thin, visible-facing construction edges.
- **Semantic geometry:** thin projected boundaries for the *actual shader
  masks*—for example frame, inset, displaced recess shadow, seams, brace,
  rim, contact edge, or glow boundary.

The debug overlay must not add a second rendered prop, alter shared viewport
pixels, or show generic grid lines in place of the semantic parts it claims to
explain.

## Storefront field notes

For outdoor buildings, read the storefront field notes in the active
checkout's `docs/semantic_gpu_cage/authoring.md`. They cover the four-corner
shell, shared procedural floor, GPU siding and corrugation, painted lettering,
west-sun shading, window and roof trim, grass, and camera-cone ordering.

Keep visible identity through distance changes. Use a building-wide blend for
the siding, projected spacing for roof ribs and strokes, and independent
fades for fine accents. Apply surface lighting to painted details. Use the
existing shader, projection, and draw-order paths as the starting point.

For ordering issues, reproduce the camera pose and identify the two
overlapping surfaces before changing a layer. The player wall cutaway,
footprint ordering, and grass-to-floor depth check answer different
questions. See `docs/semantic_gpu_cage/debugging.md` for F9, F10, and the
Fan Draw Order overlay.

### Translating a Blender model

- Compare the detailed source with its outline cage, when available. Measure
  the outline, openings, major silhouette, contact faces, member sections,
  and joins. Preserve visible depth changes as carrier geometry when they
  affect parallax, occlusion, or silhouette. Paint repeated surface relief
  and small bevels as projected semantic strokes.
- Give each joint shadow a receiving face. A brace under a header shades its
  underside, and a rail at a post shades the face it enters. Keep the other
  faces flat. Let a protruding member hide its shadow at oblique angles.
  Use a soft falloff up close and keep a one-logical-pixel core where the
  joint needs to read at distance. Shade the material before atmospheric haze.
- Keep structural strokes independent of repeating texture. Let distant
  siding become broad color blocks while posts, roof lips, and intact window
  crosses remain legible. Snap each crossbar to its own screen axis when it
  gets too thin, and remove the cross when the window breaks.
- Compare interior and exterior views, including the player inside while the
  follow camera trails outside. For stray pixels, reproduce the pose, hide
  candidate render layers individually, and compare the same logical cells
  before changing the owner.

Read the **Blender-to-GPU example: Gable Coffee Shop** in
`docs/semantic_gpu_cage/authoring.md` for the source collection, shader
entry points, joinery and palette decisions, and shared-viewport checks.

## Delivery and verification

For a new prop, create or update the component script, shader, style resource,
integration point, and a focused calibration/authoring fixture as appropriate.
Verify script loadability with the repository smoke-test wrapper and inspect
the running scene for the requested visual behavior. Static checks do not
prove pixel-art appearance, LOD behavior, collision, or physical-controller
behavior.

Keep unrelated working-tree changes untouched. Do not commit or push unless
the user asks.
