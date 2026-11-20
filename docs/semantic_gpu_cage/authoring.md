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
- The town sun is in the west, which is negative world X. Shade fixed world
  faces accordingly. West is brightest, east darkest, and north and south
  sit between them. Give the roof top its own tone. Keep the hard foundation
  contact shadow tucked close to the raised base, with a small eastward
  extension. Keep foot trim and cast shadows visually distinct.

### Roofing and joinery

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
- Put the porch beam between the posts and below the awning plane. Paint a
  roof shadow on the upper face, and check oblique views for floating strips
  or roof overlap. Give the front cornice a lit lip, dark groove, beveled face,
  and lower bead. Keep rear trim slim, close to the wall, with a shadow below.
  Keep porch posts at the outer corners and the rail gap aligned with the door.
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
