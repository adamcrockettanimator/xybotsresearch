# Semantic GPU Cage Authoring

This is the reusable construction method behind the current GPU-cage barrel
and crate. It is for game elements that should read as perspective-correct,
late-1980s pixel art while still being explainable as meaningful parts.

## The idea in one sentence

Build a small 3D **cage** for the object's major planes, project that cage to
the shared logical viewport, and have the GPU paint named visual layers from
the projected faces.

The cage is like the carpenter's chalk layout; it tells the painter where the
front, side, top, recesses, and edges are. It is not a textured low-poly
asset. The shader paints the final pixels.

## Runtime ownership

| Owner | Responsibility |
| --- | --- |
| Gameplay / CPU | World position, facing, collision, damage, destruction, loot, and camera inputs. |
| Static cage mesh | A small stable set of local vertices and face indices. It is rebuilt only when authoring topology changes. |
| GPU shader | Projection, visible-face tests, material masks, logical-pixel widths, colour treatment, and semantic LOD. |
| Style resource | Artist-facing colours, switches, widths, fades, angles, and distance thresholds. |
| Full-resolution overlay | Debug-only cage and semantic mask boundaries. It never paints into the shared logical viewport. |

Only the left column is gameplay/network data. Do not save or replicate
screen-space points: camera movement changes them every frame.

## Shared logical-viewport rule

The final semantic prop must be painted into the same low-resolution gameplay
target as its neighbouring pixel art. Its output then scales with the game.
Normal 3D mesh rendering and full-resolution debugging are allowed only as
references or overlays; they cannot silently become the final prop path.

Current examples use a `160x120` logical viewport. Treat its dimensions as
runtime configuration, not an excuse to hard-code arbitrary physical-pixel
line widths.

## Compose named paint layers

Before coding, write the layer order from back to front. For example:

```text
contact shadow
recess/interior
base planes by axis
inset panel or body variation
seams / slats / braces
trim or hoop shadow
trim or hoop metal
trim or hoop highlight
one-pixel close-only rim or bevel highlight
```

Not every prop needs every layer. The point is that each visible feature has a
name, a purpose, a masking rule, and a predictable place in the stack.

### Shared-edge accents

Prefer GPU logical-cell masks for normal semantic layers. A shared corner
accent can be the exception when it must visually win over every face-local
carrier: paint only that small final accent through the logical raster overlay
after the GPU layers. This is appropriate for the crate's three-segment front
Y, not for general panel, slat, or silhouette paint. Keep its stroke count
small, use projected cage endpoints, and fade alternate camera-relative
candidates rather than switching them on a sign change.

For an overall side material gradient, expose bottom and top light multipliers
and apply their local-height interpolation to the side plane, inset panel,
slats, and brace together. Keep the top plane on its own authored colour.

## Cages should be minimal but descriptive

- A crate begins with eight cube corners. More rows/columns are only useful if
  a feature needs them.
- A barrel uses a low-sided, height-row cage so its round silhouette, top,
  hoops, and staves have shared projected structure.
- A character, environment piece, or effect can use a different cage: planes,
  ribbons, capsules, or a small skeletal chain. The principle is unchanged.
- Reuse a projected face or edge for several masks when it represents the same
  physical structure. Do not make duplicate CPU geometry merely to draw a
  highlight, shadow, or line.

## Inspector and persistence contract

Give each artist-visible component a clear control group:

- paint colours and material stops;
- show/hide switches;
- logical-pixel widths;
- shape controls such as inset, swell, radius, or lid height;
- silhouette/angle suppression;
- full and hidden distances for each detail family.

Keep those controls in a dedicated style `Resource` and save only edited style
values. Remote Inspector tuning should survive stopping and restarting the
game. Runtime transform, current projected points, and debug state should not
become authored style accidentally.

### Remote Inspector safety

Do not store per-frame rebuilt projected faces, debug strokes, or raster-layer
arrays as ordinary script members. The Remote Debugger serializes those members
while an Inspector slider is sending updates; continuous mutation can overflow
its 8 MB packet limit and disconnect the game. Keep transient geometry local to
the rebuild method, update drawing nodes only when the geometry changes, and
persist only the final artist-facing style values.

## Semantic LOD

LOD is a visual decision per feature, not simply opacity for the whole prop.

1. Keep the essential silhouette and axis/form colours.
2. Fade highlights and fine seams first.
3. Reduce heavy trim from a close multi-pixel width to one logical pixel.
4. Retain or remove shadows according to whether they preserve readability.
5. Hide interior/recess work when its opening is too oblique or too small to
   read.

Use meaningful groups—such as `staves`, `rim highlight`, `brace`, `hoop
accent`, `interior opening`—and give each group an independent fade range when
the user needs art direction over it.

## Existing implementations

- `scripts/semantic_gpu_lattice_crate.gd`: eight-corner crate, static projected
  faces, semantic panel/frame/slat/brace masks, style persistence, and debug
  overlay.
- `scripts/semantic_gpu_cage_barrel.gd`: low-sided barrel cage with the more
  extensive interior, rim, lid, hoop, stave, and layer-specific LOD work.
- `tests/calibration/semantic_crate_authoring.gd`: focused authoring scene.

Read the closest one before adding a new prop. Copy the architectural pattern,
not the prop-specific numbers or names.

## Storefront field notes

### Footprint and rendering

- Use the four world-space footprint corners as the exterior shell's
  placement. Derive wall segments and elevations, then let the GPU paint
  continuous walls and mask door, window, and trim details in world-aligned
  face coordinates. Grid boundaries alone do not require rendered seams.
  Keep physical doorway spans, collision, moving doors, and local cutaways
  on their established paths.
- Use one raised rectangular plane for the room and porch at their common
  elevation. The plane samples the same world-rooted staggered procedural
  WoodFloor2 material as the cell renderer. Its board lanes, ends, and palette
  vary procedurally. Retain the bitmap comparison where the texture selector
  needs it. Filter projected texel footprints near grazing angles and keep
  the facade contact shadow and doorway spill tied to the shared plane.
- Distinguish the top-down footprint, GPU carrier geometry, shader paint,
  and CPU visibility and layer work. An overlay line identifies a construction
  edge or a mask boundary. Measure the relevant passes at a matched camera
  pose with debug overlays disabled when comparing CPU and GPU frame cost.

### Siding, lettering, and lighting

- Use continuous world-height courses, a fixed board pitch, and one stable
  tone variation per board. Keep the established storefront free of staggered
  vertical joints and alternating brick-like blocks. Shade each lap with a
  broad gradient and a hard, dark underside. The first two courses can hold a
  one-logical-pixel underside, the higher boards show more underside, and
  the courses above the porch roof cap it at three logical pixels.
- On a receding wall, show the siding thickness at the far jamb or corner
  post. The near post covers the return. Let the bright lower lip project
  past the dark recessed edge.
- Set the siding detail blend once per building from the camera's nearest
  footprint distance. Keep both ends of the wall at the same detail level.
  Fade the ramps and lap shadows into stronger flat per-board shades so
  distant walls still read as paneling. Preserve the author-approved near
  look and adjust the fade range independently of board spacing.
- Paint lettering such as COFFEE as ink within the siding material. Anchor
  the glyphs to the full facade so a physical wall span cannot break them.
  Use simple block strokes with room between letters. Set the near weight
  in face coordinates and use the projected footprint to keep strokes
  legible at roughly one logical pixel farther away. Apply the same siding
  gradients, lap shadows, face light, and haze to the near-black ink.
  For framed town signs, allocate projected logical-pixel columns and rows
  to whole glyphs, preserving letter spacing and interior gaps where the
  projection permits. Switch to the compact three-column form before a
  five-column glyph loses strokes; below three columns or five rows, use
  restrained coverage as a fallback rather than claiming full legibility.
- The town sun is in the west, which is negative world X. Shade fixed world
  faces accordingly. West is brightest, east darkest, and north and south
  sit between them. Give the roof top its own tone. Keep the hard foundation
  contact shadow tucked close to the raised base, with a small eastward
  extension. Keep foot trim and cast shadows visually distinct.

### Indoor depth and outdoor haze

Use Classic shading as the baseline for enterable outdoor buildings. For each
surface hit, clip the camera-to-hit ray against the building footprints.
Darken the interior material using the covered part of the ray, then apply
the town's ochre haze using the uncovered part. Looking through an open
door from the street applies indoor depth first and street haze second. A
ray wholly inside one building has zero exterior haze. Looking out through
a door or window applies haze to the outdoor segment beyond the opening.

For a new outdoor level, register its enclosed building rectangles through
the controller's `town_roof_rects()` API. Use world-grid coordinates and
non-overlapping footprints. Exclude the porch and awning overhang from the
enclosure. The renderer's `_set_town_lighting()` supplies the same footprints
to walls, cell floors and ceilings, and continuous storefront planes. The
current shader uniform array bounds the number of footprints. If a level
needs more entries, update the renderer and all shader consumers together.

Reuse `town_outdoor_depth()` and `daylight_color()` from
[`coordinate_frame_daylight.gdshaderinc`](../../scripts/coordinate_frame_daylight.gdshaderinc).
In shader includes, keep `room_bounds` distinct from the storefront plane's
`bounds` uniform. A name collision made the floor report zero outdoor depth
while the back wall still received haze. For horizontal surfaces, use
[`coordinate_frame_plane_depth_light.gdshaderinc`](../../scripts/coordinate_frame_plane_depth_light.gdshaderinc)
with the indoor distance and the plane's own height delta. Classic uses
the existing floor tone at the doorway and skips the experimental bright
strip at the jamb.

Compare the back wall and the floor directly beneath it at the same doorway
from across the street and up close. Then step inside and check both the
far interior wall and a view out through a window. Include a narrow shop
and a deep room so short and long indoor rays both get exercised.

### Line continuity and motion

- An intentional line is a solid, connected aliased stroke while its semantic
  layer is visible. Choose logical pixel cells from the projected feature;
  sampling a narrow world-space band at pixel centres can leave holes or make
  the whole line disappear between columns. Diagonals need connected raster
  coverage, not independently sampled fragments.
- At a fixed distance and angle, small camera translations must not switch a
  visible line on and off. Fade or simplify details deliberately by their
  authored distance and angle rules. Check a sequence of subpixel camera
  positions, both face ownership transitions and occlusion, not just stills.
- The porch timber pass selects projected face-edge pixels for post rims and
  top/bottom rows for rails and braces. Verify those selections on real
  geometry, including grazing angles, short braces and overlapping members;
  a selected cell can still be clipped by a carrier or another surface.

### Roofing and joinery

These notes describe the storefront kit. The gable shop uses the simpler
cornice, beam, and frame treatments in the Blender-to-GPU example below.

- Paint corrugation on the roof and awning planes. The current storefront
  uses 18 fine ribs with linear ramps, a darker slope on one side, and a
  brighter slope on the other. Use crisp, close-only one-pixel crest and
  crevice accents at restrained contrast. Crossfade into broader light and
  dark pairs anchored to every other crest when the 18 ribs become too
  small. Let the broader pattern lose contrast gradually. Check angle and
  projected spacing as well as distance.
- Start galvanized metal gray. Add muted brown oxide streaks along the sheet
  and fade their fine variation as projected texels become too small. Keep
  the oxidation scale independent of corrugation density. Use the nearby
  metal highlights to convey form, with rust providing color variation.
- Keep broad porch shading legible as fine details simplify: the facade is
  darkest directly below the awning and lightens toward the floor; the deck
  is darkest at the wall and lightens toward the street. Balusters receive
  a contact shadow below the handrail. These structural shadows do not use
  the close-only highlight fade.
- Put the porch beam between the posts and below the awning plane. Paint a
  roof shadow on the upper face, and check oblique views for floating strips
  or roof overlap. Give the front cornice a lit lip, dark groove, beveled face,
  and lower bead. Keep rear trim slim, close to the wall, with a shadow below.
  Center porch posts on the deck corners so their outer faces extend beyond
  both deck edges, with the same section as the
  building corner posts. Carry supports to ground below the raised apron, and
  show the ground shadow beneath the floor. Keep the rail gap aligned with the door.
- Give the door header a continuous tone and the visible jamb a return that
  narrows head-on. Use a thin full-height side return on the window and keep
  its head and sill lighting. Treat the center cross as one piece by shading
  the four pane borders and stopping those edge accents at the intersection.
  Use the near-only glint on the brass knob when it can resolve.
- Keep the window opening bounds shared with gameplay. The intact cross and
  pane reflections can use a parallax sash shadow. After breakage, keep
  fragments on the outer frame and clear the cross. When touching these
  paths, verify real shots at the appropriate height through collision, aim
  assist, hit confirmation, and tracer placement. Preserve fence movement
  blocking and projectile pass-through.

### Occlusion and verification

- Keep the local player's wall cutaway triangle bounded by the silhouette.
  For footprint draw ordering, test the entire angular cone. A wall behind
  a prop can overlap it in projection and must contribute a background
  constraint. Reserve a Canvas layer between a town background wall and
  the player so a crate can draw between them. Reproduce the camera pose and
  check layer numbers alongside the pixels. Crate, grass, and player overlaps
  can use different sorting paths.
- Dry grass uses a tight carrier per clump, world-rooted one-logical-pixel
  stems, and a separate fade for extra close blades. The clump cone checks
  visibility and sorts against walls. Compare each grass pixel's depth with
  the shared raised floor to hide stems behind the deck and room floor.
  Grass and actors can still overlap imperfectly when a whole clump straddles
  the actor's depth. Check a reproduced pose before changing the layer rules.
  Fence rails also need grazing-angle checks so thin rails remain continuous.
- Inspect the running scene head-on, at a grazing angle, and progressively
  farther away. Include west and east views for world lighting and an interior
  view for floor and cutaway changes. For layering, confirm both a wall behind
  a prop and a wall legitimately in front. Use the existing storefront and
  footprint smoke tests in addition to the player-view captures.

The storefront examples live in `scripts/town_storefront_style.gd`,
`scripts/town_storefront_plane.gdshader`,
`scripts/coordinate_frame_semantic_floor.gdshaderinc`,
`scripts/town_grass_strokes.gdshader`, and the coordinate-frame wall shader
and renderer. `tests/town_storefront_test.gd` and
`tests/footprint_wall_visibility_test.gd` cover the relevant gameplay and
ordering rules.

## Blender-to-GPU example: Gable Coffee Shop

The gable shop is the reference for reading an authored Blender building and
rebuilding it as semantic pixel art. The source is
`D:/Godot/xybotsResearch/blender/syntyCowboyTown.blend`, collection
`Shop_1x2.5_gableRoof`. Use the detailed model for the construction and
lighting reference and `OUTLINE.001` for the shell and cutouts. The Coffee
Town example is north-facing at `Rect2i(5, 11, 1, 2)`, beside the two earlier
1×2 shops. Those neighbors are useful comparisons for the distant palette,
simple foundation, and the dimensional joinery.

### Read the model before choosing the carriers

- Measure relative to the footprint, street orientation, and finished floor.
  This asset uses four Blender units per town cell. Record the wall, gable,
  false front, roof slopes, porch, foundation, door and window openings,
  post sections, brace joints, and roof lining. Treat the model's bevels as
  evidence for where a pixel highlight or crevice belongs. Check both sides
  of moving parts. The model supplied exterior knobs, and the game doors also
  needed hardware on the inside.
- Keep geometry where it changes the silhouette, occlusion, parallax, or how
  a part attaches. The shell and roof planes, the door leaf, and the analytic
  timber members carry depth. Shaders paint the repeating siding, metal ribs,
  rust, panel bevels, and small hardware details. Use the authored opening
  bounds for both the visible window and gameplay breakage and vaulting.
- Keep related dimensions shared. The two rear, two front, and two porch
  posts use the same square section. Their heights vary, and the tall front
  posts keep their side face and the same shading above the porch roof.
  Preserve the deck as one walkable plane with a dark fascia below it and
  a single simple contact shadow at ground level.

### Paint form and contact shadows

- Give the porch beam and rafters flat directional face tones, with darker
  undersides. The overhanging metal shades the timber immediately below
  it. The false-front cornice casts its own contact stroke on the siding
  directly below the cornice. Keep that stroke off the corner posts.
  Keep one metal-colored pixel along the exposed gable/eave edge when
  the sheet is edge-on. Avoid painting a line down the roof ridge or
  stacking decorative bands under the metal. At the prototype comparison
  distance, omit an extra siding seam when it competes with the overhang.
- End a knee brace vertically into its post and horizontally against the
  underside of the header. Show the brace's actual visible planes. Select an
  edge highlight or shadow from the adjacent visible face and fade the
  accent as it becomes too small. Limit joint shadows to their receivers.
  The brace meets the header underside, rafters meet the header's back, and
  the brace and railing shade the inward face of the post where they enter.
  Use the actual member face and contact extent. A distance to the entire
  neighbor box by itself paints across corners and wraps the beam.
- Project the post return so it hides part of the shadow on a receding
  wall. Follow the joint from the top trim down across the foundation.
  Shade the foundation under the lowest siding course. On the porch,
  put the rail's deck shadow directly below the rail and extend it to the
  fascia. Keep small foot contacts local to the posts and balusters.
- Use two distinct door shadows. On the wall outside the casing, use
  rounded falloff around the corners, a shorter shadow above and a broader
  shadow below the threshold. On the closed door leaf, put the darkest
  reveal under the header and a narrower contact at the sill and jambs.
  Fade the reveal as the leaf swings out. Keep the casing a solid flat
  ring with a continuous side return at oblique angles. At distance, reserve
  the first logical stroke for the casing. Draw the reveal only where there
  is room inside the opening and the view exposes it. Give a shadow caster
  priority whenever its silhouette and its shadow compete for one pixel.
  Paint the two inset
  panels with coherent projected bevel strokes. Keep knob positions tied to
  the leaf, with hardware on both faces.
- Place contact shadows on the material before outdoor haze. Up close,
  allow a wider soft falloff. At distance retain one logical pixel where it
  conveys form, with less contrast as atmospheric perspective increases.
  Resolve overlapping contact masks without piling multiple dark bands
  onto the same joint. Fade periodic siding detail into broad blocks
  of color. Hold subpixel posts and the metal roof lip independently of
  those texture fades. The intact window cross is a single piece. Select
  the center column and projected row separately when each bar becomes
  subpixel, even if its world-space band falls between pixel centers.
  Preserve the broken window's opening and fragments after removing the cross.

### Interior and render ownership

- Keep wallpaper above the wainscot all the way to the vaulted roof
  lining. Show the transverse rafters, ridge timber, and eave plates.
  Use the darkest wood samples already present in the room for the ceiling,
  with a small value difference on the rafters to keep them readable.
  Select the interior roof from the player's room as well as the actual
  camera position. A trailing camera can sit outside while the player is
  inside. Clip inward-facing walls at the same lining as the roof and keep
  exterior porch members behind the solid upper wall. Preserve the view
  through the window and door openings and check intentional wall cutaway.
- Assign one owner per visible surface. The gable deck owns its entire top
  and the depth-tested timber skirt owns the outside fascia. A legacy flat
  skirt under the railing and opening caused isolated dark pixels up on the
  boards. Hiding render layers individually and comparing the same logical
  cells identified the wall carrier drawing the duplicate. Scope fixes to
  that carrier so legacy storefronts retain their treatment.

### Where to look and how to verify

- Dimensions and material controls live in
  [TownCoffeeKit](../../scripts/town_coffee_kit.gd) and
  [its resource](../../resources/town_coffee_kit.tres). The
  [lot recipe](../../resources/generated_coffee_town.tres) places the shops.
  [TownBuildingStyle](../../scripts/town_building_style.gd) defines the
  physical spans and timber members.
- Start with [wall paint](../../scripts/town_building_paint.gdshaderinc),
  [the door leaf shader](../../scripts/coordinate_frame_gpu_wall_homography.gdshader),
  [porch timbers](../../scripts/town_porch_timber.gdshader), and
  [deck and roof planes](../../scripts/town_storefront_plane.gdshader).
  [Shared projection](../../scripts/town_storefront_projection.gdshaderinc)
  has `town_projected_edge_distance` and `town_contact_coverage`.
  [The runtime renderer](../../scripts/coordinate_frame_runtime_renderer.gd)
  binds the cage, materials, and occlusion.
- Use [the shared viewport experiment](../../tests/calibration/town_shared_viewport_experiment.tscn)
  for the 160×120 render of [Generated Coffee Town](../../generated_coffee_town.tscn).
  Revisit exact close, oblique, rear, edge-on, and distance poses. Use
  slight camera offsets to check projected strokes and the window cross.
  Compare closed and open doors, intact and broken windows, and interior
  views with the camera on both sides of the threshold. Capture through
  the graphical renderer, preferably offscreen while the user needs the
  mouse. Inspect at native resolution or nearest-neighbor enlargement.
  Count logical pixels for exact-width claims and compare matching cells
  before and after a fix.
- Run `tests/generated_coffee_town_test.gd`, `tests/town_storefront_test.gd`,
  and `tests/town_shared_prop_bridge_test.gd` with
  `tools/run_godot_smoke.ps1`. Headless checks cover gameplay and routing.
  Use the graphical capture and shader diagnostics to verify what was drawn.
