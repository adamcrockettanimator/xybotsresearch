# Pulled Corridor Tile Atlas

This atlas is built from manually pulled-apart corridor breakdown images named
corridor_view_*_tiles.png.

The extractor treats white or transparent pixels as empty workspace and extracts
each separated non-white connected component as a reusable chunk. This matches
the manual Photoshop workflow of pulling wall, floor, ceiling, and door pieces
out of a corridor view.

Files:

- pulled_corridor_tiles_atlas.png - packed atlas
- pulled_corridor_tiles_atlas.json - atlas rectangles and source positions
- pulled_corridor_tiles_atlas.csv - spreadsheet-friendly atlas data
- chunks/ - individual extracted chunks
- source_images/ - copied source breakdown images

Current source files scanned: 1
Current unique chunks: 5
