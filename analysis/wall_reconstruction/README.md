# Xybots Wall Reconstruction Pass

This is an automated first pass at turning captured playfield wall tiles into
usable review assets.

## Reliable Output

`corridor_views_contact_sheet.png`

- Contact sheet of unique captured corridor views.
- Cropped from the lower 336x120 pixels of `playfield_layer.png`.
- Pure black void pixels are converted to transparency.
- These are useful as complete background plates or reference views.

`unique_corridor_views/`

- Individual 336x120 corridor plates.
- One PNG per unique observed view.

`unique_corridor_views_tight/`

- Same views, trimmed to non-transparent content.
- Easier to drag into Photoshop as loose assets.

`corridor_views.csv`

- Maps each generated view back to its first source capture folder.

## Experimental Output

`zone_candidates_contact_sheet.png`

- Contact sheet of rough cropped wall/floor zones.
- These are heuristic slices from each unique corridor view.
- They are useful for visual sorting, but they are not guaranteed to be clean
  logical wall components.

`zone_candidates/`

- Individual cropped candidate zones:
  - `center_back`
  - `left_wall`
  - `right_wall`
  - `floor`
  - `right_door_edge`

`zone_candidates.csv`

- Maps each zone candidate back to view index, crop region, size, and hash.

## Notes

This pass does not yet infer the true underlying maze/wall grammar. It is a
practical asset-organizing pass from observed rendered tilemaps. The complete
views are more trustworthy than the zone crops.
