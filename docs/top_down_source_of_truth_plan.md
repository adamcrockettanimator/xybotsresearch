# 2D top-down source-of-truth plan

## Goal

Build the Xybots-style game around a top-down 2D simulation model. The player controls a position inside a thin-walled grid cell, and the screen renderer projects that state into Xybots-like pixel-art slots.

## Why this replaces the 3D diagnostic

The 3D diagnostic made it obvious when collision and rendering disagreed, but it also created a false expectation that the 2D view should match a normal perspective camera. Xybots appears to use authored pixel-art projection slots, captured movement phases, and camera-locked tile transitions. A literal 3D camera will keep fighting those choices.

## Architecture

1. Simulation model

- Store open cells in a grid.
- Store walls as thin cell edges, not as filled blocks.
- Store the player as `cell + local offset`.
- Store facing as a cardinal direction.
- Resolve movement, collision, turns, and multiplayer positions in this model.

2. Map/material model

- Each wall edge gets a material or theme ID.
- Floor, sky, props, windows, doors, building fronts, and interiors are all map-authored data.
- One wall edge can later choose different sprite variants depending on visible slot, facing, distance, and theme.

3. Renderer model

- Given camera cell and facing, walk a table of view-relative wall-slot checks.
- Convert each slot into a world cell edge lookup.
- Draw selected slots back-to-front using the current material's sprite for that slot.
- Draw actors and props after environment slots using depth/local-position sorting.
- During movement/turn transitions, use captured or authored transition frames until we replace them with slot-based transitional art.

4. Debug model

- Always show a small top-down source overlay during this phase.
- The overlay should show the current cell, real intra-cell player position, facing, wall edges, contact limits, and visible slot IDs.
- Use the overlay to correct the slot table against reference captures.

## Milestones

1. Stabilize the top-down overlay so it shows the true player offset and collision limits.
2. Rewrite the straight-wall slot table from the user diagram, validating four canonical cases:
   - Start of hallway facing north sees side walls and the far end wall.
   - End of hallway facing north sees the nearest front wall plus side edges.
   - End of hallway facing west/east sees the long side wall pieces.
   - Standing against a side wall and turning preserves intra-cell position.
3. Split wall data from renderer data: map edges know material IDs; slots know screen sprite positions.
4. Add material variants for wall slots so a western town can mix exteriors, interiors, doors, windows, signs, and special walls.
5. Add props as map-positioned entities with slot/depth projection.
6. Add actor registration so each player is simulated in top-down space but rendered in the correct 2D projected position.
7. Add multiplayer by syncing compact top-down state: cell, local offset, facing, animation state, shot state, and health.
