# Xybots MAME Capture Restore

This document preserves the local MAME capture/editor work needed to keep recording Xybots reference footage on another computer.

## Backed-Up Files

- `patches/mame/xybots_capture_hotkeys_and_recorder.patch`
  - Combined patch from local `mame-src` against upstream MAME commit `3c9dc04eb1848ae0da666e5f43f1b2fe457c31fd`.
  - Includes the local capture commits and the current uncommitted recorder changes.
  - Adds Xybots capture hotkeys, wall-turn recording, Premiere-friendly frame names, session indexing, and controlled movement capture scripting.
- `tools/mame-launchers/`
  - Backup copy of the PowerShell launchers from `D:\Godot\xybotsResearch\mame`.

## Not Included

- Built MAME binaries, including `xybots.exe`.
- ROM files, including `xybots.zip`.
- Recorded output under `snap/xybots_capture`.

Keep your legally obtained ROM separately. The launch scripts expect `xybots.zip` to remain zipped.

## Restore On Another Computer

1. Clone this project repo.

2. Clone MAME somewhere local.

   ```powershell
   git clone https://github.com/mamedev/mame.git D:\Godot\xybotsResearch\mame-src
   ```

3. Check out the patch base commit.

   ```powershell
   Set-Location D:\Godot\xybotsResearch\mame-src
   git checkout 3c9dc04eb1848ae0da666e5f43f1b2fe457c31fd
   ```

4. Apply the backed-up Xybots capture patch.

   ```powershell
   git apply D:\Godot\xybotsResearch\Project\xybots-research\patches\mame\xybots_capture_hotkeys_and_recorder.patch
   ```

5. Build the Xybots MAME target. The capture launchers expect `xybots.exe` in the MAME source root.

   ```powershell
   make SUBTARGET=xybots SOURCES=src/mame/atari/xybots.cpp -j8
   ```

6. Put the Xybots ROM at the launcher default path, or pass a custom ROM root.

   Default:

   ```text
   D:\MAME\roms\xybots.zip
   ```

7. Launch the capture build with cheats enabled.

   ```powershell
   Set-Location D:\Godot\xybotsResearch\Project\xybots-research
   .\tools\mame-launchers\launch_xybots_wall_capture_cheats.ps1 -MameSourceRoot D:\Godot\xybotsResearch\mame-src -RomRoot D:\MAME\roms
   ```

## Capture Hotkeys

- `F10`: Toggle every-frame wall/playfield recording.
- `F11`: Write one full capture: playfield PNG, playfield JSON, sprite PNGs.
- `F12`: Toggle automatic unique sprite capture.
- `Tab`: Open MAME menu, including cheats.
- `Esc`: Exit MAME.

Recording output is written under:

```text
<mame-src>\snap\xybots_capture
```

Wall-turn/frame recording sessions are written under:

```text
<mame-src>\snap\xybots_capture\wall_turn_recordings\session_####
```

The playfield frames are named for video import:

```text
frame_00001.png
frame_00002.png
...
```

## Controlled Movement Capture

Use this launcher when you want the automated labeled movement sessions:

```powershell
.\tools\mame-launchers\launch_xybots_controlled_capture.ps1 -MameSourceRoot D:\Godot\xybotsResearch\mame-src -RomRoot D:\MAME\roms
```

The launcher waits for setup. After the game is running:

1. Press any key at the first screen.
2. Press `5` to insert a coin.
3. Press `1` to start.
4. Clear robots and place the player.
5. Create this trigger file:

   ```powershell
   New-Item -ItemType File D:\Godot\xybotsResearch\mame-src\snap\xybots_capture\start_controlled_capture.txt -Force
   ```

MAME then records labeled sessions for forward, backward, turn left, turn right, strafe left, and strafe right.
