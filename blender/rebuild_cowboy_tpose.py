import bpy
from mathutils import Vector

SOURCE = r"D:\Godot\xybotsResearch\blender\Cowboy1.blend"
OUTPUT = r"D:\Godot\xybotsResearch\blender\cowboy1_tpose.blend"

scene = bpy.context.scene
armature = next(obj for obj in scene.objects if obj.type == 'ARMATURE')
mesh = next(obj for obj in scene.objects if obj.type == 'MESH' and obj.find_armature() == armature)

# The source file's active 0_T-Pose action drives the visual T-pose at frame 0.
scene.frame_set(0)
bpy.context.view_layer.update()

# Bake only the evaluated Armature deformation into mesh coordinates. Vertex
# groups remain on the mesh, so they can immediately drive a fresh modifier.
armature_modifier = next(mod for mod in mesh.modifiers if mod.type == 'ARMATURE')
modifier_name = armature_modifier.name
preserve_volume = armature_modifier.use_deform_preserve_volume

if bpy.context.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
for obj in bpy.context.selected_objects:
    obj.select_set(False)
mesh.select_set(True)
bpy.context.view_layer.objects.active = mesh
bpy.ops.object.modifier_apply(modifier=modifier_name)

# Convert the currently displayed T-pose bones to the new rest/bind pose.
for obj in bpy.context.selected_objects:
    obj.select_set(False)
armature.select_set(True)
bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.armature_apply(selected=False)
if armature.animation_data:
    armature.animation_data.action = None
armature.data.pose_position = 'REST'

# Reattach skinning. The baked T-pose mesh and new T-pose rest bones now share
# the same bind shape, while the original 61 vertex groups are preserved.
bpy.ops.object.mode_set(mode='OBJECT')
skin = mesh.modifiers.new(modifier_name, 'ARMATURE')
skin.object = armature
skin.use_deform_preserve_volume = preserve_volume

scene.frame_set(0)
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=OUTPUT)

depsgraph = bpy.context.evaluated_depsgraph_get()
evaluated_mesh = mesh.evaluated_get(depsgraph)
world_bounds = [evaluated_mesh.matrix_world @ Vector(corner) for corner in evaluated_mesh.bound_box]
print("COWBOY_TPOSE_RESULT", {
    "output": OUTPUT,
    "vertex_groups": len(mesh.vertex_groups),
    "active_action": armature.animation_data.action.name if armature.animation_data and armature.animation_data.action else None,
    "pose_position": armature.data.pose_position,
    "posed_bones": sum(1 for bone in armature.pose.bones if not bone.matrix_basis.is_identity),
    "bounds": [[round(point.x, 4), round(point.y, 4), round(point.z, 4)] for point in world_bounds],
})
