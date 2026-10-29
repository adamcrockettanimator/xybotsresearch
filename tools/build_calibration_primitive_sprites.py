"""Build portable, ground-anchored sprites from Blender calibration plates.

The source images may have more than one source texel per logical game pixel.
This tool trims their transparent surround and records the floor point in the
same source-pixel coordinate system as the crop, so Godot can place the sprite
at a projected world foot without guessing where the source canvas used to be.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


PROJECT_DIR = Path(__file__).resolve().parent.parent
SOURCE_DIR = PROJECT_DIR / "assets" / "Calibration" / "primitive_sprite_sources"
OUTPUT_DIR = PROJECT_DIR / "assets" / "Calibration" / "primitive_sprites"
PADDING_PIXELS = 2


def padded_bbox(alpha: Image.Image) -> tuple[int, int, int, int]:
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("Source plate has no opaque pixels.")
    left, top, right, bottom = bbox
    return (
        max(0, left - PADDING_PIXELS),
        max(0, top - PADDING_PIXELS),
        min(alpha.width, right + PADDING_PIXELS),
        min(alpha.height, bottom + PADDING_PIXELS),
    )


def build() -> dict:
    with (SOURCE_DIR / "manifest.json").open("r", encoding="utf-8") as handle:
        source_manifest = json.load(handle)
    output_manifest = {
        "schema_version": 1,
        "logical_canvas": source_manifest["logical_canvas"],
        "reference_depth_godot_units": source_manifest["reference_depth_godot_units"],
        "source_pixels_per_logical_pixel": source_manifest["source_pixels_per_logical_pixel"],
        "perspective_lods": source_manifest.get("perspective_lods", []),
        "barrel_semantic_lods": source_manifest.get("barrel_semantic_lods", []),
        "notes": "Cropped greybox and semantic-prop sprites. Imported_Barrel_01 uses an unlit Z-normal palette, while normal/depth edge treatment exists only in its closest lod_00. ground_anchor is measured from the cropped PNG top-left in source pixels.",
        "sprites": [],
    }
    for plate in source_manifest["plates"]:
        source_path = PROJECT_DIR / plate["path"]
        image = Image.open(source_path).convert("RGBA")
        left, top, right, bottom = padded_bbox(image.getchannel("A"))
        cropped = image.crop((left, top, right, bottom))
        # Preserve any source depth-tier directory below the view directory.
        # Without this, all Grid_Cell_Block LODs would overwrite one another
        # during the crop stage.
        output_path = OUTPUT_DIR / source_path.relative_to(SOURCE_DIR)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        cropped.save(output_path)
        source_pixels = float(source_manifest["source_pixels_per_logical_pixel"])
        # Blender reports the projected foot in logical 160x120 coordinates.
        # The PNG/crop uses the higher-resolution source canvas, so convert the
        # foot before subtracting the source-pixel crop origin.
        foot_x, foot_y = (value * source_pixels for value in plate["foot_screen"])
        output_manifest["sprites"].append({
            "name": plate["name"],
            "view": plate["view"],
            "perspective_lod": plate.get("perspective_lod", "base"),
            "reference_depth_godot_units": plate.get("reference_depth_godot_units", source_manifest["reference_depth_godot_units"]),
            "path": output_path.relative_to(PROJECT_DIR).as_posix(),
            "crop_rect": [left, top, right - left, bottom - top],
            "ground_anchor": [round(foot_x - left, 4), round(foot_y - top, 4)],
        })
    with (OUTPUT_DIR / "manifest.json").open("w", encoding="utf-8") as handle:
        json.dump(output_manifest, handle, indent=2)
    return {"sprites": len(output_manifest["sprites"]), "output": str(OUTPUT_DIR)}


if __name__ == "__main__":
    print(build())
