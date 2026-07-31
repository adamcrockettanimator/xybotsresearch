# MAME Controls for Xybots Research

## Starting the Game

Open PowerShell and run:

```powershell
Set-Location D:\Godot\xybotsResearch
.\mame\launch_xybots.ps1
```

The launcher checks for `D:\MAME\mame.exe`, checks for `D:\MAME\roms\xybots.zip`, runs a quick ROM audit, and then starts:

```powershell
D:\MAME\mame.exe xybots
```

If MAME says the ROM is missing, place your legally obtained `xybots.zip` at:

```text
D:\MAME\roms\xybots.zip
```

Do not unzip it. Do not rename files inside it.

If the audit fails, run:

```powershell
.\mame\verify_xybots.ps1
```

That writes a timestamped log under `D:\Godot\xybotsResearch\logs`.

## Basic Gameplay Controls

Common MAME defaults:

```text
5       Insert coin
1       Start player 1
Esc     Exit
Tab     MAME menu
F12     Save screenshot
```

Xybots used unusual arcade controls, including turning controls that do not map perfectly to a normal keyboard. Playing well is secondary here. The main goal is to get into the running game and use MAME's graphics inspection tools.

## Graphics Viewer

Press:

```text
F4
```

This opens MAME's internal graphics viewer.

Use:

```text
Enter   Cycle between Palette, Graphics, and Tilemap views
[ ]     Change graphics set or tilemap
Arrow keys / Page Up / Page Down   Move around the current view
Left / Right   Change palette in graphics views
F12     Save screenshot
Esc     Leave MAME
```

## Terms

A palette is a table of final colors. Many arcade graphics store small numeric pixel values, and those values become visible colors only after a palette is applied. If a tile looks meaningless, try different palettes before deciding it is unused.

A graphics set is a group of decoded image chunks MAME has reconstructed from ROM data. For Xybots, expect small 8x8 chunks rather than full finished screenshots. MAME may label or number these sets differently than our notes, so identify them by visual content.

A tile is a small reusable image chunk, often 8x8 pixels. Larger walls, floors, doors, and UI elements may be assembled from many neighboring tiles.

A tilemap is a grid that places tile numbers on screen. Tilemaps are important because they show how small tiles are assembled into larger views, and may reveal offscreen or intermediate rendering data.

A sprite or motion object is a movable graphic object, such as a player, enemy, projectile, pickup, or effect. Large arcade sprites are often built from multiple small chunks.
