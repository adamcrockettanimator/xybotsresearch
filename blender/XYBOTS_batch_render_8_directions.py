# XYBOTS: batch-render one NLA animation family from eight compass directions.
# Required cameras: XYBOTS_CAM_N, NE, E, SE, S, SW, W, and NW.
# This renderer evaluates the NLA stack exactly as it is currently configured
# in Blender. It does not select, enable, mute, or infer any animation tracks.
# Set up the desired base and adjustment layers manually, then run this script.
# Output folders must already exist below renders/xybots_8dir; this script does not create them.

# Imports and scene render settings
import bpy, os                                                                                       # Use Blender APIs and portable path construction.
scene = bpy.context.scene                                                                            # Read the active scene whose animation and render settings will be used.
scene.render.image_settings.file_format = "PNG"                                                      # Force PNG output for each sprite frame.
scene.render.image_settings.color_mode = "RGBA"                                                      # Include an alpha channel in each written PNG.
scene.render.film_transparent = True                                                                 # Render the world background as transparent alpha.

# Output and directional-camera configuration
output_root = bpy.path.abspath("//renders/xybots_8dir")                                              # Resolve the output root relative to this saved blend file.
directions = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")                                            # Define the eight compass suffixes used for cameras and folders.
original_camera = scene.camera                                                                       # Preserve the camera active before the batch begins.
original_path = scene.render.filepath                                                                # Preserve the normal output filepath for restoration after the batch.
print("XYBOTS rendering the current Blender NLA setup without changing any tracks.")

# Render every animation frame from every direction
try:
    for direction in directions:                                                                     # Process each configured compass direction in order.
        camera = bpy.data.objects.get("XYBOTS_CAM_" + direction)                                     # Look up this direction's required camera object.
        if camera is None:                                                                           # Refuse to render if the required camera was not found.
            raise RuntimeError("Missing camera: " + direction)                                       # Stop and identify the missing directional camera.
        scene.camera = camera                                                                        # Make this direction's camera active for Blender's renderer.
        for frame in range(scene.frame_start, scene.frame_end + 1):                                  # Visit every frame, including the configured end frame.
            scene.frame_set(frame)                                                                   # Evaluate animation, constraints, and frame-dependent state.
            scene.render.filepath = os.path.join(output_root, direction, f"{direction}_{frame:03d}.png") # Build the PNG path, such as NE/NE_005.png.
            bpy.ops.render.render(write_still=True)                                                  # Render the active camera and write that still PNG.
finally:
    scene.camera = original_camera                                                                   # Restore the camera that was active before the batch.
    scene.render.filepath = original_path                                                            # Restore the render filepath that was active before the batch.

print("XYBOTS eight-direction render complete:", output_root)                                      # Report successful completion and the output root.
