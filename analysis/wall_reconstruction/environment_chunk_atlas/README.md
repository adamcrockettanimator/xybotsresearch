# Environment Chunk Atlas

This atlas is built from the wall reconstruction analysis images, not from raw
8x8 tiles. It crops larger reusable corridor chunks from:

- selected every-frame turn keyframes
- settled unique corridor view captures

Chunk families:

- ceiling: 66
- center_back: 105
- floor: 125
- left_wall: 96
- right_wall: 84

Files:

- environment_chunks_atlas.png - packed atlas image
- environment_chunks_atlas.json - atlas rectangles and source references
- environment_chunks_atlas.csv - spreadsheet-friendly atlas rectangles
- chunks/ - individual deduped PNG chunks

These chunks intentionally preserve the captured pixels. Black areas are not
made transparent because the original art uses black both as void and as line
detail.
