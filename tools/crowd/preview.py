# Cycles previews of exported crowd rigs (Blender, no Godot, no shared render lock): each rig
# posed in a clip, a column per view, a row per rig, one PNG sheet. Seconds a view at the default
# size, so it is the quick loop for garments; judge the finished rig with
# tools/glshot/crowd_lineup.gd, which draws it the way the game does.
#
#   tools/crowd/preview.sh out.png crowd_a,crowd_h[,path/to/other.glb] [views] [phase]
#
# Views: front side back q torso torso_back waist chest chest_l shoulder shoulder_back sleeve
# sleeve_f sleeve_r legs feet head (default front,side,back); phase 0..1 into CLIP (default the walk at
# 0.25). Env: CLIP, RES (width, default 420; height 1.6x), SAMPLES (20), and one of
#   FLAT=1    every surface flat grey, no normal map: the geometry alone (creases, spikes, folds)
#   REGION=1  the region vertex colours (R top, G bottom, B hair, A skin as black): which mesh is
#             which - a dark mark on a top that renders green is the trousers poking through,
#             black is skin
# Each rig is imported into a fresh file: two glTF imports in one file share same-named images
# and meshes ("body", "Body"), and the second rig rendered in the first one's textures.
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(args[0])
NAMES = args[1].split(",")
VIEWS = (args[2] if len(args) > 2 else "front,side,back").split(",")
PHASE = float(args[3]) if len(args) > 3 else 0.25
CLIP = os.environ.get("CLIP", "Casual_Walk_inplace")
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RES = int(os.environ.get("RES", "420"))
# yaw from the front (degrees, the camera round to the figure's left), distance, camera height
# and aim height as fractions of the figure's height (absolute metres below 0.5)
VIEW = {"front": (0.0, 3.3, 0.55, 0.5), "side": (90.0, 3.3, 0.55, 0.5), "back": (180.0, 3.3, 0.55, 0.5),
        "q": (40.0, 3.3, 0.55, 0.5), "torso": (25.0, 1.5, 0.72, 0.7), "torso_back": (200.0, 1.5, 0.72, 0.7),
        "waist": (15.0, 1.0, 0.58, 0.56), "chest": (-20.0, 0.65, 0.78, 0.74), "chest_l": (25.0, 0.65, 0.78, 0.74),
        "shoulder": (60.0, 1.1, 0.8, 0.76), "shoulder_back": (150.0, 1.1, 0.8, 0.76),
        "sleeve": (115.0, 0.75, 0.74, 0.72), "sleeve_f": (60.0, 0.75, 0.74, 0.72), "sleeve_r": (-125.0, 0.75, 0.74, 0.72),
        "legs": (25.0, 1.9, 0.3, 0.3),
        "feet": (35.0, 1.1, 0.25, 0.1), "head": (20.0, 0.9, 0.86, 0.84)}


def scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = int(os.environ.get("SAMPLES", "20"))
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = RES, int(RES * 1.6)
    sc.view_settings.view_transform = 'AgX'
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.62, 0.72, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    sun.data.energy = 3.5
    sun.data.angle = math.radians(2)
    sun.rotation_euler = (math.radians(52), 0, math.radians(-150))
    sc.collection.objects.link(sun)
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.08, 0.08, 0.085, 1)
    bpy.ops.mesh.primitive_plane_add(size=20)
    bpy.context.object.data.materials.append(gm)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 50
    return sc, cam


def dress(o):
    for m in o.data.materials:
        if not (m and m.use_nodes and "Principled BSDF" in m.node_tree.nodes):
            continue
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = 0.75
        for lk in list(bsdf.inputs["Base Color"].links):
            nt.links.remove(lk)
        if os.environ.get("REGION"):
            ca = nt.nodes.new("ShaderNodeVertexColor")
            ca.layer_name = o.data.color_attributes[0].name if o.data.color_attributes else ""
            nt.links.new(ca.outputs["Color"], bsdf.inputs["Base Color"])
        elif os.environ.get("FLAT"):
            for lk in list(bsdf.inputs["Normal"].links):
                nt.links.remove(lk)
            bsdf.inputs["Base Color"].default_value = (0.6, 0.6, 0.6, 1)
        else:
            # the importer multiplies the atlas by COLOR_0 (the region mask): the atlas alone
            tex = [n for n in nt.nodes if n.type == 'TEX_IMAGE' and n.image and "nrm" not in n.image.name.lower()]
            if tex:
                nt.links.new(tex[0].outputs["Color"], bsdf.inputs["Base Color"])


tiles = {}
for row, name in enumerate(NAMES):
    sc, cam = scene()
    path = name if name.endswith(".glb") else os.path.join(REPO, "assets", "models", name + ".glb")
    bpy.ops.import_scene.gltf(filepath=path)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    act = bpy.data.actions.get(CLIP) or next((a for a in bpy.data.actions if a.name.startswith(CLIP)), None)
    if arm.animation_data is None:
        arm.animation_data_create()
    if act:
        arm.animation_data.action = act
        f0, f1 = act.frame_range
        sc.frame_set(int(round(f0 + (f1 - f0) * PHASE)))
    ms = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent is not None]
    for o in ms:
        dress(o)
    bpy.context.view_layer.update()
    h = max((o.matrix_world @ Vector(c)).z for o in ms for c in o.bound_box)
    for col, v in enumerate(VIEWS):
        yaw, d, cy, ay = VIEW[v]
        cy, ay = (cy * h if cy > 0.5 or v != "feet" else cy), (ay * h if v != "feet" else ay)
        a = math.radians(yaw)
        # the rigs face -Y in Blender once imported (+Z in Godot)
        cam.location = Vector((math.sin(a) * d, -math.cos(a) * d, cy))
        cam.rotation_euler = (Vector((0, 0, ay)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        f = "%s__%02d_%02d.png" % (OUT[:-4], row, col)
        sc.render.filepath = f
        bpy.ops.render.render(write_still=True)
        tiles[(row, col)] = f
# the sheet, in a fresh file
W, H = RES, int(RES * 1.6)
sheet = np.zeros((H * len(NAMES), W * len(VIEWS), 4), np.float32)
for (row, col), f in tiles.items():
    im = bpy.data.images.load(f)
    px = np.array(im.pixels[:], np.float32).reshape(H, W, 4)
    # Blender's pixel rows run bottom up; the sheet's first row is the top
    r0 = (len(NAMES) - 1 - row) * H
    sheet[r0:r0 + H, col * W:(col + 1) * W] = px
    bpy.data.images.remove(im)
    os.remove(f)
img = bpy.data.images.new("sheet", W * len(VIEWS), H * len(NAMES))
img.pixels = sheet.ravel()
img.filepath_raw = OUT
img.file_format = 'PNG'
img.save()
print("PREVIEW", OUT, "%d rigs x %d views" % (len(NAMES), len(VIEWS)))
