bl_info = {
    "name": "Rigify Clean Human Rebuild",
    "author": "OpenAI",
    "version": (1, 0, 0),
    "blender": (5, 2, 1),
    "location": "View3D > Sidebar > Rigify Rebuild",
    "description": "Safely rebuild a fitted metarig onto a pristine Rigify Human rig",
    "category": "Rigging",
}

"""A conservative migration aid for meshes weighted to a fitted metarig.

It deliberately never copies Rigify metadata from the reference armature.  The
only fitting data copied is matching EditBone head, tail and roll.  Rigify 5.2.1
generates DEF bones by prefix and marks only those bones use_deform (see
rigify/generate.py and rigify/utils/naming.py); both facts are checked at runtime.
"""

import bpy
import math
from bpy.props import BoolProperty, EnumProperty, PointerProperty, StringProperty
from mathutils import Quaternion, Vector


REPORT_LIMIT = 80
SCENE_REPORT_KEY = "rigify_clean_rebuild_report"
FK_TEST_ACTION_NAME = "RigifyRebuild_FK_Weight_Test"
FK_TEST_ACTION_TAG = "rigify_clean_rebuild_fk_weight_test"
FK_TEST_ACTION_PROP = "rigify_clean_rebuild_fk_test_action"
FK_TEST_PREVIOUS_ACTION_PROP = "rigify_clean_rebuild_fk_previous_action"
FK_TEST_NLA_MUTE_PROP = "rigify_clean_rebuild_fk_previous_mute"
FK_TEST_MARKER_PREFIX = "[RCR FK]"
FK_TEST_FRAMES_PER_STEP = 5
FK_TEST_ROTATION_DEGREES = 45.0
FK_TEST_AXES = ('X', 'Y', 'Z')
ONE_NECK_PROP = "rigify_clean_rebuild_one_neck"


def _log(scene, title, lines):
    """Store a bounded, UI-visible report and print the complete diagnostic."""
    full = [title, *lines]
    print("\n[Rigify Clean Rebuild] " + "\n[Rigify Clean Rebuild] ".join(full))
    shown = full[:REPORT_LIMIT]
    if len(full) > REPORT_LIMIT:
        shown.append("... %d additional line(s); see Blender System Console." % (len(full) - REPORT_LIMIT))
    scene[SCENE_REPORT_KEY] = "\n".join(shown)


def _armature_poll(_self, obj):
    return obj is not None and obj.type == 'ARMATURE'


def _mesh_poll(_self, obj):
    return obj is not None and obj.type == 'MESH'


def _activate(context, obj, mode='OBJECT'):
    if context.object and context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    for item in context.view_layer.objects:
        item.select_set(False)
    obj.hide_set(False)
    obj.select_set(True)
    context.view_layer.objects.active = obj
    if mode != 'OBJECT':
        bpy.ops.object.mode_set(mode=mode)


def _require_rigify():
    try:
        from rigify.metarigs import human  # Installed Rigify implementation.
        return human
    except ImportError as exc:
        raise RuntimeError("Rigify is not enabled. Enable the bundled Rigify extension, then retry.") from exc


def _reference(scene):
    obj = scene.rigify_rebuild_reference
    if not obj or obj.type != 'ARMATURE':
        raise RuntimeError("Choose the old fitted metarig as Reference Armature.")
    return obj


def _clean(scene):
    obj = scene.rigify_rebuild_clean_metarig
    if not obj or obj.type != 'ARMATURE':
        raise RuntimeError("Create the clean metarig first.")
    return obj


def _generated(scene):
    obj = scene.rigify_rebuild_generated_rig
    if not obj or obj.type != 'ARMATURE':
        raise RuntimeError("Generate the clean Rigify rig first.")
    return obj


def _mesh_targets(context):
    scene = context.scene
    targets = [obj for obj in context.selected_objects if obj.type == 'MESH']
    chosen = scene.rigify_rebuild_character_mesh
    if chosen and chosen.type == 'MESH' and chosen not in targets:
        targets.append(chosen)
    if not targets and context.active_object and context.active_object.type == 'MESH':
        targets.append(context.active_object)
    if not targets:
        raise RuntimeError("Select one or more character meshes, or choose Character Mesh.")
    return targets


def _is_def_bone(rig, bone):
    # Rigify Generator.__assign_layers: DEF prefix => use_deform. Check both.
    return bone is not None and bone.name.startswith("DEF-") and bone.use_deform


def _safe_mapping_for_mesh(mesh, source_armature, rig, scene=None):
    """Return mapping and classifications without inferring one-to-many matches.

    A direct destination is accepted only after runtime confirmation that it is a
    real generated DEF bone.  This is intentionally stricter than stripping or
    adding prefixes blindly.
    """
    source_bones = set(source_armature.data.bones.keys())
    def_bones = {bone.name: bone for bone in rig.data.bones if _is_def_bone(rig, bone)}
    safe, complex_, unmatched, ignored = [], [], [], []
    one_neck = bool(scene and scene.get(ONE_NECK_PROP, False))
    one_neck_remap = {
        # Intentional migration after deleting clean spine.004: these are not
        # naming guesses. See RIGIFYREBUILD_OT_simplify_one_neck below.
        'spine.004': 'DEF-spine.005',
        'spine.005': 'DEF-spine.006',
    }
    for group in mesh.vertex_groups:
        name = group.name
        if name not in source_bones:
            ignored.append(name)
            continue
        if not source_armature.data.bones[name].use_deform:
            ignored.append(name + " (reference bone is non-deforming)")
            continue
        if one_neck and name == 'spine.006':
            unmatched.append(name + " (one-neck migration requires an explicit decision)")
            continue
        if one_neck and name in one_neck_remap:
            destination = one_neck_remap[name]
            if destination in def_bones:
                safe.append((name, destination))
            else:
                unmatched.append(name + " (expected %s is not a generated DEF bone)" % destination)
            continue
        exact = "DEF-" + name
        if exact in def_bones:
            # Rigify naming.py deformer() creates this direct form. Runtime
            # presence and use_deform make it an actual safe generated target.
            safe.append((name, exact))
            continue
        # A DEF name carrying the source as a whole component is a diagnostic
        # only; it is never selected as a transfer destination in version 1.
        related = [n for n in def_bones if n[4:] == name or n[4:].startswith(name + ".") or n[4:].startswith(name + "_")]
        if related:
            complex_.append((name, related))
        else:
            unmatched.append(name)
    return safe, complex_, unmatched, ignored


def _all_mesh_mappings(context):
    source = _reference(context.scene)
    rig = _generated(context.scene)
    return [(mesh, *_safe_mapping_for_mesh(mesh, source, rig, context.scene)) for mesh in _mesh_targets(context)]


def _weight(group, index):
    try:
        return group.weight(index)
    except RuntimeError:
        return 0.0


def _copy_safe_weights(mesh, safe, policy):
    """Copy numerical values exactly; no normalization and no source deletion."""
    copied, skipped, validation = [], [], []
    vertex_count = len(mesh.data.vertices)
    for source_name, dest_name in safe:
        source = mesh.vertex_groups.get(source_name)
        dest = mesh.vertex_groups.get(dest_name)
        if dest and policy == 'SKIP':
            skipped.append((source_name, dest_name, "destination exists"))
            continue
        if dest and policy == 'REPLACE':
            mesh.vertex_groups.remove(dest)
            dest = None
        if not dest:
            dest = mesh.vertex_groups.new(name=dest_name)
        # MERGE means add source values to existing values; use REPLACE instead
        # when exact equality with source is desired.
        for vertex in mesh.data.vertices:
            value = _weight(source, vertex.index)
            if value:
                dest.add([vertex.index], value, 'ADD' if policy == 'MERGE' else 'REPLACE')
            elif policy != 'MERGE':
                # A newly-created group has no zero entries; existing groups in
                # Replace mode were removed above, so this preserves zero exactly.
                pass
        max_diff, mismatches = 0.0, 0
        for vertex in mesh.data.vertices:
            diff = abs(_weight(source, vertex.index) - _weight(dest, vertex.index))
            max_diff = max(max_diff, diff)
            if diff > 1e-7:
                mismatches += 1
        validation.append((source_name, dest_name, vertex_count, mismatches, max_diff))
        copied.append((source_name, dest_name))
    return copied, skipped, validation


def _switch_armature_modifier(mesh, old_armature, new_rig):
    matches = [mod for mod in mesh.modifiers if mod.type == 'ARMATURE' and mod.object == old_armature]
    if not matches:
        return "no Armature modifier targeting %s" % old_armature.name
    for modifier in matches:
        modifier.object = new_rig
    return "switched %d existing Armature modifier(s)" % len(matches)


def _validate_controls(rig):
    """Verify controls, not just bone collection labels.

    get_limb_generated_names is Rigify's own name derivation for generated
    limbs. super_finger.py names a master control from each first ORG finger.
    """
    try:
        from rigify.rigs.utils import get_limb_generated_names
    except ImportError as exc:
        raise RuntimeError("Rigify is unavailable for generated-control validation.") from exc
    bones = rig.pose.bones
    failures, successes = [], []
    # rigs/utils.py documents the exact control names for an arm/leg chain.
    # Its get_limb_generated_names() helper is useful when generated ORG bones
    # retain the generic limbs.super_limb type, but the Human metarig uses the
    # specialized limbs.arm/limbs.leg types. Use the known Human chain names
    # below as the authoritative fallback rather than treating collections as
    # evidence of controls.
    limbs = get_limb_generated_names(rig)
    for side in ('.L', '.R'):
        arm_entries = [entry for key, entry in limbs.items() if entry and entry.get('limb_type') == 'arm' and key.endswith(side)]
        leg_entries = [entry for key, entry in limbs.items() if entry and entry.get('limb_type') == 'leg' and key.endswith(side)]
        fallback = {
            "arm" + side: {"upper_arm_ik" + side, "upper_arm_fk" + side,
                            "forearm_fk" + side, "hand_fk" + side,
                            "hand_ik" + side, "upper_arm_ik_target" + side},
            "leg" + side: {"thigh_ik" + side, "thigh_fk" + side,
                            "shin_fk" + side, "foot_fk" + side,
                            "foot_ik" + side, "thigh_ik_target" + side},
        }
        for label, entries in (("arm" + side, arm_entries), ("leg" + side, leg_entries)):
            expected = (set(entries[0]['controls']) | set(entries[0]['ik_ctrl'])) if entries else fallback[label]
            missing = sorted(name for name in expected if name not in bones)
            (failures if missing else successes).append("%s: %s" % (label, ", ".join(missing) if missing else "controls present"))
    finger_orgs = [pb for pb in bones if pb.rigify_type == 'limbs.super_finger']
    if not finger_orgs:
        failures.append("no generated limbs.super_finger ORG bones")
    else:
        for pb in finger_orgs:
            source = pb.name[4:] if pb.name.startswith('ORG-') else pb.name
            # naming.make_derived_name(source, 'ctrl', '_master') puts suffix before .L/.R.
            stem, dot, side = source.rpartition('.')
            master = (stem + "_master." + side) if dot and side in {'L', 'R'} else source + "_master"
            if master not in bones:
                failures.append("finger master absent: %s" % master)
        if not any(line.startswith("finger master") for line in failures):
            successes.append("fingers: %d master controls present" % len(finger_orgs))
    # Human's basic_spine generator produces torso controls; require actual,
    # non-ORG/MCH/DEF pose bones containing hips and chest rather than a collection.
    # Iterating bpy_prop_collection[PoseBone] yields PoseBone objects, not
    # strings; inspect their names when filtering non-control prefixes.
    controls = [bone.name for bone in bones if not bone.name.startswith(('ORG-', 'MCH-', 'DEF-'))]
    if not any('hips' in name for name in controls) or not any('chest' in name for name in controls):
        failures.append("torso: expected generated hips and chest controls are absent")
    else:
        successes.append("torso/spine: hips and chest controls present")
    return failures, successes


def _vertex_group_stats(mesh, name):
    group = mesh.vertex_groups.get(name)
    if not group:
        return 0, 0.0, 0.0
    values = [_weight(group, vertex.index) for vertex in mesh.data.vertices]
    nonzero = [value for value in values if value > 1e-7]
    return len(nonzero), sum(nonzero), max(nonzero, default=0.0)


class RIGIFYREBUILD_OT_simplify_one_neck(bpy.types.Operator):
    """Make the clean Human Super Head chain neck + head rather than neck + neck + head."""
    bl_idname = "rigify_rebuild.simplify_one_neck"
    bl_label = "2b. Simplify Clean Metarig to One Neck"
    bl_options = {'REGISTER', 'UNDO'}

    def invoke(self, context, event):
        return context.window_manager.invoke_confirm(self, event)

    def execute(self, context):
        try:
            _require_rigify()
            scene, clean = context.scene, _clean(context.scene)
            if scene.get(ONE_NECK_PROP, False):
                raise RuntimeError("The clean metarig is already configured for one neck bone.")
            for required in ('spine.003', 'spine.004', 'spine.005', 'spine.006'):
                if required not in clean.data.bones:
                    raise RuntimeError("Clean metarig is missing %s; refusing one-neck migration." % required)

            # Do not guess about the old head group. If it has paint, moving or
            # merging it requires an explicit artistic decision from the user.
            source_006 = []
            for mesh in _mesh_targets(context):
                count, total, maximum = _vertex_group_stats(mesh, 'spine.006')
                if count:
                    source_006.append("%s: vertices=%d total=%.6g max=%.6g" % (mesh.name, count, total, maximum))
            if source_006:
                _log(scene, "One-neck migration blocked", [
                    "Old spine.006 has nonzero weights and cannot be safely auto-routed.",
                    *source_006,
                    "No armature, mesh, or vertex group was changed.",
                ])
                raise RuntimeError("Old spine.006 has weights; see report. No changes were made.")

            # Rigify's own parameter-copy helper moves the pristine clean
            # super_head settings (including connect_chain and collection refs)
            # from the soon-to-be-deleted root onto spine.005. It never reads
            # metadata from the old reference metarig.
            from rigify.operators.copy_mirror_parameters import copy_rigify_params
            _activate(context, clean)
            old_root = clean.pose.bones['spine.004']
            new_root = clean.pose.bones['spine.005']
            if not copy_rigify_params(old_root, new_root):
                raise RuntimeError("Could not copy pristine Super Head parameters within the clean metarig.")
            for collection in old_root.bone.collections:
                collection.assign(new_root.bone)

            _activate(context, clean, 'EDIT')
            eb = clean.data.edit_bones
            spine_003, spine_004 = eb['spine.003'], eb['spine.004']
            spine_005, spine_006 = eb['spine.005'], eb['spine.006']
            old_004 = (spine_004.head.copy(), spine_004.tail.copy(), spine_004.roll)
            old_005 = (spine_005.head.copy(), spine_005.tail.copy(), spine_005.roll)
            # Requested positional shift: former .004 becomes the one neck;
            # former .005 becomes the head. .004 is then removed from the chain.
            spine_005.parent = spine_003
            spine_005.use_connect = False
            spine_005.head, spine_005.tail, spine_005.roll = old_004
            spine_006.parent = spine_005
            spine_006.use_connect = True
            spine_006.head, spine_006.tail, spine_006.roll = old_005
            eb.remove(spine_004)
            bpy.ops.object.mode_set(mode='OBJECT')

            scene[ONE_NECK_PROP] = True
            # rig_CLEAN remains in the file as an old generated artifact, but
            # transfer is blocked until the user deliberately regenerates it.
            scene.rigify_rebuild_generated_rig = None
            _log(scene, "One-neck clean metarig migration complete", [
                "Removed clean spine.004 from the Super Head chain.",
                "Clean spine.005 is now the one neck at former spine.004; clean spine.006 is the head at former spine.005.",
                "Future safe mapping: old spine.004 -> DEF-spine.005; old spine.005 -> DEF-spine.006.",
                "Old spine.006 had no weights on selected meshes; it was not transferred.",
                "Regenerate rig_CLEAN before analyzing or creating a new test mesh.",
            ])
            self.report({'INFO'}, "One-neck metarig prepared; regenerate rig_CLEAN next")
            return {'FINISHED'}
        except Exception as exc:
            if context.object and context.object.mode != 'OBJECT':
                bpy.ops.object.mode_set(mode='OBJECT')
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}


def _fk_test_action(rig):
    """Find only an action explicitly created and tagged by this addon."""
    name = rig.get(FK_TEST_ACTION_PROP, "")
    action = bpy.data.actions.get(name) if name else None
    return action if action and action.get(FK_TEST_ACTION_TAG) else None


def _is_fk_test_active(rig):
    action = _fk_test_action(rig)
    return bool(action and rig.animation_data and rig.animation_data.action == action)


def _fk_weight_test_bones(rig):
    """Return FK controls in a root-to-branch order, including direct fingers.

    Rigify limb_rigs.py uses the ``_fk`` suffix for normal limb controls. Its
    super_finger.py creates its FK control chain with direct derived names, so
    the direct controls corresponding to generated ORG finger chains are also
    included. The order walks generated ORG ancestry instead of sorting text:
    spine continuation first, then right branches, then left branches. MCH/ORG/
    DEF bones can never enter this result.
    """
    pose = rig.pose.bones
    eligible = {pb.name: pb for pb in pose
                if '_fk' in pb.name and not pb.name.startswith(('ORG-', 'MCH-', 'DEF-'))}

    # Direct-name controls created by the installed Human rig types:
    # BaseSpineRig -> torso; basic_spine -> hips/chest;
    # super_head -> neck/neck_bend/head. Add only controls actually present.
    for name in ('torso', 'hips', 'chest', 'neck', 'neck_bend', 'head'):
        control = pose.get(name)
        if control and not control.name.startswith(('ORG-', 'MCH-', 'DEF-')):
            eligible[name] = control

    # human.py assigns basic.super_copy to both shoulders. That Rig's
    # generate_bones() copies its control with the unprefixed ORG name.
    for pb in pose:
        if pb.name.startswith('ORG-') and pb.rigify_type == 'basic.super_copy':
            direct = pose.get(pb.name[4:])
            if direct and not direct.name.startswith(('ORG-', 'MCH-', 'DEF-')):
                eligible[direct.name] = direct

    def walk_org_chain(bone, visited):
        if bone.name in visited:
            return
        visited.add(bone.name)
        if bone.name.startswith('ORG-'):
            direct = pose.get(bone.name[4:])
            if direct and not direct.name.startswith(('ORG-', 'MCH-', 'DEF-')):
                eligible[direct.name] = direct
        for child in bone.children:
            if child.name.startswith('ORG-'):
                walk_org_chain(child, visited)

    # A super_finger rig is rooted at the first generated ORG finger bone.
    for pb in pose:
        if pb.name.startswith('ORG-') and pb.rigify_type == 'limbs.super_finger':
            walk_org_chain(pb.bone, set())

    def branch_key(bone):
        """Human metarig traversal: spine, right branch, left branch, name.

        The Human metarig source names finger chains f_index/f_middle/f_ring/
        f_pinky/thumb. Giving those a fixed rank avoids alphabetic thumb-first
        grouping and keeps one finger's .01/.02/.03 chain together.
        """
        name = bone.name[4:] if bone.name.startswith('ORG-') else bone.name
        if name.startswith('spine'):
            primary = 0
        elif name.endswith('.R'):
            primary = 1
        elif name.endswith('.L'):
            primary = 2
        else:
            primary = 3
        finger_rank = next((index for index, token in enumerate(
            ('f_index', 'f_middle', 'f_ring', 'f_pinky', 'thumb')) if name.startswith(token)), 99)
        segment = name.split('.')[1] if name.startswith(('f_', 'thumb')) and name.count('.') >= 2 else ''
        return primary, finger_rank, name.rsplit('.', 1)[0] if segment else name, segment, name

    def fk_name_for_org(name):
        stem, separator, side = name.rpartition('.')
        return stem + '_fk.' + side if separator and side in {'L', 'R'} else name + '_fk'

    ordered, visited_controls, visited_orgs = [], set(), set()

    def add_if_eligible(name):
        if name in eligible and name not in visited_controls:
            ordered.append(eligible[name])
            visited_controls.add(name)

    def walk_hierarchy(bone):
        if bone.name in visited_orgs:
            return
        visited_orgs.add(bone.name)
        source_name = bone.name[4:]
        source_pose = pose.get(bone.name)
        if source_pose and source_pose.rigify_type == 'spines.basic_spine':
            # basic_spine.py makes these named master/end controls.
            add_if_eligible('hips')
            add_if_eligible('chest')
        elif source_pose and source_pose.rigify_type == 'spines.super_head':
            # super_head.py makes these named controls, not *_fk controls.
            add_if_eligible('neck')
            add_if_eligible('neck_bend')
            add_if_eligible('head')
        elif source_pose and source_pose.rigify_type == 'basic.super_copy':
            add_if_eligible(source_name)
        add_if_eligible(fk_name_for_org(source_name))
        add_if_eligible(source_name)  # direct-name finger/toe end controls
        for child in sorted((child for child in bone.children if child.name.startswith('ORG-')), key=branch_key):
            walk_hierarchy(child)

    roots = [bone for bone in rig.data.bones if bone.name.startswith('ORG-')
             and (bone.parent is None or not bone.parent.name.startswith('ORG-'))]
    # BaseSpineRig creates torso as the top-level Human spine control.
    add_if_eligible('torso')
    for root in sorted(roots, key=branch_key):
        walk_hierarchy(root)

    # Rigify controls not traceable to an ORG hierarchy are still useful; put
    # them last instead of disrupting the anatomical test progression.
    for name in sorted(eligible):
        add_if_eligible(name)
    return ordered


def _set_test_rotation(pb, axis_name=None, angle=0.0):
    axis_vectors = {
        'X': Vector((1.0, 0.0, 0.0)),
        'Y': Vector((0.0, 1.0, 0.0)),
        'Z': Vector((0.0, 0.0, 1.0)),
    }
    if pb.rotation_mode == 'QUATERNION':
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0)) if axis_name is None else Quaternion(axis_vectors[axis_name], angle)
    elif pb.rotation_mode == 'AXIS_ANGLE':
        if axis_name is None:
            pb.rotation_axis_angle = (0.0, 0.0, 0.0, 1.0)
        else:
            axis = axis_vectors[axis_name]
            pb.rotation_axis_angle = (angle, axis.x, axis.y, axis.z)
    else:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        if axis_name:
            pb.rotation_euler[{'X': 0, 'Y': 1, 'Z': 2}[axis_name]] = angle


def _insert_test_rotation_key(pb, frame):
    path = 'rotation_quaternion' if pb.rotation_mode == 'QUATERNION' else (
        'rotation_axis_angle' if pb.rotation_mode == 'AXIS_ANGLE' else 'rotation_euler')
    pb.keyframe_insert(data_path=path, frame=frame)


def _make_fk_weight_test_action(context, rig):
    """Build and retain a self-contained FK test action and its timeline markers."""
    bones = _fk_weight_test_bones(rig)
    if not bones:
        raise RuntimeError("No Rigify FK controls were found on the generated rig.")
    action = bpy.data.actions.new(FK_TEST_ACTION_NAME)
    action[FK_TEST_ACTION_TAG] = True
    rig[FK_TEST_ACTION_PROP] = action.name
    adt = rig.animation_data_create()
    # Blender 5.2 actions are slot-based. The local API quickstart documents
    # creating a slot before assigning/keying the action.
    slot = action.slots.new(rig.id_type, rig.name)
    adt.action = action
    adt.action_slot = slot

    markers = context.scene.timeline_markers
    for marker in list(markers):
        if marker.name.startswith(FK_TEST_MARKER_PREFIX):
            markers.remove(marker)

    frame = 0
    amount = math.radians(FK_TEST_ROTATION_DEGREES)
    for pb in bones:
        for axis_name in FK_TEST_AXES:
            neutral_1 = frame
            positive = frame + FK_TEST_FRAMES_PER_STEP
            neutral_2 = frame + FK_TEST_FRAMES_PER_STEP * 2
            negative = frame + FK_TEST_FRAMES_PER_STEP * 3
            neutral_3 = frame + FK_TEST_FRAMES_PER_STEP * 4
            markers.new(name=f"{FK_TEST_MARKER_PREFIX} {pb.name} {axis_name}", frame=neutral_1)
            for test_axis, test_angle, test_frame in (
                (None, 0.0, neutral_1), (axis_name, amount, positive),
                (None, 0.0, neutral_2), (axis_name, -amount, negative),
                (None, 0.0, neutral_3),
            ):
                _set_test_rotation(pb, test_axis, test_angle)
                _insert_test_rotation_key(pb, test_frame)
            frame = neutral_3

    scene = context.scene
    scene.frame_start = 0
    scene.frame_end = frame
    scene.frame_preview_start = 0
    scene.frame_preview_end = frame
    scene.frame_set(0)
    return action, bones, frame


def _enable_fk_weight_test(context, rig):
    adt = rig.animation_data_create()
    previous = adt.action
    action = _fk_test_action(rig)
    if not action:
        # The builder assigns the action temporarily in order for Blender 5.2's
        # keyframe_insert API to create its action slot and keyframe channels.
        action, bones, end_frame = _make_fk_weight_test_action(context, rig)
    else:
        bones, end_frame = _fk_weight_test_bones(rig), context.scene.frame_end
    rig[FK_TEST_PREVIOUS_ACTION_PROP] = previous.name if previous else ""
    for track in adt.nla_tracks:
        track[FK_TEST_NLA_MUTE_PROP] = bool(track.mute)
        track.mute = True
    adt.action = action
    if action.slots:
        adt.action_slot = action.slots[0]
    context.scene.frame_set(context.scene.frame_start)
    return action, bones, end_frame


def _disable_fk_weight_test(rig):
    adt = rig.animation_data
    action = _fk_test_action(rig)
    if not adt or not action or adt.action != action:
        raise RuntimeError("The persistent FK weight-test action is not currently active.")
    previous_name = rig.get(FK_TEST_PREVIOUS_ACTION_PROP, "")
    adt.action = bpy.data.actions.get(previous_name) if previous_name else None
    for track in adt.nla_tracks:
        if FK_TEST_NLA_MUTE_PROP in track:
            track.mute = bool(track[FK_TEST_NLA_MUTE_PROP])
            del track[FK_TEST_NLA_MUTE_PROP]
    if FK_TEST_PREVIOUS_ACTION_PROP in rig:
        del rig[FK_TEST_PREVIOUS_ACTION_PROP]


class RIGIFYREBUILD_OT_toggle_fk_weight_test(bpy.types.Operator):
    bl_idname = "rigify_rebuild.toggle_fk_weight_test"
    bl_label = "Toggle FK Weight-Test Animation"
    bl_options = {'REGISTER', 'UNDO'}

    def execute(self, context):
        try:
            rig = _generated(context.scene)
            failures, _successes = _validate_controls(rig)
            if failures:
                raise RuntimeError("Generated-rig control validation failed; refusing to create a test action.")
            if _is_fk_test_active(rig):
                _disable_fk_weight_test(rig)
                _log(context.scene, "FK weight-test action disabled", [
                    "The persistent test action and its markers were retained.",
                    "The previously active action and NLA mute states were restored.",
                ])
                self.report({'INFO'}, "Restored the action active before the FK weight test")
            else:
                action, bones, end_frame = _enable_fk_weight_test(context, rig)
                _log(context.scene, "FK weight-test action enabled", [
                    "Action: %s" % action.name,
                    "FK controls tested: %d" % len(bones),
                    "Order: %s" % ", ".join(pb.name for pb in bones),
                    "Timeline: 0-%d; rotations: +/- %.1f degrees on X/Y/Z." % (end_frame, FK_TEST_ROTATION_DEGREES),
                    "Click this button again to restore the previous action; this test action remains saved.",
                ])
                self.report({'INFO'}, "Enabled persistent FK weight-test action")
            return {'FINISHED'}
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}


class RIGIFYREBUILD_OT_delete_fk_weight_test(bpy.types.Operator):
    bl_idname = "rigify_rebuild.delete_fk_weight_test"
    bl_label = "Delete FK Weight-Test Action"
    bl_options = {'REGISTER', 'UNDO'}

    def invoke(self, context, event):
        return context.window_manager.invoke_confirm(self, event)

    def execute(self, context):
        try:
            rig = _generated(context.scene)
            action = _fk_test_action(rig)
            if not action:
                raise RuntimeError("No FK weight-test action created by this addon exists on rig_CLEAN.")
            if _is_fk_test_active(rig):
                _disable_fk_weight_test(rig)
            for marker in list(context.scene.timeline_markers):
                if marker.name.startswith(FK_TEST_MARKER_PREFIX):
                    context.scene.timeline_markers.remove(marker)
            # A Blender 5.2 action can retain a user via its action slot even
            # after it is no longer the active action. This button has already
            # confirmed deletion and accepts only our explicit action tag, so
            # force-unlink this one action rather than rejecting a valid delete.
            bpy.data.actions.remove(action, do_unlink=True)
            if FK_TEST_ACTION_PROP in rig:
                del rig[FK_TEST_ACTION_PROP]
            if FK_TEST_PREVIOUS_ACTION_PROP in rig:
                del rig[FK_TEST_PREVIOUS_ACTION_PROP]
            _log(context.scene, "FK weight-test action deleted", [
                "Deleted only the action tagged by Rigify Clean Rebuild.",
                "Removed its [RCR FK] timeline markers.",
                "The prior action and NLA mute states are active again.",
            ])
            self.report({'INFO'}, "Deleted the addon-created FK weight-test action")
            return {'FINISHED'}
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}


class RIGIFYREBUILD_OT_create_clean(bpy.types.Operator):
    bl_idname = "rigify_rebuild.create_clean_human"
    bl_label = "1. Create Clean Human Metarig"
    bl_options = {'REGISTER', 'UNDO'}

    def execute(self, context):
        try:
            human = _require_rigify()
            reference = _reference(context.scene)
            _activate(context, reference)
            bpy.ops.object.armature_add()
            clean = context.active_object
            bpy.ops.object.mode_set(mode='EDIT')
            for bone in list(clean.data.edit_bones):
                clean.data.edit_bones.remove(bone)
            # Exact bundled factory, matching rigify/metarig_menu.py behavior.
            human.create(clean)
            bpy.ops.object.mode_set(mode='OBJECT')
            clean.name = "metarig_CLEAN"
            clean.data.name = "metarig_CLEAN"
            clean.matrix_world = reference.matrix_world.copy()
            clean.data.rigify_rig_basename = "rig_CLEAN"
            context.scene.rigify_rebuild_clean_metarig = clean
            context.scene.rigify_rebuild_generated_rig = None
            _log(context.scene, "Clean Human metarig created", [
                "Created via installed rigify.metarigs.human.create().",
                "Reference armature was not edited.",
                "Clean object matrix matched reference; no Rigify properties were copied.",
            ])
            self.report({'INFO'}, "Created pristine metarig_CLEAN")
            return {'FINISHED'}
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}


class RIGIFYREBUILD_OT_fit_clean(bpy.types.Operator):
    bl_idname = "rigify_rebuild.fit_clean_metarig"
    bl_label = "2. Fit Clean Metarig"
    bl_options = {'REGISTER', 'UNDO'}

    def execute(self, context):
        try:
            reference, clean = _reference(context.scene), _clean(context.scene)
            if any(abs(reference.matrix_world[row][column] - clean.matrix_world[row][column]) > 1e-6
                   for row in range(4) for column in range(4)):
                raise RuntimeError(
                    "Reference and clean metarig object transforms differ. "
                    "Refusing local EditBone transfer; recreate the clean metarig or restore matching transforms."
                )
            _activate(context, reference, 'EDIT')
            old_data = {bone.name: (bone.head.copy(), bone.tail.copy(), bone.roll) for bone in reference.data.edit_bones}
            bpy.ops.object.mode_set(mode='OBJECT')
            _activate(context, clean, 'EDIT')
            matched, unmatched = [], []
            for bone in clean.data.edit_bones:
                values = old_data.get(bone.name)
                if values is None:
                    unmatched.append(bone.name)
                    continue
                # Reference and clean have equal object transforms (set in step 1),
                # so local head/tail/roll safely retain the world-space fitting.
                bone.head, bone.tail, bone.roll = values
                matched.append(bone.name)
            bpy.ops.object.mode_set(mode='OBJECT')
            _activate(context, clean)
            _log(context.scene, "Metarig fit report", [
                "MATCHED (%d): %s" % (len(matched), ", ".join(matched)),
                "UNMATCHED (%d): %s" % (len(unmatched), ", ".join(unmatched) or "none"),
                "AMBIGUOUS (0): exact-name matching only; proximity was never used.",
                "Only EditBone head/tail/roll changed on metarig_CLEAN.",
            ])
            self.report({'INFO'}, "Fitted %d matching bones; inspect metarig_CLEAN" % len(matched))
            return {'FINISHED'}
        except Exception as exc:
            if context.object and context.object.mode != 'OBJECT':
                bpy.ops.object.mode_set(mode='OBJECT')
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}


class RIGIFYREBUILD_OT_generate(bpy.types.Operator):
    bl_idname = "rigify_rebuild.generate_clean_rig"
    bl_label = "3. Generate Clean Rig"
    bl_options = {'REGISTER', 'UNDO'}

    def execute(self, context):
        try:
            _require_rigify()
            clean = _clean(context.scene)
            _activate(context, clean)
            # This is Rigify UI's own supported generator operator (ui.py).
            result = bpy.ops.pose.rigify_generate()
            if 'FINISHED' not in result:
                raise RuntimeError("Rigify generation did not finish.")
            rig = clean.data.rigify_target_rig
            if not rig:
                raise RuntimeError("Rigify did not assign rigify_target_rig.")
            rig.name = "rig_CLEAN"
            rig.data.name = "rig_CLEAN"
            context.scene.rigify_rebuild_generated_rig = rig
            failures, successes = _validate_controls(rig)
            _log(context.scene, "Generated-rig control validation", successes + failures + [
                "STATUS: BLOCKED" if failures else "STATUS: PASS - weight analysis enabled.",
            ])
            if failures:
                self.report({'ERROR'}, "Generated rig is missing controls; see report/console. Weight transfer blocked.")
                return {'CANCELLED'}
            self.report({'INFO'}, "Generated rig passed major control checks")
            return {'FINISHED'}
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}


class RIGIFYREBUILD_OT_analyze(bpy.types.Operator):
    bl_idname = "rigify_rebuild.analyze_weights"
    bl_label = "4. Analyze Weight Transfer"
    bl_options = {'REGISTER'}

    def execute(self, context):
        try:
            rig = _generated(context.scene)
            failures, _successes = _validate_controls(rig)
            if failures:
                raise RuntimeError("Generated-rig control validation failed; weight transfer remains blocked.")
            lines = []
            for mesh, safe, complex_, unmatched, ignored in _all_mesh_mappings(context):
                lines.append("MESH %s" % mesh.name)
                lines += ["SAFE_ONE_TO_ONE %s -> %s" % item for item in safe]
                lines += ["COMPLEX %s -> %s" % (src, ", ".join(dst)) for src, dst in complex_]
                lines += ["UNMATCHED %s" % name for name in unmatched]
                lines += ["IGNORED %s" % name for name in ignored]
                lines.append("TOTALS safe=%d complex=%d unmatched=%d ignored=%d" % (len(safe), len(complex_), len(unmatched), len(ignored)))
            _log(context.scene, "Weight-transfer analysis", lines)
            self.report({'INFO'}, "Weight mapping analysis complete; see report/console")
            return {'FINISHED'}
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}


def _transfer(context, meshes, make_tests=False):
    scene, old_arm, rig = context.scene, _reference(context.scene), _generated(context.scene)
    failures, _ = _validate_controls(rig)
    if failures:
        raise RuntimeError("Generated-rig control validation failed; refusing transfer.")
    reports, targets = [], []
    for original in meshes:
        target = original.copy() if make_tests else original
        if make_tests:
            target.data = original.data.copy()  # independent object AND mesh datablock
            target.name = original.name + "_Rigify_TEST"
            target.data.name = original.data.name + "_Rigify_TEST"
            target["rigify_clean_rebuild_test"] = True
            for coll in original.users_collection:
                coll.objects.link(target)
        safe, complex_, unmatched, ignored = _safe_mapping_for_mesh(target, old_arm, rig, scene)
        copied, skipped, validation = _copy_safe_weights(target, safe, scene.rigify_rebuild_existing_policy)
        switch = _switch_armature_modifier(target, old_arm, rig)
        reports += ["MESH %s: copied=%d skipped=%d; %s" % (target.name, len(copied), len(skipped), switch)]
        reports += ["VALIDATE %s -> %s: vertices=%d mismatches=%d max_difference=%.9g" % row for row in validation]
        reports += ["SKIPPED %s -> %s: %s" % row for row in skipped]
        reports += ["UNRESOLVED complex=%d unmatched=%d ignored=%d (not copied)" % (len(complex_), len(unmatched), len(ignored))]
        targets.append(target)
    return targets, reports


def _is_test_mesh(obj):
    return bool(obj.get("rigify_clean_rebuild_test", False) or "_Rigify_TEST" in obj.name)


class RIGIFYREBUILD_OT_prune_legacy_test_groups(bpy.types.Operator):
    bl_idname = "rigify_rebuild.prune_legacy_test_groups"
    bl_label = "Prune Copied Legacy Groups From Test"
    bl_options = {'REGISTER', 'UNDO'}

    def invoke(self, context, event):
        return context.window_manager.invoke_confirm(self, event)

    def execute(self, context):
        try:
            selected = [obj for obj in context.selected_objects if obj.type == 'MESH' and _is_test_mesh(obj)]
            if not selected and context.active_object and context.active_object.type == 'MESH' and _is_test_mesh(context.active_object):
                selected = [context.active_object]
            if not selected:
                raise RuntimeError("Select an *_Rigify_TEST mesh. Original meshes are intentionally excluded.")
            source, rig, lines = _reference(context.scene), _generated(context.scene), []
            for mesh in selected:
                safe, _complex, _unmatched, _ignored = _safe_mapping_for_mesh(mesh, source, rig, context.scene)
                removed, skipped = [], []
                for source_name, destination_name in safe:
                    source_group = mesh.vertex_groups.get(source_name)
                    destination_group = mesh.vertex_groups.get(destination_name)
                    if not source_group or not destination_group:
                        skipped.append("%s (destination missing)" % source_name)
                        continue
                    maximum = max((abs(_weight(source_group, vertex.index) - _weight(destination_group, vertex.index))
                                   for vertex in mesh.data.vertices), default=0.0)
                    if maximum > 1e-7:
                        skipped.append("%s (destination differs; max %.9g)" % (source_name, maximum))
                        continue
                    mesh.vertex_groups.remove(source_group)
                    removed.append(source_name)
                lines.append("%s: removed %d copied legacy group(s): %s" %
                             (mesh.name, len(removed), ", ".join(removed) or "none"))
                lines += ["%s: kept %s" % (mesh.name, item) for item in skipped]
            _log(context.scene, "Legacy test-group cleanup", lines + [
                "Only numerically identical, successfully copied source groups were removed.",
                "Unmatched, complex, and original-mesh groups were retained.",
            ])
            self.report({'INFO'}, "Pruned verified legacy groups from %d test mesh(es)" % len(selected))
            return {'FINISHED'}
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}


class RIGIFYREBUILD_OT_create_test(bpy.types.Operator):
    bl_idname = "rigify_rebuild.create_test_character"
    bl_label = "5. Create Test Character"
    bl_options = {'REGISTER', 'UNDO'}

    def execute(self, context):
        try:
            targets, lines = _transfer(context, _mesh_targets(context), make_tests=True)
            _log(context.scene, "Test-character transfer", lines + ["Original objects and mesh datablocks were not changed."])
            self.report({'INFO'}, "Created %d independent Rigify test mesh(es)" % len(targets))
            return {'FINISHED'}
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}


class RIGIFYREBUILD_OT_convert_original(bpy.types.Operator):
    bl_idname = "rigify_rebuild.convert_original"
    bl_label = "Convert Original Character"
    bl_options = {'REGISTER', 'UNDO'}

    def invoke(self, context, event):
        return context.window_manager.invoke_confirm(self, event)

    def execute(self, context):
        try:
            _targets, lines = _transfer(context, _mesh_targets(context), make_tests=False)
            _log(context.scene, "Original-character conversion", lines + ["Source vertex groups were retained; no armature or weight group was deleted."])
            self.report({'INFO'}, "Original selected mesh(es) converted; source groups retained")
            return {'FINISHED'}
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}


class RIGIFYREBUILD_PT_panel(bpy.types.Panel):
    bl_label = "Rigify Clean Rebuild"
    bl_idname = "RIGIFYREBUILD_PT_panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'Rigify Rebuild'

    def draw(self, context):
        layout, scene = self.layout, context.scene
        layout.prop(scene, "rigify_rebuild_reference")
        layout.prop(scene, "rigify_rebuild_character_mesh")
        layout.label(text="Selected mesh objects are included.")
        layout.separator()
        layout.prop(scene, "rigify_rebuild_clean_metarig")
        layout.prop(scene, "rigify_rebuild_generated_rig")
        layout.separator()
        layout.operator(RIGIFYREBUILD_OT_create_clean.bl_idname)
        layout.operator(RIGIFYREBUILD_OT_fit_clean.bl_idname)
        layout.operator(RIGIFYREBUILD_OT_simplify_one_neck.bl_idname, icon='BONE_DATA')
        layout.operator(RIGIFYREBUILD_OT_generate.bl_idname)
        layout.operator(RIGIFYREBUILD_OT_analyze.bl_idname)
        layout.prop(scene, "rigify_rebuild_existing_policy", text="Existing DEF Groups")
        layout.operator(RIGIFYREBUILD_OT_create_test.bl_idname)
        layout.operator(RIGIFYREBUILD_OT_prune_legacy_test_groups.bl_idname, icon='TRASH')
        rig = scene.rigify_rebuild_generated_rig
        label = "Restore Previous Action" if rig and _is_fk_test_active(rig) else "Toggle FK Weight-Test Animation"
        layout.operator(RIGIFYREBUILD_OT_toggle_fk_weight_test.bl_idname, text=label, icon='ACTION')
        layout.operator(RIGIFYREBUILD_OT_delete_fk_weight_test.bl_idname, icon='TRASH')
        layout.separator()
        layout.operator(RIGIFYREBUILD_OT_convert_original.bl_idname, icon='ERROR')
        report = scene.get(SCENE_REPORT_KEY, "No report yet.")
        box = layout.box()
        box.label(text="Latest report (full report: System Console)")
        for line in report.splitlines()[:16]:
            box.label(text=line[:130])


CLASSES = (
    RIGIFYREBUILD_OT_simplify_one_neck,
    RIGIFYREBUILD_OT_create_clean, RIGIFYREBUILD_OT_fit_clean,
    RIGIFYREBUILD_OT_generate, RIGIFYREBUILD_OT_analyze,
    RIGIFYREBUILD_OT_create_test, RIGIFYREBUILD_OT_prune_legacy_test_groups,
    RIGIFYREBUILD_OT_convert_original,
    RIGIFYREBUILD_OT_toggle_fk_weight_test,
    RIGIFYREBUILD_OT_delete_fk_weight_test,
    RIGIFYREBUILD_PT_panel,
)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.rigify_rebuild_reference = PointerProperty(name="Reference Armature", type=bpy.types.Object, poll=_armature_poll)
    bpy.types.Scene.rigify_rebuild_character_mesh = PointerProperty(name="Character Mesh", type=bpy.types.Object, poll=_mesh_poll)
    bpy.types.Scene.rigify_rebuild_clean_metarig = PointerProperty(name="Clean Metarig", type=bpy.types.Object, poll=_armature_poll)
    bpy.types.Scene.rigify_rebuild_generated_rig = PointerProperty(name="Generated Rig", type=bpy.types.Object, poll=_armature_poll)
    bpy.types.Scene.rigify_rebuild_existing_policy = EnumProperty(
        name="Existing DEF Groups", items=[
            ('SKIP', "Skip Existing", "Default: preserve an existing destination group"),
            ('REPLACE', "Replace", "Replace an existing destination group with source weights"),
            ('MERGE', "Merge", "Add source weights to an existing destination group"),
        ], default='SKIP')


def unregister():
    for prop in ("rigify_rebuild_reference", "rigify_rebuild_character_mesh", "rigify_rebuild_clean_metarig", "rigify_rebuild_generated_rig", "rigify_rebuild_existing_policy"):
        delattr(bpy.types.Scene, prop)
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
