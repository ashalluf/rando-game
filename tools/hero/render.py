# Studio preview renderer. Usage:
#   blender -b -t 2 [file.blend] --python render.py -- --glb path.glb (optional) --out prefix --views front,side,34,face [--samples 48] [--res 1024] [--anim clip --frame f]
import bpy, sys, os, math, mathutils
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default
glb = arg("--glb"); out = arg("--out"); views = arg("--views", "front,side,34,face").split(",")
samples = int(arg("--samples", "48")); res = int(arg("--res", "1024"))
fix_meshy = "--fix-meshy" in argv
action_name = arg("--action"); frame = float(arg("--frame", "0"))

if glb:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
scene = bpy.context.scene
if "--nylon" in argv:
    # the same suit in shiny black nylon: soft specular instead of the velour sheen
    for m in bpy.data.materials:
        if not m.use_nodes or not m.name.startswith("hero_tracksuit"):
            continue
        for n in m.node_tree.nodes:
            if n.type == 'MIX' and n.blend_type == 'MULTIPLY':
                n.inputs[7].default_value = (0.012, 0.012, 0.014, 1)
            if n.type == 'BSDF_PRINCIPLED':
                n.inputs["Roughness"].default_value = 0.3
                n.inputs["Sheen Weight"].default_value = 0.0
                n.inputs["Specular IOR Level"].default_value = 0.65
# Meshy materials: the game's prepare_rig() zeroes metallic, sets roughness 0.85 and turns emission off.
if fix_meshy:
    for m in bpy.data.materials:
        if not m.use_nodes: continue
        for n in m.node_tree.nodes:
            if n.type == 'BSDF_PRINCIPLED':
                n.inputs["Metallic"].default_value = 0.0
                for l in list(n.inputs["Metallic"].links): m.node_tree.links.remove(l)
                n.inputs["Roughness"].default_value = 0.85
                for l in list(n.inputs["Roughness"].links): m.node_tree.links.remove(l)
                n.inputs["Emission Strength"].default_value = 0.0
                for l in list(n.inputs["Emission Color"].links): m.node_tree.links.remove(l)
                n.inputs["Specular IOR Level"].default_value = 0.5
arms = [o for o in scene.objects if o.type == 'ARMATURE']
if arms and arms[0].animation_data:
    for tr in list(arms[0].animation_data.nla_tracks):
        arms[0].animation_data.nla_tracks.remove(tr)
if action_name:
    arm = arms[0]
    act = bpy.data.actions.get(action_name) or [a for a in bpy.data.actions if a.name.startswith(action_name)][0]
    if "--fix-arms" in argv:  # the game's arm rebuild (for the Meshy rig's raw clips)
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import fixarms
        fixarms.fix_arms(arm, act)
    arm.animation_data_create(); arm.animation_data.action = act
    scene.frame_set(int(frame), subframe=frame - int(frame))
elif "--neutral" in argv:
    # Neutral stand for character previews: the rig's rest pose with the arms dropped exactly the
    # way the game drops them for its idle (Pedestrian.fix_arm_pose, ported in fixarms.py).
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import fixarms
    arm = arms[0]
    act = bpy.data.actions.new("idle_neutral"); act.id_root = 'OBJECT'
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        for c in range(4):
            fc = act.fcurves.new(f'pose.bones["{pb.name}"].rotation_quaternion', index=c)
            fc.keyframe_points.add(2)
            v = 1.0 if c == 0 else 0.0
            fc.keyframe_points.foreach_set("co", [0.0, v, 1.0, v])
    fixarms.fix_arms(arm, act)
    fixarms.add_finger_keys(arm, act)
    arm.animation_data_create(); arm.animation_data.action = act
    scene.frame_set(0)

# World bounds of all visible meshes (evaluated, so armature poses count).
dg = bpy.context.evaluated_depsgraph_get()
lo = mathutils.Vector((1e9, 1e9, 1e9)); hi = -lo
for o in scene.objects:
    if o.type != 'MESH' or o.hide_render: continue
    eo = o.evaluated_get(dg); me = eo.to_mesh()
    for v in me.vertices:
        w = eo.matrix_world @ v.co
        lo = mathutils.Vector(map(min, lo, w)); hi = mathutils.Vector(map(max, hi, w))
    eo.to_mesh_clear()
print("BOUNDS", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi), "height", round(hi.z - lo.z, 3))
# Same framing for every character: ground at 0, a 1.8 m frame, centred on the hips; the face
# shot aims at the Head bone so it does not depend on stray vertices.
ground = 0.0; height = 1.8
_arm = [o for o in scene.objects if o.type == 'ARMATURE']
if _arm:
    _hips = _arm[0].matrix_world @ _arm[0].pose.bones["Hips"].head
    _head = _arm[0].matrix_world @ _arm[0].pose.bones["Head"].head
    cx, cy = _hips.x, _hips.y
else:
    cx = (lo.x + hi.x) / 2; cy = (lo.y + hi.y) / 2; _head = None

# Studio: grey world, grey floor, big soft key + fill + rim area lights.
world = bpy.data.worlds.new("studio"); scene.world = world; world.use_nodes = True
bg = world.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.18, 0.18, 0.18, 1); bg.inputs[1].default_value = 0.6
# A seamless studio bowl (flat floor that sweeps up into a wall all the way round), so every view
# gets the same plain grey background with no horizon line.
import bmesh
prof = [(r, 0.0) for r in (0.0, 3.0, 6.0, 8.0)]
for k in range(1, 13):
    a = math.radians(90 * k / 12); prof.append((8.0 + 5.0 * math.sin(a), 5.0 * (1 - math.cos(a))))
prof.append((13.0, 25.0))
bm = bmesh.new(); seg = 96; rings = []
for (r, z) in prof:
    rings.append([bm.verts.new((cx + r * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg), ground + z)) for i in range(seg)])
for a_, b_ in zip(rings, rings[1:]):
    for i in range(seg):
        bm.faces.new((a_[i], a_[(i + 1) % seg], b_[(i + 1) % seg], b_[i]))
bowl_me = bpy.data.meshes.new("bowl"); bm.to_mesh(bowl_me); bm.free()
for p_ in bowl_me.polygons: p_.use_smooth = True
floor = bpy.data.objects.new("bowl", bowl_me); scene.collection.objects.link(floor)
fm = bpy.data.materials.new("floor"); fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.3, 0.3, 1)
fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
floor.data.materials.append(fm)
def area(name, loc, energy, size, color=(1, 1, 1)):
    l = bpy.data.lights.new(name, 'AREA'); l.energy = energy; l.size = size; l.color = color
    ob = bpy.data.objects.new(name, l); scene.collection.objects.link(ob); ob.location = loc
    d = mathutils.Vector((cx, cy, ground + height * 0.6)) - ob.location
    ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return ob
# The characters face -Y in Blender (glTF +Z).
area("key", (cx - 2.2, cy - 3.0, ground + 2.8), 650, 2.5, (1.0, 0.97, 0.93))
area("fill", (cx + 3.0, cy - 2.0, ground + 1.4), 220, 3.0, (0.93, 0.96, 1.0))
area("rim", (cx + 0.8, cy + 3.2, ground + 2.6), 500, 1.5)

cam_data = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = samples
scene.cycles.use_denoising = True; scene.cycles.denoiser = 'OPENIMAGEDENOISE'
scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
scene.view_settings.view_transform = 'AgX'; scene.view_settings.look = 'None'; scene.view_settings.exposure = float(arg('--exposure', '-0.3'))
scene.cycles.max_bounces = 6; scene.cycles.transparent_max_bounces = 16
def shoot(view):
    if view in ("lwrist", "rhand", "feet", "knee"):
        # detail close-ups: left wrist (watch), right hand (ring), feet (sneakers), knee (folds)
        scene.render.resolution_x = res; scene.render.resolution_y = res
        pb = _arm[0].pose.bones
        mw = _arm[0].matrix_world
        if view == "lwrist":
            target = mw @ pb["LeftHand"].head; direction = mathutils.Vector((0.6, -1.0, 0.25)); dist = 0.42; cam_data.lens = 70
        elif view == "rhand":
            target = mw @ pb["RightHand"].head + mathutils.Vector((0, -0.01, -0.07)); direction = mathutils.Vector((-0.8, -1.0, 0.1)); dist = 0.4; cam_data.lens = 70
        elif view == "knee":
            target = mw @ pb["LeftLeg"].head + mathutils.Vector((0, 0, -0.1)); direction = mathutils.Vector((0.9, -1.0, 0.15)); dist = 1.1; cam_data.lens = 70
        else:
            target = mathutils.Vector((cx, cy - 0.05, 0.07)); direction = mathutils.Vector((0.45, -1.0, 0.35)); dist = 1.0; cam_data.lens = 70
        direction.normalize()
        cam.location = target + direction * dist
        cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = f"{out}{view}.png"
        bpy.ops.render.render(write_still=True)
        print("WROTE", scene.render.filepath)
        return
    if view == "chest":
        scene.render.resolution_x = res; scene.render.resolution_y = res
        cam_data.lens = 70
        target = (_head + mathutils.Vector((0, -0.05, -0.2))) if _head is not None else mathutils.Vector((cx, cy, 1.4))
        dist = 1.0; direction = mathutils.Vector((0.25, -1, 0.1)).normalized()
        cam.location = target + direction * dist
        cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = f"{out}{view}.png"
        bpy.ops.render.render(write_still=True)
        print("WROTE", scene.render.filepath)
        return
    if view == "face":
        scene.render.resolution_x = res; scene.render.resolution_y = res
        cam_data.lens = 85
        target = (_head + mathutils.Vector((0, -0.03, 0.075))) if _head is not None else mathutils.Vector((cx, cy, ground + height * 0.925))
        dist = 0.95; direction = mathutils.Vector((0.28, -1, 0.02)).normalized()
        if _arm and "headfront" in _arm[0].pose.bones:
            # look the character in the face whichever way the head is turned, 16 degrees off-axis
            hf = _arm[0].matrix_world @ _arm[0].pose.bones["headfront"].head
            fwd = (hf - _head); fwd.z = 0; fwd.normalize()
            direction = (mathutils.Quaternion((0, 0, 1), math.radians(16)) @ fwd + mathutils.Vector((0, 0, 0.02))).normalized()
    else:
        scene.render.resolution_x = int(res * 0.6); scene.render.resolution_y = res
        cam_data.lens = 70
        target = mathutils.Vector((cx, cy, ground + height * 0.5))
        dist = height * 3.25
        ang = {"front": 0.0, "side": 90.0, "34": 35.0, "back": 180.0}[view]
        a = math.radians(ang)
        # Rotate around Z starting from the front (-Y) toward the character's left (+X).
        direction = mathutils.Vector((math.sin(a), -math.cos(a), 0.06)).normalized()
    cam.location = target + direction * dist
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = f"{out}{view}.png"
    bpy.ops.render.render(write_still=True)
    print("WROTE", scene.render.filepath)
for v in views: shoot(v)
