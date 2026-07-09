# Xybots Sprite Research Tools

This folder contains the local automation used to inspect, reconstruct, mask,
deduplicate, and package Xybots sprite captures.

## MAME Motion-Object Capture

The MAME source changes are stored as a patch:

```text
patches/mame/xybots_motion_object_capture.patch
```

The matching implementation notes are stored in:

```text
docs/xybots_motion_object_capture.md
```

The patched MAME workflow captures live Xybots motion-object strips, auto-detects
new strip graphics while you play, writes conservative stitched candidate PNGs,
and writes a more relaxed `characters` pass that tries to combine nearby strips
from the same frame into larger sprite candidates.

Typical output folders from the patched local MAME build:

```text
D:\Godot\xybotsResearch\mame-src\snap\xybots_capture\auto\strips
D:\Godot\xybotsResearch\mame-src\snap\xybots_capture\auto\stitched
D:\Godot\xybotsResearch\mame-src\snap\xybots_capture\auto\characters
```

## Layered PSD Builder

Use this after capture to turn the `characters` PNG folder into a Photoshop
document with one PNG per layer. Use `stitched` instead if you want the more
conservative partial assemblies.

```powershell
powershell -ExecutionPolicy Bypass -File D:\Godot\xybotsResearch\Project\xybots-research\tools\xybots_research\Build-LayeredPsdFromPngs.ps1 `
  -InputDir D:\Godot\xybotsResearch\mame-src\snap\xybots_capture\auto\characters `
  -OutputPsd D:\Godot\xybotsResearch\mame-src\snap\xybots_capture\auto\xybots_characters_layers_4096_top_first.psd `
  -CanvasWidth 4096 `
  -CanvasHeight 4096
```

Notes:

- The default canvas is `4096x4096`.
- Layer names are copied from the source PNG filenames.
- Layer order is reversed internally so Photoshop shows low-numbered files at
  the top of the layer stack and high-numbered files at the bottom.
- Layers are placed at the document origin so they can be manually arranged.

## Photoshop Fallback Importer

If Photoshop rejects a generated PSD, use:

```text
Import-XybotsStitchedLayers.jsx
```

That script asks Photoshop to import each PNG as a layer and save the PSD itself.
It is slower, but it uses Photoshop's own file writer.

## Photoshop 8x8 Tile Mover

Use this when manually arranging `xybots_sprites_raw_8x8_tiles_clean_1x.psd`
inside Photoshop:

```text
Start-XybotsTileMover.ps1
```

Run it from PowerShell while Photoshop is open:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Godot\xybotsResearch\tools\Start-XybotsTileMover.ps1
```

This opens a small always-on-top Windows tool that controls the active Photoshop
document through Photoshop scripting. This path is preferred over the ScriptUI
`.jsx` palette because recent Photoshop builds can fail to show modeless
ExtendScript palettes reliably.

Workflow:

- Select an 8x8 tile with the rectangular marquee.
- Click `SetTop`, `SetCopy`, `SetPaste`, or `SetJunk` to store that tile
  position.
- `Move` moves the current copy tile into the current paste tile, clears the
  source tile, then advances copy right 8 px and paste down 8 px.
- `Return` moves paste right 8 px and back to the stored top row.
- `Junk` moves the current copy tile into the next junk tile, clears the source
  tile, advances copy right 8 px, advances junk right 8 px, and leaves paste
  unchanged.

The script edits the currently active layer by clearing the source selection,
creating a temporary pasted layer, translating it into place, and immediately
merging it down.

`XybotsTileMover.jsx` is kept as an in-Photoshop ScriptUI version, but the
PowerShell launcher is the more reliable tool.

## Other Scripts

The remaining scripts are historical and practical helpers from the research
process:

- ROM/tile export and raw atlas generation
- live motion-object capture helpers
- sprite masking against captured background plates
- transparent trimming and duplicate cleanup
- manual player pose/LOD reconstruction experiments
