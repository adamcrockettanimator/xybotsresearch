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
10. Keep derived ROM artwork local unless the user explicitly requests otherwise. Commit reusable scripts, manifests, and documentation, not copyrighted/private art exports.

## Output Hygiene

- Put exploratory candidates in a `candidates` subfolder for that LOD.
- Put accepted PNGs in the pose folder with numeric names:

```text
pose_0002/lod_00_00AA-00B8_5x3.png
pose_0002/lod_01_00B9-00C7_5x3.png
pose_0002/pose_0002_lod_strip.png
pose_0002/pose_0002_manifest.csv
```

- Once a pose is accepted, candidates can be deleted or moved aside.

## Xybots Notes

For Xybots-specific confirmed patterns and tile ranges, read `references/xybots.md`.
