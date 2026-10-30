# Semantic GPU Cage Prop Brief

Use this short brief in a fresh session. Attach visual references after it.
Unknown items can be left as “decide from reference.”

```text
Create a semantic GPU-cage [PROP NAME] for Xybots/Grudge County.

Purpose and scale:
- Gameplay role: [decoration / collision / breakable / pickup / character / FX]
- Approximate world footprint and height: [values or comparison prop]
- Should it remain readable at far distance as: [silhouette / icon / colour block]

Construction cage:
- Major form: [cube / cylinder / tapered shape / planes / ribbon / other]
- Minimum meaningful cage features: [corners, rows, axes, top, recess, etc.]
- Parts that should share the same projected edges: [list]

Semantic paint order, back to front:
1. [contact shadow]
2. [interior / recessed region]
3. [base planes]
4. [frames, seams, slats, braces, trim]
5. [close-only highlights]

Artist controls needed:
- Colours: [list]
- Shape values: [list]
- Logical-pixel widths: [list]
- Visibility / angle fade: [list]
- Distance LOD groups: [which parts fade, narrow to 1px, or persist]

Gameplay integration:
- Collision: [yes/no and shape]
- Damage/destruction/loot: [rules]
- Persistence: save style edits to [new or existing .tres]

Debugging:
- Show cage wireframe: [yes/no]
- Show semantic mask boundaries for: [list]

Acceptance image/readability notes:
- [what must look correct at close, middle, far, and oblique angles]
```

For a normal request, also say whether to add a comparison fixture or replace
an existing prop. Do not assume a calibration scene is the main game entrypoint.
