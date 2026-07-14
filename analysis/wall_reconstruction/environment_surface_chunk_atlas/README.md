# Environment Surface Chunk Atlas

This atlas is generated from the Xybots environment analysis frames:

- selected every-frame turn keyframes
- settled unique corridor view captures

Unlike `environment_chunk_atlas`, this pass tries to split the images into
surface-like chunks. It classifies pixels as:

- `ceiling` - upper brown/gray ceiling and trim pieces
- `floor` - lower tan/orange floor perspective pieces
- `wall` - blue/gray wall pieces and vertical side structures

Dark outline pixels adjacent to each surface are retained so chunks keep the
arcade pixel-art edges. Black void pixels are treated as empty background.

Files:

- `environment_surface_chunks_atlas.png` - packed atlas image
- `environment_surface_chunks_atlas.json` - atlas rectangles and source references
- `environment_surface_chunks_atlas.csv` - spreadsheet-friendly atlas rectangles
- `environment_surface_chunk_summary.csv` - count and size summary by surface type
- `chunks/` - individual deduped PNG chunks

Current source images scanned: 275
Current unique chunks: 448

Chunk counts:
- ceiling: 182
- floor: 105
- wall: 161

This is an automated estimate of the amount of reusable wall/floor/ceiling art
needed for corridor navigation. It is intentionally conservative: similar
chunks that differ by even a few pixels remain separate until reviewed by hand.