# POLYGON Western Blender Asset Library

The untouched vendor source is in `SourceFiles`. The generated Blender Asset Browser library root is `BlenderAssets`; add that folder in **Edit > Preferences > File Paths > Asset Libraries**.

The conversion produces one asset `.blend` per canonical FBX in catalog folders: Buildings, Characters, Environments, FX, Props, Vehicles, and Weapons. Alternate Unreal character exports, the combined `Characters.fbx`, and the demo-scene FBX remain preserved source only, avoiding duplicate assets.

The conversion uses the vendor `MaterialList_PolygonWestern.txt` to connect only exact named diffuse-atlas assignments. It does not guess metallic, roughness, normal, alpha, or emission channel mappings; those are retained from the FBX when present and logged for review when not confidently known. Image paths in generated library files are relative to each asset `.blend`.

`tools/convert_western_assets.py` is the repeatable/resumable tool used for setup. In Blender's Python Console, run:

```python
exec(compile(open(r"D:\Godot\xybotsResearch\blender\assets\POLYGON_Western_Pack_Source_Files_v4\tools\convert_western_assets.py", encoding="utf-8").read(), "convert_western_assets.py", "exec"))
run_batch(limit=20)
```

Run it again until `processed_this_run` is zero. Use `run_batch(limit=20, force=True)` only to rebuild assets deliberately. Logs and reports are written to `conversion_logs`.

For native Blender thumbnails, use `tools/generate_asset_previews.py`. It runs short resumable batches with Blender's built-in Collection Asset preview generator and waits for each `RENDER_PREVIEW` job before saving, so the thumbnails match the **Generate Preview** button in the Asset Browser.
