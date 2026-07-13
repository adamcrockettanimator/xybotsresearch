# Xybots Environment Notes

## Current Source Findings

These notes are based on the current local MAME source in
`D:\Godot\xybotsResearch\mame-src\src\mame\atari\xybots.cpp`.

Xybots uses three visible graphics systems:

- playfield tilemap: the corridor/wall/floor environment
- motion objects: player, enemies, shots, pickups, and other sprites
- alpha tilemap: HUD/text overlay

The environment is not a single painted bitmap. It is a playfield tilemap:

```cpp
TILEMAP(config, m_playfield_tilemap, "gfxdecode", 2, 8, 8, TILEMAP_SCAN_ROWS, 64, 32)
```

That gives a logical playfield of:

```text
64 columns * 32 rows
8x8 pixels per tile
512x256 pixels total
```

The visible screen is:

```text
336x240
```

No playfield scroll calls were found in `xybots.cpp`. The screen update draws the
playfield directly, then merges motion objects, then draws alpha:

```cpp
m_mob->draw_async(cliprect);
m_playfield_tilemap->draw(screen, bitmap, cliprect, 0, 0);
// merge motion objects into bitmap
m_alpha_tilemap->draw(screen, bitmap, cliprect, 0, 0);
```

This strongly suggests that turning and moving through the maze are represented
by rewriting playfield RAM with a new projected hallway view, not by scrolling a
continuous world map.

## Playfield RAM

The playfield tilemap RAM is mapped here:

```cpp
map(0x803000, 0x803fff).ram().w(m_playfield_tilemap, FUNC(tilemap_device::write16)).share("playfield");
```

That is `0x1000` bytes, or `2048` 16-bit tile entries:

```text
64 * 32 = 2048 tiles
```

The tile callback decodes each 16-bit word as:

```cpp
uint16_t const data = m_playfield_tilemap->basemem_read(tile_index);
int const code = data & 0x1fff;
int const color = (data >> 11) & 0x0f;
tileinfo.set(0, code, color, (data >> 15) & 1);
```

So each playfield tile has:

```text
bits 0-12   tile code
bits 11-14  color/palette bits, overlapping the upper code bits in the current callback
bit 15      tile flag passed to tileinfo
```

The overlap between `code = data & 0x1fff` and `color = (data >> 11) & 0x0f`
is source-verified behavior from MAME, not a typo in these notes.

The graphics region used by playfield code index `0` is:

```cpp
GFXDECODE_ENTRY("tiles", 0, gfx_8x8x4_packed_msb, 512, 16)
```

So the environment graphics are 8x8, 4bpp tiles from the ROM region named
`tiles`.

## Working Hypothesis

Xybots appears to draw the pseudo-3D corridor as a conventional 8x8 tilemap.
However, the tilemap likely represents the already-projected current view, not a
top-down maze map. The gameplay maze probably exists separately in RAM or ROM
data, and the game writes a rendered corridor view into playfield RAM whenever
the player steps or turns.

That means the Godot version probably needs two layers:

1. logical maze state: cell position and facing direction
2. view renderer: writes or selects a projected wall/floor tile arrangement

The first Godot prototype can use captured/static background plates while we
learn the exact tilemap rules.

## Next Investigation

Add a playfield capture path to the MAME instrumentation.

For a selected frame, export:

```text
playfield_layer.png
playfield_debug.png
playfield_tiles.json
```

The JSON should include one record per tile:

```json
{
  "tile_index": 0,
  "map_x": 0,
  "map_y": 0,
  "screen_x": 0,
  "screen_y": 0,
  "raw": "0x0000",
  "code": 0,
  "color": 0,
  "flag": 0
}
```

The debug PNG should overlay tile coordinates and/or tile codes on the
playfield-only render.

## Movement/Turning Capture Plan

Capture these controlled states:

1. standing still in a corridor
2. one frame before turning left
3. one frame after turning left
4. one frame before turning right
5. one frame after turning right
6. one frame before moving forward
7. one frame after moving forward
8. facing a wall
9. facing a door/end panel

Then diff `playfield_tiles.json` between captures.

Important questions:

- Does every visible tile change on turn, or only parts of the tilemap?
- Does moving forward animate through intermediate playfield states?
- Are wall/floor pieces stable tile codes reused across views?
- Does the alpha layer contribute anything to the corridor, or only HUD/text?
- Does playfield bit 15 correspond to flip, opacity, priority, or another tile
  flag in practice?

## Godot Implication

Do not build a permanent environment model until the playfield capture confirms
the view rules.

Immediate Godot work should stay limited to:

- character controller using the handmade SpriteFrames
- optional static background plate for scale
- debug labels for run/aim animation selection

Once playfield capture exists, build the environment from the actual 8x8 tile
data rather than approximating it from screenshots.
