# XYBOTS: batch-render one NLA animation family from eight compass directions.
# Required cameras: XYBOTS_CAM_N, NE, E, SE, S, SW, W, and NW.
# The selected NLA track chooses the animation family automatically. For example,
# selecting Run_Left_Full or Run_Left_Full_ADJ renders these enabled NLA layers:
#   Run_Left_Full, Run_Left_Full_ADJ, and Run_Left_Full_ADJ_<DIRECTION>.
# The two adjustment layers are optional. Other animation tracks on the same
# animated object are temporarily muted, so an older animation cannot blend in.
# Static objects and objects without this animation family are left untouched.
# Output folders must already exist below renders/xybots_8dir; this script does not create them.

# Imports and scene render settings
import bpy, os                                                                                       # Use Blender APIs and portable path construction.
scene = bpy.context.scene                                                                            # Read the active scene whose animation and render settings will be used.
scene.render.image_settings.file_format = "PNG"                                                      # Force PNG output for each sprite frame.
scene.render.image_settings.color_mode = "RGBA"                                                      # Include an alpha channel in each written PNG.
scene.render.film_transparent = True                                                                 # Render the world background as transparent alpha.

# Output, NLA animation-family, and directional-camera configuration
output_root = bpy.path.abspath("//renders/xybots_8dir")                                              # Resolve the output root relative to this saved blend file.
directions = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")                                            # Define the eight compass suffixes used for cameras and folders.
ANIMATION_NAME = None                                                                                 # None derives the family from the active NLA track; set e.g. "Run_Left_Full" only as a manual override.
original_camera = scene.camera                                                                       # Preserve the camera active before the batch begins.
original_path = scene.render.filepath                                                                # Preserve the normal output filepath for restoration after the batch.

# Return the track name plus its action names, so either normal NLA naming style works.
def nla_track_names(track):
    names = {track.name}                                                                              # NLA tracks are commonly named after their action.
    for strip in track.strips:                                                                        # A track can also carry the meaningful name only on its strip action.
        if strip.action is not None:
            names.add(strip.action.name)
    return names

# Convert a base or adjustment NLA track/action name to its base animation-family name.
def nla_base_name(track):
    names = nla_track_names(track)
    adjustment_names = sorted(name for name in names if "_ADJ" in name)                              # A selected global or directional adjustment still identifies its base family.
    if adjustment_names:
        return adjustment_names[0].split("_ADJ", 1)[0]
    return sorted(names)[0] if names else None                                                        # A selected base track names its own family.

# Prefer the NLA track the animator has selected; otherwise accept one unmuted base track.
def resolve_animation_name():
    if ANIMATION_NAME:
        return ANIMATION_NAME                                                                         # An explicit name is useful for unattended rendering.
    active_track = getattr(bpy.context, "active_nla_track", None)                                  # This is a Context property in Blender, and can be absent while running from the Text Editor.
    if active_track is not None:
        base_name = nla_base_name(active_track)
        if base_name:
            return base_name
    selected_base_names = set()                                                                       # NLA selection persists on tracks even when the script runs from a different editor.
    for obj in bpy.data.objects:
        animation_data = obj.animation_data
        if animation_data is None:
            continue
        for track in animation_data.nla_tracks:
            if getattr(track, "select", False):
                selected_base_names.add(nla_base_name(track))
    selected_base_names.discard(None)
    if len(selected_base_names) == 1:
        return selected_base_names.pop()
    unmuted_base_names = set()                                                                        # Fallback for scripts run without a selected NLA track.
    for obj in bpy.data.objects:
        animation_data = obj.animation_data
        if animation_data is None:
            continue
        for track in animation_data.nla_tracks:
            if not track.mute:
                unmuted_base_names.update(name for name in nla_track_names(track) if "_ADJ" not in name)
    if len(unmuted_base_names) == 1:
        return unmuted_base_names.pop()
    raise RuntimeError(
        "Could not determine one NLA animation family. Select its base or _ADJ track, "
        "or set ANIMATION_NAME explicitly. Candidates: " + repr(sorted(unmuted_base_names))
    )

# Store every NLA track on objects that own this animation family and its original mute state.
ANIMATION_NAME = resolve_animation_name()                                                            # Resolve once, before per-direction muting changes the current state.
print("XYBOTS rendering NLA animation family:", ANIMATION_NAME)                                     # Make the chosen family visible in Blender's System Console.
family_prefix = ANIMATION_NAME + "_ADJ"                                                              # Adjustment tracks always start with this base-animation prefix.
controlled_tracks = []                                                                                # Each item is (object name, NLA track, original mute state); static/unrelated objects are absent.
for obj in bpy.data.objects:                                                                         # Examine all objects, not just the selected armature.
    animation_data = obj.animation_data                                                              # Static objects normally have no animation data and are skipped.
    if animation_data is None:
        continue
    tracks = list(animation_data.nla_tracks)                                                         # Read once so the whole owning object's NLA stack can be isolated together.
    owns_family = any(                                                                                # An object belongs only when it has this base layer or one of its adjustments.
        any(name == ANIMATION_NAME or name.startswith(family_prefix) for name in nla_track_names(track))
        for track in tracks
    )
    if owns_family:
        controlled_tracks.extend((obj.name, track, track.mute) for track in tracks)                  # Preserve all its track states before temporarily isolating this animation.

# Enable the base layer plus the optional global and one directional adjustment layer.
def set_directional_nla_layers(direction):
    enabled_names = {
        ANIMATION_NAME,                                                                              # The original full animation is always included when present.
        ANIMATION_NAME + "_ADJ",                                                                    # The global adjustment is enabled only if its track exists.
        ANIMATION_NAME + "_ADJ_" + direction,                                                       # The camera-specific adjustment is enabled only if its track exists.
    }
    enabled_count = 0                                                                                # Report which optional layers were actually found without failing on omissions.
    for obj_name, track, _original_mute in controlled_tracks:
        enabled = bool(nla_track_names(track) & enabled_names)                                      # A track may match through either its track or action name.
        track.mute = not enabled                                                                      # Mute every non-selected track on this animation's owning object, preventing blended old animations.
        if enabled:
            enabled_count += 1
    print(f"XYBOTS NLA {direction}: enabled {enabled_count} matching track(s).")

# Render every animation frame from every direction
try:
    for direction in directions:                                                                     # Process each configured compass direction in order.
        camera = bpy.data.objects.get("XYBOTS_CAM_" + direction)                                     # Look up this direction's required camera object.
        if camera is None:                                                                           # Refuse to render if the required camera was not found.
            raise RuntimeError("Missing camera: " + direction)                                       # Stop and identify the missing directional camera.
        set_directional_nla_layers(direction)                                                        # Use the base, global, and this camera's optional adjustment tracks.
        scene.camera = camera                                                                        # Make this direction's camera active for Blender's renderer.
        for frame in range(scene.frame_start, scene.frame_end + 1):                                  # Visit every frame, including the configured end frame.
            scene.frame_set(frame)                                                                   # Evaluate animation, constraints, and frame-dependent state.
            scene.render.filepath = os.path.join(output_root, direction, f"{direction}_{frame:03d}.png") # Build the PNG path, such as NE/NE_005.png.
            bpy.ops.render.render(write_still=True)                                                  # Render the active camera and write that still PNG.
finally:
    scene.camera = original_camera                                                                   # Restore the camera that was active before the batch.
    scene.render.filepath = original_path                                                            # Restore the render filepath that was active before the batch.
    for _obj_name, track, original_mute in controlled_tracks:
        track.mute = original_mute                                                                   # Restore all NLA muting even if rendering stops with an error.

print("XYBOTS eight-direction render complete:", output_root)                                      # Report successful completion and the output root.
