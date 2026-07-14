# Xybots Corridor System Analysis

## What The Captures Show

Xybots does not scroll a continuous wall bitmap. It rewrites the lower playfield
tilemap into a projected first-person corridor view.

The visible screen is 336x240 pixels, or 42x30 8x8 tiles. The corridor area is
mostly rows 15-29. In the controlled capture test, each meaningful step or turn
changed roughly 257-296 visible tile slots, concentrated in those lower rows.

That means each move/turn rebuilds most of the corridor region. The top HUD and
score panels stay mostly stable.

## How It Makes A 3D-Looking Scene

The perspective is baked into tile art and tile placement.

The game has many 8x8 wall/floor tile fragments. Those fragments already contain
diagonal edges, perspective floor lines, wall patterns, ceiling strips, end-wall
panels, and side-door details. A full corridor view is assembled by placing those
fragments into a 2D tilemap.

In practice, the renderer appears to compose these conceptual regions:

- top HUD/status area
- black forward void/background
- ceiling/upper trim strip
- left wall plane
- right wall plane
- back/end wall or far corridor opening
- floor plane with perspective guide lines
- side door/side passage edge pieces
- occasional detail markers or pickups on the wall/floor

The lower corridor capture crop is 336x120, but the actual non-transparent
corridor content in our extracted unique views is about 176x120. The remaining
right side is usually black void or sprite/action space.

## How Turning Probably Works

Turning uses the same system as moving: the playfield tilemap gets rewritten.

From the data we have, a settled turn is not a simple transform of the previous
view. It is a new tile arrangement. In the controlled captures, one settled
turn changed hundreds of lower-screen tiles, which is consistent with rebuilding
the projected view for the new facing direction.

What we do not yet know:

- whether the arcade game has intermediate tilemap frames during the actual
  turn animation
- whether those frames are generated from rules or pulled from preauthored
  tile patterns

To answer that, capture every frame during a turn instead of waiting for the
view to settle.

## Captured Asset Counts

Current automated reconstruction from the available captures:

- 52 unique full corridor plates
- 52 tight-cropped corridor plates
- 52 rough center/back-wall zone candidates
- 52 rough floor zone candidates
- 52 rough left-wall zone candidates
- 52 rough right-wall zone candidates

Unique hashes in the rough zone pass:

- center/back-wall zones: 42
- floor zones: 51
- left-wall zones: 46
- right-wall zones: 33

Those counts are not a final required asset count. They include different maze
states, door/side-passage states, and probably some transition or partial
captures. They are useful as an upper-bound reference from current data.

## Practical Asset List

### Option A: Full Corridor Plates

This is the fastest route for a Godot prototype.

Required assets:

- one static HUD/status frame or leave HUD separate
- 52 observed corridor view plates from `unique_corridor_views/`
- optional transparent/tight versions from `unique_corridor_views_tight/`

Pros:

- very accurate to the captured arcade view
- easy to place in Godot
- no need to solve the tile grammar yet

Cons:

- requires a plate for every view state
- harder to support unseen maze situations
- less educational if the goal is to understand the original construction

### Option B: Reusable Hand-Assembled Components

This is closer to how the arcade appears to work.

Likely component inventory:

- back wall / far opening panels: about 15-25 useful variants
- floor perspective panels: about 15-25 useful variants
- left wall planes: about 15-25 useful variants
- right wall planes: about 12-20 useful variants
- ceiling/upper trim strips: about 8-15 variants
- side door / side passage edges: about 8-16 variants
- vertical column/door edge pieces: about 6-12 variants
- wall detail decals/markers: about 5-15 variants

Estimated hand-made component count:

- lean prototype: 40-60 assets
- broad playable set: 80-120 assets
- close arcade reconstruction: 150+ assets or a true tilemap renderer

The reusable components should be built from observed captures, not invented
from scratch. Start with the repeated shapes in `zone_candidates_contact_sheet`
and manually consolidate obvious duplicates.

## Recommended Next Step

For Godot, start with Option A for gameplay feel:

1. choose a handful of full corridor plates
2. map them to simple logical states like straight, left opening, right opening,
   dead end, and corner
3. switch plates when the player moves or turns

In parallel, continue manually assembling reusable wall pieces from the 8x8 tile
sheet. Once the component vocabulary is clearer, replace the full plates with a
tile/component renderer.
