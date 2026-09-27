"""Run inside Blender after generate_cowboy.py: blender --background blender/cowboy_generator.blend --python scripts/test_cowboy_generator.py"""
import bpy

def require(condition, message):
    if not condition: raise AssertionError(message)

def parts(name): return [o for o in bpy.data.objects if o.get("cowboy_part") == name]

def run_tests():
    require(bpy.data.collections.get("Cowboy_Generated"), "generated Cowboy collection is missing")
    for n in ("Hat", "Bandana_Front", "Belt", "Buckle"):
        require(bpy.data.objects.get(n), n+" is missing")
    holsters=parts("holster"); require(holsters and all(o.get("empty_holster") for o in holsters), "holster must be a marked empty shell")
    require(not [o for o in bpy.data.objects if 'gun' in o.name.lower() or 'revolver' in o.name.lower()], "a gun/revolver was generated")
    hands=parts("hand"); require(len(hands)==2, "expected exactly two hand objects")
    fingers=parts("finger")
    for side in ("Left","Right"):
        require(len([o for o in fingers if o.get('side')==side])==5, side+" hand must have five distinct digits")
    buttons=parts("vest_button"); require(len(buttons)==2 and {o.get('side') for o in buttons}=={'Right'}, "buttons must exist only on one vest panel")
    pants=bpy.data.materials.get("Cowboy_Pants_Denim")
    require(pants and all(o.data.materials and o.data.materials[0] == pants for o in parts("belt_loop")), "belt loops must use pants material")
    for part in ("belt","buckle"):
        require(all(o.data.materials and o.data.materials[0] != pants for o in parts(part)), part+" must not use pants material")
    cam=bpy.data.objects.get("Cowboy_SpriteCamera"); require(cam and cam.data.type=='ORTHO', "front sprite camera must be orthographic")
    print("PASS: cowboy generator requirement checks completed")

if __name__ == '__main__': run_tests()
