# Blender Development Instructions

This repository contains Blender Python tools and addons.

## Target Environment

Target the Blender installation documented in `reference/README.md`. Prefer APIs and implementation details matching that Blender version. Do not assume behavior from older Blender tutorials or Blender's current development branch.

## Local References

Before searching the web for Blender implementation details, search these local references. Do not read entire documentation directories into model context; search, then open only the relevant files or sections.

### `reference/blender_python_api/`

Offline Blender Python API documentation. Use this first for `bpy`, `bmesh`, `mathutils`, operators, armatures, edit bones, pose bones, vertex groups, modifiers, properties, panels, addon registration, context/mode handling, and animation APIs.

Read `reference/blender_python_api/API_SOURCE_INFO.txt` before relying on it. If it records the exact-release documentation-source fallback, it is searchable official RST and examples, but generated per-type HTML pages are not locally available; inspect the relevant local source first and use the web only if that source cannot answer a type-level question.

### `reference/rigify_source/`

Source code for the Rigify version bundled with the target Blender installation. This is the primary authority for Rigify implementation details: metarig creation, generated-rig structure, bone naming, DEF/ORG/MCH/control bones, rig generation, rig types, fingers, limbs, utilities, metadata, custom properties, and generator behavior. For Rigify-specific work, inspect this source before guessing.

### `reference/blender_developer_docs/`

Official Blender developer documentation. Use it for architecture, coding conventions, addon-development practices, developer guidance, and background concepts.

## Search Strategy

Use targeted local searches, for example:

```powershell
rg -n "metarig" reference/rigify_source
rg -n "limbs.arm" reference/rigify_source
rg -n "super_finger" reference/rigify_source
rg -n "generate" reference/rigify_source
rg -n "edit_bones" reference/blender_python_api
rg -n "VertexGroup" reference/blender_python_api
```

If local documentation and source implementation disagree:

1. Prefer the implementation bundled with the target Blender version.
2. Note the discrepancy.
3. Do not silently substitute APIs from Blender main.

## Rigify Development Rules

1. Inspect the local Rigify source before implementing or guessing behavior.
2. Do not assume generated bone naming conventions without verifying them.
3. Preserve clean Rigify metadata on metarigs.
4. Prefer official Rigify operators and generator mechanisms where practical.
5. Do not reproduce Rigify internals unnecessarily.
6. Distinguish between metarig bones, ORG bones, DEF bones, MCH bones, and animation controls.
7. Never assume a vertex group should simply be renamed to `DEF-` plus a bone name without confirming the generated structure.
8. Treat version-specific Rigify behavior as authoritative.

## Blender Addon Development Rules

Use current APIs matching the target installation and avoid deprecated APIs. For production-data tools: preserve user data; prefer non-destructive workflows; provide validation and dry-run/analyze modes when practical; make major operations undoable; use test duplicates before modifying originals when appropriate; and never silently delete meshes, armatures, animation, vertex groups, or skin weights.

## Web Search

Use web search only when the local references are insufficient or incomplete, a recent bug/version issue must be checked, or external package information is required. When web information conflicts with the installed-version source, prefer installed-version implementation unless there is evidence of a known bug or fix.
