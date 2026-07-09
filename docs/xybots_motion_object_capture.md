# Xybots Motion Object Capture

This is a developer-only inspection path for Xybots motion objects. It observes
the sprite renderer and writes capture files for one frame at a time. It does
not modify ROM data, gameplay, emulation timing, sprite coordinates, priority
rules, or the normal MAME render path.

## Rendering Notes

The Xybots frame path is:

1. `xybots_state::screen_update()`
2. `m_mob->draw_async(cliprect)`
3. `atari_motion_objects_device::draw()`
4. `build_active_list()`
5. `render_object()`
6. Xybots merges `m_mob->bitmap()` into the playfield
7. Xybots draws the alpha layer

`draw_async()` is synchronous in the current sprite device implementation. It
clears dirty regions, wraps the backing motion-object bitmap, and immediately
calls the device `draw()` implementation.

The safest point to capture the full sprite-only layer is immediately after
`m_mob->draw_async(cliprect)` returns in `xybots_state::screen_update()`, before
the playfield merge.

The safest first-version point for decoded Xybots fields is the driver, using
the 64 raw entries in motion-object RAM. `build_active_list()` copies the four
entry words into the active list and does not preserve the source slot number,
so slot identity does not survive into `render_object()`.

For Xybots, the motion-object RAM range is `0x802e00-0x802fff`, or 64 entries of
four 16-bit words. Xybots uses unlinked, unsplit, sequential motion objects.
Width is fixed at one 8-pixel tile. Height is `(word2 & 7) + 1`.

## Captured Files

Captures are written under the configured snapshot directory. With default MAME
options this is usually:

```text
snap/xybots_capture/capture_0001/
```

Each capture contains:

```text
metadata.json
sprite_layer.png
sprite_layer_debug.png
objects/
    slot_00.png
    slot_01.png
    ...
```

`sprite_layer.png` is the complete motion-object bitmap for the visible frame,
converted to RGBA with transparent pixels where the motion-object bitmap stores
`0xffff`. Priority bits are ignored for color conversion and preserved in JSON.

`objects/slot_NN.png` files are local reconstructed motion-object strips using
the same decoded graphics element, palette base, priority bits, transparency,
height, and horizontal flip rules used by the renderer.

`sprite_layer_debug.png` starts from `sprite_layer.png` and overlays object
bounding boxes, slot numbers, and graphics codes.

## Metadata Schema

Example:

```json
{
  "game": "xybots",
  "capture_index": 1,
  "emulated_frame": 12345,
  "capture_dir": "xybots_capture/capture_0001",
  "trigger": "MAME_XYBOTS_CAPTURE=1 and KEYCODE_F12",
  "screen": {
    "width": 336,
    "height": 240
  },
  "motion_object_space": {
    "width": 512,
    "height": 512
  },
  "objects": [
    {
      "slot": 17,
      "raw_words": ["0x04B0", "0x0005", "0x6405", "0x3203"],
      "code": 1200,
      "code_hex": "0x04B0",
      "source_tiles": [1200, 1201, 1202, 1203, 1204, 1205],
      "color": 3,
      "priority": 5,
      "raw_position": {
        "x": 100,
        "y": 200
      },
      "rendered_position": {
        "x": 100,
        "y": 264
      },
      "size_tiles": {
        "width": 1,
        "height": 6
      },
      "size_pixels": {
        "width": 8,
        "height": 48
      },
      "flip": {
        "x": false,
        "y": false
      },
      "visible": true,
      "image": "objects/slot_17.png"
    }
  ]
}
```

## Build

From the MAME source root:

```powershell
C:\msys64\usr\bin\bash.exe -lc 'export MSYSTEM=UCRT64; source /etc/profile; export MINGW64=1; cd /d/Godot/xybotsResearch/mame-src && make SUBTARGET=xybots SOURCES=src/mame/atari/xybots.cpp PTR64=1 -j4'
```

This produces:

```text
D:\Godot\xybotsResearch\mame-src\xybots.exe
```

## Run

Enable capture with an environment variable. Capture is disabled by default.

```powershell
$env:MAME_XYBOTS_CAPTURE = "1"
D:\Godot\xybotsResearch\mame-src\xybots.exe xybots -rompath D:\MAME\roms
```

Press `F12` to toggle automatic unique sprite capture.

While auto capture is on, each frame is scanned but files are only written when
the rendered sprite content has not been seen before in the current run. Press
`F12` again to stop auto capture and write a final one-frame truth dump.

Automatic capture writes:

```text
snap/xybots_capture/auto/
    strips/
        strip_00001_slot_37_code_04B0_h6_c3_p5.png
        ...
    stitched/
        stitched_00001_frame_12345_parts_3.png
        ...
    characters/
        character_00001_frame_12345_parts_6.png
        ...
```

`strips` are the individual Xybots motion objects. `stitched` images are
candidate assembled sprites made by grouping adjacent visible strips with the
same color and priority. `characters` are a second, more relaxed grouping pass
that merges nearby same-frame strips with matching color and priority into
larger logical sprite candidates. They are intentionally heuristic review output,
not a claim that the game has a formal "character object" at that level.

## Changed Source Files

`src/mame/atari/xybots.cpp`

- Adds Xybots-only capture state and helpers.
- Checks `MAME_XYBOTS_CAPTURE` in `machine_start()`.
- Uses `F12` to toggle automatic unique capture after `m_mob->draw_async(cliprect)`
  and before the playfield merge.
- Exports new unique strip PNGs, conservative stitched candidate PNGs, and
  relaxed character candidate PNGs while auto capture is running.
- Writes a final one-frame dump with `sprite_layer.png`, per-slot object PNGs,
  `metadata.json`, and `sprite_layer_debug.png` when auto capture is stopped.

`docs/xybots_motion_object_capture.md`

- Documents the call chain, capture points, workflow, schema, and limitations.

## Verification Checklist

1. Run Xybots without `MAME_XYBOTS_CAPTURE`; confirm no files are written and
   gameplay/rendering are unchanged.
2. Run with `MAME_XYBOTS_CAPTURE=1`; confirm startup logs the capture feature.
3. Press `F12` during gameplay; confirm auto capture turns on in the console.
4. Move through the game; confirm new files appear in `snap/xybots_capture/auto`.
5. Press `F12` again; confirm auto capture turns off and one numbered capture
   directory is written.
6. Open `sprite_layer.png`; confirm sprites are present, playfield/HUD are
   absent, colors look correct, and transparency is present.
7. Pick a visible slot in `metadata.json`; confirm `height_tiles * 8` matches
   the PNG height.
8. Confirm the source tile list increments in the order used by the renderer.
9. Compare `sprite_layer_debug.png` with `sprite_layer.png` to verify slot
   labels and bounding boxes are plausible.

## Known Limitations

- This is Xybots-specific. It does not attempt to generalize to other Atari
  motion-object games.
- Slot decoding is mirrored in the driver from the Xybots motion-object config.
  It is intentionally not a generic callback from `render_object()` yet.
- Stitched and character images are heuristic. They group visible strips with
  matching color and priority, which is useful for reviewing player/enemy
  captures but can also group unrelated nearby objects.
- Object PNGs are rendered in local strip space. Wrapped screen-space placement
  is represented in metadata and the sprite-layer/debug images.
