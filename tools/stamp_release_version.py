"""Stamp a unique UTC release identifier before committing and exporting."""
from datetime import datetime, timezone
from pathlib import Path
import re

project = Path(__file__).resolve().parents[1] / "project.godot"
text = project.read_text(encoding="utf-8")
version = datetime.now(timezone.utc).strftime("%Y.%m.%d-%H%M%SZ")
text, count = re.subn(r'^config/version="[^"]*"$', f'config/version="{version}"', text, count=1, flags=re.MULTILINE)
if count != 1:
    raise SystemExit("Expected exactly one application config/version setting")
project.write_text(text, encoding="utf-8")
print(version)
