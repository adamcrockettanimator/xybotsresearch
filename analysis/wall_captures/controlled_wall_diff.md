# Xybots Controlled Wall Capture Diff

| Capture | Label | Frame | Active Tiles | Unique Raw |
|---|---:|---:|---:|---:|
| capture_0141 | 1 stand still | 5416 | 755 | 308 |
| capture_0142 | 2 forward once | 5422 | 755 | 318 |
| capture_0143 | 3 forward twice | 5429 | 755 | 309 |
| capture_0144 | 4 turn left | 5454 | 755 | 272 |
| capture_0145 | 5 turn right | 5460 | 755 | 272 |
| capture_0146 | 6 turn right again | 5492 | 755 | 371 |
| capture_0147 | 7 wall/door? | 5497 | 755 | 359 |
| capture_0148 | 8 extra capture | 5504 | 755 | 309 |

## Consecutive Tile Diffs

| From -> To | Changed Tiles | Changed Visible-Screen Tiles | Rows Touched | Top Changed Rows |
|---|---:|---:|---|---|
| capture_0141 -> capture_0142 | 296 | 296 | 1,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29 | 15:20, 16:20, 17:20, 18:20, 19:20, 20:20, 21:20, 22:20 |
| capture_0142 -> capture_0143 | 257 | 257 | 15,16,17,18,19,20,21,22,23,24,25,26,27,28,29 | 15:20, 16:20, 17:20, 18:20, 19:20, 20:20, 21:20, 22:20 |
| capture_0143 -> capture_0144 | 262 | 262 | 1,3,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29 | 16:20, 17:20, 18:20, 19:20, 20:20, 21:20, 22:20, 23:20 |
| capture_0144 -> capture_0145 | 0 | 0 | - | - |
| capture_0145 -> capture_0146 | 289 | 289 | 15,16,17,18,19,20,21,22,23,24,25,26,27,28,29 | 15:20, 16:20, 17:20, 18:20, 19:20, 20:20, 21:20, 22:20 |
| capture_0146 -> capture_0147 | 273 | 273 | 15,16,17,18,19,20,21,22,23,24,25,26,27,28,29 | 15:20, 16:20, 17:20, 18:20, 19:20, 21:20, 22:20, 23:20 |
| capture_0147 -> capture_0148 | 273 | 273 | 1,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29 | 16:20, 17:20, 18:20, 19:20, 20:20, 21:20, 22:20, 23:20 |

## Initial Findings

- The full 64x32 playfield RAM has 2048 entries.
- Visible screen is 42x30 tiles, or 336x240 pixels.
- Consecutive large diffs indicate the corridor is being rewritten as a projected view, not smoothly scrolled as a bitmap.
- Zero-diff or tiny-diff pairs are likely repeated captures before the view changed or after it settled to the same layout.