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
