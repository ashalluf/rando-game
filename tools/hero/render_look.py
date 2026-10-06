"""Cycles stand-ins for the game's hero shaders, and the game's own gun holds, for render.py.

The glTF only carries what a StandardMaterial3D can say; in the game HeroLook swaps the skin,
hair and tracksuit onto shaders/hero_*.gdshader with the hero_x_* maps beside the .glb. A
Cycles preview of the bare glTF is therefore not what the game draws, so dress() rebuilds the
same recipe in nodes:

    hero_skin       stubble hairs (detail alpha x mask red) over the albedo, the tiling pores
                    added to the wrinkle normal, random-walk subsurface
    hero_hair       the layer occlusion from UV2, an anisotropic lobe along the strands
    hero_tracksuit  the rest / bent fold normals mixed by the elbow and knee angles of the pose
                    (as HeroLook.update() does), plus the velour pile and a sheen

pose() puts the armature in a pose dumped by tools/grip_fit.gd (POSE_OUT=...): the hands after
the IK, GripHands and AimTwist, which only exist in the game. add_gun() imports that gun at the
place the game holds it.
"""
import json
import math
import os

import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.join(REPO, "assets", "models")
# glTF (Y up) to Blender (Z up): (x, y, z) -> (x, -z, y)
C = mathutils.Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
ELBOW_BEND = (35.0, 115.0)
KNEE_BEND = (15.0, 95.0)


def _xf(a):
    """12 floats from grip_fit.gd (basis columns, then origin) as a 4x4."""
    m = mathutils.Matrix.Identity(4)
    for c in range(3):
        for r in range(3):
            m[r][c] = a[c * 3 + r]
    m[0][3], m[1][3], m[2][3] = a[9], a[10], a[11]
    return m


def pose(arm, path):
    """Poses `arm` from a grip_fit.gd dump. Every bone gets the world-space change the game gave
    it (posed times rest inverse, in skeleton space) carried into Blender's axes, which is
    independent of how the importer re-oriented the bones."""
    data = json.load(open(path))
    bones = data["bones"]
    target = {}
    for b in arm.data.bones:
        if b.name not in bones:
            continue
        d = _xf(bones[b.name]["pose"]) @ _xf(bones[b.name]["rest"]).inverted()
        target[b.name] = C @ d @ C.inverted() @ b.matrix_local
    order = []  # parents before children

    def visit(bone):
        order.append(bone)
        for ch in bone.children:
            visit(ch)
    for b in arm.data.bones:
        if b.parent is None:
            visit(b)
    posed = {}
    for b in order:
        pb = arm.pose.bones[b.name]
        pb.rotation_mode = 'QUATERNION'
        want = target.get(b.name)
        if b.parent is None:
            parent_pose = mathutils.Matrix.Identity(4)
            parent_rest = mathutils.Matrix.Identity(4)
        else:
            parent_pose = posed[b.parent.name]
            parent_rest = b.parent.matrix_local
        if want is None:  # a bone the game does not have (none today): follow the parent
            want = parent_pose @ parent_rest.inverted() @ b.matrix_local
        basis = (parent_rest.inverted() @ b.matrix_local).inverted() @ parent_pose.inverted() @ want
        loc, rot, sca = basis.decompose()
        pb.location = loc
        pb.rotation_quaternion = rot
        pb.scale = sca
        posed[b.name] = want
    bpy.context.view_layer.update()
    return data


def add_gun(arm, data):
    """Imports the gun of a pose dump where the game holds it (skeleton space -> armature)."""
    glb = os.path.join(MODELS, data["glb"] + ".glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    new = [o for o in bpy.data.objects if o not in before]
    holder = bpy.data.objects.new("gun", None)
    bpy.context.scene.collection.objects.link(holder)
    holder.matrix_world = arm.matrix_world @ C @ _xf(data["gun"]) @ C.inverted()
    for o in new:
        if o.parent is None:
            mw = o.matrix_world.copy()
            o.parent = holder
            o.matrix_parent_inverse = mathutils.Matrix.Identity(4)
            o.matrix_basis = mw
    # the launcher's warhead is loaded in a held gun
    bpy.context.view_layer.update()
    return new


def wrinkle_weights(arm):
    w = []
    for chain, rng in ((("LeftArm", "LeftForeArm", "LeftHand"), ELBOW_BEND), (("RightArm", "RightForeArm", "RightHand"), ELBOW_BEND),
                       (("LeftUpLeg", "LeftLeg", "LeftFoot"), KNEE_BEND), (("RightUpLeg", "RightLeg", "RightFoot"), KNEE_BEND)):
        pb = arm.pose.bones
        if not all(n in pb for n in chain):
            w.append(0.0)
            continue
        a, b, c = (pb[n].head for n in chain)
        bend = math.degrees((b - a).angle((c - b)))
        t = min(1.0, max(0.0, (bend - rng[0]) / (rng[1] - rng[0])))
        w.append(t * t * (3 - 2 * t))
    return w


def _img(nodes, name, x, y, non_color=True):
    path = os.path.join(MODELS, name)
    if not os.path.exists(path):
        return None
    n = nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(path, check_existing=True)
    if non_color:
        n.image.colorspace_settings.name = "Non-Color"
    n.image.alpha_mode = 'CHANNEL_PACKED'
    n.location = (x, y)
    return n


def _vec(nodes, op, x, y, b=None, c=None):
    n = nodes.new("ShaderNodeVectorMath")
    n.operation = op
    n.location = (x, y)
    if b is not None:
        n.inputs[1].default_value = b
    if c is not None:
        n.inputs[2].default_value = c
    return n


def _math(nodes, op, x, y, b=None):
    n = nodes.new("ShaderNodeMath")
    n.operation = op
    n.location = (x, y)
    if b is not None:
        n.inputs[1].default_value = b
    return n


def _bsdf(m):
    return next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def _normal_map(m):
    """The glTF's Normal Map node and the image feeding it."""
    b = _bsdf(m)
    if not b.inputs["Normal"].links:
        return None, None
    nm = b.inputs["Normal"].links[0].from_node
    src = nm.inputs["Color"].links[0].from_node if nm.inputs["Color"].links else None
    return nm, src


def _slopes(nodes, links, color_socket, strength, x, y, zero_z=True):
    """(c * 2 - 1) * strength with z dropped: a tangent-space slope to add."""
    s = strength
    n = _vec(nodes, 'MULTIPLY_ADD', x, y, (2 * s, 2 * s, 0 if zero_z else 2), (-s, -s, 0 if zero_z else -1))
    links.new(color_socket, n.inputs[0])
    return n


def _feed_normal(nodes, links, nm, slope_nodes, x, y):
    """Sum of slopes -> an encoded normal (z = 1) into the Normal Map node."""
    acc = slope_nodes[0].outputs[0]
    for i, s in enumerate(slope_nodes[1:]):
        add = _vec(nodes, 'ADD', x - 200, y - 120 * i)
        links.new(acc, add.inputs[0])
        links.new(s.outputs[0], add.inputs[1])
        acc = add.outputs[0]
    enc = _vec(nodes, 'MULTIPLY_ADD', x, y, (0.5, 0.5, 0.0), (0.5, 0.5, 1.0))
    links.new(acc, enc.inputs[0])
    links.new(enc.outputs[0], nm.inputs["Color"])


def _uv(nodes, x, y, layer=""):
    n = nodes.new("ShaderNodeUVMap")
    n.uv_map = layer
    n.location = (x, y)
    return n


def dress(arm=None, stubble=0.9, pores=0.6, sss_scale=0.006):
    meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith("hero_mesh")]
    uv2 = meshes[0].data.uv_layers[1].name if meshes and len(meshes[0].data.uv_layers) > 1 else ""
    weights = wrinkle_weights(arm) if arm else [0.0] * 4
    print("DRESS wrinkle weights", [round(v, 2) for v in weights])
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        nodes, links = m.node_tree.nodes, m.node_tree.links
        if not any(n.type == 'BSDF_PRINCIPLED' for n in nodes):
            continue
        b = _bsdf(m)
        if m.name == "hero_skin":
            uv = _uv(nodes, -1600, 400)
            scale = _vec(nodes, 'MULTIPLY', -1400, 400, (46.0, 46.0, 1.0))
            links.new(uv.outputs[0], scale.inputs[0])
            detail = _img(nodes, "hero_x_skin_detail.png", -1200, 400)
            links.new(scale.outputs[0], detail.inputs[0])
            mask = _img(nodes, "hero_x_skin_mask.png", -1200, 100)
            links.new(uv.outputs[0], mask.inputs[0])
            sep = nodes.new("ShaderNodeSeparateColor")
            sep.location = (-900, 100)
            links.new(mask.outputs["Color"], sep.inputs[0])
            hairs = _math(nodes, 'MULTIPLY', -700, 250)
            links.new(detail.outputs["Alpha"], hairs.inputs[0])
            links.new(sep.outputs[0], hairs.inputs[1])
            hairs2 = _math(nodes, 'MULTIPLY', -550, 250, stubble * 0.9)
            links.new(hairs.outputs[0], hairs2.inputs[0])
            base_src = b.inputs["Base Color"].links[0].from_socket
            mix = nodes.new("ShaderNodeMix")
            mix.data_type = 'RGBA'
            mix.location = (-350, 300)
            links.new(hairs2.outputs[0], mix.inputs["Factor"])
            links.new(base_src, mix.inputs[6])
            mix.inputs[7].default_value = (0.0035, 0.003, 0.0026, 1.0)
            links.new(mix.outputs[2], b.inputs["Base Color"])
            nm, src = _normal_map(m)
            if nm and src:
                s0 = _slopes(nodes, links, src.outputs["Color"], 1.0, -700, -200)
                s1 = _slopes(nodes, links, detail.outputs["Color"], pores, -700, -350)
                _feed_normal(nodes, links, nm, [s0, s1], -450, -250)
            b.inputs["Subsurface Weight"].default_value = 1.0
            b.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.2)
            b.inputs["Subsurface Scale"].default_value = sss_scale
            try:
                b.subsurface_method = 'RANDOM_WALK_SKIN'
            except TypeError:
                pass
        elif m.name == "hero_hair":
            b.inputs["Anisotropic"].default_value = 0.8
            b.inputs["Anisotropic Rotation"].default_value = 0.25  # the strands run along V
            b.inputs["Roughness"].default_value = 0.36
            tan = nodes.new("ShaderNodeTangent")
            tan.direction_type = 'UV_MAP'
            tan.location = (-300, -500)
            links.new(tan.outputs[0], b.inputs["Tangent"])
            if uv2:
                u = _uv(nodes, -900, 400, uv2)
                sep = nodes.new("ShaderNodeSeparateXYZ")
                sep.location = (-700, 400)
                links.new(u.outputs[0], sep.inputs[0])
                base_src = b.inputs["Base Color"].links[0].from_socket
                mul = nodes.new("ShaderNodeMix")
                mul.data_type = 'RGBA'
                mul.blend_type = 'MULTIPLY'
                mul.location = (-350, 300)
                mul.inputs["Factor"].default_value = 1.0
                links.new(base_src, mul.inputs[6])
                links.new(sep.outputs[0], mul.inputs[7])
                links.new(mul.outputs[2], b.inputs["Base Color"])
        elif m.name == "hero_tracksuit" or m.name == "hero_tracksuit_rib":
            nm, src = _normal_map(m)
            uv = _uv(nodes, -1600, -300)
            pile_scale = 140.0 if m.name == "hero_tracksuit" else 60.0
            ps = _vec(nodes, 'MULTIPLY', -1400, -300, (pile_scale, pile_scale, 1.0))
            links.new(uv.outputs[0], ps.inputs[0])
            pile = _img(nodes, "hero_x_pile.png", -1200, -300)
            links.new(ps.outputs[0], pile.inputs[0])
            slopes = []
            if nm and src:
                col = src.outputs["Color"]
                if m.name == "hero_tracksuit":
                    bent = _img(nodes, "hero_x_suit_bent_normal.jpg", -1200, -700)
                    wmask = _img(nodes, "hero_x_suit_wrinkle_mask.png", -1200, -1000)
                    if bent and wmask:
                        links.new(uv.outputs[0], bent.inputs[0])
                        links.new(uv.outputs[0], wmask.inputs[0])
                        sep = nodes.new("ShaderNodeSeparateColor")
                        sep.location = (-950, -1000)
                        links.new(wmask.outputs["Color"], sep.inputs[0])
                        chans = [sep.outputs[0], sep.outputs[1], sep.outputs[2], wmask.outputs["Alpha"]]
                        acc = None
                        for i, ch in enumerate(chans):
                            mm = _math(nodes, 'MULTIPLY', -800, -900 - 100 * i, weights[i])
                            links.new(ch, mm.inputs[0])
                            if acc is None:
                                acc = mm.outputs[0]
                            else:
                                ad = _math(nodes, 'ADD', -650, -900 - 100 * i)
                                links.new(acc, ad.inputs[0])
                                links.new(mm.outputs[0], ad.inputs[1])
                                acc = ad.outputs[0]
                        mix = nodes.new("ShaderNodeMix")
                        mix.data_type = 'RGBA'
                        mix.clamp_factor = True
                        mix.location = (-500, -700)
                        links.new(acc, mix.inputs["Factor"])
                        links.new(col, mix.inputs[6])
                        links.new(bent.outputs["Color"], mix.inputs[7])
                        col = mix.outputs[2]
                slopes.append(_slopes(nodes, links, col, 1.0, -350, -500))
                slopes.append(_slopes(nodes, links, pile.outputs["Color"], 0.3 if m.name == "hero_tracksuit" else 0.15, -350, -650))
                _feed_normal(nodes, links, nm, slopes, -150, -550)
            b.inputs["Sheen Weight"].default_value = 1.0
            b.inputs["Sheen Roughness"].default_value = 0.35
            b.inputs["Sheen Tint"].default_value = (0.35, 0.35, 0.38, 1.0)
        elif m.name == "hero_eyes":
            b.inputs["Coat Weight"].default_value = 1.0
            b.inputs["Coat Roughness"].default_value = 0.02
            b.inputs["Roughness"].default_value = 0.3
        elif m.name == "hero_gold":
            b.inputs["Roughness"].default_value = 0.16
