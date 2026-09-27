"""Native, resumable Asset Browser preview generator for this library.

Runs inside Blender's UI with timers because asset_generate_preview() is an
asynchronous job. It deliberately saves only after RENDER_PREVIEW has ended.
"""
from pathlib import Path
import bpy

LIBRARY = Path(r"D:\Godot\xybotsResearch\blender\assets\POLYGON_Western_Pack_Source_Files_v4\BlenderAssets")
LOG = LIBRARY.parent / "conversion_logs" / "native_preview_complete.txt"
STATE = {"remaining": [], "current": None, "original_save_version": None}


def _write_log(path):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as handle:
        handle.write(str(path) + "\n")


def _open_next():
    if not STATE["remaining"]:
        if STATE["original_save_version"] is not None:
            bpy.context.preferences.filepaths.save_version = STATE["original_save_version"]
        print("POLYGON Western native-preview batch complete")
        return None
    path = STATE["remaining"].pop(0)
    STATE["current"] = path
    print(f"Generating preview: {path} ({len(STATE['remaining'])} remaining in this batch)")
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    collections = [c for c in bpy.data.collections if c.asset_data]
    if not collections:
        print(f"SKIP no Collection Asset: {path}")
        return 0.1
    # Each generated file contains exactly one logical Collection Asset.
    collections[0].asset_generate_preview()
    return 0.1


def _tick():
    if bpy.app.is_job_running("RENDER_PREVIEW"):
        return 0.1
    if STATE["current"] is not None:
        # Avoid .blend1 backups for generated output; restore the user's setting
        # when this short batch ends.
        bpy.ops.wm.save_as_mainfile(filepath=str(STATE["current"]), check_existing=False)
        _write_log(STATE["current"])
        STATE["current"] = None
    return _open_next()


def start(max_files=5):
    """Generate native previews for `max_files` output blends, then stop."""
    if bpy.app.timers.is_registered(_tick):
        raise RuntimeError("A native-preview batch is already running.")
    done = set(LOG.read_text(encoding="utf-8").splitlines()) if LOG.exists() else set()
    STATE["remaining"] = [p for p in sorted(LIBRARY.rglob("*.blend")) if str(p) not in done][:max_files]
    STATE["current"] = None
    STATE["original_save_version"] = bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version = 0
    # open_mainfile() clears ordinary timers; persistence keeps this state
    # machine alive while it switches through the generated asset files.
    bpy.app.timers.register(_tick, first_interval=0.1, persistent=True)
    print(f"Queued {len(STATE['remaining'])} native previews.")
