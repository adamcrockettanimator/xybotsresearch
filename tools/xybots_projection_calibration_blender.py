"""Build the non-destructive Xybots projection/greybox calibration scene.

Run in the open Blender instance from the Scripting workspace, or through the
Codex Blender connection. The source contract is shared with Godot at
assets/Calibration/xybots_projection_contract.json.
"""

import bpy
import json
import math
import os
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
CONTRACT_PATH = os.path.join(PROJECT_DIR, "assets", "Calibration", "xybots_projection_contract.json")
GRID_TEXTURE_PATH = os.path.join(PROJECT_DIR, "assets", "Calibration", "xybots_greybox_grid.png")
CAPTURE_DIRECTORY = os.path.join(PROJECT_DIR, "assets", "Calibration", "captures")
PRIMITIVE_PLATE_DIRECTORY = os.path.join(PROJECT_DIR, "assets", "Calibration", "primitive_plates")
PRIMITIVE_SPRITE_SOURCE_DIRECTORY = os.path.join(PROJECT_DIR, "assets", "Calibration", "primitive_sprite_sources")
SCENE_NAME = "Xybots_Projection_Calibration"
COLLECTION_NAME = "Xybots_Greybox_Assets"
CAMERA_NAME = "Xybots_Calibration_Camera"


def contract():
    with open(CONTRACT_PATH, "r", encoding="utf-8") as handle:
        return json.load(handle)


def srgb_to_linear(value):
    """Convert the contract's display-space greys to Blender shader values."""
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def write_shared_grid_texture(contract_data):
    """Write the same neutral grid swatch Godot can import as a Texture2D."""
    width = height = 256
    image = bpy.data.images.get("Xybots_Greybox_Grid_Texture")
    if image is None or image.size[:] != (width, height):
        if image is not None:
            bpy.data.images.remove(image)
        image = bpy.data.images.new("Xybots_Greybox_Grid_Texture", width, height, alpha=True)
    base = float(contract_data["greybox_grid"]["base_gray_srgb"])
    minor = float(contract_data["greybox_grid"]["minor_line_srgb"])
    major = float(contract_data["greybox_grid"]["major_line_srgb"])
    pixels = []
    for y in range(height):
        for x in range(width):
            minor_line = x % 32 < 3 or y % 32 < 3
            major_line = x % 128 < 5 or y % 128 < 5
            value = major if major_line else (minor if minor_line else base)
            pixels.extend((value, value, value, 1.0))
    image.pixels.foreach_set(pixels)
    image.filepath_raw = GRID_TEXTURE_PATH
    image.file_format = 'PNG'
    image.save()
    return image


def ensure_scene():
    scene = bpy.data.scenes.get(SCENE_NAME)
    if scene is None:
        scene = bpy.data.scenes.new(SCENE_NAME)
    return scene


def clear_owned_collection(scene):
    collection = bpy.data.collections.get(COLLECTION_NAME)
    if collection is None:
        collection = bpy.data.collections.new(COLLECTION_NAME)
    if collection.name not in {child.name for child in scene.collection.children}:
        scene.collection.children.link(collection)
    for obj in list(collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    return collection


def grid_anchor(collection):
    anchor = bpy.data.objects.new("Xybots_Grid_Origin", None)
    collection.objects.link(anchor)
    anchor.empty_display_type = 'PLAIN_AXES'
    anchor.empty_display_size = 0.25
    anchor["xybots_role"] = "shared_grid_origin"
    return anchor


def material_grid(contract_data, _anchor, flat_geometry=False, normal_tinted=False, use_grid=True):
    """Build the calibration grid material.

    ``normal_tinted`` is deliberately an unlit, authored-value pass: face-up
    surfaces are bright, vertical surfaces are middle grey, and down-facing
    surfaces are dark.  It is the colour input to the pixel-edge compositor,
    not a replacement for its normal/depth masks.
    """
    material_name = "Xybots_Greybox_Normal_Tint" if normal_tinted and not use_grid else ("Xybots_Greybox_Normal_Tint_Grid" if normal_tinted else ("Xybots_Greybox_Flat_Grid" if flat_geometry else "Xybots_Greybox_Grid"))
    material = bpy.data.materials.get(material_name)
    if material is None:
        material = bpy.data.materials.new(material_name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeEmission") if flat_geometry else nodes.new("ShaderNodeBsdfPrincipled")
    geometry = nodes.new("ShaderNodeNewGeometry")
    position = nodes.new("ShaderNodeSeparateXYZ")
    normal = nodes.new("ShaderNodeVectorMath")
    normal.operation = 'ABSOLUTE'
    normal_separate = nodes.new("ShaderNodeSeparateXYZ")
    base = nodes.new("ShaderNodeRGB")
    minor_mix = nodes.new("ShaderNodeMath")
    major_mix = nodes.new("ShaderNodeMath")
    apply_minor = nodes.new("ShaderNodeMixRGB")
    apply_major = nodes.new("ShaderNodeMixRGB")
    base_value = srgb_to_linear(0.5) if flat_geometry else 0.5
    base.outputs[0].default_value = (base_value, base_value, base_value, 1.0)
    base_color = base.outputs[0]
    if normal_tinted:
        # Geometric Z-normal encodes the artist-facing orientation rule.  This
        # is colour, not illumination: it survives an unlit render exactly.
        normal_z_range = nodes.new("ShaderNodeMapRange")
        normal_z_range.clamp = True
        normal_z_range.inputs['From Min'].default_value = -1.0
        normal_z_range.inputs['From Max'].default_value = 1.0
        normal_tint = nodes.new("ShaderNodeValToRGB")
        normal_tint_separate = nodes.new("ShaderNodeSeparateXYZ")
        normal_tint.color_ramp.interpolation = 'LINEAR'
        normal_tint.color_ramp.elements.remove(normal_tint.color_ramp.elements[1])
        down = normal_tint.color_ramp.elements[0]
        down.position = 0.0
        down.color = (srgb_to_linear(0.20),) * 3 + (1.0,)
        side = normal_tint.color_ramp.elements.new(0.5)
        side.color = (srgb_to_linear(0.50),) * 3 + (1.0,)
        up = normal_tint.color_ramp.elements.new(1.0)
        up.color = (srgb_to_linear(0.82),) * 3 + (1.0,)
        links.new(geometry.outputs['Normal'], normal_tint_separate.inputs['Vector'])
        links.new(normal_tint_separate.outputs['Z'], normal_z_range.inputs['Value'])
        links.new(normal_z_range.outputs['Result'], normal_tint.inputs['Fac'])
        base_color = normal_tint.outputs['Color']
    for color_node, color in ((minor_mix, (0.0, 0.0, 0.0, 1.0)), (major_mix, (0.0, 0.0, 0.0, 1.0))):
        color_node.operation = 'MAXIMUM'
        color_node.inputs[0].default_value = 0.0
    links.new(geometry.outputs['Position'], position.inputs['Vector'])
    links.new(geometry.outputs['Normal'], normal.inputs[0])
    links.new(normal.outputs[0], normal_separate.inputs['Vector'])
    # Derive both grid frequencies from the shared contract.  The grid remains
    # useful for room/projection calibration, but final greybox props can opt
    # out and show only their normal-driven lighting plus edge treatment.
    def line_mask(axis_socket, frequency, threshold):
        multiply = nodes.new("ShaderNodeMath")
        fraction = nodes.new("ShaderNodeMath")
        line = nodes.new("ShaderNodeMath")
        multiply.operation = 'MULTIPLY'
        multiply.inputs[1].default_value = frequency
        fraction.operation = 'FRACT'
        line.operation = 'LESS_THAN'
        line.inputs[1].default_value = threshold
        links.new(axis_socket, multiply.inputs[0])
        links.new(multiply.outputs[0], fraction.inputs[0])
        links.new(fraction.outputs[0], line.inputs[0])
        return line.outputs[0]

    def maximum(first, second):
        combine = nodes.new("ShaderNodeMath")
        combine.operation = 'MAXIMUM'
        links.new(first, combine.inputs[0])
        links.new(second, combine.inputs[1])
        return combine.outputs[0]

    def multiply(first, second):
        combine = nodes.new("ShaderNodeMath")
        combine.operation = 'MULTIPLY'
        links.new(first, combine.inputs[0])
        links.new(second, combine.inputs[1])
        return combine.outputs[0]

    def visible_grid(frequency, threshold):
        line_x = line_mask(position.outputs['X'], frequency, threshold)
        line_y = line_mask(position.outputs['Y'], frequency, threshold)
        line_z = line_mask(position.outputs['Z'], frequency, threshold)
        # A grid uses only the two axes lying in the face.  The previous
        # version included the face-normal axis; on a floor Z is constant,
        # making every pixel read as a line and erasing the grid.
        xy = multiply(maximum(line_x, line_y), normal_separate.outputs['Z'])
        xz = multiply(maximum(line_x, line_z), normal_separate.outputs['Y'])
        yz = multiply(maximum(line_y, line_z), normal_separate.outputs['X'])
        return maximum(maximum(xy, xz), yz)

    blender_units_per_godot = float(contract_data["blender"]["ground_units_per_godot_cell"])
    minor_interval = float(contract_data["greybox_grid"]["minor_interval_godot_units"])
    major_interval = float(contract_data["greybox_grid"]["major_interval_godot_units"])
    # Keep the grid's world frequency shared by floor, walls and props, while
    # making the actual strokes considerably thinner/less stark.  The dense
    # minor grid is an alignment aid, not another set of exterior outlines.
    minor_mix = visible_grid(1.0 / (minor_interval * blender_units_per_godot), 0.08)
    major_mix = visible_grid(1.0 / (major_interval * blender_units_per_godot), 0.02)
    dark = nodes.new("ShaderNodeRGB")
    light = nodes.new("ShaderNodeRGB")
    minor = float(contract_data["greybox_grid"]["minor_line_srgb"])
    major = float(contract_data["greybox_grid"]["major_line_srgb"])
    if flat_geometry:
        minor = srgb_to_linear(minor)
        major = srgb_to_linear(major)
    dark.outputs[0].default_value = (minor,) * 3 + (1.0,)
    light.outputs[0].default_value = (major,) * 3 + (1.0,)
    if use_grid:
        links.new(minor_mix, apply_minor.inputs[0])
        links.new(base_color, apply_minor.inputs[1])
        links.new(dark.outputs[0], apply_minor.inputs[2])
        links.new(major_mix, apply_major.inputs[0])
        links.new(apply_minor.outputs[0], apply_major.inputs[1])
        links.new(light.outputs[0], apply_major.inputs[2])
        surface_color = apply_major.outputs[0]
    else:
        surface_color = base_color
    if flat_geometry:
        # Emission deliberately ignores the key light, shadows, and material
        # response. This is the Blender half of the projection-only pass.
        shader.inputs['Strength'].default_value = 1.0
        links.new(surface_color, shader.inputs['Color'])
        links.new(shader.outputs['Emission'], output.inputs['Surface'])
    else:
        links.new(surface_color, shader.inputs['Base Color'])
        links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    material.diffuse_color = (0.5, 0.5, 0.5, 1.0)
    return material


def material_flat_z_palette(name, palette_srgb):
    """Create the barrel's unlit, three-value orientation shader.

    This intentionally never samples the purchased asset's albedo, normals, or
    lighting.  It is the first semantic interpretation of that source mesh:
    face-up wood gets the light value, vertical staves get the middle value,
    and downward faces get the dark value.  The close LOD can then add the
    separate normal/depth compositor treatment without baking either effect.
    """
    material = bpy.data.materials.get(name)
    if material is None:
        material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    geometry = nodes.new("ShaderNodeNewGeometry")
    separate_normal = nodes.new("ShaderNodeSeparateXYZ")
    remap_z = nodes.new("ShaderNodeMapRange")
    remap_z.clamp = True
    remap_z.inputs['From Min'].default_value = -1.0
    remap_z.inputs['From Max'].default_value = 1.0
    values = nodes.new("ShaderNodeValToRGB")
    values.color_ramp.interpolation = 'CONSTANT'
    values.color_ramp.elements.remove(values.color_ramp.elements[1])
    for element, key, position in (
        (values.color_ramp.elements[0], "down", 0.0),
        (values.color_ramp.elements.new(0.5), "side", 0.5),
        (values.color_ramp.elements.new(1.0), "up", 1.0),
    ):
        color = palette_srgb[key]
        element.position = position
        element.color = tuple(srgb_to_linear(float(component)) for component in color) + (1.0,)
    links.new(geometry.outputs['Normal'], separate_normal.inputs['Vector'])
    links.new(separate_normal.outputs['Z'], remap_z.inputs['Value'])
    links.new(remap_z.outputs['Result'], values.inputs['Fac'])
    links.new(values.outputs['Color'], emission.inputs['Color'])
    emission.inputs['Strength'].default_value = 1.0
    links.new(emission.outputs['Emission'], output.inputs['Surface'])
    material.diffuse_color = tuple(srgb_to_linear(float(component)) for component in palette_srgb["side"]) + (1.0,)
    return material


def install_pixel_edge_compositor(scene, camera):
    """Install the established Normal/Position/Depth/Alpha pixel treatment.

    This is the calibration-scene counterpart of Blender's existing
    ``Pixel Edge Highlight - Eevee`` compositor.  It samples the four direct
    output-pixel neighbours, so the result remains one source pixel wide at
    the four-times source resolution used for portable prop sprites.
    """
    layer = scene.view_layers[0]
    layer.use_pass_normal = True
    layer.use_pass_z = True
    layer.use_pass_position = True

    def make_socket(group, name, direction, socket_type, default=None):
        sock = group.interface.new_socket(name=name, in_out=direction, socket_type=socket_type)
        if default is not None:
            sock.default_value = default
        return sock

    def make_node(group, node_type, label, x, y):
        created = group.nodes.new(node_type)
        created.label = label
        created.location = (x, y)
        return created

    def wire(group, first, second):
        group.links.new(first, second)

    def math_node(group, operation, first, second=None, label='', x=0, y=0):
        created = make_node(group, 'ShaderNodeMath', label or operation, x, y)
        created.operation = operation
        for index, value in enumerate((first, second)):
            if value is not None:
                if hasattr(value, 'node'):
                    wire(group, value, created.inputs[index])
                else:
                    created.inputs[index].default_value = value
        return created.outputs[0]

    def vector_node(group, operation, first, second=None, label='', x=0, y=0):
        created = make_node(group, 'ShaderNodeVectorMath', label or operation, x, y)
        created.operation = operation
        for index, value in enumerate((first, second)):
            if value is not None:
                if hasattr(value, 'node'):
                    wire(group, value, created.inputs[index])
                else:
                    created.inputs[index].default_value = value
        return created.outputs['Value'] if operation in {'DOT_PRODUCT', 'LENGTH', 'DISTANCE'} else created.outputs['Vector']

    def translated(group, source, x, y, label, row):
        created = make_node(group, 'CompositorNodeTranslate', label, 0, row)
        wire(group, source, created.inputs['Image'])
        wire(group, x, created.inputs['X'])
        wire(group, y, created.inputs['Y'])
        return created.outputs['Image']

    for name in ('Xybots Pixel Edges - Neighbour', 'Xybots Pixel Edge Composite'):
        old = bpy.data.node_groups.get(name)
        if old is not None:
            bpy.data.node_groups.remove(old)

    neighbour = bpy.data.node_groups.new('Xybots Pixel Edges - Neighbour', 'CompositorNodeTree')
    for name, socket_type, default in (
        ('Normal', 'NodeSocketVector', None), ('Position', 'NodeSocketVector', None), ('Depth', 'NodeSocketFloat', None),
        ('Alpha', 'NodeSocketFloat', None), ('X', 'NodeSocketFloat', 0.0), ('Y', 'NodeSocketFloat', 0.0),
        ('Normal Threshold', 'NodeSocketFloat', 0.08), ('Curvature Threshold', 'NodeSocketFloat', 0.012),
        ('Depth Threshold', 'NodeSocketFloat', 0.12), ('Normal Bias', 'NodeSocketVector', (1.0, 1.0, 1.0)),
        ('Camera X', 'NodeSocketVector', (1.0, 0.0, 0.0)), ('Camera Y', 'NodeSocketVector', (0.0, 1.0, 0.0)),
        ('Camera Z', 'NodeSocketVector', (0.0, 0.0, 1.0)),
    ):
        make_socket(neighbour, name, 'INPUT', socket_type, default)
    for name in ('Convex', 'Concave', 'Depth Edge', 'Silhouette'):
        make_socket(neighbour, name, 'OUTPUT', 'NodeSocketFloat')
    ni = make_node(neighbour, 'NodeGroupInput', 'Inputs', -1400, 0)
    no = make_node(neighbour, 'NodeGroupOutput', 'Masks', 1800, 0)
    a = ni.outputs
    translated_normal = translated(neighbour, a['Normal'], a['X'], a['Y'], 'Neighbour normal', 600)
    translated_position = translated(neighbour, a['Position'], a['X'], a['Y'], 'Neighbour position', 300)
    translated_depth = translated(neighbour, a['Depth'], a['X'], a['Y'], 'Neighbour depth', 0)
    translated_alpha = translated(neighbour, a['Alpha'], a['X'], a['Y'], 'Neighbour coverage', -300)
    center = math_node(neighbour, 'GREATER_THAN', a['Alpha'], 0.5, 'Surface pixel')
    adjacent = math_node(neighbour, 'GREATER_THAN', translated_alpha, 0.5, 'Neighbour surface')
    silhouette = math_node(neighbour, 'MULTIPLY', center, math_node(neighbour, 'SUBTRACT', 1.0, adjacent), 'Inner silhouette')
    normal = vector_node(neighbour, 'NORMALIZE', a['Normal'], label='Center normal')
    adjacent_normal = vector_node(neighbour, 'NORMALIZE', translated_normal, label='Neighbour normal')
    normal_change = math_node(neighbour, 'SUBTRACT', 1.0, vector_node(neighbour, 'DOT_PRODUCT', normal, adjacent_normal), 'Normal change')
    normal_gate = math_node(neighbour, 'GREATER_THAN', normal_change, a['Normal Threshold'], 'Normal threshold')
    difference = vector_node(neighbour, 'SUBTRACT', normal, adjacent_normal, 'Normal difference')
    components = []
    for axis_name in ('Camera X', 'Camera Y', 'Camera Z'):
        components.append(vector_node(neighbour, 'DOT_PRODUCT', difference, vector_node(neighbour, 'NORMALIZE', a[axis_name]), 'Camera-basis difference'))
    camera_difference = make_node(neighbour, 'ShaderNodeCombineXYZ', 'Camera-space normal difference', 0, 0)
    for index, value in enumerate(components):
        wire(neighbour, value, camera_difference.inputs[index])
    bias_gate = math_node(neighbour, 'GREATER_THAN', vector_node(neighbour, 'DOT_PRODUCT', camera_difference.outputs[0], a['Normal Bias']), 0.0001, 'Biased side')
    delta = vector_node(neighbour, 'SUBTRACT', translated_position, a['Position'], 'Neighbour position delta')
    bend = vector_node(neighbour, 'DOT_PRODUCT', vector_node(neighbour, 'NORMALIZE', delta), normal, 'Signed bend')
    convex = math_node(neighbour, 'LESS_THAN', bend, math_node(neighbour, 'MULTIPLY', a['Curvature Threshold'], -1.0), 'Convex')
    concave = math_node(neighbour, 'GREATER_THAN', bend, a['Curvature Threshold'], 'Concave')
    normal_edge_gate = math_node(neighbour, 'MULTIPLY', math_node(neighbour, 'MULTIPLY', normal_gate, bias_gate), math_node(neighbour, 'MULTIPLY', center, adjacent), 'Normal edge gate')
    convex = math_node(neighbour, 'MULTIPLY', convex, normal_edge_gate, 'Convex mask')
    concave = math_node(neighbour, 'MULTIPLY', concave, normal_edge_gate, 'Concave mask')
    behind = math_node(neighbour, 'GREATER_THAN', math_node(neighbour, 'SUBTRACT', translated_depth, a['Depth']), a['Depth Threshold'], 'Behind center')
    plane_distance = math_node(neighbour, 'ABSOLUTE', vector_node(neighbour, 'DOT_PRODUCT', delta, normal), label='Plane distance')
    depth_edge = math_node(neighbour, 'MULTIPLY', math_node(neighbour, 'MULTIPLY', behind, math_node(neighbour, 'GREATER_THAN', plane_distance, a['Depth Threshold'])), math_node(neighbour, 'MULTIPLY', center, adjacent), 'Depth edge mask')
    for name, value in (('Convex', convex), ('Concave', concave), ('Depth Edge', depth_edge), ('Silhouette', silhouette)):
        wire(neighbour, value, no.inputs[name])

    edges = bpy.data.node_groups.new('Xybots Pixel Edge Composite', 'CompositorNodeTree')
    for name, socket_type, default in (
        ('Image', 'NodeSocketColor', (0.0, 0.0, 0.0, 0.0)), ('Normal', 'NodeSocketVector', (0.0, 0.0, 0.0)),
        ('Position', 'NodeSocketVector', (0.0, 0.0, 0.0)), ('Depth', 'NodeSocketFloat', 0.0), ('Alpha', 'NodeSocketFloat', 0.0),
        ('Highlights', 'NodeSocketFloat', 1.0), ('Highlight Strength', 'NodeSocketFloat', 0.35), ('Highlight Tint', 'NodeSocketColor', (1.0, 1.0, 1.0, 1.0)),
        ('Shadows', 'NodeSocketFloat', 1.0), ('Shadow Strength', 'NodeSocketFloat', 0.45), ('Shadow Tint', 'NodeSocketColor', (1.0, 1.0, 1.0, 1.0)),
        ('Outline', 'NodeSocketFloat', 0.0), ('Outline Color', 'NodeSocketColor', (0.015, 0.015, 0.015, 1.0)),
        ('Normal Threshold', 'NodeSocketFloat', 0.08), ('Curvature Threshold', 'NodeSocketFloat', 0.012),
        ('Depth Threshold', 'NodeSocketFloat', 0.12), ('Normal Bias', 'NodeSocketVector', (1.0, 1.0, 1.0)),
        ('Camera X', 'NodeSocketVector', (1.0, 0.0, 0.0)), ('Camera Y', 'NodeSocketVector', (0.0, 1.0, 0.0)),
        ('Camera Z', 'NodeSocketVector', (0.0, 0.0, 1.0)),
    ):
        make_socket(edges, name, 'INPUT', socket_type, default)
    for name, socket_type in (('Image', 'NodeSocketColor'), ('Highlight Mask', 'NodeSocketFloat'), ('Shadow Mask', 'NodeSocketFloat'), ('Outline Mask', 'NodeSocketFloat')):
        make_socket(edges, name, 'OUTPUT', socket_type)
    ei = make_node(edges, 'NodeGroupInput', 'Controls and render passes', -1000, 0)
    eo = make_node(edges, 'NodeGroupOutput', 'Image and masks', 1500, 0)
    ea = ei.outputs
    neighbours = []
    for index, (x, y) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))):
        item = make_node(edges, 'CompositorNodeGroup', 'Neighbour (%+d, %+d)' % (x, y), -650, 600 - index * 310)
        item.node_tree = neighbour
        for name in ('Normal', 'Position', 'Depth', 'Alpha', 'Normal Threshold', 'Curvature Threshold', 'Depth Threshold', 'Normal Bias', 'Camera X', 'Camera Y', 'Camera Z'):
            wire(edges, ea[name], item.inputs[name])
        item.inputs['X'].default_value = x
        item.inputs['Y'].default_value = y
        neighbours.append(item)
    def union(mask_name):
        value = neighbours[0].outputs[mask_name]
        for item in neighbours[1:]:
            value = math_node(edges, 'MAXIMUM', value, item.outputs[mask_name], mask_name + ' union')
        return value
    outer = union('Silhouette')
    shadow_raw = math_node(edges, 'MAXIMUM', union('Concave'), union('Depth Edge'), 'Shadow union')
    highlight_raw = union('Convex')
    no_outer = math_node(edges, 'SUBTRACT', 1.0, outer, 'No silhouette')
    shadow = math_node(edges, 'MULTIPLY', math_node(edges, 'MULTIPLY', shadow_raw, no_outer), ea['Shadows'], 'Shadow enabled')
    highlight = math_node(edges, 'MULTIPLY', math_node(edges, 'MULTIPLY', math_node(edges, 'MULTIPLY', highlight_raw, no_outer), math_node(edges, 'SUBTRACT', 1.0, shadow)), ea['Highlights'], 'Highlight enabled')
    outline = math_node(edges, 'MULTIPLY', outer, ea['Outline'], 'Outline enabled')
    highlight_tint = vector_node(edges, 'SCALE', ea['Highlight Tint'], label='Highlight tint')
    highlight_tint.node.inputs['Scale'].default_value = 0.35
    shadow_tint = vector_node(edges, 'SCALE', ea['Shadow Tint'], label='Shadow tint')
    shadow_tint.node.inputs['Scale'].default_value = 0.45
    highlight_color = vector_node(edges, 'MULTIPLY', ea['Image'], vector_node(edges, 'ADD', highlight_tint, (1.0, 1.0, 1.0)), 'Tinted highlight')
    shadow_color = vector_node(edges, 'MULTIPLY', ea['Image'], vector_node(edges, 'SUBTRACT', (1.0, 1.0, 1.0), shadow_tint), 'Tinted shadow')
    def mix(first, second, factor, label):
        item = make_node(edges, 'ShaderNodeMix', label, 800, 0)
        item.data_type = 'RGBA'
        item.blend_type = 'MIX'
        wire(edges, factor, item.inputs[0])
        wire(edges, first, item.inputs[6])
        wire(edges, second, item.inputs[7])
        return item.outputs[2]
    result = mix(ea['Image'], highlight_color, highlight, 'Apply highlight')
    result = mix(result, shadow_color, shadow, 'Apply shadow')
    result = mix(result, ea['Outline Color'], outline, 'Apply outline')
    set_alpha = make_node(edges, 'CompositorNodeSetAlpha', 'Preserve alpha', 1200, 0)
    wire(edges, result, set_alpha.inputs['Image'])
    wire(edges, ea['Alpha'], set_alpha.inputs['Alpha'])
    for name, value in (('Image', set_alpha.outputs['Image']), ('Highlight Mask', highlight), ('Shadow Mask', shadow), ('Outline Mask', outline)):
        wire(edges, value, eo.inputs[name])

    tree = bpy.data.node_groups.get('Xybots Calibration Compositor')
    if tree is not None:
        bpy.data.node_groups.remove(tree)
    tree = bpy.data.node_groups.new('Xybots Calibration Compositor', 'CompositorNodeTree')
    tree.interface.new_socket(name='Image', in_out='OUTPUT', socket_type='NodeSocketColor')
    scene.compositing_node_group = tree
    render = make_node(tree, 'CompositorNodeRLayers', 'Render passes', -400, 0)
    render.layer = layer.name
    output = make_node(tree, 'NodeGroupOutput', 'Composite', 850, 0)
    controls = make_node(tree, 'CompositorNodeGroup', 'PIXEL EDGE CONTROLS', 300, 0)
    controls.node_tree = edges
    for name in ('Image', 'Normal', 'Position', 'Depth', 'Alpha'):
        wire(tree, render.outputs[name], controls.inputs[name])
    wire(tree, controls.outputs['Image'], output.inputs['Image'])
    for column, name in enumerate(('Camera X', 'Camera Y', 'Camera Z')):
        socket = controls.inputs[name]
        for row in range(3):
            curve = socket.driver_add('default_value', row)
            driver = curve.driver
            driver.type = 'SCRIPTED'
            variable = driver.variables.new()
            variable.name = 'm'
            variable.type = 'SINGLE_PROP'
            variable.targets[0].id = camera
            variable.targets[0].data_path = 'matrix_world[%d][%d]' % (column, row)
            driver.expression = 'm'
    return edges


def set_pixel_edge_export_width(scene, source_pixels):
    """Convert a desired final one-logical-pixel edge into source pixels."""
    tree = scene.compositing_node_group
    if tree is None:
        return
    controls = next((node for node in tree.nodes if node.label == 'PIXEL EDGE CONTROLS'), None)
    if controls is None or controls.node_tree is None:
        return
    for neighbour in controls.node_tree.nodes:
        if neighbour.bl_idname != 'CompositorNodeGroup' or neighbour.node_tree is None:
            continue
        if neighbour.node_tree.name != 'Xybots Pixel Edges - Neighbour':
            continue
        x = neighbour.inputs['X'].default_value
        y = neighbour.inputs['Y'].default_value
        if x != 0.0:
            neighbour.inputs['X'].default_value = math.copysign(float(source_pixels), x)
        if y != 0.0:
            neighbour.inputs['Y'].default_value = math.copysign(float(source_pixels), y)


def add_mesh_object(collection, name, operator, location, dimensions, material, bevel=0.0):
    bpy.ops.object.select_all(action='DESELECT')
    operator()
    obj = bpy.context.active_object
    for linked in list(obj.users_collection):
        linked.objects.unlink(obj)
    collection.objects.link(obj)
    obj.name = name
    obj.location = location
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Xybots_Bevel", 'BEVEL')
        modifier.width = bevel
        modifier.segments = 1
    obj.data.materials.append(material)
    obj["xybots_greybox"] = True
    return obj


def add_pyramid(collection, name, location, dimensions, material):
    half_x, half_y, height = dimensions[0] * 0.5, dimensions[1] * 0.5, dimensions[2]
    vertices = [(-half_x, -half_y, 0), (half_x, -half_y, 0), (half_x, half_y, 0), (-half_x, half_y, 0), (0, 0, height)]
    faces = [(0, 1, 2, 3), (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)]
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.location = location
    obj.data.materials.append(material)
    obj["xybots_greybox"] = True
    return obj


def add_primitive(collection, spec, scale, material):
    name, kind = spec["name"], spec["type"]
    x, game_y = spec["position"]
    # Godot's 2D map is screen-handed (+Y points down); Blender is
    # right-handed (+Y points away from the screen in this rig).  Mirror the
    # map's Y coordinate once at this boundary, rather than reflecting every
    # camera frame or selected sprite later.
    forward = -game_y
    def mark_primitive(obj):
        obj["xybots_primitive_name"] = name
        obj["xybots_semantic_lods"] = bool(spec.get("semantic_lods", spec.get("semantic_barrel", False)))
        return obj
    if kind == "append_asset":
        # Copy exactly the named authored object from another .blend.  This is
        # deliberately an append, rather than a link: the source rig remains
        # untouched and this calibration copy can be moved for every camera and
        # depth render without changing the artist's source file.
        source_blend = bpy.path.abspath(str(spec["source_blend"]))
        source_name = str(spec["source_object"])
        with bpy.data.libraries.load(source_blend, link=False) as (data_from, data_to):
            if source_name not in data_from.objects:
                raise RuntimeError(f"Source object {source_name} was not found in {source_blend}.")
            data_to.objects = [source_name]
        obj = data_to.objects[0]
        if obj is None or obj.type != 'MESH':
            raise RuntimeError(f"Appended calibration asset {source_name} is not an available mesh.")
        collection.objects.link(obj)
        obj.name = name
        obj.location = (x * scale, forward * scale, 0.0)
        obj["xybots_preserve_materials"] = bool(spec.get("preserve_materials", True))
        obj["xybots_semantic_lods"] = bool(spec.get("semantic_lods", spec.get("semantic_barrel", False)))
        obj["xybots_source_object"] = source_name
        return mark_primitive(obj)
    if kind == "linked_asset":
        # Keep the Asset Browser source completely untouched.  This local,
        # single-user duplicate is the only version that the calibration build
        # moves, hides, or renders.  Its mesh remains in the asset's authored
        # Blender units, while only its Godot-map placement crosses the 2x
        # game-cell-to-Blender ground-space bridge.
        source_name = str(spec["source_object"])
        source = bpy.data.objects.get(source_name)
        if source is None or source.type != 'MESH':
            raise RuntimeError(f"Linked calibration asset {source_name} is not an available mesh.")
        obj = source.copy()
        obj.data = source.data.copy()
        obj.name = name
        obj.location = (x * scale, forward * scale, 0.0)
        for linked in list(obj.users_collection):
            linked.objects.unlink(obj)
        collection.objects.link(obj)
        obj["xybots_preserve_materials"] = bool(spec.get("preserve_materials", False))
        obj["xybots_semantic_lods"] = bool(spec.get("semantic_lods", spec.get("semantic_barrel", False)))
        obj["xybots_neutral_top_lighting"] = bool(spec.get("neutral_top_lighting", False))
        obj["xybots_source_object"] = source_name
        return mark_primitive(obj)
    dx, dy, dz = spec["dimensions"]
    location = (x * scale, forward * scale, dz * scale * 0.5)
    ground_location = (x * scale, forward * scale, 0.0)
    dimensions = (dx * scale, dy * scale, dz * scale)
    if kind == "box":
        return mark_primitive(add_mesh_object(collection, name, bpy.ops.mesh.primitive_cube_add, location, dimensions, material))
    if kind == "wireframe_cell_block":
        # This is the canonical unit test, not production prop geometry: its
        # outside dimensions are exactly one game cell wide/deep and one live
        # wall height tall.  Keep only the wireframe so walls and cell edges
        # remain visible through it during the first perspective comparison.
        obj = add_mesh_object(collection, name, bpy.ops.mesh.primitive_cube_add, location, dimensions, material)
        wireframe = obj.modifiers.new("Xybots_Calibration_Wireframe", 'WIREFRAME')
        wireframe.thickness = 0.022 * scale
        wireframe.use_even_offset = True
        wireframe.use_replace = True
        # Keep the fixture's outside extents at the canonical cell boundary;
        # the visible wire grows inward instead of making the test block wider
        # or taller than the game unit it is supposed to measure.
        wireframe.offset = -1.0
        obj["xybots_calibration_fixture"] = "one_cell_by_one_cell_by_wall_height"
        return mark_primitive(obj)
    if kind == "floor_wire_square":
        wire_thickness = 0.016 * scale
        obj = add_mesh_object(collection, name, bpy.ops.mesh.primitive_plane_add, (ground_location[0], ground_location[1], wire_thickness * 0.5), (dimensions[0], dimensions[1], 0.0), material)
        wireframe = obj.modifiers.new("Xybots_Floor_Footprint_Wire", 'WIREFRAME')
        wireframe.thickness = wire_thickness
        wireframe.use_even_offset = True
        wireframe.use_replace = True
        wireframe.offset = 0.0
        obj["xybots_floor_wire_thickness_at_reference"] = wire_thickness
        return mark_primitive(obj)
    if kind == "floor_wire_circle":
        wire_thickness = 0.016 * scale
        # A filled disc plus the same modifier as the square means only the
        # perimeter renders, and lets every depth tier retune one shared
        # one-logical-pixel stroke without changing the circle's diameter.
        obj = add_mesh_object(collection, name, lambda: bpy.ops.mesh.primitive_circle_add(vertices=24, fill_type='NGON'), (ground_location[0], ground_location[1], wire_thickness * 0.5), (dimensions[0], dimensions[1], 0.0), material)
        wireframe = obj.modifiers.new("Xybots_Floor_Footprint_Wire", 'WIREFRAME')
        wireframe.thickness = wire_thickness
        wireframe.use_even_offset = True
        wireframe.use_replace = True
        wireframe.offset = 0.0
        obj["xybots_floor_wire_thickness_at_reference"] = wire_thickness
        return mark_primitive(obj)
    if kind == "beveled_box":
        return mark_primitive(add_mesh_object(collection, name, bpy.ops.mesh.primitive_cube_add, location, dimensions, material, bevel=0.06 * scale))
    if kind == "sphere":
        return mark_primitive(add_mesh_object(collection, name, lambda: bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8), location, dimensions, material))
    if kind == "cylinder":
        return mark_primitive(add_mesh_object(collection, name, lambda: bpy.ops.mesh.primitive_cylinder_add(vertices=16), location, dimensions, material))
    if kind == "sideways_cylinder":
        obj = add_mesh_object(collection, name, lambda: bpy.ops.mesh.primitive_cylinder_add(vertices=16), location, dimensions, material)
        obj.rotation_euler[1] = math.radians(90.0)
        return mark_primitive(obj)
    if kind == "cone":
        return mark_primitive(add_mesh_object(collection, name, lambda: bpy.ops.mesh.primitive_cone_add(vertices=16), location, dimensions, material))
    if kind == "pyramid":
        # The custom pyramid mesh is authored with its base at local Z=0;
        # unlike Blender's centered primitive operators it must not receive
        # the half-height placement offset used above.
        return mark_primitive(add_pyramid(collection, name, ground_location, dimensions, material))
    if kind == "stepped_block":
        base = add_mesh_object(collection, name + "_Base", bpy.ops.mesh.primitive_cube_add, location, dimensions, material)
        top = add_mesh_object(collection, name + "_Step", bpy.ops.mesh.primitive_cube_add, (location[0], location[1] + dimensions[1] * 0.12, location[2] + dimensions[2] * 0.38), (dimensions[0] * 0.58, dimensions[1] * 0.58, dimensions[2] * 0.28), material)
        mark_primitive(base)
        mark_primitive(top)
        return base
    raise ValueError(f"Unknown primitive type: {kind}")


def add_room(collection, scale, wall_height, material):
    floor = add_mesh_object(collection, "Greybox_Floor", bpy.ops.mesh.primitive_plane_add, (0, 0, 0), (6.0 * scale, 6.0 * scale, 0.0), material)
    floor["xybots_role"] = "floor"
    for name, location, dims in (
        ("Greybox_Left_Wall", (-3.0 * scale, 0.0, wall_height * scale * 0.5), (0.05, 6.0 * scale, wall_height * scale)),
        ("Greybox_Right_Wall", (3.0 * scale, 0.0, wall_height * scale * 0.5), (0.05, 6.0 * scale, wall_height * scale)),
        ("Greybox_Back_Wall", (0.0, 3.0 * scale, wall_height * scale * 0.5), (6.0 * scale, 0.05, wall_height * scale)),
    ):
        wall = add_mesh_object(collection, name, bpy.ops.mesh.primitive_cube_add, location, dims, material)
        wall["xybots_role"] = "wall"


def set_horizon(scene, camera, row, height):
    target = 1.0 - row / (height - 1.0)
    forward = camera.matrix_world.to_quaternion() @ Vector((0.0, 0.0, -1.0))
    probe = camera.matrix_world.translation + forward * 50.0
    low, high = -1.0, 1.0
    camera.data.shift_y = low
    bpy.context.view_layer.update()
    low_value = world_to_camera_view(scene, camera, probe).y
    camera.data.shift_y = high
    bpy.context.view_layer.update()
    high_value = world_to_camera_view(scene, camera, probe).y
    increasing = high_value > low_value
    for _ in range(36):
        middle = (low + high) * 0.5
        camera.data.shift_y = middle
        bpy.context.view_layer.update()
        value = world_to_camera_view(scene, camera, probe).y
        if (value < target) == increasing:
            low = middle
        else:
            high = middle
    camera.data.shift_y = (low + high) * 0.5


def add_lighting(scene, collection):
    world = bpy.data.worlds.get("Xybots_Greybox_World")
    if world is None:
        world = bpy.data.worlds.new("Xybots_Greybox_World")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs['Color'].default_value = tuple(srgb_to_linear(value / 255.0) for value in (32, 36, 42)) + (1.0,)
    background.inputs['Strength'].default_value = 0.50
    scene.world = world
    # A broad overhead area light gives raw purchased assets readable form
    # without baking a directional left/right shadow into their sprite turns.
    light_data = bpy.data.lights.new("Xybots_Greybox_Key_Data", 'AREA')
    light_data.energy = 500.0
    light_data.shape = 'DISK'
    light_data.size = 7.0
    light = bpy.data.objects.new("Xybots_Greybox_Key", light_data)
    collection.objects.link(light)
    light.location = (0.0, 0.0, 7.0)
    light.rotation_euler = (0.0, 0.0, 0.0)
    return light


def set_camera_heading(scene, camera, data, scale, yaw_degrees):
    yaw = math.radians(yaw_degrees)
    # Map the live game basis into Blender coordinates.  In Godot, yaw zero
    # looks toward game -Y and positive yaw turns toward game +X.  The shared
    # Godot-to-Blender Y reflection makes that Blender (sin(yaw), +cos(yaw)).
    # Without this reflection the sprite sequence changes direction opposite
    # the live camera while the player turns.
    forward = Vector((math.sin(yaw), math.cos(yaw), 0.0))
    camera_height = data["projection"]["camera_height_godot_units"] * data["blender"]["vertical_units_per_godot_unit"]
    logical_depth = float(data["projection"]["live_camera_rear_offset_godot_units"])
    camera.location = (-forward.x * logical_depth * scale, -forward.y * logical_depth * scale, camera_height)
    camera.rotation_euler = forward.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.view_layer.update()
    set_horizon(scene, camera, data["projection"]["horizon_y_from_top"], data["logical_canvas"]["height"])


def create_camera(scene, collection, data, scale):
    old = bpy.data.objects.get(CAMERA_NAME)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    camera_data = bpy.data.cameras.new(CAMERA_NAME + "_Data")
    camera_data.type = 'PERSP'
    camera_data.lens = data["blender"]["lens_mm"]
    camera_data.sensor_width = data["blender"]["sensor_width_mm"]
    camera_data.sensor_fit = 'HORIZONTAL'
    camera_data.clip_start = 0.02
    camera_data.clip_end = 100.0
    camera = bpy.data.objects.new(CAMERA_NAME, camera_data)
    collection.objects.link(camera)
    scene.camera = camera
    set_camera_heading(scene, camera, data, scale, 0.0)
    return camera


def render_reference_views(scene, camera, data, scale, prefix="blender"):
    os.makedirs(CAPTURE_DIRECTORY, exist_ok=True)
    original_percentage = scene.render.resolution_percentage
    scene.render.resolution_percentage = 100
    for view in data["calibration_views"]:
        set_camera_heading(scene, camera, data, scale, float(view["yaw_degrees"]))
        scene.render.filepath = os.path.join(CAPTURE_DIRECTORY, f"{prefix}_{view['id']}.png")
        bpy.ops.render.render(write_still=True)
    set_camera_heading(scene, camera, data, scale, 0.0)
    scene.render.resolution_percentage = original_percentage


def render_flat_reference_views(scene, camera, data, scale, collection, flat_material):
    """Render the same geometry/camera set with the lighting-independent grid."""
    original_materials = []
    original_filter_size = scene.render.filter_size
    original_taa_samples = scene.eevee.taa_render_samples
    for obj in collection.objects:
        if obj.type != 'MESH':
            continue
        original_materials.append((obj, list(obj.data.materials)))
        obj.data.materials.clear()
        obj.data.materials.append(flat_material)
    try:
        # This is a 160x120 diagnostic, not a beauty render.  Minimize
        # Blender's reconstruction filtering so its grid edges are comparable
        # to Godot's direct CanvasItem lines.
        scene.render.filter_size = 0.01
        scene.eevee.taa_render_samples = 1
        render_reference_views(scene, camera, data, scale, prefix="blender_flat")
    finally:
        scene.render.filter_size = original_filter_size
        scene.eevee.taa_render_samples = original_taa_samples
        for obj, materials in original_materials:
            obj.data.materials.clear()
            for material in materials:
                obj.data.materials.append(material)


def render_primitive_plates(scene, camera, data, scale, collection, flat_material):
    """Export transparent per-primitive calibration plates and their anchors.

    Plates intentionally retain the 160x120 projection frame.  This preserves
    the exact camera mapping during the first Godot comparison; crop/atlas
    production is a later authoring step once the contract is locked.
    """
    os.makedirs(PRIMITIVE_PLATE_DIRECTORY, exist_ok=True)
    mesh_objects = [obj for obj in collection.objects if obj.type == 'MESH']
    original_hidden = {obj: obj.hide_render for obj in mesh_objects}
    # Asset Browser collection instances live outside our owned calibration
    # collection.  Hide them during isolated plates so only the local duplicate
    # can contribute pixels; the raw source stays visible in normal Blender use.
    external_geometry = [obj for obj in scene.objects if obj not in mesh_objects and obj.type not in {'CAMERA', 'LIGHT'}]
    external_hidden = {obj: obj.hide_render for obj in external_geometry}
    original_materials = []
    original_transparency = scene.render.film_transparent
    original_filter_size = scene.render.filter_size
    original_taa_samples = scene.eevee.taa_render_samples
    manifest = {
        "schema_version": 1,
        "logical_canvas": data["logical_canvas"],
        "notes": "Transparent full-frame plates; foot_screen is in logical pixels.",
        "plates": [],
    }
    try:
        scene.render.film_transparent = True
        scene.render.filter_size = 0.01
        scene.eevee.taa_render_samples = 1
        for obj in external_geometry:
            obj.hide_render = True
        for obj in mesh_objects:
            original_materials.append((obj, list(obj.data.materials)))
            obj.data.materials.clear()
            obj.data.materials.append(flat_material)
        for view in data["calibration_views"]:
            view_id = view["id"]
            set_camera_heading(scene, camera, data, scale, float(view["yaw_degrees"]))
            view_directory = os.path.join(PRIMITIVE_PLATE_DIRECTORY, view_id)
            os.makedirs(view_directory, exist_ok=True)
            for spec in data["primitives"]:
                name = spec["name"]
                targets = [obj for obj in mesh_objects if obj.get("xybots_primitive_name") == name]
                if not targets:
                    raise RuntimeError(f"No Blender geometry found for primitive plate {name}.")
                for obj in mesh_objects:
                    obj.hide_render = obj not in targets
                filename = f"{name.lower()}.png"
                filepath = os.path.join(view_directory, filename)
                scene.render.filepath = filepath
                bpy.ops.render.render(write_still=True)
                world_foot = Vector((float(spec["position"][0]) * scale, -float(spec["position"][1]) * scale, 0.0))
                screen = world_to_camera_view(scene, camera, world_foot)
                manifest["plates"].append({
                    "name": name,
                    "view": view_id,
                    "path": os.path.relpath(filepath, PROJECT_DIR).replace("\\", "/"),
                    "foot_screen": [round(screen.x * data["logical_canvas"]["width"], 4), round((1.0 - screen.y) * data["logical_canvas"]["height"], 4)],
                })
    finally:
        scene.render.film_transparent = original_transparency
        scene.render.filter_size = original_filter_size
        scene.eevee.taa_render_samples = original_taa_samples
        for obj, hidden in original_hidden.items():
            obj.hide_render = hidden
        for obj, hidden in external_hidden.items():
            obj.hide_render = hidden
        for obj, materials in original_materials:
            obj.data.materials.clear()
            for material in materials:
                obj.data.materials.append(material)
        set_camera_heading(scene, camera, data, scale, 0.0)
    with open(os.path.join(PRIMITIVE_PLATE_DIRECTORY, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)


def render_primitive_sprite_sources(scene, camera, data, scale, collection, flat_material):
    """Render portable primitives at calibrated camera-relative depths.

    These source plates differ from the diagnostic plates above: every object is
    temporarily moved to the same camera-relative floor point before rendering.
    That makes the later alpha crop a genuine portable sprite with a stable
    ground anchor and a known depth, rather than a crop from its old test-room
    location (where many primitives are intentionally offscreen in other views).
    """
    os.makedirs(PRIMITIVE_SPRITE_SOURCE_DIRECTORY, exist_ok=True)
    mesh_objects = [obj for obj in collection.objects if obj.type == 'MESH']
    original_hidden = {obj: obj.hide_render for obj in mesh_objects}
    external_geometry = [obj for obj in scene.objects if obj not in mesh_objects and obj.type not in {'CAMERA', 'LIGHT'}]
    external_hidden = {obj: obj.hide_render for obj in external_geometry}
    original_locations = {obj: obj.location.copy() for obj in mesh_objects}
    original_scales = {obj: obj.scale.copy() for obj in mesh_objects}
    original_wire_thicknesses = [
        (obj, modifier, modifier.thickness)
        for obj in mesh_objects
        for modifier in obj.modifiers
        if modifier.type == 'WIREFRAME' and "xybots_floor_wire_thickness_at_reference" in obj
    ]
    original_materials = []
    original_transparency = scene.render.film_transparent
    original_filter_size = scene.render.filter_size
    original_taa_samples = scene.eevee.taa_render_samples
    original_dither_intensity = scene.render.dither_intensity
    original_resolution_x = scene.render.resolution_x
    original_resolution_y = scene.render.resolution_y
    original_resolution_percentage = scene.render.resolution_percentage
    original_use_nodes = scene.use_nodes
    reference_depth = 2.5
    runtime_prop_scale = 0.38
    # These comparison sprites deliberately resolve to one source texel per
    # logical game pixel. Their earlier 4x and 2x passes held too much detail
    # beside the hand-authored barrels; 1x keeps the same physical scale with
    # the intended chunky pixel vocabulary.
    source_pixels_per_logical_pixel = 1
    logical_bottom_overscan = 120
    source_width = int(data["logical_canvas"]["width"] * source_pixels_per_logical_pixel)
    source_height = int((data["logical_canvas"]["height"] + logical_bottom_overscan) * source_pixels_per_logical_pixel)
    manifest = {
        "schema_version": 1,
        "logical_canvas": data["logical_canvas"],
        "reference_depth_godot_units": reference_depth,
        "source_pixels_per_logical_pixel": source_pixels_per_logical_pixel,
        "perspective_lods": data.get("perspective_lods", []),
        "barrel_semantic_lods": data.get("barrel_semantic_lods", []),
        "notes": "Transparent cropped source plates. Rig_Barrel_LOD_00 and Original_Barrel_01 use 16 headings and ten half-cell depth tiers. Their source canvas has bottom overscan so the nearest tier retains the complete ground-contact silhouette.",
        "plates": [],
    }
    try:
        scene.render.film_transparent = True
        scene.render.filter_size = 0.01
        # Sprite plates are read one-for-one by Godot.  A single Eevee TAA
        # sample plus render dithering turns soft raw-material shading into
        # isolated black speckles, so use the scene's stable final-sample
        # quality and disable output dither for this deterministic export.
        scene.eevee.taa_render_samples = max(64, original_taa_samples)
        scene.render.dither_intensity = 0.0
        # Preserve more than one source texel per final logical pixel.  The
        # runtime applies the reciprocal scale, so this adds near-view detail
        # without making the world object physically larger at its reference
        # depth.
        scene.render.resolution_x = source_width
        scene.render.resolution_y = source_height
        scene.render.resolution_percentage = 100
        # The compositor is authored as a one-output-pixel treatment.  These
        # plates are four times denser, so sample four source pixels away and
        # keep a one-*logical*-pixel highlight/shadow/outline in Godot.
        set_pixel_edge_export_width(scene, source_pixels_per_logical_pixel)
        for obj in mesh_objects:
            original_materials.append((obj, list(obj.data.materials)))
            if not bool(obj.get("xybots_preserve_materials", False)) and not bool(obj.get("xybots_render_material_locked", False)):
                obj.data.materials.clear()
                obj.data.materials.append(flat_material)
        for obj in external_geometry:
            obj.hide_render = True
        for view in data["calibration_views"]:
            view_id = view["id"]
            yaw = math.radians(float(view["yaw_degrees"]))
            forward = Vector((math.sin(yaw), math.cos(yaw), 0.0))
            set_camera_heading(scene, camera, data, scale, float(view["yaw_degrees"]))
            # Expand only below the live 160x120 frame.  The calibrated image
            # scale remains identical in its original region; the extra rows
            # simply preserve a close barrel's feet before its world sprite
            # goes below the game camera.
            set_horizon(
                scene,
                camera,
                float(data["projection"]["horizon_y_from_top"]) * source_pixels_per_logical_pixel,
                source_height,
            )
            for spec in data["primitives"]:
                name = spec["name"]
                # The current Godot comparison scene is a barrel-only lineup.
                # Retain the geometric definitions in the calibration file,
                # but do not spend a full 32-view export pass on inactive props.
                uses_semantic_lods = bool(spec.get("semantic_lods", spec.get("semantic_barrel", False)))
                if not uses_semantic_lods and name != "Grid_Cell_Block":
                    continue
                barrel_views = {item["id"] for item in data.get("barrel_calibration_views", [])}
                if uses_semantic_lods and view_id not in barrel_views:
                    continue
                targets = [obj for obj in mesh_objects if obj.get("xybots_primitive_name") == name]
                if not targets:
                    raise RuntimeError(f"No Blender geometry found for primitive sprite source {name}.")
                # The cell block is the first proof fixture.  Render it at
                # several *real* depths instead of uniformly shrinking one
                # near image.  The remaining primitives remain on the base
                # tier until this calibration is accepted.
                if uses_semantic_lods:
                    lods = data.get("barrel_semantic_lods", [])
                elif bool(spec.get("perspective_lods", False)) or name == "Grid_Cell_Block":
                    lods = data.get("perspective_lods", [])
                else:
                    lods = [{"id": "base", "reference_depth_godot_units": reference_depth}]
                for lod in lods:
                    lod_id = str(lod["id"])
                    lod_depth = float(lod["reference_depth_godot_units"])
                    target_ground = camera.location.copy()
                    target_ground.z = 0.0
                    target_ground += forward * lod_depth * scale
                    view_directory = os.path.join(PRIMITIVE_SPRITE_SOURCE_DIRECTORY, view_id)
                    if lod_id != "base":
                        view_directory = os.path.join(view_directory, lod_id)
                    os.makedirs(view_directory, exist_ok=True)
                    source_ground = Vector((float(spec["position"][0]) * scale, -float(spec["position"][1]) * scale, 0.0))
                    for obj in mesh_objects:
                        obj.hide_render = obj not in targets
                    fixture_scale = float(spec.get("runtime_scale", runtime_prop_scale))
                    for obj in targets:
                        # Scale the whole assembled primitive around its authored
                        # floor point, not around each mesh origin.  This keeps
                        # cylinders/boxes resting on the ground and keeps the
                        # stepped block's two pieces registered to one another.
                        obj.location = target_ground + (original_locations[obj] - source_ground) * fixture_scale
                        obj.scale = original_scales[obj] * fixture_scale
                        if "xybots_floor_wire_thickness_at_reference" in obj:
                            # The footprint's extent is still physically
                            # projected. Only its perimeter receives the
                            # semantic guarantee: one logical output pixel
                            # wide at every authored depth tier.
                            # Raster coverage needs a little more than the
                            # mathematically exact width once a projected line
                            # lands between source pixels.  Preserve the near
                            # one-pixel stroke, then widen only the distant
                            # physical wire enough to keep it from dropping to
                            # zero alpha on alternating depth tiers.
                            stroke_factor = max(1.0, 3.0 * lod_depth / reference_depth)
                            stroke = float(obj["xybots_floor_wire_thickness_at_reference"]) * stroke_factor
                            for modifier in obj.modifiers:
                                if modifier.type == 'WIREFRAME':
                                    modifier.thickness = stroke
                    # The full normal/depth compositor is deliberately a
                    # close-read cue for the barrel.  Every other barrel tier
                    # receives only its clean three-value Z-normal palette.
                    # Do not change the established greybox fixture treatment.
                    scene.use_nodes = bool(lod.get("edge_composite", False)) if uses_semantic_lods else original_use_nodes
                    filepath = os.path.join(view_directory, f"{name.lower()}.png")
                    scene.render.filepath = filepath
                    bpy.context.view_layer.update()
                    bpy.ops.render.render(write_still=True)
                    screen = world_to_camera_view(scene, camera, target_ground)
                    manifest["plates"].append({
                        "name": name,
                        "view": view_id,
                        "perspective_lod": lod_id,
                        "reference_depth_godot_units": lod_depth,
                        "path": os.path.relpath(filepath, PROJECT_DIR).replace("\\", "/"),
                        # The cropper receives logical-pixel coordinates and
                        # converts them to this higher-resolution canvas once.
                        # Keep the overscanned vertical extent in that logical
                        # coordinate space; multiplying here too would make
                        # every ground anchor twice as low.
                        "foot_screen": [round(screen.x * source_width / source_pixels_per_logical_pixel, 4), round((1.0 - screen.y) * source_height / source_pixels_per_logical_pixel, 4)],
                    })
                    for obj in targets:
                        obj.location = original_locations[obj]
                        obj.scale = original_scales[obj]
    finally:
        scene.render.film_transparent = original_transparency
        scene.render.filter_size = original_filter_size
        scene.eevee.taa_render_samples = original_taa_samples
        scene.render.dither_intensity = original_dither_intensity
        scene.render.resolution_x = original_resolution_x
        scene.render.resolution_y = original_resolution_y
        scene.render.resolution_percentage = original_resolution_percentage
        scene.use_nodes = original_use_nodes
        set_pixel_edge_export_width(scene, 1)
        for obj, hidden in original_hidden.items():
            obj.hide_render = hidden
        for obj, hidden in external_hidden.items():
            obj.hide_render = hidden
        for obj, location in original_locations.items():
            obj.location = location
        for obj, object_scale in original_scales.items():
            obj.scale = object_scale
        for obj, modifier, thickness in original_wire_thicknesses:
            modifier.thickness = thickness
        for obj, materials in original_materials:
            obj.data.materials.clear()
            for material in materials:
                obj.data.materials.append(material)
        set_camera_heading(scene, camera, data, scale, 0.0)
    with open(os.path.join(PRIMITIVE_SPRITE_SOURCE_DIRECTORY, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)


def build():
    data = contract()
    write_shared_grid_texture(data)
    scene = ensure_scene()
    collection = clear_owned_collection(scene)
    scale = data["blender"]["ground_units_per_godot_cell"]
    # Blender 5.2 exposes Eevee Next through the stable BLENDER_EEVEE enum.
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = data["logical_canvas"]["width"]
    scene.render.resolution_y = data["logical_canvas"]["height"]
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    anchor = grid_anchor(collection)
    material = material_grid(data, anchor)
    flat_material = material_grid(data, anchor, flat_geometry=True)
    normal_tint_material = material_grid(data, anchor, flat_geometry=True, normal_tinted=True, use_grid=False)
    barrel_flat_material = material_flat_z_palette("Xybots_Imported_Barrel_Flat_Z", data["barrel_flat_palette_srgb"])
    add_room(collection, scale, data["projection"]["wall_height_godot_units"], material)
    for spec in data["primitives"]:
        add_primitive(collection, spec, scale, material)
    for obj in collection.objects:
        if obj.type == 'MESH' and obj.get("xybots_primitive_name") == "Imported_Barrel_01":
            obj.data.materials.clear()
            obj.data.materials.append(barrel_flat_material)
            # Render export must not replace this purpose-built material with
            # the generic greybox tint on its way through the common exporter.
            obj["xybots_render_material_locked"] = True
    add_lighting(scene, collection)
    camera = create_camera(scene, collection, data, scale)
    install_pixel_edge_compositor(scene, camera)
    render_reference_views(scene, camera, data, scale)
    render_flat_reference_views(scene, camera, data, scale, collection, flat_material)
    render_primitive_plates(scene, camera, data, scale, collection, flat_material)
    render_primitive_sprite_sources(scene, camera, data, scale, collection, normal_tint_material)
    scene["xybots_projection_contract"] = CONTRACT_PATH
    scene["xybots_logical_canvas"] = tuple(data["logical_canvas"].values())
    bpy.context.window.scene = scene
    bpy.context.view_layer.objects.active = camera
    camera.select_set(True)
    bpy.context.view_layer.update()
    return {"scene": scene.name, "collection": collection.name, "camera": camera.name, "objects": len(collection.objects)}


if __name__ == "__main__":
    result = build()
