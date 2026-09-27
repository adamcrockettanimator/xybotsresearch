# Rigify Clean Human Rebuild

Addon entry point: `rigify_clean_rebuild.py`.

For development reload, open this file in Blender's Text Editor and choose
**Run Script**. The panel appears in **3D Viewport > N > Rigify Rebuild**.
Before running it, enable the bundled **Rigify** extension/add-on. To install
the file persistently, use Blender Preferences' legacy Add-ons install action
for `rigify_clean_rebuild.py` (or package that single file in a ZIP), then
enable **Rigging: Rigify Clean Human Rebuild**.

Use the panel in numeric order. Set **Reference Armature** to `metarig` and
either choose `subdCowboyCollapsed` as **Character Mesh**, select it in the
viewport, or select several mesh objects. Step 5 makes independent object and
mesh-data duplicates named `*_Rigify_TEST`; it does not edit the selected
originals. The final button displays Blender's confirmation dialog and is the
only step that edits original selected meshes.

If the fitted source treated `spine.004` as the neck and `spine.005` as the
head, use **2b. Simplify Clean Metarig to One Neck** after fitting and before
generation. It removes clean `spine.004`, moves clean `spine.005` to its former
position as the sole neck, moves clean `spine.006` to the former `.005` position
as the head, and keeps the pristine Super Head configuration by using Rigify's
own parameter-copy helper. It maps old `.004` weights to `DEF-spine.005` and old
`.005` weights to `DEF-spine.006`. It refuses to change anything if the old
`spine.006` group has nonzero weights, because that case needs a deliberate
weight-routing decision. Regenerate before creating a new test mesh.

The addon transfers only runtime-verified direct `DEF-<source>` destinations.
One-to-many/segmented, unmatched, non-deforming, and unrelated groups are
reported but never copied in version 1. Open Blender's **Window > Toggle System
Console** to see the complete report; the panel holds a shortened copy.

After testing, **Prune Copied Legacy Groups From Test** can declutter only a
selected `*_Rigify_TEST` mesh. It removes an old source group only after its
destination DEF group is present and numerically identical on every vertex.
It never runs on the original mesh and leaves unresolved or complex groups in
place for review.

**Toggle FK Weight-Test Animation** creates a persistent action named
`RigifyRebuild_FK_Weight_Test`. It keys the actual Rigify FK controls (including
the direct-name finger FK controls), plus the Human torso, hips, chest,
shoulders, neck, neck bend, and head controls, through neutral, positive,
neutral, negative, neutral rotations around local X/Y/Z. A second click
restores the action that was active before the test and restores NLA mute
states; it retains the test action and its `[RCR FK]` timeline markers for
later use.

Keys are arranged by generated ORG hierarchy rather than alphabetically: spine
continuation first, then right-side branches before left-side branches, with an
arm/hand followed by each of that hand's finger chains.

Use **Delete FK Weight-Test Action** to remove only the addon-tagged test action
and its `[RCR FK]` markers. It asks for confirmation, restores the prior action
first when needed, then force-unlinks and deletes that explicitly tagged action.

Rigify source basis: `reference/rigify_source/metarigs/human.py`,
`generate.py`, `utils/naming.py`, `rigs/limbs/arm.py`, and
`rigs/limbs/super_finger.py`.
