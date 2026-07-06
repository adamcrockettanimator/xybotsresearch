---
name: arcade-sprite-reconstruction
description: Reconstruct arcade sprite artwork from decoded ROM graphics chunks. Use when working from 8x8/16x16 tile chunks, contact sheets, MAME graphics dumps, motion-object tiles, LOD sprite sequences, or when assembling transparent PNG sprites by testing tile ranges, dimensions, and column-major or row-major ordering.
---

# Arcade Sprite Reconstruction

## Core Workflow

1. Decode from the ROM or binary graphics region when possible. Do not sample from labeled contact sheets unless the sheet layout is fully known.
2. Treat each graphics chunk as a tile. For Xybots player sprites, chunks are `8x8`, 4bpp, with pen/index `0` transparent.
3. Pick the next unused tile code as the start of the next candidate block.
4. Assemble candidates column-major first unless evidence says otherwise:

```text
height x width = 5x3

col 0: start+0, start+1, start+2, start+3, start+4
col 1: start+5, start+6, start+7, start+8, start+9
col 2: start+A, start+B, start+C, start+D, start+E
```

5. Generate a small set of plausible candidate sizes, not one guess at a time. For shrinking LODs, test the previous size, one-column smaller, one-row smaller, and tiny endings such as `3x2`, `2x1`, `1x1`.
6. Choose the smallest complete silhouette.
7. Reject candidates that consume too many tiles. Common signs:
   - sprite appears to stand on the next sprite's head
   - extra head/feet/body appears below or beside the intended sprite
   - stray side column belongs to the next LOD
8. Reject candidates that are too small. Common signs:
   - gun edge, backpack, feet, or side silhouette is cut off
   - torso reads correctly but weapon column is missing
9. Save review files with numeric LOD names, e.g. `lod_00`, `lod_01`, `lod_02`. Avoid written numbers such as `eight` or `nine`.
10. Treat an unexpected size anomaly as an alignment warning. For Xybots player poses, a sudden `1x1` LOD after larger player silhouettes usually means an earlier LOD consumed the wrong number of tiles.
11. Keep derived ROM artwork local unless the user explicitly requests otherwise. Commit reusable scripts, manifests, and documentation, not copyrighted/private art exports.

## Output Hygiene

- Put exploratory candidates in a `candidates` subfolder for that LOD.
- Put accepted PNGs in a separate finals tree so review folders can be deleted later:

```text
exports/sprites/reconstructed_pose_finals/
├── all_final_pose_lod_strips.png
├── pose_0000_lod_strip.png
├── pose_0001_lod_strip.png
└── individual_final_pngs/
    ├── pose_0000/
    └── pose_0001/
```

- Put accepted PNGs in each final pose folder with numeric names:

```text
individual_final_pngs/pose_0002/lod_00_00AA-00BB_6x3.png
individual_final_pngs/pose_0002/lod_01_00BC-00CA_5x3.png
```

- Once a pose is accepted, candidates can be deleted or moved aside.

## Xybots Notes

For Xybots-specific confirmed patterns and tile ranges, read `references/xybots.md`.
