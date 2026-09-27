import bpy


# ============================================================
# COPY / BAKE ANIMATION FROM ONE ARMATURE TO ANOTHER
# Blender 5.2
#
# SELECT:
#   SOURCE first
#   TARGET second / last (TARGET must be active)
#
# Creates two Actions on the target:
#   - a full-length baked copy of the source Action
#   - a seven-frame version, sampled evenly across that full action
#
# The source/imported armature is intentionally left alone so it can be
# inspected or deleted manually after verifying the copied Actions.
# ============================================================


# ------------------------------------------------------------
# SETTINGS
# ------------------------------------------------------------

STRIP_NAMESPACE = True
FRAME_STEP = 1
ACTION_SUFFIX = "_COPY"
SAMPLED_ACTION_SUFFIX = "_COPY_7F"
SAMPLED_FRAME_COUNT = 7

# The imported FBX commonly carries root motion on the armature object.  Do
# not key the target armature object: that leaves object-level keys that move a
# supposedly-resting rig.  Instead, bake the evaluated world transform into
# this root pose bone.  It must be the root of the target hierarchy.
ROOT_MOTION_TARGET_BONE = "spine"


# ------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------

def clean_bone_name(name):
    if STRIP_NAMESPACE and ":" in name:
        return name.split(":")[-1]

    return name


def find_target_bone(source_bone, target_pose):
    """Find the target pose bone for a source pose bone."""
    if source_bone.name in target_pose.bones:
        return target_pose.bones[source_bone.name]

    clean_name = clean_bone_name(source_bone.name)

    if clean_name in target_pose.bones:
        return target_pose.bones[clean_name]

    clean_lower = clean_name.lower()

    for target_bone in target_pose.bones:
        if clean_bone_name(target_bone.name).lower() == clean_lower:
            return target_bone

    return None


def get_source_and_target():
    armatures = [
        obj
        for obj in bpy.context.selected_objects
        if obj.type == 'ARMATURE'
    ]

    if len(armatures) != 2:
        raise RuntimeError(
            "Select exactly two armatures: SOURCE first, TARGET last."
        )

    target = bpy.context.view_layer.objects.active

    if target is None or target.type != 'ARMATURE':
        raise RuntimeError("The active object must be the TARGET armature.")

    source = next(obj for obj in armatures if obj != target)
    return source, target


def set_scene_time(scene, frame):
    """Evaluate a whole or fractional source frame exactly."""
    whole_frame = int(frame)
    scene.frame_set(whole_frame, subframe=frame - whole_frame)
    bpy.context.view_layer.update()


def evenly_spaced_frames(frame_start, frame_end, count):
    """Return `count` inclusive samples, supporting arbitrary action lengths."""
    if count < 2:
        raise ValueError("SAMPLED_FRAME_COUNT must be at least 2.")

    if frame_end < frame_start:
        raise ValueError("Source Action has an invalid frame range.")

    span = frame_end - frame_start
    return [frame_start + span * index / (count - 1) for index in range(count)]


def create_target_action(name, target):
    """Create an Action with an explicit slot compatible with the target."""
    action = bpy.data.actions.new(name)
    action.slots.new(target.id_type, target.name)
    action.use_fake_user = True
    return action


def assign_target_action(target, action):
    """Assign an action and its compatible object slot to the target."""
    animation_data = target.animation_data
    animation_data.action = action

    if not animation_data.action_suitable_slots:
        raise RuntimeError(
            f"Action '{action.name}' has no slot compatible with {target.name}."
        )

    animation_data.action_slot = animation_data.action_suitable_slots[0]


def key_pose_channels(pose_bone, key_frame):
    """Key a pose bone's transform channels in the current target Action."""
    pose_bone.keyframe_insert(
        data_path="location",
        frame=key_frame,
        group=pose_bone.name,
    )

    if pose_bone.rotation_mode == 'QUATERNION':
        rotation_path = "rotation_quaternion"
    elif pose_bone.rotation_mode == 'AXIS_ANGLE':
        rotation_path = "rotation_axis_angle"
    else:
        rotation_path = "rotation_euler"

    pose_bone.keyframe_insert(
        data_path=rotation_path,
        frame=key_frame,
        group=pose_bone.name,
    )
    pose_bone.keyframe_insert(
        data_path="scale",
        frame=key_frame,
        group=pose_bone.name,
    )


def bake_root_motion_to_spine(source, target, source_root, target_root):
    """Put source object motion and root pose into target spine in world space.

    ``PoseBone.matrix`` is in armature-object space.  The source root's world
    pose is therefore ``source.matrix_world @ source_root.matrix``.  Express
    that world pose in the target armature's object space, then convert it to
    the target root's basis transform for normal pose-channel keying.
    """
    source_root_world = source.matrix_world @ source_root.matrix
    target_root_pose = target.matrix_world.inverted_safe() @ source_root_world

    # The target spine is deliberately required to be a hierarchy root, so no
    # animated parent matrix can alter this world-space transfer.
    target_root.matrix_basis = target_root.bone.convert_local_to_pose(
        target_root_pose,
        target_root.bone.matrix_local,
        invert=True,
    )


def key_pose_transforms(source, target, bone_map, source_root_name, key_frame):
    target_root = target.pose.bones[ROOT_MOTION_TARGET_BONE]
    source_root = source.pose.bones[source_root_name]

    bake_root_motion_to_spine(source, target, source_root, target_root)
    key_pose_channels(target_root, key_frame)

    for source_name, target_name in bone_map.items():
        if target_name == ROOT_MOTION_TARGET_BONE:
            continue

        src = source.pose.bones[source_name]
        dst = target.pose.bones[target_name]

        # Copy the pose transform relative to the target bone's rest pose.
        dst.matrix_basis = src.matrix_basis.copy()
        key_pose_channels(dst, key_frame)


def bake_action(source, target, action, bone_map, source_root_name, samples):
    """Bake source frames into action using (source_frame, target_frame) pairs."""
    scene = bpy.context.scene
    assign_target_action(target, action)

    for source_frame, target_frame in samples:
        set_scene_time(scene, source_frame)

        key_pose_transforms(
            source,
            target,
            bone_map,
            source_root_name,
            target_frame,
        )


# ------------------------------------------------------------
# GET SOURCE / TARGET
# ------------------------------------------------------------

source, target = get_source_and_target()

if not source.animation_data:
    raise RuntimeError(f"{source.name} has no animation data.")

source_action = source.animation_data.action

if not source_action:
    raise RuntimeError(f"{source.name} has no active Action.")


# ------------------------------------------------------------
# FRAME RANGE / BONE MAP
# ------------------------------------------------------------

frame_start = int(source_action.frame_range[0])
frame_end = int(source_action.frame_range[1])

bone_map = {}
unmatched = []

for src_bone in source.pose.bones:
    dst_bone = find_target_bone(src_bone, target.pose)

    if dst_bone:
        bone_map[src_bone.name] = dst_bone.name
    else:
        unmatched.append(src_bone.name)

source_root_name = next(
    (
        source_name
        for source_name, target_name in bone_map.items()
        if target_name == ROOT_MOTION_TARGET_BONE
    ),
    None,
)

if source_root_name is None:
    raise RuntimeError(
        f"No source pose bone maps to required root-motion bone "
        f"'{ROOT_MOTION_TARGET_BONE}'."
    )

target_root = target.pose.bones[ROOT_MOTION_TARGET_BONE]
if target_root.parent is not None:
    raise RuntimeError(
        f"Root-motion bone '{ROOT_MOTION_TARGET_BONE}' must have no parent; "
        f"its parent is '{target_root.parent.name}'."
    )


# ------------------------------------------------------------
# CREATE BOTH TARGET ACTIONS
# ------------------------------------------------------------

target.animation_data_create()

full_action = create_target_action(source_action.name + ACTION_SUFFIX, target)
sampled_action = create_target_action(
    source_action.name + SAMPLED_ACTION_SUFFIX,
    target,
)

# Only one action can be active on the armature. The fake user keeps the
# inactive sampled action through saving.

sampled_source_frames = evenly_spaced_frames(
    frame_start,
    frame_end,
    SAMPLED_FRAME_COUNT,
)
sampled_action["source_action"] = source_action.name
sampled_action["source_frame_samples"] = list(sampled_source_frames)

for action in (full_action, sampled_action):
    action["root_motion_target_bone"] = ROOT_MOTION_TARGET_BONE
    action["root_motion_source_bone"] = source_root_name
    action["source_object_motion_baked_to_root"] = True


# ------------------------------------------------------------
# REPORT
# ------------------------------------------------------------

print("\n" + "=" * 60)
print("COPYING ANIMATION")
print("=" * 60)
print("Source:              ", source.name)
print("Target:              ", target.name)
print("Source Action:       ", source_action.name)
print("Full Action:         ", full_action.name)
print("7-frame Action:      ", sampled_action.name)
print("Full frames:         ", frame_start, "-", frame_end)
print("Sample source frames:", ", ".join(f"{frame:.3f}" for frame in sampled_source_frames))
print("Sample target frames: 1 -", SAMPLED_FRAME_COUNT)
print("Root-motion source bone:", source_root_name)
print("Root-motion target bone:", ROOT_MOTION_TARGET_BONE)
print("Target object transforms: unchanged (baked to root bone)")
print()
print("Matched bones:", len(bone_map))
print("Unmatched:    ", len(unmatched))


# ------------------------------------------------------------
# BAKE BOTH VERSIONS
# ------------------------------------------------------------

scene = bpy.context.scene
original_frame = scene.frame_current_final

full_samples = [
    (frame, frame)
    for frame in range(frame_start, frame_end + 1, FRAME_STEP)
]
sampled_samples = [
    (source_frame, index + 1)
    for index, source_frame in enumerate(sampled_source_frames)
]

bake_action(
    source,
    target,
    full_action,
    bone_map,
    source_root_name,
    full_samples,
)
bake_action(
    source,
    target,
    sampled_action,
    bone_map,
    source_root_name,
    sampled_samples,
)


# ------------------------------------------------------------
# TIMELINE / FINAL REPORT
# ------------------------------------------------------------

scene.frame_start = frame_start
scene.frame_end = frame_end

# Leave the complete copy active; the seven-frame version remains available in
# the Action Editor and is protected by its fake user.
assign_target_action(target, full_action)
set_scene_time(scene, original_frame)

print()
print("=" * 60)
print("FINISHED")
print("=" * 60)
print("Created full Action:    ", full_action.name)
print("Created 7-frame Action: ", sampled_action.name)

if unmatched:
    print("\nUNMATCHED SOURCE BONES:")
    for name in unmatched:
        print("   ", name)

print("=" * 60)
