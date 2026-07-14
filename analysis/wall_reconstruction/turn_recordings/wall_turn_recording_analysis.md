# Wall Turn Recording Analysis

Capture root: `D:\Godot\xybotsResearch\mame-src\snap\xybots_capture\wall_turn_recordings`
Generated sessions: 5

| Session | Raw Frames | Unique Tile States | Keyframes | Selected | Contact Sheet |
|---|---:|---:|---:|---:|---|
| session_0001 | 641 | 86 | 86 | 80 | session_0001/contact_sheet_corridor.png |
| session_0002 | 263 | 42 | 42 | 42 | session_0002/contact_sheet_corridor.png |
| session_0003 | 157 | 19 | 19 | 19 | session_0003/contact_sheet_corridor.png |
| session_0004 | 244 | 2 | 2 | 2 | session_0004/contact_sheet_corridor.png |
| session_0005 | 2302 | 219 | 239 | 80 | session_0005/contact_sheet_corridor.png |

Interpretation:
- These recordings are playfield-only captures: sprites and HUD alpha are excluded.
- `unique_visible_tile_states` changes when the visible playfield tilemap changes.
- For turn reconstruction, start with the contact sheets, then inspect each session's `keyframe_changes.csv` to see which tile rows/regions changed.
- Raw frame-by-frame data is intentionally left in MAME's `snap` folder to avoid bloating the Godot repo.
