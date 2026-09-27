"""
Xybots-style cube-grid camera rig and pixel-accurate wireframe renderer.

Tested by syntax only outside Blender. Intended for Blender 4.3+.

USAGE
-----
1. Open Blender's Scripting workspace.
2. Load this file in the Text Editor and press Run Script.
3. Open the 3D View sidebar (N) > Xybots.
4. Set Turn to 0 degrees for the straight one-point view.
5. Click "Render Pixel Wireframe".

The generated image is shown in Blender as "Xybots_Pixel_Wireframe" and is
also saved to the Output Path. This custom renderer uses the actual Blender
camera and lattice geometry, but rasterizes it without antialiasing so every
line and vertex marker is exactly one output pixel.

Animate Camera_Pivot.rotation_euler.z for turns. At intermediate angles the
two horizontal grid directions have separate vanishing points on the horizon;
vertical grid lines remain parallel because the camera has no pitch or roll.
"""

import bpy
import math
import os
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view


# -----------------------------------------------------------------------------
# Art-direction controls
# -----------------------------------------------------------------------------

COLLECTION_NAME = "Xybots_Wireframe_Setup"
LATTICE_NAME = "Cube_Grid_Lattice"
PIVOT_NAME = "Camera_Pivot"
CAMERA_NAME = "Camera_Render"
TOP_CAMERA_NAME = "Camera_TopDown_Reference"
IMAGE_NAME = "Xybots_Pixel_Wireframe"

GRID_CELLS_X = 9
# Eleven rows around the centered camera leave five complete cells visible in
# the forward view, matching the five-cell depth of the reference layout.
GRID_CELLS_Y = 11
CELL_SIZE = 2.0

# The source hallway appears about 1.5 times as wide as it is tall.
# CELL_SIZE / CELL_HEIGHT = 1.5.
CELL_HEIGHT = CELL_SIZE / 1.5

# The source horizon is above vertical center. Camera height controls the
# visible floor/ceiling proportion; lens shift places the horizon on screen.
# One half-cell above the floor: the nearest side-wall/floor edges then project
# at a 1:1 pixel slope (one pixel up for one pixel across) in the straight view.
CAMERA_HEIGHT_FRACTION = 0.75
CAMERA_FORWARD_OFFSET_FRACTION = 0.49  # 0.50 is exactly on the front wall.
# Lift the complete projected composition 18 pixels to match the approved
# Photoshop overlay while retaining the same camera geometry and 1:1 diagonals.
HORIZON_Y_FROM_TOP = 31.5

RENDER_WIDTH = 160
RENDER_HEIGHT = 120
# 1.2× the initial 24 mm calibration.  This keeps the horizon and 1:1 floor
# diagonals fixed while matching the concept's near and far grid-point spread.
CAMERA_LENS_MM = 28.8
CAMERA_SENSOR_WIDTH_MM = 36.0
CAMERA_NEAR_CLIP = 0.02
CAMERA_FAR_CLIP = 100.0

# The authored clockwise North -> East turn.  Each stable camera pose is four
# timeline frames apart, leaving three frames between neighboring key poses.
# Blender's negative Z yaw is clockwise when North is +Y and East is +X.
TURN_KEYFRAMES = (
    (1, 0.0),
    (5, -22.5),
    (9, -45.0),
    (13, -66.5),
    (17, -90.0),
)
TURN_PREVIEW_FRAME = 9  # Northeast: the diagonal key pose.

# Five authored samples: start, three renderable in-between positions, and end.
TRANSITION_SAMPLE_FRAMES = (1, 2, 3, 4, 5)
MOVE_ACTION_SPECS = (
    # name,                 start cell, end cell, facing yaw
    ("Xybots_Move_N_Forward",     (0, 0), (0, 1),   0.0),
    ("Xybots_Move_N_Strafe_E",    (0, 0), (1, 0),   0.0),
    ("Xybots_Move_N_Diagonal_NE", (0, 0), (1, 1),   0.0),
    ("Xybots_Move_NE_Forward",    (0, 0), (1, 1), -45.0),
    ("Xybots_Move_NE_Right_SE",   (0, 0), (1, -1), -45.0),
    ("Xybots_Move_NE_East",       (0, 0), (1, 0), -45.0),
)

# Grayscale depth ramp for the one-pixel lattice lines.
NEAR_LINE_VALUE = 1.0
FAR_LINE_VALUE = 0.07
DEPTH_RAMP_NEAR = 0.10
# Deliberately short ramp: the lattice should collapse into near-black much
# sooner than physical distance shading, matching the arcade reference.
DEPTH_RAMP_FAR = CELL_SIZE * 4.0

RED_PIXEL = (1.0, 0.0, 0.0, 1.0)
BACKGROUND_PIXEL = (0.0, 0.0, 0.0, 1.0)


# -----------------------------------------------------------------------------
# Scene construction
# -----------------------------------------------------------------------------

def _remove_collection(name):
    collection = bpy.data.collections.get(name)
    if collection is None:
        return

    for obj in list(collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(collection)


def _new_collection(scene):
    collection = bpy.data.collections.new(COLLECTION_NAME)
    scene.collection.children.link(collection)
    return collection


def _lattice_mesh_data():
    """Return deduplicated vertices and edges for one layer of cube cells."""
    half_x = GRID_CELLS_X * CELL_SIZE * 0.5
    half_y = GRID_CELLS_Y * CELL_SIZE * 0.5
    x_values = [-half_x + i * CELL_SIZE for i in range(GRID_CELLS_X + 1)]
    y_values = [-half_y + i * CELL_SIZE for i in range(GRID_CELLS_Y + 1)]
    z_values = [0.0, CELL_HEIGHT]

    vertices = []
    vertex_indices = {}
    edges = set()

    def vertex(x, y, z):
        key = (round(x, 7), round(y, 7), round(z, 7))
        if key not in vertex_indices:
            vertex_indices[key] = len(vertices)
            vertices.append((x, y, z))
        return vertex_indices[key]

    def edge(a, b):
        if a != b:
            edges.add(tuple(sorted((a, b))))

    # Floor and ceiling grids.
    for z in z_values:
        for y in y_values:
            for i in range(len(x_values) - 1):
                edge(vertex(x_values[i], y, z), vertex(x_values[i + 1], y, z))
        for x in x_values:
            for i in range(len(y_values) - 1):
                edge(vertex(x, y_values[i], z), vertex(x, y_values[i + 1], z))

    # Vertical edges at every cell intersection.
    for x in x_values:
        for y in y_values:
            edge(vertex(x, y, 0.0), vertex(x, y, CELL_HEIGHT))

    return vertices, sorted(edges)


def _create_lattice(collection):
    vertices, edges = _lattice_mesh_data()
    mesh = bpy.data.meshes.new(f"{LATTICE_NAME}_Mesh")
    mesh.from_pydata(vertices, edges, [])
    mesh.update()

    lattice = bpy.data.objects.new(LATTICE_NAME, mesh)
    collection.objects.link(lattice)
    lattice.display_type = 'WIRE'
    lattice.show_in_front = True
    lattice.color = (0.05, 0.7, 0.9, 1.0)
    lattice["xybots_pixel_lattice"] = True
    return lattice


def _look_straight_down(camera):
    camera.rotation_euler = (0.0, 0.0, 0.0)
    # A Blender camera looks along local -Z; zero rotation therefore looks down.


def _create_cameras(collection, scene):
    camera_height = CELL_HEIGHT * CAMERA_HEIGHT_FRACTION

    pivot = bpy.data.objects.new(PIVOT_NAME, None)
    collection.objects.link(pivot)
    pivot.empty_display_type = 'ARROWS'
    pivot.empty_display_size = CELL_SIZE * 0.22
    pivot.location = (0.0, 0.0, camera_height)
    pivot["description"] = "Rotate local Z to turn; camera orbits from the center-cell pivot."

    camera_data = bpy.data.cameras.new(f"{CAMERA_NAME}_Data")
    camera_data.type = 'PERSP'
    camera_data.lens = CAMERA_LENS_MM
    camera_data.sensor_width = CAMERA_SENSOR_WIDTH_MM
    camera_data.sensor_fit = 'HORIZONTAL'
    camera_data.clip_start = CAMERA_NEAR_CLIP
    camera_data.clip_end = CAMERA_FAR_CLIP

    camera = bpy.data.objects.new(CAMERA_NAME, camera_data)
    collection.objects.link(camera)
    camera.parent = pivot
    # Place the camera at the rear side of its center-cell pivot.  It still
    # looks along local +Y, so every keyed yaw looks through the pivot and out
    # into the corridor rather than away from it.
    camera.location = (0.0, -CELL_SIZE * CAMERA_FORWARD_OFFSET_FRACTION, 0.0)

    # Level camera looking along +Y. No pitch/roll means verticals stay parallel.
    camera.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    scene.camera = camera

    top_data = bpy.data.cameras.new(f"{TOP_CAMERA_NAME}_Data")
    top_data.type = 'ORTHO'
    top_data.ortho_scale = max(GRID_CELLS_X, GRID_CELLS_Y) * CELL_SIZE * 1.12
    top_camera = bpy.data.objects.new(TOP_CAMERA_NAME, top_data)
    collection.objects.link(top_camera)
    top_camera.location = (0.0, 0.0, max(GRID_CELLS_X, GRID_CELLS_Y) * CELL_SIZE)
    _look_straight_down(top_camera)

    return pivot, camera, top_camera


def _world_black(scene):
    world = bpy.data.worlds.get("Xybots_Black_World")
    if world is None:
        world = bpy.data.worlds.new("Xybots_Black_World")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    background.inputs["Strength"].default_value = 0.0
    scene.world = world


def _horizon_y_normalized(scene, camera):
    """Project a point directly ahead at camera height; this is the horizon."""
    bpy.context.view_layer.update()
    forward = camera.matrix_world.to_quaternion() @ Vector((0.0, 0.0, -1.0))
    point = camera.matrix_world.translation + forward * 50.0
    return world_to_camera_view(scene, camera, point).y


def _set_horizon_pixel(scene, camera, pixel_y_from_top):
    """Solve Camera.shift_y so the horizon hits the requested output row."""
    target = 1.0 - (pixel_y_from_top / (RENDER_HEIGHT - 1.0))
    low, high = -1.0, 1.0

    camera.data.shift_y = low
    low_y = _horizon_y_normalized(scene, camera)
    camera.data.shift_y = high
    high_y = _horizon_y_normalized(scene, camera)
    increasing = high_y > low_y

    for _ in range(32):
        middle = (low + high) * 0.5
        camera.data.shift_y = middle
        value = _horizon_y_normalized(scene, camera)
        if (value < target) == increasing:
            low = middle
        else:
            high = middle

    camera.data.shift_y = (low + high) * 0.5


def _action_fcurves(action):
    """Return an Action's F-curves in both Blender 4.x and Blender 5.x."""
    if hasattr(action, "fcurves"):
        return action.fcurves
    return [
        curve
        for layer in action.layers
        for strip in layer.strips
        if hasattr(strip, "channelbags")
        for channel_bag in strip.channelbags
        for curve in channel_bag.fcurves
    ]


def _set_action_linear(action):
    for curve in _action_fcurves(action):
        for keyframe in curve.keyframe_points:
            keyframe.interpolation = 'LINEAR'


def _remove_generated_actions():
    for action in list(bpy.data.actions):
        if action.get("xybots_pixel_generated", False):
            bpy.data.actions.remove(action)


def _finish_generated_action(pivot, action_name):
    action = pivot.animation_data.action if pivot.animation_data else None
    if action is None:
        raise RuntimeError("Could not create the camera animation action.")
    action.name = action_name
    action["xybots_pixel_generated"] = True
    _set_action_linear(action)
    return action


def _author_north_to_east_turn(scene, pivot):
    """Store the authored stable-position North-to-East turn on the timeline.

    The camera remains parented at a fixed radius from the center-cell pivot;
    therefore the keyed pivot yaw creates a true orbit rather than translating
    the camera through the scene.  Linear interpolation makes frames 2–4
    evenly spaced camera poses.
    """
    pivot.animation_data_clear()
    pivot.rotation_mode = 'XYZ'
    center_location = Vector((0.0, 0.0, pivot.location.z))
    scene.frame_start = TURN_KEYFRAMES[0][0]
    scene.frame_end = TURN_KEYFRAMES[-1][0]

    for frame, yaw_degrees in TURN_KEYFRAMES:
        scene.frame_set(frame)
        pivot.location = center_location
        pivot.rotation_euler.z = math.radians(yaw_degrees)
        pivot.keyframe_insert(data_path="location", frame=frame)
        pivot.keyframe_insert(data_path="rotation_euler", index=2, frame=frame)

    action = _finish_generated_action(pivot, "Xybots_Turn_N_to_E")

    # The diagnostic render is intentionally the requested Northeast key pose.
    scene.frame_set(TURN_PREVIEW_FRAME)
    return action


def _author_translation_action(scene, pivot, action_name, start_cell, end_cell, yaw_degrees):
    """Create one cell-to-cell transition with three explicit middle samples."""
    pivot.animation_data_clear()
    pivot.rotation_mode = 'XYZ'
    pivot_height = pivot.location.z
    start = Vector((start_cell[0] * CELL_SIZE, start_cell[1] * CELL_SIZE, pivot_height))
    end = Vector((end_cell[0] * CELL_SIZE, end_cell[1] * CELL_SIZE, pivot_height))

    for sample_index, frame in enumerate(TRANSITION_SAMPLE_FRAMES):
        progress = sample_index / float(len(TRANSITION_SAMPLE_FRAMES) - 1)
        scene.frame_set(frame)
        pivot.location = start.lerp(end, progress)
        pivot.rotation_euler.z = math.radians(yaw_degrees)
        pivot.keyframe_insert(data_path="location", frame=frame)
        pivot.keyframe_insert(data_path="rotation_euler", index=2, frame=frame)

    return _finish_generated_action(pivot, action_name)


def _author_translation_actions(scene, pivot):
    actions = {}
    for action_name, start_cell, end_cell, yaw_degrees in MOVE_ACTION_SPECS:
        actions[action_name] = _author_translation_action(
            scene, pivot, action_name, start_cell, end_cell, yaw_degrees
        )
    return actions


def _activate_action(scene, pivot, action, frame):
    pivot.animation_data_create()
    pivot.animation_data.action = action
    scene.frame_set(frame)


def build_scene():
    scene = bpy.context.scene
    _remove_collection(COLLECTION_NAME)
    _remove_generated_actions()
    collection = _new_collection(scene)
    _create_lattice(collection)
    pivot, camera, _top_camera = _create_cameras(collection, scene)

    scene.render.resolution_x = RENDER_WIDTH
    scene.render.resolution_y = RENDER_HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.pixel_aspect_x = 1.0
    scene.render.pixel_aspect_y = 1.0
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    _world_black(scene)

    # Neutral color handling for deliberately chosen pixel values.
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0

    _set_horizon_pixel(scene, camera, HORIZON_Y_FROM_TOP)
    scene.xybots_turn_degrees = 0.0
    turn_action = _author_north_to_east_turn(scene, pivot)
    movement_actions = _author_translation_actions(scene, pivot)
    _activate_action(scene, pivot, turn_action, TURN_PREVIEW_FRAME)
    scene["xybots_movement_actions"] = list(movement_actions.keys())
    scene.xybots_turn_degrees = TURN_KEYFRAMES[2][1]
    bpy.context.view_layer.objects.active = camera
    camera.select_set(True)
    return camera


# -----------------------------------------------------------------------------
# Exact one-pixel projection renderer
# -----------------------------------------------------------------------------

def _camera_depth(camera, world_point):
    camera_point = camera.matrix_world.inverted() @ world_point
    return -camera_point.z


def _clip_segment_to_camera_depth(camera, p0, p1):
    d0 = _camera_depth(camera, p0)
    d1 = _camera_depth(camera, p1)
    near = camera.data.clip_start
    far = camera.data.clip_end

    if (d0 < near and d1 < near) or (d0 > far and d1 > far):
        return None

    q0, q1 = p0.copy(), p1.copy()

    # Clip parametrically in camera-depth space. Depth varies linearly along a
    # world-space segment for a fixed camera transform.
    if d0 < near or d0 > far:
        target = near if d0 < near else far
        if abs(d1 - d0) < 1e-10:
            return None
        t = (target - d0) / (d1 - d0)
        q0 = p0.lerp(p1, t)
        d0 = target

    if d1 < near or d1 > far:
        target = near if d1 < near else far
        original_d0 = _camera_depth(camera, p0)
        original_d1 = _camera_depth(camera, p1)
        if abs(original_d1 - original_d0) < 1e-10:
            return None
        t = (target - original_d0) / (original_d1 - original_d0)
        q1 = p0.lerp(p1, t)
        d1 = target

    return q0, q1, d0, d1


def _project(scene, camera, point):
    co = world_to_camera_view(scene, camera, point)
    return co.x * (RENDER_WIDTH - 1), co.y * (RENDER_HEIGHT - 1)


def _depth_value(depth):
    denominator = max(1e-8, DEPTH_RAMP_FAR - DEPTH_RAMP_NEAR)
    t = max(0.0, min(1.0, (depth - DEPTH_RAMP_NEAR) / denominator))
    # Smoothstep prevents most of the useful near range from bunching together.
    t = t * t * (3.0 - 2.0 * t)
    return NEAR_LINE_VALUE + (FAR_LINE_VALUE - NEAR_LINE_VALUE) * t


def _clip_segment_to_screen(x0, y0, d0, x1, y1, d1):
    """Liang-Barsky clip, retaining perspective-correct endpoint depths."""
    dx = x1 - x0
    dy = y1 - y0
    t_min = 0.0
    t_max = 1.0

    boundaries = (
        (-dx, x0),
        (dx, (RENDER_WIDTH - 1) - x0),
        (-dy, y0),
        (dy, (RENDER_HEIGHT - 1) - y0),
    )
    for p, q in boundaries:
        if abs(p) < 1e-12:
            if q < 0.0:
                return None
            continue
        t = q / p
        if p < 0.0:
            if t > t_max:
                return None
            t_min = max(t_min, t)
        else:
            if t < t_min:
                return None
            t_max = min(t_max, t)

    def depth_at(t):
        inverse = ((1.0 - t) / max(d0, 1e-8)) + (t / max(d1, 1e-8))
        return 1.0 / max(inverse, 1e-8)

    return (
        x0 + dx * t_min,
        y0 + dy * t_min,
        depth_at(t_min),
        x0 + dx * t_max,
        y0 + dy * t_max,
        depth_at(t_max),
    )


def _draw_segment(pixels, zbuffer, x0, y0, d0, x1, y1, d1):
    dx = x1 - x0
    dy = y1 - y0
    steps = max(1, int(math.ceil(max(abs(dx), abs(dy)))))

    for step in range(steps + 1):
        t = step / steps
        x = int(round(x0 + dx * t))
        y = int(round(y0 + dy * t))
        if not (0 <= x < RENDER_WIDTH and 0 <= y < RENDER_HEIGHT):
            continue

        # Perspective-correct interpolation of camera depth.
        inverse_depth = ((1.0 - t) / max(d0, 1e-8)) + (t / max(d1, 1e-8))
        depth = 1.0 / max(inverse_depth, 1e-8)
        index = y * RENDER_WIDTH + x
        if depth <= zbuffer[index]:
            zbuffer[index] = depth
            value = _depth_value(depth)
            pixels[index] = (value, value, value, 1.0)


def _lattice_object():
    for obj in bpy.context.scene.objects:
        if obj.get("xybots_pixel_lattice"):
            return obj
    return None


def render_pixel_wireframe(context=None):
    context = context or bpy.context
    scene = context.scene
    camera = scene.camera
    lattice = _lattice_object()
    if camera is None or lattice is None:
        raise RuntimeError("Run 'Build / Reset Scene' before rendering.")

    context.view_layer.update()
    pixel_count = RENDER_WIDTH * RENDER_HEIGHT
    pixels = [BACKGROUND_PIXEL for _ in range(pixel_count)]
    zbuffer = [float('inf')] * pixel_count

    world_vertices = [lattice.matrix_world @ vertex.co for vertex in lattice.data.vertices]

    # White-to-gray, depth-mapped, exact one-pixel edges.
    for edge in lattice.data.edges:
        p0 = world_vertices[edge.vertices[0]]
        p1 = world_vertices[edge.vertices[1]]
        clipped = _clip_segment_to_camera_depth(camera, p0, p1)
        if clipped is None:
            continue
        q0, q1, d0, d1 = clipped
        x0, y0 = _project(scene, camera, q0)
        x1, y1 = _project(scene, camera, q1)

        screen_segment = _clip_segment_to_screen(x0, y0, d0, x1, y1, d1)
        if screen_segment is None:
            continue
        _draw_segment(pixels, zbuffer, *screen_segment)

    # One red pixel at each projected grid intersection. A vertex is drawn only
    # when it is at least as close as the edge already occupying that pixel.
    for point in world_vertices:
        depth = _camera_depth(camera, point)
        if not (camera.data.clip_start <= depth <= camera.data.clip_end):
            continue
        x_float, y_float = _project(scene, camera, point)
        x = int(round(x_float))
        y = int(round(y_float))
        if not (0 <= x < RENDER_WIDTH and 0 <= y < RENDER_HEIGHT):
            continue
        index = y * RENDER_WIDTH + x
        tolerance = max(0.002, depth * 0.002)
        if depth <= zbuffer[index] + tolerance:
            pixels[index] = RED_PIXEL
            zbuffer[index] = min(zbuffer[index], depth)

    image = bpy.data.images.get(IMAGE_NAME)
    if image is not None and tuple(image.size) != (RENDER_WIDTH, RENDER_HEIGHT):
        bpy.data.images.remove(image)
        image = None
    if image is None:
        image = bpy.data.images.new(IMAGE_NAME, RENDER_WIDTH, RENDER_HEIGHT, alpha=True)

    flat_pixels = [channel for pixel in pixels for channel in pixel]
    image.pixels.foreach_set(flat_pixels)
    image.update()

    output_path = bpy.path.abspath(scene.xybots_output_path)
    output_directory = os.path.dirname(output_path)
    if output_directory:
        os.makedirs(output_directory, exist_ok=True)
    image.filepath_raw = output_path
    image.file_format = 'PNG'
    image.save()

    # Show the result automatically if an Image Editor is already open.
    for area in context.screen.areas if context.screen else []:
        if area.type == 'IMAGE_EDITOR':
            area.spaces.active.image = image

    return image, output_path


# -----------------------------------------------------------------------------
# Blender UI
# -----------------------------------------------------------------------------

def _update_turn(scene, _context):
    pivot = bpy.data.objects.get(PIVOT_NAME)
    if pivot is not None:
        pivot.rotation_euler.z = math.radians(scene.xybots_turn_degrees)


class XYBOTS_OT_build_scene(bpy.types.Operator):
    bl_idname = "xybots.build_scene"
    bl_label = "Build / Reset Scene"
    bl_description = "Rebuild the cube lattice and camera rig"
    bl_options = {'REGISTER', 'UNDO'}

    def execute(self, context):
        build_scene()
        self.report({'INFO'}, "Xybots wireframe scene rebuilt")
        return {'FINISHED'}


class XYBOTS_OT_render_pixel_wireframe(bpy.types.Operator):
    bl_idname = "xybots.render_pixel_wireframe"
    bl_label = "Render Pixel Wireframe"
    bl_description = "Render exact one-pixel depth lines and red grid intersections"

    def execute(self, context):
        try:
            _image, path = render_pixel_wireframe(context)
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}
        self.report({'INFO'}, f"Saved pixel wireframe: {path}")
        return {'FINISHED'}


class XYBOTS_PT_panel(bpy.types.Panel):
    bl_label = "Xybots Pixel Camera"
    bl_idname = "XYBOTS_PT_pixel_camera"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Xybots"

    def draw(self, context):
        layout = self.layout
        scene = context.scene
        layout.operator("xybots.build_scene", icon='FILE_REFRESH')
        layout.prop(scene, "xybots_turn_degrees")

        camera = bpy.data.objects.get(CAMERA_NAME)
        if camera is not None:
            layout.prop(camera.data, "lens")
            layout.label(text=f"Horizon: row {HORIZON_Y_FROM_TOP:g}")

        layout.prop(scene, "xybots_output_path")
        layout.operator("xybots.render_pixel_wireframe", icon='RENDER_STILL')
        layout.separator()
        layout.label(text="0° = one-point perspective")
        layout.label(text="Turn = two horizontal VPs")


CLASSES = (
    XYBOTS_OT_build_scene,
    XYBOTS_OT_render_pixel_wireframe,
    XYBOTS_PT_panel,
)


def register():
    for cls in CLASSES:
        try:
            bpy.utils.unregister_class(cls)
        except RuntimeError:
            pass
        bpy.utils.register_class(cls)

    if not hasattr(bpy.types.Scene, "xybots_turn_degrees"):
        bpy.types.Scene.xybots_turn_degrees = bpy.props.FloatProperty(
            name="Turn (degrees)",
            description="Yaw around the center-cell pivot",
            default=0.0,
            min=-180.0,
            max=180.0,
            update=_update_turn,
        )

    if not hasattr(bpy.types.Scene, "xybots_output_path"):
        bpy.types.Scene.xybots_output_path = bpy.props.StringProperty(
            name="Output Path",
            subtype='FILE_PATH',
            default="//xybots_pixel_wireframe.png",
        )


def unregister():
    for cls in reversed(CLASSES):
        try:
            bpy.utils.unregister_class(cls)
        except RuntimeError:
            pass
    if hasattr(bpy.types.Scene, "xybots_turn_degrees"):
        del bpy.types.Scene.xybots_turn_degrees
    if hasattr(bpy.types.Scene, "xybots_output_path"):
        del bpy.types.Scene.xybots_output_path


if __name__ == "__main__":
    register()
    build_scene()
    render_pixel_wireframe()
