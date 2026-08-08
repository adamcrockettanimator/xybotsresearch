# Runtime wall projection experiment

This scene is intentionally separate from the slot-overlay renderer in `main.tscn`.

Run `runtime_wall_projection_demo.tscn` directly. It uses the same thin 2D grid-wall model and the project's keyboard/Xbox-controller conventions, but renders wall geometry in real time using yaw-only custom Canvas projection.

- Vertical edges remain parallel because the projector uses one screen X for both endpoints of every vertical edge.
- The first renderer is deliberately affine: every wall is two textured Canvas triangles using ordinary UV interpolation.
- Visibility is ray-first-hit based and only ray-visible map edges are drawn.
- F1 toggles diagnostic quad/corner/depth displays.
- F2 toggles four discrete darkness bands.
- F3 switches between affine two-triangle mapping and projective homography mapping.
- `[`/`]` change focal length; `-`/`=` change horizon position; `R` restores the diagnostic maze.

The wall texture is generated at runtime as a checker/grid because existing wall files are already full-screen, view-specific overlays rather than flat master textures. This makes warping, triangle seams, and perspective behavior immediately visible before choosing a production flat wall source.
