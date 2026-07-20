# XybotsResearch handoff - 2026-07-20

## Current repo state

- Canonical Godot repo: `D:\Godot\xybotsResearch\Project\xybots-research`.
- Branch: `main`, tracking `origin/main`.
- Outer folder `D:\Godot\xybotsResearch` contains broader research, MAME, captures, exports, and analysis. Treat the nested Godot repo as the code checkpoint location.
- Important external reference folder: `D:\Godot\xybotsResearch\analysis\first_person_dungeon_video_refs`.
- Current prototype entry scene: `main.tscn`.
- Main runtime script: `scripts/xybots_character_controller.gd`.

## Important references

- `D:\Godot\xybotsResearch\analysis\maze_construction.md` summarizes the first-person dungeon tutorial screenshots, the Heroine Dusk reference, and how those ideas relate to Xybots.
- `docs/xybots_environment_notes.md` tracks environment observations.
- `docs/xybots_motion_object_capture.md` tracks player and object capture notes.
- `docs/xybots_wall_capture_workflow.md` tracks wall capture workflow.
- `analysis/wall_reconstruction/corridor_system_analysis.md` and related `analysis/wall_reconstruction` folders contain the current wall reconstruction experiments.

## Prototype behavior before this handoff

- The prototype renders a cropped Xybots-style playfield at `160x120`.
- It uses a four-cell, one-cell-wide thin-wall hallway.
- Player state is tracked as:
  - `grid_position`: current top-down cell.
  - `local_floor_position`: intra-cell 2D art-space position.
  - `facing`: cardinal direction, where 0=N, 1=E, 2=S, 3=W.
- Movement happens inside the tile first. Crossing a boundary starts a captured transition if that edge is open.
- Thin walls block crossing but still allow the player to approach the visible wall-contact position.
- Stable environment views are composed from `assets/Environment/Floor_Turn.png` plus numbered transparent wall slot sprites in `assets/Environment/WallsStraight`.
- Captured movement/turn phases still use full playfield frame images from `assets/reference_xybots_local/playfield_phases`.
- The 3D diagnostic was useful for thinking, but it is not reliable as the source of truth because Xybots' 2D projection is stylized and does not map cleanly to a literal perspective camera.

## Main conclusion

The long-term source of truth should be a 2D top-down thin-wall map, not a 3D diagnostic scene. The 2D renderer should be a projection of that map: cell/facing/local offset determine which player-view slots draw, in what order, with which material variant.

The 3D view can remain as optional diagnostic scaffolding, but it should not drive gameplay, collision, wall identity, texture assignment, actor registration, or multiplayer synchronization.

## Known open issue

The current straight-wall visibility table is still approximate. It can show many of the expected numbered wall slots, but the table and branch logic are not yet fully faithful to the user's `Wall_Grid.png` diagram. The next useful work is to make the map overlay and slot-resolution debug clear enough that each wrong slot can be corrected against screenshots.

## Next milestone

Implement the 2D source-of-truth plan in `docs/top_down_source_of_truth_plan.md`, starting with a stronger top-down overlay that shows actual local position, facing, thin walls, movement contact limits, and visible wall slot IDs.
