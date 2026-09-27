import bpy, time, os

PREVIEW_PATH = r"D:\Godot\xybotsResearch\blender\renders\xybots_live_native_preview.png"
STATE_KEY = "xybots_native_preview_state"
state = bpy.app.driver_namespace.setdefault(STATE_KEY, {})
state["poll_token"] = state.get("poll_token", 0) + 1
TOKEN = state["poll_token"]
state.update({"rendering": False, "last_error": "", "preview_path": PREVIEW_PATH})

def _xybots_signature():
    scene = bpy.context.scene
    material = bpy.data.materials["XYBOTS_THREE_TONE_TOON"]
    ramp = material.node_tree.nodes["Three grayscale bands"].color_ramp
    values = [scene.frame_current, scene.camera.name if scene.camera else ""]
    for element in ramp.elements:
        values.extend((element.position, *element.color[:]))
    return tuple(values)

def _xybots_render_native_preview():
    if state["rendering"]:
        return
    state["rendering"] = True
    scene = bpy.context.scene
    original_path = scene.render.filepath
    try:
        scene.render.filepath = PREVIEW_PATH
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.get("XYBOTS_LIVE_NATIVE_PREVIEW")
        if image is None:
            image = bpy.data.images.load(PREVIEW_PATH, check_existing=False)
            image.name = "XYBOTS_LIVE_NATIVE_PREVIEW"
        else:
            image.reload()
        for area in bpy.context.screen.areas:
            if area.type == 'IMAGE_EDITOR':
                area.spaces.active.image = image
        state["last_render_epoch"] = time.time()
    except Exception as exc:
        state["last_error"] = repr(exc)
    finally:
        scene.render.filepath = original_path
        state["rendering"] = False

def _xybots_preview_poll():
    if state.get("poll_token") != TOKEN:
        return None
    signature = _xybots_signature()
    if signature != state.get("last_signature"):
        state["last_signature"] = signature
        _xybots_render_native_preview()
    return 0.10

state["last_signature"] = _xybots_signature()
bpy.app.timers.register(_xybots_preview_poll, first_interval=0.10, persistent=True)
_xybots_render_native_preview()
