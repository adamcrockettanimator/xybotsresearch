# Xybots Wall Capture Workflow

The wall/corridor art is the Xybots playfield tilemap, not motion-object sprite
data. The local MAME capture build in `D:\Godot\xybotsResearch\mame-src` exports
that tilemap for analysis.

## Build

From PowerShell:

```powershell
C:\msys64\msys2_shell.cmd -ucrt64 -defterm -no-start -here -c "cd /d/Godot/xybotsResearch/mame-src && make SUBTARGET=xybots SOURCES=src/mame/atari/xybots.cpp -j6"
```

Output:

```text
D:\Godot\xybotsResearch\mame-src\xybots.exe
```

## Run

Use the workspace launcher:

```powershell
D:\Godot\xybotsResearch\mame\launch_xybots_wall_capture.ps1
```

Controls:

```text
F11  Write one full capture
F12  Toggle automatic unique sprite capture
Esc  Exit MAME
```

## Output

One-shot captures are written under:

```text
D:\Godot\xybotsResearch\mame-src\snap\xybots_capture\capture_####\
```

Wall-specific files:

```text
playfield_layer.png
playfield_debug.png
playfield_tiles.json
```

`playfield_layer.png` is the visible wall/floor playfield without sprites or HUD.

`playfield_debug.png` overlays an 8x8 tile grid and tile-code labels.

`playfield_tiles.json` records all 2048 playfield entries:

```json
{
  "tile_index": 0,
  "map_x": 0,
  "map_y": 0,
  "screen_x": 0,
  "screen_y": 0,
  "raw": "0x0000",
  "code": 0,
  "code_hex": "0x0000",
  "color": 0,
  "flag": 0
}
```

## What To Capture

Capture comparable states with `F11`:

```text
standing still in a corridor
before and after turning left
before and after turning right
before and after moving forward
facing a wall
facing a door/end panel
```

Diff `playfield_tiles.json` between captures to learn whether Xybots rewrites
the whole projected hallway or only updates parts of the playfield.
