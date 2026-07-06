# Xybots Sprite Reconstruction Notes

## Source

- ROM zip: `D:\MAME\roms\xybots.zip`
- Sprite ROM entries:
  - `136054-1105.2e` at `0x000000`
  - `136054-1106.2ef` at `0x010000`
  - `136054-1107.2f` at `0x020000`
  - `136054-1108.2fj` at `0x030000`
  - `136054-1109.2jk` at `0x040000`
  - `136054-1110.2k` at `0x050000`
  - `136054-1111.2l` at `0x060000`
- Sprite chunks are `8x8`, 4bpp, packed MSB nibbles.
- Pen/index `0` is transparent.
- Use the debug palette from `tools/export_xybots_sprites.ps1` unless runtime palette work is requested.

## Important Contact Sheet Warning

`exports/sprites/xybots_sprites_raw_8x8_tiles.png` is a labeled contact sheet. It is scaled, padded, and annotated. Do not treat it as a packed tile atlas. Decode from ROM bytes for final PNGs.

## Assembly Order

Confirmed player sprite chunks assemble column-major:

```text
tile i destination:
dest_col = floor(i / rows)
dest_row = i % rows
```

The human shorthand used during review is `height x width`. The scripts often use `Cols x Rows`, so:

```text
human 5x3 = script Cols=3 Rows=5 = 24x40 pixels
human 4x2 = script Cols=2 Rows=4 = 16x32 pixels
human 2x1 = script Cols=1 Rows=2 = 8x16 pixels
```

## Confirmed Player Patterns

Pose 000:

```text
start 0010
pattern: 6x3, 5x3, 5x2, 4x2, 4x2, 3x2, 3x2, 3x1, 2x1, 2x1
ranges:
0010-0021
0022-0030
0031-003A
003B-0042
0043-004A
004B-0050
0051-0056
0057-0059
005A-005B
005C-005D
```

Pose 001:

```text
start 005E
pattern: 5x3, 5x3, 4x3, 4x2, 4x2, 3x2, 3x2, 2x1, 2x1, 2x1
ranges:
005E-006C
006D-007B
007C-0087
0088-008F
0090-0097
0098-009D
009E-00A3
00A4-00A5
00A6-00A7
00A8-00A9
```

The next untested pose/block starts at `00AA`.

Pose 002:

```text
start 00AA
pattern: 6x3, 5x3, 5x3, 4x2, 4x2, 4x2, 3x2, 3x2, 2x1, 2x1
ranges:
00AA-00BB
00BC-00CA
00CB-00D9
00DA-00E1
00E2-00E9
00EA-00F1
00F2-00F7
00F8-00FD
00FE-00FF
0100-0101
```

The next untested pose/block starts at `0102`.

Pose 003:

```text
start 0102
pattern: 6x3, 5x3, 5x3, 4x2, 4x2, 3x2, 3x2, 3x1, 2x1, 2x1
ranges:
0102-0113
0114-0122
0123-0131
0132-0139
013A-0141
0142-0147
0148-014D
014E-0150
0151-0152
0153-0154
```

The next untested pose/block starts at `0155`.

## Candidate Selection Heuristics

- If a candidate looks like it is standing on a head, reduce height.
- If a candidate has a second body or unrelated column, reduce width.
- If the gun side disappears, increase width.
- If the body is coherent but foot/head fragments appear below, the block consumed one or more tiles from the next LOD.
- For player pose endings, `2x1` is common.
