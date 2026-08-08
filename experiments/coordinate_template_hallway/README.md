# Coordinate-template hallway experiment

Run the project normally with Play on branch `experiment/coordinate-template-hallway`.

This experiment scans `assets/coordinates3.png` for red connected components at startup, classifies the resulting sixteen points into four nested depth rings, and creates thirteen separate screen-space plane definitions:

- three ceiling bands;
- three right-wall bands;
- three floor bands;
- three left-wall bands;
- one back wall.

Every plane projectively maps the complete `greyboxGrid.png` source texture through an inverse homography. There is intentionally no affine renderer in this experiment.

Controls:

- `F1`: show/hide detected points, numbered markers, plane outlines, and plane names.
- `F2`: show/hide the semi-transparent original coordinate template over the generated hallway.
- `F3`: show/hide the mapped grid polygons independently of the authoring lines.
- `F4`: show/hide the Xybots art layer: `Floor_Turn.png` first frame as its base floor/ceiling image, with the opaque 128x88 panel cropped from `Walls_Straight_25.png` and projectively mapped onto all seven wall bands.
- `F5`: cycle quantized homography at 1x, 2x, 3x, and 4x logical-pixel/source-texel steps. The experiment starts at 2x.
- `F6`: toggle plane-coverage debug: colored plane ownership, yellow overlaps, and magenta interior holes.
- `F7`: toggle clean seam coverage: a small UV edge tolerance with deterministic later-plane priority.

The Xybots wall layer applies four discrete runtime brightness bands by template depth: 100%, 78%, 58%, and 42%. Floor and ceiling retain the authored first `Floor_Turn.png` frame.

The coordinate template is authoring input. The runtime useful output is the explicit `planes` data generated from its detected marker positions.
