# Runtime wall projection: first prototype report

## Implemented approach

`runtime_wall_projection_demo.tscn` is a separate Node2D/Canvas experiment. It does not alter `main.tscn`, the slot renderer, map tuner, or the granular-camera branch.

The demo stores walls as thin 2D grid-edge line segments, transforms each endpoint into the player’s continuous yaw-only view space, and projects the endpoints to Canvas coordinates. The top and bottom of every vertical wall endpoint share the same projected X coordinate. This intentionally preserves parallel screen-space verticals.

The first rendering path is two textured Canvas triangles per wall using ordinary UV interpolation. This is the requested affine comparison baseline. A second runtime-switchable path renders the same walls through a Canvas shader: each screen pixel is inverse-homography mapped to the same source texture. The texture is generated as a high-contrast grid/checker at runtime because the existing wall PNGs are view-specific, transparent full-screen overlays rather than flat wall masters.

## Reused concepts

- The same thin 2D grid-wall representation used by the current renderer.
- The existing project input actions and Xbox stick convention: left stick moves, right stick yaws continuously.
- The existing renderer’s ray-first-hit visibility idea, adapted to the standalone scene.
- The existing player/camera relationship: a player-world point and forward/right view basis rather than a conventional pitched Camera3D.

## What currently works

- Continuous controller/keyboard movement and continuous yaw.
- Runtime projected wall quads at direct and oblique angles.
- Parallel vertical wall edges.
- First-hit ray visibility rather than drawing the complete maze.
- Near-plane segment clipping.
- Opaque discrete four-band distance darkness, with a smooth-darkness comparison toggle.
- Toggleable horizon, wall corner, quad-outline, depth, and view diagnostics.
- Adjustable focal length and horizon position while running.

## Not yet implemented

- A level Camera3D plus shifted-frustum comparison scene.
- Production wall master art: the checker is diagnostic by design.
- Full per-pixel visibility clipping at overlapping wall corners. The current painter approach uses first-hit ray filtering plus far-to-near ordering; a depth-buffered 3D comparison can test whether that is materially better.
- Final common character/prop occlusion. The demo has a player-world marker projected by the same function, proving the coordinate path, but not a finished animated billboard/occlusion system.

## Recommended next step

Run the scene, test straight and oblique walls while rotating continuously, and evaluate the affine texture distortion. If the pseudo-3D character feels promising, add a direct A/B mode: affine Canvas versus a small level-Camera3D shifted-frustum scene. Only pursue homography if affine is visibly the wrong kind of distortion.
