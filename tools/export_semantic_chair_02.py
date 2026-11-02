"""Export the simplified Blender chair as a GLB plus semantic edge markup.

Run with Blender in background mode.  This script never saves the source .blend.
"""

import bpy
import json
import sys
from pathlib import Path


def normalized(name: str) -> str:
    return name.lower().replace(" ", "_")


def main() -> None:
    arguments = sys.argv
    if "--" in arguments:
        divider = arguments.index("--")
        output_directory = Path(arguments[divider + 1]).resolve()
    else:
        # Makes the exact same exporter usable through Blender's Text Editor:
        # open this file and choose Run Script. It never saves the .blend.
        output_directory = Path(r"D:\Godot\xybotsResearch\Project\xybots-research\assets\semantic_props")
    output_directory.mkdir(parents=True, exist_ok=True)

    object_name = "sm_prop_chair_02_edges"
    source = next(
        (candidate for candidate in bpy.data.objects if normalized(candidate.name) == object_name),
        None,
    )
    if source is None or source.type != "MESH":
        raise RuntimeError("Could not find mesh object SM Prop Chair 02_edges")

    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    bpy.context.view_layer.objects.active = source

    glb_path = output_directory / "SM_Prop_Chair_02_edges.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
    )

    world_vertices = [list(source.matrix_world @ vertex.co) for vertex in source.data.vertices]
    material_names = [material.name if material else "" for material in source.data.materials]
    markup = {
        "source_object": source.name,
        "vertices": world_vertices,
        "edges": [
            {"vertices": list(edge.vertices), "sharp": bool(edge.use_edge_sharp)}
            for edge in source.data.edges
        ],
        "faces": [
            {
                "vertices": list(polygon.vertices),
                "material": material_names[polygon.material_index],
            }
            for polygon in source.data.polygons
        ],
    }
    markup_path = output_directory / "SM_Prop_Chair_02_edges.semantic.json"
    markup_path.write_text(json.dumps(markup, indent=2), encoding="utf-8")
    print(f"Exported {source.name}: {len(world_vertices)} vertices, {len(markup['edges'])} edges, {len(markup['faces'])} faces")


if __name__ == "__main__":
    main()
