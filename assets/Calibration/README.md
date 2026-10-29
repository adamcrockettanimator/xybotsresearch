# Xybots Projection Calibration

This folder owns the shared, neutral greybox contract used to compare Blender
and Godot before a purchased 3D prop is turned into a semantic pixel sprite.

- `xybots_projection_contract.json` is the source of truth for the 160x120
  logical canvas, perspective camera, horizon, player framing, scale grid, and
  named primitive fixtures.
- `xybots_greybox_grid.png` is the neutral 50-percent-grey grid swatch. Minor
  marks are 1/32-cell increments and major marks are whole cells. They are
  world-anchored, so their scale and origin agree on floors, walls, and props.
- `xybots_projection_calibration.blend` contains the generated Blender scene.
  It preserves Blender's original default `Scene` and puts the rig in the
  separate `Xybots_Projection_Calibration` scene.
- `blender_greybox_reference.png` is a 160x120 reference render. The `_4x`
  version is only an inspection enlargement, not source art.
- `captures/blender_flat_*`, `captures/godot_flat_*`, and
  `captures/flat_overlay_*` are the unlit projection-only comparison set.
  In an overlay, Godot is red, Blender is cyan, and agreement tends pale.
- `primitive_plates/` contains transparent 160x120 Blender plates for every
  greybox primitive and every calibration heading. `manifest.json` records the
  logical projected foot anchor for each one. These are comparison plates, not
  final cropped/atlased game sprites.
- `primitive_sprite_sources/` and `primitive_sprites/` contain the portable
  4x source plates and cropped runtime sprites. They export 32 headings at
  11.25-degree intervals. Runtime prop sprites intentionally omit the grid;
  their unlit base tint is driven by geometric Z normal (up bright, side
  neutral, down dark); only convex highlights and
  concave/depth shadows are composited—silhouette outlines are disabled.
- `Grid_Cell_Block` is the first live-game fixture: exactly `1×1×2/3` game
  units, rendered as a wireframe and never reduced to the ordinary prop scale.
  It has four separately rendered perspective sources at 1.25, 2.5, 4.0, and
  5.5 game-unit depths. Godot picks the nearest authored source for its live
  depth, then performs only the small remaining scale adjustment inside that
  band. This is the first practical semantic/perspective LOD test: distant
  views are not merely a uniformly shrunken near render.
- `Imported_Barrel_01` is the first Asset Browser prop test. The build creates
  a local single-user copy of `SM_Prop_Barrel_01` only for render export, so
  the purchased source asset remains untouched. The local copy is rendered at
  `0.38` of its raw Asset Browser size: this is the current visual match for a
  small world prop, not a claim about the vendor asset's real-world units.
  It deliberately discards the purchased material and all baked lighting.
  Its semantic render is a flat, three-value wood palette chosen from the
  geometric Z normal: upward faces are light, vertical faces are midtone, and
  downward faces are dark.
- The imported barrel has its own 16 camera headings at 22.5-degree intervals
  and ten *real* depth renders (`lod_00` through `lod_09`) from 0.72 to 5.25
  game units. `lod_00` alone receives the normal/depth compositor's convex
  highlights and concave/depth shadows; its silhouette-outline control remains
  off. The nine farther LODs remain clean flat palette renders. Godot selects
  these frames directly and never rotates, mirrors, or uniformly shrinks a
  single close barrel as a substitute for them.
  The calibration boundary mirrors Godot's screen-handed map Y into Blender:
  Godot yaw-zero forward is game `-Y`, which becomes Blender `+Y`; positive
  yaw rotates toward game `+X`. This reflection is required so the 32-way
  Blender sequence turns in the same sense as the live camera.

To rebuild the Blender fixture, run
`tools/xybots_projection_calibration_blender.py` in Blender's Scripting
workspace. It recreates only the `Xybots_Greybox_Assets` collection in the
calibration scene.

To inspect the Godot fixture, open and run
`res://tests/calibration/greybox_projection_calibration.tscn`. It draws the
same primitive manifest with the runtime perspective equation. Press `1`, `2`,
or `3` for north, 45-degree, and east-facing diagnostic poses; press `R` to
reset. This is a calibration harness, not yet a replacement for the playable
level renderer.

To check the actual Blender-to-Godot texture handoff, run
`res://tests/calibration/primitive_sprite_plate_comparison.tscn`. It overlays
the selected cyan Blender plate on the matching procedural greybox render.
Use `Q`/`E` to select a primitive, `1`/`2`/`3` to select north/45°/east, and
Space to toggle the plate.

To judge the canonical fixture against actual wall segments, run
`res://tests/calibration/live_cell_block_projection_test.tscn`. It contains
only that one Blender-rendered cell block in the ordinary coordinate-frame
level; use the existing movement and camera controls to inspect it from
several headings.
