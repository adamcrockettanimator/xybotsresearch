# Xybots Graphics Research Workspace

This workspace is for technical research into how the 1987 Atari arcade game Xybots assembles its graphics in MAME.

It is not a ROM archive. Do not redistribute ROM files or exported copyrighted graphics.

## Current Setup

- Research workspace: `D:\Godot\xybotsResearch`
- Preferred `E:\` paths were not available on this computer, so this setup uses `D:\` paths.
- MAME install: `D:\MAME`
- MAME executable: `D:\MAME\mame.exe`
- MAME version: `0.288 (mame0288)`
- Official release source: https://www.mamedev.org/release.html
- Windows x64 package used: `mame0288b_x64.exe`
- MAME ROM path from `-showconfig`: `roms`
- MAME screenshot path from `-showconfig`: `snap`
- Normal Xybots ROM location for this setup: `D:\MAME\roms\xybots.zip`
- ROM audit result: passed with MAME 0.288
- Audit log: `D:\Godot\xybotsResearch\logs\verify_xybots_2026-07-05_185904.log`
- MAME description: `xybots` = `Xybots (rev 2)`

## First Commands

From PowerShell:

```powershell
Set-Location D:\Godot\xybotsResearch
.\mame\verify_xybots.ps1
.\mame\launch_xybots.ps1
```

## Research Order

1. Verify MAME and audit the `xybots` ROM set.
2. Launch Xybots normally in MAME.
3. Use `F4` to open the built-in graphics viewer.
4. Inspect palettes, graphics sets, and tilemaps before attempting any export workflow.
5. Save screenshots with `F12`.
6. Copy selected screenshots into research folders with `.\mame\collect_latest_screenshot.ps1 -Category tiles`.

## Copyright Boundary

The ROM and any decoded/exported graphics are copyrighted reference materials for private research only. This workspace should contain notes, scripts, screenshots, and private research artifacts only. Do not publish ROM contents or copied artwork.

## Private Sprite Export

To regenerate local sprite study sheets:

```powershell
.\tools\export_xybots_sprites.ps1
```

Open these in Photoshop first:

```text
D:\Godot\xybotsResearch\exports\sprites\xybots_sprites_vertical_4_tiles_step4.png
D:\Godot\xybotsResearch\exports\sprites\xybots_sprites_vertical_8_tiles_step8.png
```

The export uses a debug palette, not final in-game colors. The sheets are for identifying structure and tile groupings only.

## Live Motion-Object Capture

To record the live sprite/motion-object table while playing:

```powershell
.\mame\launch_xybots_record_mob.ps1
```

Play or move near objects you want to inspect, then press `Esc` to exit MAME. CSV logs are written to:

```text
D:\Godot\xybotsResearch\exports\live_mob_capture
```

This records tile/code, X/Y, height, palette, priority, and horizontal flip fields from live motion-object RAM. It does not copy artwork by itself.

## Frame Recording With F12 Markers

For frame-by-frame visual study, run:

```powershell
.\mame\launch_xybots_frame_record.ps1
```

During play:

```text
F12   first press marks the start
F12   second press marks the end
Esc   exit MAME
```

Then extract one PNG per recorded frame between the first two F12 marker screenshots:

```powershell
.\tools\extract_frame_recording.ps1
```

Sessions are stored under:

```text
D:\Godot\xybotsResearch\exports\frame_recordings
```

This launcher saves F12 marker screenshots at Xybots' native `336x240` resolution so the pixel graphics remain exact.
