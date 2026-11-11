# Public build version

Before each public export, run `python tools/stamp_release_version.py` from the project directory. It records a UTC timestamp in `project.godot` (for example `2026.11.11-204400Z`). Commit that change with the source being released, then export the `Web Public` preset from that commit. The title screen and feedback form both read this setting. Record the source commit and version in the public package commit message. Each export intended for release needs a fresh stamp; Git pushes do not update the number automatically.
