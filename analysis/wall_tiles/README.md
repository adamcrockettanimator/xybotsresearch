# Xybots Wall Tile Sheets

These sheets are 1:1 pixel atlases for inspecting the Xybots wall/playfield art.

## Files

`xybots_playfield_raw_8x8_tiles_clean_1x.png`

- Source-order decode of the ROM `tiles` graphics region.
- Transparent background, no labels, no grid.
- Uses the same debug pen colors as the sprite raw-tile sheet, not final in-game
  palette colors.
- Tile index is `x / 8 + (y / 8) * 64`.

`xybots_playfield_wall_tiles_unique_pixels_clean_1x.png`

- Unique 8x8 rendered tiles observed in the visible corridor rows of the F11
  playfield captures.
- Uses actual captured game colors from `playfield_layer.png`.
- Transparent background between tiles, no labels, no grid.
- This is easier to visually inspect for wall/floor construction.

`xybots_playfield_wall_tiles_unique_pixels_clean_1x.csv`

- Maps each tile in the observed rendered sheet back to first-seen capture,
  playfield raw word, decoded code, color, flag, and map coordinate.
