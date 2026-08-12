# Coordinate-frame source set

These 160×120 images are camera-coordinate reference templates, not wall art.
Their red pixels are Blender-rendered grid intersections used to compare the
runtime yaw-only projector with the authored camera poses. The renderer retains
the complete world grid and projects all wall corners itself, so a marker that
is clipped off screen or hidden behind a wall cannot remove geometry.

Included authored coverage:

- `coord_n_*`: North stable, forward, strafe-East, and diagonal-NE samples.
- `coord_ne_*`: Northeast stable, forward, right-to-Southeast, and East samples.
- `coord_turn_n_22p5.png`: clockwise North-to-Northeast twist sample.
- `coord_turn_ne_66p5.png`: clockwise Northeast-to-East twist sample.

The two twist files came from `blender/renders/north_to_east_turn`; all other
motion samples came from `blender/renders/camera_transition_positions`.

Still to author for full reference-overlay coverage: the stable E, SE, S, SW,
W, and NW camera poses, and their motion samples. Runtime wall geometry itself
does not depend on those exports; they are needed to calibrate/verify the
matching views rather than silently mirroring an unverified template.
