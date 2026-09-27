"""Procedurally build a smooth, sprite-readable stylized cowboy for Blender 5.2.

Run: blender --background --python scripts/generate_cowboy.py
The generator owns only the Cowboy_Generated collection and Cowboy_* materials,
so it is safe to rerun in an art scene containing unrelated work.
"""
import bpy
import math
import os
from mathutils import Vector

ROOT = "Cowboy_Generated"
OUT_BLEND = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "blender", "cowboy_generator.blend"))
OUT_RENDER = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "blender", "renders", "cowboy_sprite_48x64.png"))


def material(name, color, metallic=0.0, roughness=0.52):
    """Get or make one simple named Principled material."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return m


def make_materials():
    return {
        "skin": material("Cowboy_Skin", (0.82, 0.36, 0.19), 0, .5),
        "hair": material("Cowboy_Hair_Beard", (0.075, 0.027, 0.014), 0, .7),
        "hat": material("Cowboy_Hat_Brown", (0.20, 0.065, 0.022), 0, .62),
        "band": material("Cowboy_HatBand_Tan", (0.55, 0.26, 0.07), 0, .58),
        "red": material("Cowboy_Bandana_Red", (0.55, 0.018, 0.012), 0, .48),
        "cream": material("Cowboy_Shirt_Cream", (0.83, 0.68, 0.43), 0, .72),
        "vest": material("Cowboy_Vest_Leather", (0.15, 0.042, 0.012), 0, .53),
        "pants": material("Cowboy_Pants_Denim", (0.035, 0.13, 0.36), 0, .7),
        "belt": material("Cowboy_Belt_Leather", (0.10, 0.022, 0.008), 0, .48),
        "brass": material("Cowboy_Brass", (0.78, 0.39, 0.035), .72, .28),
        "boots": material("Cowboy_Boot_Leather", (0.16, 0.045, 0.012), 0, .48),
        "white": material("Cowboy_EyeWhite", (.95, .92, .80), 0, .42),
        "iris": material("Cowboy_Iris", (.025, .012, .006), 0, .35),
    }


def ensure_collection(name, parent=None):
    coll = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    owner = parent or bpy.context.scene.collection
    if coll.name not in owner.children:
        owner.children.link(coll)
    return coll


def clear_previous():
    old = bpy.data.collections.get(ROOT)
    if old:
        for obj in list(old.all_objects): bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)
    for obj in list(bpy.data.objects):
        if obj.name.startswith("Cowboy_Sprite") or obj.name.startswith("Cowboy_Key") or obj.name.startswith("Cowboy_Fill") or obj.name.startswith("Cowboy_Rim"):
            bpy.data.objects.remove(obj, do_unlink=True)


def link(obj, coll, part, **tags):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    coll.objects.link(obj)
    obj["cowboy_generated"] = True
    obj["cowboy_part"] = part
    for k, v in tags.items(): obj[k] = v
    return obj


def smooth(obj, subdiv=1, bevel=0.0):
    if obj.type == 'MESH':
        for p in obj.data.polygons: p.use_smooth = True
    if bevel:
        mod = obj.modifiers.new("Soft_Edges", 'BEVEL'); mod.width = bevel; mod.segments = 3
    if subdiv:
        mod = obj.modifiers.new("Subdivision", 'SUBSURF'); mod.levels = subdiv; mod.render_levels = subdiv
    return obj


def uv(name, loc, scale, mat, coll, part, subdiv=1, **tags):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale
    o.data.materials.append(mat); smooth(o, subdiv); return link(o, coll, part, **tags)


def cube(name, loc, scale, mat, coll, part, bevel=.04, **tags):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.object; o.name = name; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat); smooth(o, 0, bevel); return link(o, coll, part, **tags)


def cylinder_between(name, a, b, radius, mat, coll, part, **tags):
    a, b = Vector(a), Vector(b); d = b - a
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, location=(a+b)/2)
    o = bpy.context.object; o.name = name
    o.scale = (radius, radius, d.length/2 + radius*.12)
    o.rotation_mode = 'QUATERNION'; o.rotation_quaternion = Vector((0,0,1)).rotation_difference(d.normalized())
    o.data.materials.append(mat); smooth(o, 1); return link(o, coll, part, **tags)


def triangle_prism(name, points, depth, mat, coll, part, **tags):
    # The vertices are front-facing (-Y); this gives the scarf a deliberately solid edge.
    verts = [(x, -depth/2, z) for x,z in points] + [(x, depth/2, z) for x,z in points]
    faces = [(0,1,2), (5,4,3), (0,3,4,1), (1,4,5,2), (2,5,3,0)]
    mesh = bpy.data.meshes.new(name + "_Mesh"); mesh.from_pydata(verts, [], faces); mesh.materials.append(mat)
    o = bpy.data.objects.new(name, mesh); coll.objects.link(o); smooth(o, 0, .025)
    return link(o, coll, part, **tags)


def create_hand(side, wrist, coll, mats):
    sign = 1 if side == "Right" else -1
    hand = uv("Hand_"+side, wrist, (.19,.14,.22), mats['skin'], coll, "hand", 1, side=side, digit_count=5)
    # Fingers point down, remain individually spaced across X; thumb is deliberately splayed outward.
    for i, (dx, zoff, length) in enumerate([(-.10,.02,.15),(-.035,.00,.19),(.035,0,.20),(.10,.015,.175)]):
        p = (wrist[0] + dx*sign, wrist[1]-.012, wrist[2]+zoff)
        cylinder_between("Finger_%s_%d" % (side, i+1), p, (p[0]+dx*.12*sign, p[1]-.01, p[2]-length), .045 if i<3 else .04, mats['skin'], coll, "finger", side=side, finger=i+1)
    a = (wrist[0]+.16*sign, wrist[1], wrist[2]-.01); b = (wrist[0]+.28*sign, wrist[1]-.025, wrist[2]-.105)
    cylinder_between("Thumb_"+side, a, b, .055, mats['skin'], coll, "finger", side=side, finger="thumb")
    return hand


def create_boot(side, x, coll, mats):
    shaft = uv("BootShaft_"+side, (x,0, .38), (.25,.28,.40), mats['boots'], coll, "boot", 1, side=side)
    foot = uv("BootFoot_"+side, (x,-.16,.13), (.29,.47,.18), mats['boots'], coll, "boot", 1, side=side)
    heel = cube("BootHeel_"+side, (x,.18,.075), (.16,.17,.09), mats['boots'], coll, "boot", .035, side=side)
    # Raised outer edges make a clear V top without thin decorative seams.
    for s in (-1,1):
        v = cube("BootV_%s_%s"%(side,s), (x+s*.12,-.19,.68), (.075,.075,.055), mats['boots'], coll, "boot", .035, side=side)
        v.rotation_euler[1] = s*.55


def phase1(root, mats):
    body=ensure_collection("Body",root); hands=ensure_collection("Hands",root); boots=ensure_collection("Boots",root); hat=ensure_collection("Hat",root)
    # Scale: soles at Z=0, top of bare head around 2.33 m.  Broad forms intentionally favor the 48x64 sprite.
    uv("Pelvis", (0,.05,.95), (.38,.24,.27), mats['pants'], body, "pelvis", 1)
    uv("Torso", (0,.035,1.48), (.49,.27,.56), mats['cream'], body, "torso", 1)
    uv("Neck", (0,.02,1.91), (.15,.14,.20), mats['skin'], body, "neck", 1)
    uv("Head", (0,-.015,2.19), (.39,.34,.42), mats['skin'], body, "head", 1)
    for side, sign in (("Left",-1),("Right",1)):
        shoulder=(sign*.43,.02,1.72); elbow=(sign*.68,.025,1.48); wrist=(sign*.85,-.005,1.16)
        cylinder_between("UpperArm_"+side, shoulder, elbow, .145, mats['cream'], body, "upper_arm", side=side)
        cylinder_between("Forearm_"+side, elbow, wrist, .125, mats['cream'], body, "forearm", side=side)
        create_hand(side,wrist,hands,mats)
        hip=(sign*.22,.055,.92); knee=(sign*.25,.04,.54); ankle=(sign*.27,.02,.28)
        cylinder_between("Thigh_"+side,hip,knee,.20,mats['pants'],body,"thigh",side=side)
        cylinder_between("Shin_"+side,knee,ankle,.18,mats['pants'],body,"shin",side=side)
        create_boot(side,sign*.27,boots,mats)
    # Hat: central broad brim plus curled sides (all smooth beveled/subdivided pieces), crown and a separate band.
    uv("Hat", (0,.015,2.47), (.76,.47,.105), mats['hat'], hat, "hat", 1)
    for side, sign in (("Left",-1),("Right",1)):
        curl=uv("HatBrimCurl_"+side,(sign*.59,.02,2.54),(.28,.36,.14),mats['hat'],hat,"hat",1,side=side); curl.rotation_euler[1]=sign*.35
    uv("HatCrown",(0,.045,2.72),(.37,.29,.36),mats['hat'],hat,"hat",1)
    cube("HatBand",(0,-.005,2.55),(.39,.30,.055),mats['band'],hat,"hat_band",.035)


def phase2(root, mats):
    eyes=ensure_collection("Eyes",root); hair=ensure_collection("Hair",root); beard=ensure_collection("Beard",root); bandana=ensure_collection("Bandana",root); vest=ensure_collection("Vest",root); shirt=ensure_collection("Shirt",root)
    # Face is on negative Y because the sprite camera looks along +Y.
    for side, sign in (("Left",-1),("Right",1)):
        uv("EyeWhite_"+side,(sign*.145,-.326,2.23),(.105,.045,.095),mats['white'],eyes,"eye",1,side=side)
        uv("Pupil_"+side,(sign*.145,-.37,2.23),(.045,.022,.055),mats['iris'],eyes,"pupil",1,side=side)
        brow=cube("Eyebrow_"+side,(sign*.145,-.372,2.35),(.13,.028,.045),mats['hair'],beard,"eyebrow",.025,side=side); brow.rotation_euler[1]=sign*.18
        uv("Ear_"+side,(sign*.39,-.005,2.18),(.085,.07,.12),mats['skin'],hair,"ear",1,side=side)
        for n,z in enumerate((2.05,2.13,2.28)):
            uv("HairLock_%s_%d"%(side,n),(sign*.36,.08,z),(.10,.12,.13),mats['hair'],hair,"hair",1,side=side)
    uv("Nose",(0,-.405,2.18),(.10,.095,.13),mats['skin'],beard,"nose",1)
    uv("Mustache_Left",(-.105,-.415,2.075),(.15,.05,.06),mats['hair'],beard,"mustache",1)
    uv("Mustache_Right",(.105,-.415,2.075),(.15,.05,.06),mats['hair'],beard,"mustache",1)
    # This deliberately sits far ahead of the scarf (scarf front is y=-.31).
    uv("ChinBeard",(0,-.37,1.98),(.19,.075,.16),mats['hair'],beard,"beard",1)
    uv("JawBeard_Left",(-.21,-.31,2.00),(.10,.06,.16),mats['hair'],beard,"beard",1)
    uv("JawBeard_Right",(.21,-.31,2.00),(.10,.06,.16),mats['hair'],beard,"beard",1)
    scarf=triangle_prism("Bandana_Front",[(-.34,1.90),(.34,1.90),(0,1.58)],.075,mats['red'],bandana,"bandana")
    # Place the solid scarf in front of the vest; the beard remains farther forward.
    scarf.location.y=-.40
    uv("Bandana_Knot_Back",(0,.22,1.87),(.10,.08,.09),mats['red'],bandana,"bandana_knot",1,position="back")
    # Big rolled cuffs ensure sleeve read at sprite scale.
    for side,sign in (("Left",-1),("Right",1)):
        cuff=uv("RolledCuff_"+side,(sign*.76,.015,1.29),(.16,.155,.12),mats['cream'],shirt,"cuff",1,side=side)
    for side,sign in (("Left",-1),("Right",1)):
        panel=cube("VestPanel_"+side,(sign*.255,-.285,1.48),(.19,.052,.42),mats['vest'],vest,"vest_panel",.075,side=side)
        panel.rotation_euler[1] = sign*.05


def phase3(root, mats):
    belt=ensure_collection("Belt",root); loops=ensure_collection("BeltLoops",root); buckle=ensure_collection("Buckle",root); holster=ensure_collection("Holster",root); vest=ensure_collection("Vest",root)
    # Belt is one continuous visible dark-brown band; loops are separate denim material objects.
    cube("Belt",(0,-.01,1.085),(.405,.275,.07),mats['belt'],belt,"belt",.025)
    for i,x in enumerate((-.28,-.12,.12,.28)):
        loop=cube("BeltLoop_%d"%i,(x,-.285,1.09),(.033,.027,.14),mats['pants'],loops,"belt_loop",.012,material_requirement="pants")
    buckle_obj=cube("Buckle",(0,-.325,1.09),(.16,.045,.115),mats['brass'],buckle,"buckle",.035)
    # Holster is explicitly an empty three-sided shell, open at its top/front; no weapon geometry is generated.
    for name,loc,scale in (("Holster_Back",(.49,.05,.88),(.13,.045,.28)),("Holster_Outer",(.62,.05,.84),(.035,.07,.24)),("Holster_Inner",(.36,.05,.84),(.035,.07,.24))):
        cube(name,loc,scale,mats['belt'],holster,"holster",.035,side="Right",empty_holster=True)
    # Brass buttons strictly only on the character's right vest panel (viewer left in front view).
    for i,z in enumerate((1.60,1.43)):
        uv("VestButton_Right_%d"%i,(.18,-.36,z),(.06,.026,.06),mats['brass'],vest,"vest_button",1,side="Right")


def setup_sprite_camera(root):
    cam_data=bpy.data.cameras.new("Cowboy_SpriteCamera")
    cam=bpy.data.objects.new("Cowboy_SpriteCamera",cam_data); bpy.context.scene.collection.objects.link(cam)
    cam.location=(0,-8,1.52); cam.rotation_euler=(math.radians(90),0,0)
    # Track exact front without relying on UI context.
    cam.rotation_euler=(math.radians(90),0,0); cam.rotation_euler.rotate_axis('Z', math.radians(180))
    # Camera local -Z must point +Y. A quaternion makes this unambiguous.
    cam.rotation_mode='QUATERNION'; cam.rotation_quaternion=Vector((0,1,0)).to_track_quat('-Z','Y')
    # 6 m vertical coverage places the roughly 3.1 m hat-to-sole silhouette
    # at about 33 pixels in this 48x64 validation canvas.
    cam.data.type='ORTHO'; cam.data.ortho_scale=6.0; cam.data.lens=50
    cam["cowboy_generated"]=True; cam["cowboy_part"]="sprite_camera"; bpy.context.scene.camera=cam
    # Blender 5.2 exposes the Eevee Next renderer as BLENDER_EEVEE.
    scene=bpy.context.scene; scene.render.engine='BLENDER_EEVEE'; scene.render.resolution_x=48; scene.render.resolution_y=64; scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False
    scene.world.color=(.075,.075,.075)
    return cam


def setup_lighting(root):
    def area(name, loc, energy, size, color):
        data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.shape='DISK'; data.size=size; data.color=color
        o=bpy.data.objects.new(name,data); bpy.context.scene.collection.objects.link(o); o.location=loc
        o.rotation_mode='QUATERNION'; o.rotation_quaternion=(Vector((0,0,1.4))-o.location).to_track_quat('-Z','Y'); o['cowboy_generated']=True; return o
    area('Cowboy_Key',( -3,-4,5),850,4.0,(1.0,.78,.58)); area('Cowboy_Fill',(3,-3,3),380,5.0,(.55,.70,1.0)); area('Cowboy_Rim',(0,3,4),450,3.0,(1.0,.55,.25))


def render_sprite_preview(filepath=OUT_RENDER, scale=10):
    """Render the low-res PNG and save an exact pixel-repeated inspection image.

    This intentionally avoids Pillow: it must work in stock Blender Python and
    repeats every source RGBA pixel rather than using any image interpolation.
    """
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    bpy.context.scene.render.filepath=filepath
    # A generator may run in a user's work scene. Exclude only non-generator
    # objects for this validation render, then restore every visibility flag.
    hidden=[]
    for obj in bpy.context.scene.objects:
        if not obj.get("cowboy_generated"):
            hidden.append((obj, obj.hide_render)); obj.hide_render=True
    bpy.ops.render.render(write_still=True)
    for obj, was_hidden in hidden: obj.hide_render=was_hidden
    # Background/MCP renders may not retain a Render Result datablock, so read
    # the just-written PNG as the authoritative low-resolution source.
    src=bpy.data.images.load(filepath, check_existing=False)
    width, height=src.size
    src_pixels=list(src.pixels[:])
    target_name="Cowboy_NearestNeighborPreview"
    old=bpy.data.images.get(target_name)
    if old: bpy.data.images.remove(old)
    dst=bpy.data.images.new(target_name, width*scale, height*scale, alpha=True, float_buffer=False)
    out=[]
    for y in range(height):
        row=src_pixels[y*width*4:(y+1)*width*4]
        expanded=[]
        for x in range(width): expanded.extend(row[x*4:x*4+4]*scale)
        out.extend(expanded*scale)
    dst.pixels.foreach_set(out)
    dst.filepath_raw=filepath.replace('.png','_nearest_x%d.png'%scale)
    dst.file_format='PNG'
    dst.save()
    bpy.data.images.remove(src)


def assemble_character(render=True):
    clear_previous(); root=ensure_collection(ROOT); mats=make_materials()
    phase1(root,mats); phase2(root,mats); phase3(root,mats); setup_sprite_camera(root); setup_lighting(root)
    root["generator"]="scripts/generate_cowboy.py"; root["design"]="smooth subdivision stylized cowboy for low-resolution sprite readability"
    bpy.context.view_layer.update()
    if render: render_sprite_preview()
    os.makedirs(os.path.dirname(OUT_BLEND),exist_ok=True); bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    print("Cowboy generator complete:", OUT_BLEND)


if __name__ == "__main__":
    assemble_character(render=True)
