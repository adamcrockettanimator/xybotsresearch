# Xybots Research — Compact Working Context

Updated: 2026-10-26

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

## Renderer rules that must not regress

- The local player uses a **continuous opaque-silhouette fan** from the live camera to the current animation frame's left and right opaque body bounds.  It is a solid segment-versus-triangle test, not a sparse set of visibility rays: a finite wall segment that contacts the fan draws above the player; every visible wall segment without contact draws below.  The narrow side guard prevents the fan from falsely fading a wall merely because it grazes the player's side, while preserving a wall directly behind the player as a cutaway.
- The `Fan Draw Order` F3 diagnostic is the inspection tool for that rule: cyan is the local fan, amber is a clipped wall-contact span, green walls ended below the player, and red walls ended above.  It is diagnostic only; it must not change selection, fading, or layer values.
- Props and opponents must be culled from the **actual runtime camera projection**, not from the player center and not from the old `DEBUG_VIEW_CONE` approximation.  `_world_actor_overlaps_current_camera_fan()` first asks the coordinate renderer for the live projected screen position, including current camera yaw, origin, and overscan; only an unavailable renderer falls back to the geometric cone.  This prevents right-edge objects from popping out after a small camera turn.
- Normal painter ordering remains the physical-wall/actor baseline for props and opponents.  Do not apply the local-player fan layer rule independently to every prop or opponent: one Canvas `z_index` cannot encode conflicting per-object wall relationships, and the earlier attempt hoisted barrels/pickups above the local player.  A future general solution needs per-object compositing/masking rather than a second global layer override.

## Known state to preserve

- Character scaling is currently quite large near the camera. This is unintended, but visually interesting enough to preserve as a deliberate experiment for later evaluation.
- Do not silently normalize or discard that near-camera scaling behavior before it has been compared intentionally.

## Current problems / next technical priorities

1. Stabilize character world projection: the local player and opponent should agree on scale and placement when occupying comparable positions, especially in the same cell.
2. Make players, coins, bullets, and effects interpolate continuously with camera pose transitions instead of appearing to lag until a transition ends.
3. Restore consistent distance lighting only after object scale/position is stable.
4. Finish the two independently movable/resizable player windows and minimalist per-player map presentation.
5. Keep collision robust at diagonal poses; prevent wall clipping except when the explicit walk-through-walls cheat is enabled.

## Semantic-prop renderer follow-up

- The current GPU barrel proof-of-concept gives every barrel its own always-updating 160×120 transparent `SubViewport`.  That was acceptable for a one-barrel experiment but is the wrong ownership model for split-screen gameplay: every visible barrel repeats a full logical-screen offscreen pass per player.
- Preserve the authored appearance while implementing these optimizations in this order: (1) one shared semantic-prop render layer/viewport per player instead of a viewport per barrel, (2) stop updates for culled props, (3) add a distance LOD that uses fewer barrel-intersection steps and simpler lid/stave/hoop work when the projected barrel is tiny, (4) replace the barrel's 49-sample body search with a lower-cost analytic or bounded-refinement intersection, and (5) move the crate face/panel/slat generation from CPU `draw_*` command construction into a projected-face GPU shader.  Keep CPU world-space corner projection, collision, destruction, and loot authoritative.
- Do not sum the four per-player viewport GPU readings in `coordinate_runtime_profile.csv`; they can refer to shared rendering work.  Profile equivalent player counts and effect loads before and after each optimization.

## Headless smoke-test safety

- Never launch a headless Godot smoke test directly.  A failed `assert`, load failure, or runtime error can leave its `SceneTree` running indefinitely after the terminal/editor closes.  Use `pwsh -File .\tools\run_godot_smoke.ps1 -Script 'res://path/to_test.gd'`; it applies a frame cap, a 45-second wall-clock timeout, terminates a hung process, and treats `SCRIPT ERROR` output as a failure.

## Resumption rule

Start from this file, inspect the relevant current code, then open only the visual references for that specific task. Do not try to reconstruct the project from the entire chat history or every prior screenshot.
