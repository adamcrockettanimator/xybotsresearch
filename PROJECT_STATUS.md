# Xybots Research — Compact Working Context

Updated: 2026-08-20

Use this file when resuming work. It is the compact working reference for the project, not a replacement for the source art, Blender scenes, or task-specific visual guides.

## Current baseline

- The maze grid and collision are the authoritative world state.
- The renderer is moving away from the old pre-rendered, per-slot wall sprites toward Blender-derived coordinate frames and GPU projective texture mapping.
- The target look is Xybots-style pseudo-3D: depth recedes, vertical edges stay parallel, and pixel treatment is intentional rather than physically smooth.
- Runtime wall rendering uses reusable master textures and layered wall art; floor and ceiling have matching coordinate-space experiments.
- Current gameplay includes two-player support (with a player-two AI fallback), coins, a machine gun pickup, shooting, damage, death/respawn, a round timer, and scoring.

## Important assets and references

- Preserve the Blender scenes, Blender render scripts, coordinate templates, red-dot coordinate images, and their generated frames.
- Preserve the runtime wall layers, floor/ceiling layers, height/parallax tests, and texture-filter test images.
- Existing screenshots and guide images are technical evidence. Do not bulk-delete them merely to shorten history; consult only the images relevant to the active task.
- The old sprite/slot-graph renderer remains useful as historical/debug reference, but it is not the preferred long-term renderer.

## Current renderer direction

- Camera poses and transitions are based on the Blender-derived coordinate system.
- Master textures are projected onto coordinate-derived quads, with GPU-based projective/homography rendering.
- Pixelated look, mip/UV snapping, seam coverage, layered wall parallax, and floor/ceiling mapping are experimental controls that should remain available while the visual language is refined.
- World objects (players, coins, shots, effects) need to follow the same camera-pose/projection model as the geometry.

## Known state to preserve

- Character scaling is currently quite large near the camera. This is unintended, but visually interesting enough to preserve as a deliberate experiment for later evaluation.
- Do not silently normalize or discard that near-camera scaling behavior before it has been compared intentionally.

## Current problems / next technical priorities

1. Stabilize character world projection: the local player and opponent should agree on scale and placement when occupying comparable positions, especially in the same cell.
2. Make players, coins, bullets, and effects interpolate continuously with camera pose transitions instead of appearing to lag until a transition ends.
3. Restore consistent distance lighting only after object scale/position is stable.
4. Finish the two independently movable/resizable player windows and minimalist per-player map presentation.
5. Keep collision robust at diagonal poses; prevent wall clipping except when the explicit walk-through-walls cheat is enabled.

## Resumption rule

Start from this file, inspect the relevant current code, then open only the visual references for that specific task. Do not try to reconstruct the project from the entire chat history or every prior screenshot.
