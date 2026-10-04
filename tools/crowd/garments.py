# Our own garments for the crowd (Blender, called from build_character.py on the bound body).
#
# The MakeHuman library clothes are photographed textures on generic meshes: soft, printed-on,
# the same V-neck on every tee. These are modelled here the way the hero's tracksuit is
# (tools/hero/tracksuit.py), for the outfits most of the crowd wears:
#
#   tee       crew-neck T-shirt, short or long sleeves, regular or fitted
#   trousers  five-pocket jeans, chinos, leggings or denim shorts
#   shirt     button shirt: turn-down collar, placket and buttons, shirt-tail hem, cuffs or
#             sleeves rolled to the forearm
#   jacket    zip jacket: stand collar and zip, rib cuffs and hem band
#
# How each is made:
#  - a SHELL grown off the body's own faces, so it inherits the body's UVs (the atlas takes its
#    island like any garment's) and skin weights. The shell is offset for the garment's fit and
#    then shaped the way cloth hangs, which is what stops a garment reading as painted-on skin:
#    each horizontal slice of the torso is bridged to its convex hull (the fabric spans the
#    breastbone, the spine and the hollow between the breasts), then the torso HANGS - below the
#    chest the cloth may only come in toward the body at a set slope, so a tee falls from the
#    chest and belly instead of following the waist - and sleeves and trouser legs are rounded
#    into tubes round the limb (straight-leg jeans hang from the knee).
#  - every garment edge is CUT by planes (sector planes round the neck, like the tracksuit's
#    neck ring), never picked face by face, and then HEMMED: a turned lip with the fabric's
#    thickness and an inner face runs round every opening, so an edge has a real cross-section
#    and a sleeve or a hem never shows a knife edge or the dark inside of the shell.
#  - collars, cuffs, waistbands, the shirt's placket and the jacket's zip are swept bands with a
#    profile (stand, rolled lip, inner face; a shirt collar's stand, fold and fall with points).
#    Buttons and the zip's metal are small separate parts that keep their own colour.
#  - the body under a garment is deleted by build_character.py's cover test, one ring kept and
#    tucked, as for the library clothes.
# Everything a garment needs to be painted (its cut planes, edge lines, seams and landmarks) is
# written to WORK/<name>/garments.json; crowd_atlas.py paints the texels (garment_paint.py).
import json
import math
import os

import bmesh
import bpy
import mathutils.geometry as MG
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import crowd_common as C

TORSO_BONES = ("Hips", "Spine02", "Spine01", "Spine", "LeftShoulder", "RightShoulder", "neck")
HEAD_BONES = ("Head", "head_end", "headfront")
LEG_UP = ("LeftUpLeg", "RightUpLeg")
LEG_LO = ("LeftLeg", "RightLeg")
FEET = ("LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase")
SIDES = (("Left", 1.0), ("Right", -1.0))
# Atlas pixels per metre of garment the bands' virtual textures are laid out at, before the
# atlas' own scale; measured off each shell (the body UV layout's density) and used for its bands.
PX_PER_M = 1460.0


def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def activate(o):
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


# =================================================================================================
# The body the garments are grown from
# =================================================================================================
class Body:
    """Measurements of the bound body (metres, Blender space: the figure faces -Y, Z up)."""

    def __init__(self, body, arm):
        self.obj, self.arm = body, arm
        me = body.data
        self.me = me
        self.mw = body.matrix_world.copy()
        self.mwi = self.mw.inverted()
        self.V = np.array([self.mw @ v.co for v in me.vertices])
        n3 = self.mw.to_3x3()
        self.VN = np.array([(n3 @ v.normal).normalized() for v in me.vertices])
        self.F = [list(p.vertices) for p in me.polygons]
        self.cent = np.array([self.V[f].mean(0) for f in self.F])
        bones = [b.name for b in arm.data.bones]
        gidx = {g.index: g.name for g in body.vertex_groups if g.name in bones}
        self.bone_names = sorted(set(gidx.values()))
        col = {n: k for k, n in enumerate(self.bone_names)}
        W = np.zeros((len(self.V), len(self.bone_names)))
        for v in me.vertices:
            for g in v.groups:
                n = gidx.get(g.group)
                if n:
                    W[v.index, col[n]] = g.weight
        self.W = W
        self.vdom = np.array([self.bone_names[i] for i in W.argmax(1)], dtype=object)
        self.vdom[W.max(1) <= 0] = ""
        self.fdom = np.array([self.bone_names[int(W[f].sum(0).argmax())] for f in self.F], dtype=object)
        self.bvh = BVHTree.FromPolygons([tuple(v) for v in self.V], [tuple(f) for f in self.F])
        amw = arm.matrix_world
        self.b = {b.name: np.array(amw @ b.head_local) for b in arm.data.bones}
        self.bt = {b.name: np.array(amw @ b.tail_local) for b in arm.data.bones}
        nbr = [[] for _ in self.V]
        for e in me.edges:
            a, c = e.vertices
            nbr[a].append(c)
            nbr[c].append(a)
        self.nbr = nbr
        # a smoothed body to grow cloth from and hold it off: nipples, the navel and the
        # collarbones' ridges are not things a shirt follows (grown off the raw body, and bridged
        # by slice hulls that had the nipple tips on them, the first tee printed both)
        Vs = taubin(self.V, nbr, np.zeros(len(self.V), bool), 24)
        self.Vs = Vs
        acc = np.zeros_like(Vs)
        for f in self.F:
            for j in range(1, len(f) - 1):
                fn = np.cross(Vs[f[j]] - Vs[f[0]], Vs[f[j + 1]] - Vs[f[0]])
                for k in (f[0], f[j], f[j + 1]):
                    acc[k] += fn
        self.VNs = acc / np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-12)
        self.bvh_s = BVHTree.FromPolygons([tuple(v) for v in Vs], [tuple(f) for f in self.F])
        # crotch: the lowest body point between the legs
        mid = (np.abs(self.V[:, 0]) < 0.015) & (self.V[:, 2] < self.b["Hips"][2]) & (self.V[:, 2] > self.b["LeftLeg"][2])
        self.crotch_z = float(self.V[mid, 2].min()) if mid.any() else float(self.b["LeftUpLeg"][2] - 0.1)

    def B(self, n):
        return self.b[n]

    def skin_hit(self, origin, direction, reach):
        """Distance from origin to the skin along direction (from outside in), or None."""
        d = Vector(direction).normalized()
        o = Vector(origin)
        hit = self.bvh.ray_cast(o + d * reach, -d, reach)
        return None if hit[0] is None else (hit[0] - o).length


# =================================================================================================
# Mesh helpers
# =================================================================================================
def new_mesh_object(ctx, name, me):
    """A new object parented like the body (same frame), with the body's vertex group names."""
    o = bpy.data.objects.new(ctx.name + "." + name, me)
    bpy.context.scene.collection.objects.link(o)
    o.parent = ctx.body.obj.parent
    o.matrix_parent_inverse = ctx.body.obj.matrix_parent_inverse.copy()
    o.matrix_basis = ctx.body.obj.matrix_basis.copy()
    return o


def shell_from_faces(ctx, name, face_mask):
    """The selected body faces as a new object: body UVs and skin weights kept, and each vertex's
    body index in the "orig" attribute."""
    body = ctx.body.obj
    me = body.data.copy()
    me.materials.clear()
    a = me.attributes.new("orig", 'INT', 'POINT')
    a.data.foreach_set("value", list(range(len(me.vertices))))
    o = new_mesh_object(ctx, name, me)
    for g in body.vertex_groups:
        o.vertex_groups.new(name=g.name)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not face_mask[f.index]], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(me)
    bm.free()
    return o


def get_orig(o):
    vals = [0] * len(o.data.vertices)
    o.data.attributes["orig"].data.foreach_get("value", vals)
    return np.array(vals)


def mesh_arrays(o):
    me = o.data
    P = np.array([v.co[:] for v in me.vertices])
    nbr = [[] for _ in range(len(P))]
    for e in me.edges:
        a, b = e.vertices
        nbr[a].append(b)
        nbr[b].append(a)
    bound = np.zeros(len(P), bool)
    ecount = {}
    for p in me.polygons:
        for ek in p.edge_keys:
            ecount[ek] = ecount.get(ek, 0) + 1
    for (a, b), c in ecount.items():
        if c == 1:
            bound[a] = bound[b] = True
    return P, nbr, bound


def set_positions(o, P):
    me = o.data
    me.vertices.foreach_set("co", np.asarray(P, np.float32).ravel())
    me.update()


def taubin(P, nbr, fixed, iters=12, lam=0.6, mu=-0.63, weight=None):
    P = P.copy()
    w = np.ones(len(P)) if weight is None else weight
    w = np.where(fixed, 0.0, w)[:, None]
    for _ in range(iters):
        for k in (lam, mu):
            avg = np.array([P[n].mean(0) if n else P[i] for i, n in enumerate(nbr)])
            P = P + k * w * (avg - P)
    return P


def smooth_field(vals, nbr, iters):
    v = np.asarray(vals, np.float64).copy()
    for _ in range(iters):
        v = 0.5 * v + 0.5 * np.array([v[n].mean(0) if n else v[i] for i, n in enumerate(nbr)])
    return v


def push_out(P, bvhs, clearance, dirs=None, reach=0.08):
    """Every point at least `clearance` (array or float) outside each BVH surface.

    With `dirs` (an outward direction per point, e.g. the body normal it was grown from) the
    test is a ray: from `reach` out along the direction back in, the first surface it meets,
    and the point is moved out along the direction until it stands `clearance` beyond it.
    Without, the nearest surface point and its face normal decide - which is wrong at every
    concavity: by the navel's rim or under the pecs the nearest face faces sideways or down,
    points outside the body read as inside, and the first tee was pulled into the navel and
    tented under both pecs."""
    out = P.copy()
    cl = np.broadcast_to(np.asarray(clearance, np.float64), (len(P),))
    for bvh in bvhs:
        for i in range(len(out)):
            if dirs is not None:
                d = Vector(dirs[i])
                if d.length < 1e-6:
                    continue
                d.normalize()
                p = Vector(out[i])
                hit = bvh.ray_cast(p + d * reach, -d, reach * 2.0)
                if hit[0] is None:
                    continue
                stand = (p - hit[0]).dot(d)
                if stand < cl[i]:
                    out[i] = np.array(p + d * (cl[i] - stand))
                continue
            loc, nrm, _idx, dist = bvh.find_nearest(Vector(out[i]))
            if loc is None:
                continue
            d = Vector(out[i]) - loc
            if d.dot(nrm) < 0 or dist < cl[i]:
                out[i] = np.array(loc + nrm * cl[i])
    return out


def vertex_normals(o):
    me = o.data
    me.update()
    n = np.zeros(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("normal", n)
    return n.reshape(-1, 3).astype(np.float64)


def clear_of(o, bvhs, clearance, where=None):
    """After subdividing (Catmull-Clark pulls a convex tube in by millimetres) and decimating: every
    vertex at least `clearance` out along its own normal from what it covers."""
    P, nbr, bound = mesh_arrays(o)
    N = vertex_normals(o)
    if where is not None:
        N = np.where(where(P)[:, None], N, 0.0)
    set_positions(o, push_out(P, bvhs, clearance, dirs=N, reach=0.05))


def smooth_edge(P, nbr, bound, mask, iters):
    """Boundary vertices (in `mask`) averaged with their two neighbours along the boundary, and
    the ring inside them eased after it: a cut edge smoothed along itself."""
    P = P.copy()
    bn = [[j for j in nbr[i] if bound[j]] if (bound[i] and mask[i]) else [] for i in range(len(P))]
    inner = [nbr[i] if (mask[i] and not bound[i] and any(bound[j] for j in nbr[i])) else [] for i in range(len(P))]
    for _ in range(iters):
        Q = P.copy()
        for i, n in enumerate(bn):
            if len(n) == 2:
                Q[i] = 0.5 * P[i] + 0.25 * (P[n[0]] + P[n[1]])
        for i, n in enumerate(inner):
            if n:
                Q[i] = 0.6 * Q[i] + 0.4 * Q[n].mean(0)
        P = Q
    return P


def lift_over(P, bvh, clearance, radial_dir, up=True):
    """Points inside a shoe moved out of it by the smaller of two moves: up over its top (a hem
    resting on the instep) or out along `radial_dir` past its side (a hem round the heel)."""
    out = P.copy()
    upv = Vector((0.0, 0.0, 1.0))
    for i in range(len(out)):
        p = Vector(out[i])
        moves = []
        h = bvh.ray_cast(p + upv * 0.2, -upv, 0.2 + clearance) if up else (None,)
        if h[0] is not None and h[0].z > p.z - clearance:
            moves.append(upv * (h[0].z + clearance - p.z))
        d = Vector(radial_dir[i])
        if d.length > 1e-6:
            d.normalize()
            h = bvh.ray_cast(p + d * 0.12, -d, 0.12)
            if h[0] is not None:
                stand = (p - h[0]).dot(d)
                if stand < clearance:
                    moves.append(d * (clearance - stand))
        if moves:
            out[i] = np.array(p + min(moves, key=lambda m: m.length))
    return out


def bvh_of(objs):
    verts, polys = [], []
    for o in objs:
        base = len(verts)
        mw = o.matrix_world
        verts += [mw @ v.co for v in o.data.vertices]
        polys += [tuple(base + i for i in p.vertices) for p in o.data.polygons]
    return BVHTree.FromPolygons(verts, polys)


def cut(o, plane_co, plane_no, region, kill_side, zone=None):
    """Bisect `region` faces of o by a plane and delete what lies on kill_side(centre) of it
    (only faces whose "zone" face attribute is `zone`, when given)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    zl = bm.faces.layers.int.get("zone")
    if zone is not None and zl is not None:
        reg = lambda f: f[zl] == zone and region(f.calc_center_median())  # noqa: E731
    else:
        reg = lambda f: region(f.calc_center_median())  # noqa: E731
    faces = [f for f in bm.faces if reg(f)]
    if faces:
        geom = list({v for f in faces for v in f.verts}) + list({e for f in faces for e in f.edges}) + faces
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(plane_co), plane_no=Vector(plane_no), dist=0.0002)
        kill = [f for f in bm.faces if reg(f) and kill_side(f.calc_center_median())]
        bmesh.ops.delete(bm, geom=kill, context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(o.data)
    bm.free()


def cut_ring(o, centre_fn, radius_fn, n, z_region):
    """Bisects the faces round a ring about a vertical axis by the ring's sector planes (the
    hero's neck ring): centre_fn() -> (x, y) of the axis, radius_fn(a) the ring's radius at
    azimuth a (0 = front), z_region(c) which faces to cut. Returns inside(c, margin): whether a
    point is inside the ring (margin > 0 shrinks it, < 0 grows it)."""
    cx, cy = centre_fn()

    def ring_point(k):
        a = 2 * math.pi * (k % n) / n
        r = radius_fn(a)
        return Vector((cx + r * math.sin(a), cy - r * math.cos(a), 0.0))

    def edge(k):
        p0, p1 = ring_point(k), ring_point(k + 1)
        t = p1 - p0
        nn = Vector((t.y, -t.x, 0.0)).normalized()
        if nn.dot(p0 - Vector((cx, cy, 0.0))) < 0:
            nn = -nn
        return p0, nn

    def inside(c, margin=0.0):
        a = math.atan2(c.x - cx, -(c.y - cy)) % (2 * math.pi)
        k = int(a / (2 * math.pi) * n) % n
        p0, nn = edge(k)
        return nn.dot(Vector((c.x, c.y, 0.0)) - p0) < -margin

    bm = bmesh.new()
    bm.from_mesh(o.data)
    for k in range(n):
        p0, nn = edge(k)
        a0 = 2 * math.pi * k / n

        def sector(c, a0=a0):
            a = math.atan2(c.x - cx, -(c.y - cy))
            return abs(((a - a0 - math.pi / n) + math.pi) % (2 * math.pi) - math.pi) < 2.5 * math.pi / n
        faces = [f for f in bm.faces if z_region(f.calc_center_median()) and sector(f.calc_center_median())
                 and inside(f.calc_center_median(), -0.04) and not inside(f.calc_center_median(), 0.04)]
        if faces:
            geom = list({v for f in faces for v in f.verts}) + list({e for f in faces for e in f.edges}) + faces
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=p0, plane_no=nn, dist=0.0002)
    bm.to_mesh(o.data)
    bm.free()
    return inside


def cut_neck(o, axis, radius, z_back, z_front, y_back, y_front, z_min, n=72):
    """The neck hole: the ring round the neck, and the neckline plane from (y_back, z_back) to
    (y_front, z_front) inside it; what is inside the ring and above the plane goes."""
    inside = cut_ring(o, lambda: axis, radius, n, lambda c: c.z > z_min)
    co = Vector((0.0, y_back, z_back))
    no = Vector((1.0, 0.0, 0.0)).cross(Vector((0.0, y_front - y_back, z_front - z_back))).normalized()
    if no.z < 0:
        no = -no
    cut(o, co, no, lambda c: c.z > z_min and inside(c, -0.03), lambda c: no.dot(c - co) > 0 and inside(c))
    return inside


def keep_largest_part(o):
    """Drop any loose islands a cut left behind (a stray face at a margin)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    seen = set()
    parts = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        comp = []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        parts.append(comp)
    parts.sort(key=len, reverse=True)
    small = [f for comp in parts[1:] if len(comp) < 0.05 * len(bm.faces) for f in comp]
    if small:
        bmesh.ops.delete(bm, geom=small, context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(o.data)
    bm.free()


def subdivide(o, levels=1):
    m = o.modifiers.new("SS", 'SUBSURF')
    m.levels = levels
    m.render_levels = levels
    m.uv_smooth = 'PRESERVE_BOUNDARIES'
    m.boundary_smooth = 'PRESERVE_CORNERS'
    activate(o)
    bpy.ops.object.modifier_apply(modifier=m.name)


def decimate(o, target):
    t0 = tris(o)
    if t0 <= target:
        return
    m = o.modifiers.new("DEC", 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.ratio = target / t0
    m.use_symmetry = True
    m.symmetry_axis = 'X'
    activate(o)
    bpy.ops.object.modifier_apply(modifier=m.name)


def triangulate(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(o.data)
    bm.free()


def boundary_loops(bm):
    """Closed boundary loops of a bmesh as lists of BMVerts in order."""
    bedges = [e for e in bm.edges if e.is_boundary]
    left = set(bedges)
    loops = []
    while left:
        e0 = left.pop()
        loop = [e0.verts[0], e0.verts[1]]
        cur = e0
        while True:
            v = loop[-1]
            nxt = None
            for e in v.link_edges:
                if e in left and e.is_boundary:
                    nxt = e
                    break
            if nxt is None:
                break
            left.discard(nxt)
            w = nxt.other_vert(v)
            if w == loop[0]:
                break
            loop.append(w)
            cur = nxt
        loops.append(loop)
    return loops


# =================================================================================================
# Hems: a turned lip round every opening
# =================================================================================================
def add_lips(o, spec_fn):
    """Hems every boundary loop of o that spec_fn(loop points) names: returns (thickness, depth)
    or None. The lip rolls from the edge round the fabric's thickness and runs back up inside by
    `depth`; its faces are flagged in the "crowd_lip" face attribute (the atlas paints the shell
    under them and they sample the fabric just inside the edge). Returns [(tag, points)] of the
    edges hemmed."""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    uvl = bm.loops.layers.uv.active
    dl = bm.verts.layers.deform.active
    lip_l = bm.faces.layers.int.get("crowd_lip") or bm.faces.layers.int.new("crowd_lip")
    orig_l = bm.verts.layers.int.get("orig")
    done = []
    for loop in boundary_loops(bm):
        pts = np.array([v.co[:] for v in loop])
        spec = spec_fn(pts)
        if spec is None:
            continue
        tag, th, depth = spec
        n = len(loop)
        # orientation: which way the boundary runs in its faces
        rings = []
        for i, v in enumerate(loop):
            nrm = v.normal.copy()
            interior = [e.other_vert(v) for e in v.link_edges if not e.is_boundary]
            if interior:
                ic = sum((w.co for w in interior), Vector()) / len(interior)
            else:
                ic = sum((f.calc_center_median() for f in v.link_faces), Vector()) / max(len(v.link_faces), 1)
            a = ic - v.co
            d = -(a - nrm * a.dot(nrm))
            if d.length < 1e-6:
                d = (loop[(i + 1) % n].co - loop[i - 1].co).cross(nrm)
            d.normalize()
            p = v.co
            rp = [p + d * th * 0.45 - nrm * th * 0.35, p - nrm * th, p - nrm * th - d * depth]
            rv = []
            for q in rp:
                nv = bm.verts.new(q)
                if dl is not None:
                    nv[dl].clear()
                    for gi, w in v[dl].items():
                        nv[dl][gi] = w
                if orig_l is not None:
                    nv[orig_l] = v[orig_l]
                rv.append(nv)
            rings.append(rv)
        bm.verts.index_update()
        index = {v: i for i, v in enumerate(loop)}
        for i in range(n):
            a, b = loop[i], loop[(i + 1) % n]
            e = bm.edges.get((a, b))
            if e is None or not e.link_faces:
                continue
            f = e.link_faces[0]
            # the face's own winding: does it run a -> b?
            fl = list(f.loops)
            la = next(lp for lp in fl if lp.vert == a)
            forward = la.link_loop_next.vert == b
            lb = next(lp for lp in fl if lp.vert == b)
            others = [lp[uvl].uv for lp in fl if lp.vert not in (a, b)]
            cuv = sum(others, Vector((0.0, 0.0))) / max(len(others), 1)
            ua, ub = la[uvl].uv.copy(), lb[uvl].uv.copy()
            ra, rb = rings[index[a]], rings[index[b]]
            cols = [(a, b, ua, ub)] + [(ra[k], rb[k], ua + (cuv - ua) * fk, ub + (cuv - ub) * fk)
                                       for k, fk in enumerate((0.05, 0.10, 0.22))]
            for k in range(3):
                va0, vb0, uva0, uvb0 = cols[k]
                va1, vb1, uva1, uvb1 = cols[k + 1]
                quad = [vb0, va0, va1, vb1] if forward else [va0, vb0, vb1, va1]
                quv = [uvb0, uva0, uva1, uvb1] if forward else [uva0, uvb0, uvb1, uva1]
                try:
                    nf = bm.faces.new(quad)
                except ValueError:
                    continue
                nf.smooth = True
                nf[lip_l] = 1
                for lp, uv in zip(nf.loops, quv):
                    lp[uvl].uv = uv
        done.append((tag, [list(v.co) for v in loop]))
    bm.to_mesh(me)
    bm.free()
    return done


def extend_limb(o, sg, a, b, s_target, r_fn, z_below, step=0.025):
    """Carries the lowest open loop on one side (x * sg > 0, below z_below) on down the limb
    a->b to s_target: rings on the tube r_fn(s) round the limb's axis, each vertex keeping its
    direction round it, weights copied, UVs continued down the island. For trouser legs that
    must reach the shoe where the skin under the shoe's collar is gone."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.normal_update()
    uvl = bm.loops.layers.uv.active
    dl = bm.verts.layers.deform.active
    cand = []
    for loop in boundary_loops(bm):
        c = sum((v.co for v in loop), Vector()) / len(loop)
        if c.x * sg > 0 and c.z < z_below:
            cand.append((c.z, loop))
    if not cand:
        bm.free()
        return 0
    loop = min(cand, key=lambda t: t[0])[1]
    a_, b_ = np.asarray(a), np.asarray(b)
    ax = (b_ - a_) / np.linalg.norm(b_ - a_)
    sv, uv_dir = [], []
    for v in loop:
        d = np.array(v.co) - a_
        s0 = d @ ax
        r = d - ax * s0
        sv.append(s0)
        uv_dir.append(r / max(np.linalg.norm(r), 1e-6))
    s_mean = float(np.mean(sv))
    if s_mean >= s_target - 0.005:
        bm.free()
        return 0
    n = max(1, int(math.ceil((s_target - s_mean) / step)))
    rings = [list(loop)]
    for k in range(1, n + 1):
        ring = []
        for j, v in enumerate(loop):
            s_new = sv[j] + (s_target - s_mean) * k / n
            q = a_ + ax * s_new + uv_dir[j] * float(r_fn(s_new))
            nv = bm.verts.new(Vector(q))
            if dl is not None:
                for gi, w in v[dl].items():
                    nv[dl][gi] = w
            ring.append(nv)
        rings.append(ring)
    m = len(loop)
    for i in range(m):
        va, vb = loop[i], loop[(i + 1) % m]
        e = bm.edges.get((va, vb))
        if e is None or not e.link_faces:
            continue
        f = e.link_faces[0]
        fl = list(f.loops)
        la = next(lp for lp in fl if lp.vert == va)
        lb = next(lp for lp in fl if lp.vert == vb)
        forward = la.link_loop_next.vert == vb
        others = [lp for lp in fl if lp.vert not in (va, vb)]
        cuv = sum((lp[uvl].uv for lp in others), Vector((0.0, 0.0))) / max(len(others), 1)
        c3 = sum((lp.vert.co for lp in others), Vector()) / max(len(others), 1)
        ga = (la[uvl].uv - cuv) / max((va.co - c3).length, 1e-4)
        gb = (lb[uvl].uv - cuv) / max((vb.co - c3).length, 1e-4)
        for k in range(1, n + 1):
            a0, b0 = rings[k - 1][i], rings[k - 1][(i + 1) % m]
            a1, b1 = rings[k][i], rings[k][(i + 1) % m]
            da0, db0 = (a0.co - va.co).length, (b0.co - vb.co).length
            da1, db1 = (a1.co - va.co).length, (b1.co - vb.co).length
            uva0, uvb0 = la[uvl].uv + ga * da0, lb[uvl].uv + gb * db0
            uva1, uvb1 = la[uvl].uv + ga * da1, lb[uvl].uv + gb * db1
            quad = [b0, a0, a1, b1] if forward else [a0, b0, b1, a1]
            quv = [uvb0, uva0, uva1, uvb1] if forward else [uva0, uvb0, uvb1, uva1]
            try:
                nf = bm.faces.new(quad)
            except ValueError:
                continue
            nf.smooth = True
            for lp, uv in zip(nf.loops, quv):
                lp[uvl].uv = uv
    bm.to_mesh(o.data)
    bm.free()
    return n


# =================================================================================================
# Swept bands (collars, cuffs, waistbands, plackets)
# =================================================================================================
def sweep(ctx, name, frames, profile, closed, caps=False):
    """A band swept along `frames` (list of (centre, radial dir, axial dir)); profile(i) gives the
    section at frame i as (radial offset, axial offset) pairs. Local UVs: u metres along the
    sweep, v metres along the section (in the "crowd_guv" corner attribute and, normalised, the
    UV map); returns the object."""
    verts, rows, uvs = [], [], []
    arc, prev = 0.0, None
    for i, (c, d, ax) in enumerate(frames):
        prof = profile(i)
        mid = c + d * prof[len(prof) // 3][0] + ax * prof[len(prof) // 3][1]
        if prev is not None:
            arc += (mid - prev).length
        prev = mid
        plen = [0.0]
        for k in range(1, len(prof)):
            plen.append(plen[-1] + math.hypot(prof[k][0] - prof[k - 1][0], prof[k][1] - prof[k - 1][1]))
        row = []
        for k, (r, h) in enumerate(prof):
            row.append(len(verts))
            verts.append(c + d * r + ax * h)
            uvs.append((arc, plen[k]))
        rows.append(row)
    total = arc + ((verts[rows[0][0]] - verts[rows[-1][0]]).length if closed else 0.0)
    faces, fuv = [], []
    nr = len(rows)
    for i in range(nr if closed else nr - 1):
        a_, b_ = rows[i], rows[(i + 1) % nr]
        wrap = closed and i == nr - 1
        for k in range(len(a_) - 1):
            q = (a_[k], a_[k + 1], b_[k + 1], b_[k])
            quv = [uvs[a_[k]], uvs[a_[k + 1]], (total if wrap else uvs[b_[k + 1]][0], uvs[b_[k + 1]][1]),
                   (total if wrap else uvs[b_[k]][0], uvs[b_[k]][1])]
            faces.append(q)
            fuv.append(quv)
    if caps and not closed:
        for row, rev in ((rows[0], True), (rows[-1], False)):
            q = tuple(reversed(row)) if rev else tuple(row)
            faces.append(q)
            fuv.append([uvs[j] for j in q])
    return mesh_with_local_uv(ctx, name, verts, faces, fuv)


def mesh_with_local_uv(ctx, name, verts, faces, fuv):
    """A mesh from world points and faces with per-corner local UVs in metres (stored as
    "crowd_guv" and, normalised into the unit square, as the UV map)."""
    me = bpy.data.meshes.new(name)
    mwi = ctx.body.mwi
    me.from_pydata([tuple(mwi @ Vector(v)) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    allu = np.array([uv for q in fuv for uv in q]) if fuv else np.zeros((1, 2))
    lo = allu.min(0)
    span = float(max((allu.max(0) - lo).max(), 1e-3))
    # Both layers first, then looked up again by name: adding a corner attribute reallocates the
    # corner data, and a handle taken before it writes into the wrong buffer (the first collars
    # kept Blender's default unit square on every face, and their metric UVs were garbage).
    me.uv_layers.new(name="UVMap")
    me.attributes.new("crowd_guv", 'FLOAT_VECTOR', 'CORNER')
    nl = len(me.loops)
    uv_flat = np.zeros((nl, 2), np.float32)
    g_flat = np.zeros((nl, 3), np.float32)
    for poly, quv in zip(me.polygons, fuv):
        for li, uv in zip(poly.loop_indices, quv):
            uv_flat[li] = ((uv[0] - lo[0]) / span, (uv[1] - lo[1]) / span)
            g_flat[li] = (uv[0], uv[1], 0.0)
    me.uv_layers["UVMap"].data.foreach_set("uv", uv_flat.ravel())
    me.attributes["crowd_guv"].data.foreach_set("vector", g_flat.ravel())
    for p in me.polygons:
        p.use_smooth = True
    o = new_mesh_object(ctx, name, me)
    o["crowd_uv_span"] = span
    return o


def fix_winding(o, centre_fn):
    """Faces of a band point away from centre_fn(face centre) (world space)."""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    score = 0.0
    mw = o.matrix_world
    for f in bm.faces:
        c = mw @ f.calc_center_median()
        score += (mw.to_3x3() @ f.normal).dot(c - Vector(centre_fn(c))) * f.calc_area()
    if score < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()


def weights_from_body(ctx, o):
    """Skin weights for a new part: interpolated from the nearest body faces."""
    body = ctx.body.obj
    for g in body.vertex_groups:
        if g.name not in o.vertex_groups:
            o.vertex_groups.new(name=g.name)
    m = o.modifiers.new("DT", 'DATA_TRANSFER')
    m.object = body
    m.use_vert_data = True
    m.data_types_verts = {'VGROUP_WEIGHTS'}
    m.vert_mapping = 'POLYINTERP_NEAREST'
    m.layers_vgroup_select_src = 'ALL'
    m.layers_vgroup_select_dst = 'NAME'
    activate(o)
    bpy.ops.object.modifier_apply(modifier=m.name)


def move_weight(o, sources, target, frac, where=None):
    """Moves `frac` of the named source groups' weight to `target` (optionally only on vertices
    where where(co) is true)."""
    tg = o.vertex_groups.get(target) or o.vertex_groups.new(name=target)
    src = {o.vertex_groups[n].index: n for n in sources if n in o.vertex_groups}
    for v in o.data.vertices:
        if where is not None and not where(v.co):
            continue
        moved = 0.0
        for g in v.groups:
            if g.group in src and g.weight > 0:
                w = g.weight
                o.vertex_groups[src[g.group]].add([v.index], w * (1.0 - frac), 'REPLACE')
                moved += w * frac
        if moved > 0:
            tg.add([v.index], moved, 'ADD')


def smooth_weights(o, iters=3, where=None, names=None):
    """Blurs weights over the mesh's own edges (optionally only the named groups, and only on
    vertices where where(co)); the total weight of each vertex is kept."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    dl = bm.verts.layers.deform.active
    if dl is None:
        bm.free()
        return
    bm.verts.ensure_lookup_table()
    if names is None:
        gids = sorted({g for v in bm.verts for g in v[dl].keys()})
    else:
        gids = [o.vertex_groups[n].index for n in names if n in o.vertex_groups]
    W0 = np.array([[v[dl].get(g, 0.0) for g in gids] for v in bm.verts])
    mask = np.array([True if where is None else where(v.co) for v in bm.verts])
    W = W0.copy()
    nb = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
    for _ in range(iters):
        avg = np.array([W[n].mean(0) if n else W[i] for i, n in enumerate(nb)])
        W = np.where(mask[:, None], 0.5 * W + 0.5 * avg, W)
    for i, v in enumerate(bm.verts):
        if not mask[i]:
            continue
        tot0, tot = W0[i].sum(), W[i].sum()
        sc = tot0 / tot if tot > 1e-6 else 0.0
        for k, g in enumerate(gids):
            w = W[i, k] * sc
            if w > 1e-4:
                v[dl][g] = w
            elif g in v[dl]:
                del v[dl][g]
    bm.to_mesh(o.data)
    bm.free()


def off_the_head(o, keep_neck):
    """A collar does not turn with the head (the hero's tracksuit): the head's share and most of
    the neck's go to the chest."""
    move_weight(o, ["Head", "head_end", "headfront"], "Spine", 1.0)
    move_weight(o, ["neck"], "Spine", 1.0 - keep_neck)


def mark(o, garment, part, region, fabric, gid):
    o["crowd_own"] = json.dumps({"garment": garment, "part": part, "region": region, "fabric": fabric, "gid": gid})


# =================================================================================================
# Shaping: how cloth hangs
# =================================================================================================
class Slices:
    """Horizontal slices of the torso's body vertices: each slice's convex hull (x, y) and its
    centre, for bridging a garment over the body's hollows."""

    def __init__(self, V, z0, z1, step=0.01):
        self.z0, self.step = z0, step
        self.n = max(2, int(math.ceil((z1 - z0) / step)) + 1)
        self.hulls, self.centres = [], []
        for k in range(self.n):
            zc = z0 + k * step
            sel = V[np.abs(V[:, 2] - zc) < step * 0.9]
            if len(sel) < 6:
                self.hulls.append(None)
                self.centres.append(None)
                continue
            pts = [Vector((p[0], p[1])) for p in sel]
            idx = MG.convex_hull_2d(pts)
            poly = np.array([[pts[i].x, pts[i].y] for i in idx])
            self.hulls.append(poly)
            self.centres.append(poly.mean(0))
        # fill gaps
        for k in range(self.n):
            if self.hulls[k] is None:
                near = min((j for j in range(self.n) if self.hulls[j] is not None), key=lambda j: abs(j - k), default=None)
                if near is not None:
                    self.hulls[k] = self.hulls[near]
                    self.centres[k] = self.centres[near]

    def index(self, z):
        return int(min(max(round((z - self.z0) / self.step), 0), self.n - 1))

    def centre(self, z):
        return self.centres[self.index(z)]

    def hull_radius(self, z, theta):
        """Radius of the slice's hull from its centre toward azimuth theta (0 = front, -y)."""
        k = self.index(z)
        poly, c = self.hulls[k], self.centres[k]
        if poly is None:
            return 0.0
        d = np.array([math.sin(theta), -math.cos(theta)])
        best = 0.0
        m = len(poly)
        for i in range(m):
            a, b = poly[i] - c, poly[(i + 1) % m] - c
            # ray t*d hits segment a + s (b - a)
            e = b - a
            den = d[0] * (-e[1]) - d[1] * (-e[0])
            if abs(den) < 1e-12:
                continue
            t = (a[0] * (-e[1]) - a[1] * (-e[0])) / den
            s = (d[0] * a[1] - d[1] * a[0]) / den
            if t > 0 and -1e-6 <= s <= 1 + 1e-6:
                best = max(best, t)
        return best


def _ray_poly(c, theta, poly):
    """Distance from c along azimuth theta (0 = front, -y) to the far boundary of a 2D polygon."""
    d = np.array([math.sin(theta), -math.cos(theta)])
    a = poly - c
    e = np.roll(poly, -1, 0) - poly
    den = d[0] * (-e[:, 1]) - d[1] * (-e[:, 0])
    ok = np.abs(den) > 1e-12
    t = np.where(ok, (a[:, 0] * (-e[:, 1]) - a[:, 1] * (-e[:, 0])) / np.where(ok, den, 1.0), -1.0)
    s = np.where(ok, (d[0] * a[:, 1] - d[1] * a[:, 0]) / np.where(ok, den, 1.0), -1.0)
    hit = ok & (t > 0) & (s >= -1e-6) & (s <= 1 + 1e-6)
    return float(t[hit].max()) if hit.any() else 0.0


def _blur_grid(G, sig_th, sig_z):
    """Gaussian blur of an (azimuth, z) grid: circular round the body, clamped along z."""
    def kern(sig):
        r = max(1, int(math.ceil(sig * 2.5)))
        k = np.exp(-0.5 * (np.arange(-r, r + 1) / max(sig, 1e-6)) ** 2)
        return k / k.sum(), r
    if sig_th > 0:
        k, r = kern(sig_th)
        G = sum(w * np.roll(G, j - r, 0) for j, w in enumerate(k))
    if sig_z > 0:
        k, r = kern(sig_z)
        Gp = np.pad(G, ((0, 0), (r, r)), mode='edge')
        G = sum(w * Gp[:, j:j + G.shape[1]] for j, w in enumerate(k))
    return G


class Envelope:
    """The smooth surface a garment hangs as round the torso or the pelvis: R(azimuth, z) about a
    vertical axis that bends smoothly with height. Each 1 cm slice of the body points it goes
    over is bridged to its convex hull (the cloth spans the breastbone, the spine and the hollows
    either side of them), eased by `ease`, and with `slope` it HANGS from `z_hang` down: below
    the chest the cloth comes in toward the body no faster than `slope` metres per metre (a tee
    falls from the chest and the belly, it does not follow the waist in). The grid is blurred
    round the body and along it, so no cell ever steps against the next; the hull bridging and
    the hang done point by point on the shell's own vertices printed every lump of the mesh."""

    def __init__(self, V, z0, z1, ease, slope=None, z_hang=None, nth=96, dz=0.01, blur=(2.0, 1.5)):
        self.z0, self.dz, self.nth = z0, dz, nth
        zs = np.arange(z0, z1 + dz * 0.5, dz)
        self.nz = len(zs)
        polys, cents = [], []
        for z in zs:
            sel = V[np.abs(V[:, 2] - z) < dz * 0.9]
            if len(sel) < 6:
                polys.append(None)
                continue
            pts = [Vector((p[0], p[1])) for p in sel]
            hi = MG.convex_hull_2d(pts)
            poly = np.array([[pts[i].x, pts[i].y] for i in hi])
            polys.append(poly)
            cents.append((z, poly.mean(0)))
        cz = np.array([c[0] for c in cents])
        cxy = np.array([c[1] for c in cents])
        deg = 2 if len(cz) > 4 else 0
        self.fx = np.polyfit(cz, cxy[:, 0], deg)
        self.fy = np.polyfit(cz, cxy[:, 1], deg)
        R = np.zeros((nth, self.nz))
        have = np.zeros(self.nz, bool)
        for k, (z, poly) in enumerate(zip(zs, polys)):
            if poly is None:
                continue
            c = self.centre(z)
            R[:, k] = [_ray_poly(c, 2 * math.pi * t / nth, poly) for t in range(nth)]
            have[k] = True
        for k in range(self.nz):
            if not have[k]:
                j = min(np.where(have)[0], key=lambda j: abs(j - k))
                R[:, k] = R[:, j]
        G = R + ease
        if slope is not None:
            top = self.nz - 1 if z_hang is None else int(min(max(round((z_hang - z0) / dz), 0), self.nz - 1))
            for k in range(top - 1, -1, -1):
                G[:, k] = np.maximum(G[:, k], G[:, k + 1] - slope * dz)
        self.G = _blur_grid(G, blur[0], blur[1])

    def centre(self, z):
        return np.array([np.polyval(self.fx, z), np.polyval(self.fy, z)])

    def place(self, p):
        """The point on the envelope at p's height and azimuth."""
        c = self.centre(p[2])
        th = math.atan2(p[0] - c[0], -(p[1] - c[1])) % (2 * math.pi)
        tf = th / (2 * math.pi) * self.nth
        t0 = int(tf) % self.nth
        ft = tf - int(tf)
        zf = min(max((p[2] - self.z0) / self.dz, 0.0), self.nz - 1.0)
        z0 = int(min(zf, self.nz - 2)) if self.nz > 1 else 0
        fz = zf - z0
        z1 = min(z0 + 1, self.nz - 1)
        g = ((self.G[t0, z0] * (1 - ft) + self.G[(t0 + 1) % self.nth, z0] * ft) * (1 - fz)
             + (self.G[t0, z1] * (1 - ft) + self.G[(t0 + 1) % self.nth, z1] * ft) * fz)
        return np.array([c[0] + math.sin(th) * g, c[1] - math.cos(th) * g, p[2]])


def hang(P, centre_fn, z_top, z_bottom, slope, sel, src=None, nth=72, dz=0.01):
    """Below z_top the cloth may only come in toward the body at `slope` (metres per metre down):
    the cylindrical radius of each selected point is raised to the running maximum from above,
    less the slope. Only points of `src` (default `sel`) below z_top feed the maximum - a
    shoulder or a sleeve root above it would hang the whole front off itself."""
    out = P.copy()
    src = sel if src is None else src
    nz = int(math.ceil((z_top - z_bottom) / dz)) + 2
    R = np.full((nth, nz), -1.0)

    def cell(i):
        c = centre_fn(P[i, 2])
        dx, dy = P[i, 0] - c[0], P[i, 1] - c[1]
        th = math.atan2(dx, -dy)
        zi = int(min(max((z_top - P[i, 2]) / dz, 0), nz - 1))
        ti = int((th + math.pi) / (2 * math.pi) * nth) % nth
        return ti, zi, math.hypot(dx, dy), c
    for i in np.where(src & (P[:, 2] <= z_top))[0]:
        ti, zi, r, _ = cell(i)
        R[ti, zi] = max(R[ti, zi], r)
    # Empty cells take the row's neighbours; the profile is blurred round the body, so a 5-degree
    # cell never steps against the next one.
    for k in range(nz):
        row = R[:, k]
        ok = row > 0
        if ok.any() and not ok.all():
            xs = np.where(ok)[0]
            row[~ok] = np.interp(np.where(~ok)[0], np.concatenate([xs - nth, xs, xs + nth]), np.tile(row[ok], 3))
    R = (R + np.roll(R, 1, 0) + np.roll(R, -1, 0) + 0.5 * (np.roll(R, 2, 0) + np.roll(R, -2, 0))) / 4.0
    Rs = R.copy()
    for k in range(1, nz):
        Rs[:, k] = np.maximum(R[:, k], Rs[:, k - 1] - slope * dz)
    # A point is held only by the cloth ABOVE it (the row over its own, less the slope over the
    # distance down from it, interpolated in z). Raised to its own cell's maximum, every point of
    # a sloping cell - the underside of the pecs - stepped out to the cell's outermost one.
    for i in np.where(sel & (P[:, 2] <= z_top))[0]:
        ti, zi, r, c = cell(i)
        if zi == 0:
            continue
        zrow = z_top - (zi - 0.5) * dz
        want = Rs[ti, zi - 1] - slope * max(zrow - P[i, 2], 0.0)
        if want > r and r > 1e-4:
            f = want / r
            out[i, 0] = c[0] + (P[i, 0] - c[0]) * f
            out[i, 1] = c[1] + (P[i, 1] - c[1]) * f
    return out


def limb_frame(p, a, b):
    """(s along a->b from a, azimuth (0 front, +pi/2 toward +x), radial vector) for points p."""
    ax = (b - a) / np.linalg.norm(b - a)
    d = p - a
    s = d @ ax
    r = d - np.outer(s, ax)
    fwd = np.array([0.0, -1.0, 0.0])
    fwd = fwd - ax * (fwd @ ax)
    fwd /= np.linalg.norm(fwd)
    lat = np.cross(ax, fwd)
    if lat[0] < 0:
        lat = -lat
    return s, np.arctan2(r @ lat, r @ fwd), r, ax


def tube(P, sel, a, b, ease_fn, round_fn, min_r_fn=None, step=0.01, widen=None, widen_from=0.04,
         stat=None, pct=100.0):
    """Rounds the selected points into a tube round the segment a->b: each radius goes toward the
    largest in its slice (round_fn(s) 0..1) plus ease_fn(s), and never below min_r_fn(s). The
    slice radii are measured on `stat` (a mask over P, default `sel`) at percentile `pct`: a
    sleeve's slices measured on everything it holds took in the chest wall and the armpit at its
    root and came out as a bell. With `widen` (metres per metre) the slice radii never narrow
    faster than that going down the limb: a sleeve hangs from its cap, it does not close in."""
    out = P.copy()
    idx = np.where(sel)[0]
    if len(idx) == 0:
        return out
    s, az, r, ax = limb_frame(P[idx], a, b)
    rl = np.linalg.norm(r, axis=1)
    bins = np.round(s / step).astype(int)
    sm = sel if stat is None else stat
    sidx = np.where(sm)[0]
    if len(sidx) == 0:
        return out
    ss, _, rs_, _ = limb_frame(P[sidx], a, b)
    rsl = np.linalg.norm(rs_, axis=1)
    sb = np.round(ss / step).astype(int)
    keys = sorted(set(sb.tolist()))
    arr = np.array([np.percentile(rsl[sb == k], pct) for k in keys])
    # smooth the slice radii along the limb
    if len(arr) > 3:
        arr = np.convolve(np.pad(arr, 2, mode='edge'), np.ones(5) / 5, mode='valid')
    if widen is not None:
        for k in range(1, len(arr)):
            if keys[k] * step > widen_from:
                arr[k] = max(arr[k], arr[k - 1] - widen * step)
    # every bin the shaped points fall in, from the measured ones (held flat past either end)
    allb = np.arange(min(bins.min(), keys[0]), max(bins.max(), keys[-1]) + 1)
    rmax = dict(zip(allb.tolist(), np.interp(allb, np.array(keys, float), arr)))
    for j, i in enumerate(idx):
        rm = rmax[bins[j]]
        t = float(round_fn(s[j]))
        want = rl[j] + (rm - rl[j]) * t + float(ease_fn(s[j]))
        if min_r_fn is not None:
            want = max(want, float(min_r_fn(s[j])))
        if rl[j] > 1e-5:
            out[i] = a + ax * s[j] + r[j] / rl[j] * want
    return out


# =================================================================================================
# Garments
# =================================================================================================
class Ctx:
    def __init__(self, body, arm, cfg, name):
        self.body = Body(body, arm)
        self.cfg = cfg
        self.name = name
        self.parts = []       # every object made
        self.layers = []      # garment shells built so far (later ones go over them)
        # the library shoes (trouser hems fall over them)
        self.shoes = [o for o in arm.children if o.type == 'MESH' and o.name.split(".")[-1].startswith("shoes")]
        self.shoe_v = np.array([o.matrix_world @ v.co for o in self.shoes for v in o.data.vertices]) if self.shoes else np.zeros((0, 3))
        self.shoe_bvh = bvh_of(self.shoes) if self.shoes else None
        self.meta = {"garments": [], "bones": {k: list(v) for k, v in self.body.b.items()},
                     "crotch_z": self.body.crotch_z}

    def shoe_collar(self, side, sg):
        """(heel collar top z, tongue top z) of the shoe on one side, or None: the highest shoe
        points behind and in front of the ankle joint, within reach of the leg."""
        if not len(self.shoe_v):
            return None
        an = self.body.B(side + "Foot")
        S = self.shoe_v[(self.shoe_v[:, 0] * sg) > 0]
        d = np.hypot(S[:, 0] - an[0], S[:, 1] - an[1])
        back = S[(d < 0.07) & (S[:, 1] > an[1])]
        front = S[(d < 0.09) & (S[:, 1] <= an[1])]
        if not len(back) or not len(front):
            return None
        return float(back[:, 2].max()), float(front[:, 2].max())


def shell_density(o):
    """Atlas-source pixels per metre of the shell in the body UV layout (2048-px source)."""
    me = o.data
    uv = me.uv_layers.active.data
    a3 = a2 = 0.0
    for p in me.polygons:
        vs = [me.vertices[i].co for i in p.vertices]
        us = [uv[li].uv for li in p.loop_indices]
        for j in range(1, len(vs) - 1):
            a3 += (vs[j] - vs[0]).cross(vs[j + 1] - vs[0]).length * 0.5
            e1, e2 = us[j] - us[0], us[j + 1] - us[0]
            a2 += abs(e1.x * e2.y - e1.y * e2.x) * 0.5
    return 2048.0 * math.sqrt(a2 / a3) if a3 > 0 else PX_PER_M


def neck_ring_fn(ctx, z_back, z_front, flare, y_back_off=0.06, y_front_off=-0.07):
    """The neckline of a crew or turn-down collar: a plane from the back of the neck to the front,
    and round it a ring at the skin's radius plus `flare` (sampled, smoothed). Returns
    (axis (x, y), cut height fn(y), ring radius fn(a), the ring radii table)."""
    B = ctx.body
    NECK = B.B("neck")
    ay = NECK[1] + 0.005
    Y_BACK, Y_FRONT = NECK[1] + y_back_off, NECK[1] + y_front_off

    def cut_z(y):
        return z_back + (y - Y_BACK) / (Y_FRONT - Y_BACK) * (z_front - z_back)
    n = 72
    raw = []
    for k in range(n):
        a = 2 * math.pi * k / n
        d = np.array([math.sin(a), -math.cos(a), 0.0])
        zb = cut_z(ay - math.cos(a) * 0.06)
        # measured on the neck itself: at the sides the plane runs under the trapezius
        c = np.array([0.0, ay, zb + 0.035 + 0.01 * (1 - math.cos(a)) / 2])
        r = B.skin_hit(c, d, 0.14)
        raw.append(r)
    ok = [r for r in raw if r is not None]
    raw = [r if r is not None else sum(ok) / len(ok) for r in raw]
    ring = [sum(raw[(k + j) % n] for j in range(-3, 4)) / 7 + flare for k in range(n)]

    def radius(a):
        t = (a % (2 * math.pi)) / (2 * math.pi) * n
        k = int(t) % n
        f = t - int(t)
        return ring[k] * (1 - f) + ring[(k + 1) % n] * f
    return (0.0, ay), cut_z, radius, ring


def loop_by_azimuth(pts, axis, n, smooth=2):
    """A closed edge loop round a vertical axis resampled at n azimuths (0 = front):
    [(radius, z)], smoothed over `smooth` neighbours either side."""
    ax, ay = axis
    P = np.asarray(pts)
    az = np.arctan2(P[:, 0] - ax, -(P[:, 1] - ay)) % (2 * math.pi)
    r = np.hypot(P[:, 0] - ax, P[:, 1] - ay)
    o = np.argsort(az)
    az, r, z = az[o], r[o], P[o, 2]
    azp = np.concatenate([az - 2 * math.pi, az, az + 2 * math.pi])
    rp, zp = np.tile(r, 3), np.tile(z, 3)
    q = np.arange(n) * 2 * math.pi / n
    R, Z = np.interp(q, azp, rp), np.interp(q, azp, zp)
    if smooth:
        k = np.ones(2 * smooth + 1) / (2 * smooth + 1)
        R = np.convolve(np.concatenate([R[-smooth:], R, R[:smooth]]), k, mode='valid')
        Z = np.convolve(np.concatenate([Z[-smooth:], Z, Z[:smooth]]), k, mode='valid')
    return list(zip(R, Z))


def neck_loop(o, z_min):
    """The top's neck edge: the boundary loop highest up."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    best = None
    for loop in boundary_loops(bm):
        pts = [tuple(v.co) for v in loop]
        zc = sum(p[2] for p in pts) / len(pts)
        if zc > z_min and (best is None or zc > best[0]):
            best = (zc, pts)
    bm.free()
    return best[1] if best else None


def collar_rib(ctx, name, axis, edge_pts, height, gid, garment, region, fabric, seg=36, th=0.0028):
    """A rib collar on the neckline (crew neck): tucked inside the shell's cut edge, rising
    `height` up the neck a few millimetres off it, rolled over at the top and back down inside."""
    B = ctx.body
    ax, ay = axis
    edge = loop_by_azimuth(edge_pts, axis, seg, 1)
    frames, profs = [], []
    for k in range(seg):
        a = 2 * math.pi * k / seg
        d = Vector((math.sin(a), -math.cos(a), 0.0))
        r_e, z_e = edge[k]
        c = Vector((ax, ay, z_e))
        s_hi = B.skin_hit(np.array([ax, ay, z_e + height]), np.array(d), 0.16)
        r_top = min((s_hi if s_hi is not None else r_e - 0.01) + 0.004 + th, r_e - 0.001)
        frames.append((c, d, Vector((0, 0, 1))))
        profs.append([(r_e - th * 1.2, -0.010), (r_e + th * 0.6, 0.0015), (r_e * 0.5 + r_top * 0.5 + th * 0.3, height * 0.5),
                      (r_top, height - th), (r_top - th * 0.7, height), (r_top - th * 1.5, height - th * 1.2),
                      (r_e - th * 2.6, -0.004)])
    o = sweep(ctx, name, frames, lambda i: profs[i], closed=True)
    fix_winding(o, lambda c: (ax, ay, c.z))
    weights_from_body(ctx, o)
    off_the_head(o, 0.25)
    smooth_weights(o, 3)
    mark(o, garment, "collar_rib", region, fabric, gid)
    return o


def build_top_shell(ctx, g, gid, kind):
    """The shell of a top (tee, shirt, jacket): torso and sleeves, shaped, cut and hemmed.
    Returns (object, landmarks dict)."""
    B = ctx.body
    V, cent = B.V, B.cent
    NECK = B.B("neck")
    CHEST = B.B("Spine")
    fit = g.get("fit", "regular")
    off_t = {"fitted": 0.006, "regular": 0.011, "loose": 0.018, "jacket": 0.022}[fit]
    slope = {"fitted": 0.7, "regular": 0.3, "loose": 0.2, "jacket": 0.22}[fit]
    hip_z = B.B("LeftUpLeg")[2]
    z_hem = hip_z + g.get("hem", -0.02)
    neck_back = NECK[2] + g.get("neck_back", -0.006)
    neck_front = NECK[2] + g.get("neck_front", -0.058)
    long_sleeve = g.get("sleeve", "short") != "short"
    # sleeve end: along the upper arm (short) or the forearm (long / rolled)
    ends = {}
    for side, sg in SIDES:
        sh, el, wr = B.B(side + "Arm"), B.B(side + "ForeArm"), B.B(side + "Hand")
        if g.get("sleeve", "short") == "short":
            ends[side] = ("up", sh, el, g.get("sleeve_t", 0.58) * np.linalg.norm(el - sh))
        elif g.get("sleeve") == "rolled":
            ends[side] = ("fore", el, wr, g.get("sleeve_t", 0.42) * np.linalg.norm(wr - el))
        else:
            ends[side] = ("fore", el, wr, np.linalg.norm(wr - el) - g.get("cuff_above_wrist", 0.012))
    margin = 0.035
    mask = np.zeros(len(B.F), bool)
    for i, c in enumerate(cent):
        d = B.fdom[i]
        if d in HEAD_BONES or d in FEET or d in LEG_LO or d.endswith("Hand"):
            continue
        if d == "neck" and c[2] > neck_back + 0.015:
            continue
        if c[2] < z_hem - margin:
            continue
        side = "Left" if c[0] > 0 else "Right"
        if d.endswith("ForeArm"):
            e = ends[side]
            if e[0] != "fore":
                continue
            s = (c - e[1]) @ ((e[2] - e[1]) / np.linalg.norm(e[2] - e[1]))
            if s > e[3] + margin:
                continue
        if d.endswith("Arm") and not d.endswith("ForeArm"):
            e = ends[side]
            if e[0] == "up":
                s = (c - e[1]) @ ((e[2] - e[1]) / np.linalg.norm(e[2] - e[1]))
                if s > e[3] + margin:
                    continue
        if d in LEG_UP and c[2] < z_hem - margin:
            continue
        mask[i] = True
    o = shell_from_faces(ctx, kind, mask)
    orig = get_orig(o)
    P, nbr, bound = mesh_arrays(o)
    base = B.Vs[orig]
    nrm = B.VNs[orig]
    vd = B.vdom[orig]
    # which vertices are sleeve: arm-weighted and past the armhole plane (shoulder joint,
    # perpendicular to the upper arm), faded over a few centimetres and smoothed
    w_sl = np.zeros(len(P))
    side_of = np.zeros(len(P), int)
    for k, (side, sg) in enumerate(SIDES):
        sh, el = B.B(side + "Arm"), B.B(side + "ForeArm")
        ax = (el - sh) / np.linalg.norm(el - sh)
        s = (base - sh) @ ax
        on = np.array([(x or "").startswith(side) and ("Arm" in (x or "")) for x in vd]) & ((base[:, 0] * sg) > 0)
        w = np.where(on, smoothstep(-0.02, 0.035, s), 0.0)
        side_of[w > 0.5] = k + 1
        w_sl = np.maximum(w_sl, w)
    w_sl = smooth_field(w_sl, nbr, 4)
    # 1. offset: the torso off the body by the fit, the sleeves rounded into tubes that start at
    #    the shoulder joint (rounding the joint itself puffed every cap into a shoulder pad)
    Pt = base + nrm * off_t
    Ps = Pt.copy()
    for side, sg in SIDES:
        sh, el, wr = B.B(side + "Arm"), B.B(side + "ForeArm"), B.B(side + "Hand")
        L1 = np.linalg.norm(el - sh)
        sel_up = (w_sl > 0.01) & ((base[:, 0] * sg) > 0)
        if ends[side][0] == "up":
            s_end = ends[side][3]
            e0, fl = g.get("sleeve_ease", 0.008), g.get("sleeve_flare", 0.007)
            ease = lambda s, s_end=s_end, e0=e0, fl=fl: 0.002 + (e0 + fl * float(np.clip(s / s_end, 0, 1))) * float(smoothstep(0.08, 0.5, s / s_end))
            rnd = lambda s, s_end=s_end: 0.6 * float(smoothstep(0.1, 0.55, s / s_end))
        else:
            ease = lambda s, L1=L1: 0.002 + g.get("sleeve_ease", 0.008) * float(smoothstep(0.08, 0.5, s / L1))
            rnd = lambda s, L1=L1: 0.55 * float(smoothstep(0.1, 0.5, s / L1))
        s_up, _, _, _ = limb_frame(base, sh, el)
        # the slices measured on the arm's own skin, past the armpit (the chest wall and the
        # shoulder's side of the joint made every sleeve a bell)
        on_arm = sel_up & np.array([x in (side + "Arm", side + "ForeArm") for x in vd]) & (s_up > 0.03)
        Ps = tube(Ps, sel_up & (s_up < L1 + 0.02), sh, el, ease, rnd, widen=g.get("sleeve_taper", 0.12),
                  widen_from=0.08, stat=on_arm, pct=90.0)
        if ends[side][0] == "fore":
            s_fo, _, _, _ = limb_frame(base, el, wr)
            on_fo = sel_up & (s_fo > -0.02)
            L2 = np.linalg.norm(wr - el)
            e_end = g.get("cuff_ease", 0.008) if g.get("sleeve") != "rolled" else g.get("roll_ease", 0.016)
            e_up = g.get("sleeve_ease", 0.008) + 0.002
            Ps = tube(Ps, on_fo, el, wr, lambda s, L2=L2, e_end=e_end, e_up=e_up: e_up + (e_end - e_up) * float(np.clip(s / L2, 0, 1)),
                      lambda s: 0.5, stat=on_fo & np.array([x == side + "ForeArm" for x in vd]), pct=90.0)
    Pn = Pt * (1 - w_sl[:, None]) + Ps * w_sl[:, None]
    Pn = taubin(Pn, nbr, bound, 12)
    # 2. the torso as an envelope (Envelope): bridged over the body's hollows and hung from the
    #    chest, laid onto the shell below the chest and faded out over the shoulders, where the
    #    offset shell carries the shape. Torso bones only (shoulder-weighted skin runs out over
    #    the deltoid and would bridge to the arm), the armpit's side of the shoulder kept.
    sh_x = abs(B.B("LeftArm")[0])
    torso_idx = np.array([x in ("Hips", "Spine02", "Spine01", "Spine", "neck") or x in LEG_UP for x in B.vdom])
    torso_idx |= np.array([x.endswith("Shoulder") for x in B.vdom]) & (np.abs(B.Vs[:, 0]) < 0.8 * sh_x)
    z_env_top = CHEST[2] + g.get("envelope_top", 0.05)
    tv = B.Vs[torso_idx & (V[:, 2] > z_hem - 0.08) & (V[:, 2] < z_env_top + 0.04)]
    env = Envelope(tv, z_hem - 0.08, z_env_top + 0.03, off_t, slope=slope, z_hang=CHEST[2] + g.get("hang_from", 0.0))
    fade = 1.0 - smoothstep(z_env_top - 0.06, z_env_top, Pn[:, 2])
    wt = np.clip((1.0 - w_sl) * fade, 0.0, 1.0)
    for i in np.where(wt > 1e-3)[0]:
        Pn[i] = Pn[i] * (1.0 - wt[i]) + env.place(Pn[i]) * wt[i]
    Pn = taubin(Pn, nbr, bound, 3)
    # 4. clear the (smoothed) body and whatever the top goes over
    Pn = push_out(Pn, [B.bvh_s], 0.006, dirs=nrm)
    if ctx.layers:
        Pn = push_out(Pn, [bvh_of(ctx.layers)], 0.007, dirs=nrm)
    set_positions(o, Pn)
    # which part of the top each face is (0 torso, 1 left sleeve, 2 right sleeve), for the cuts
    zl = o.data.attributes.new("zone", 'INT', 'FACE')
    zl.data.foreach_set("value", [int(np.bincount(side_of[list(p.vertices)], minlength=3).argmax()) for p in o.data.polygons])
    L = {"z_hem": z_hem, "neck_back": neck_back, "neck_front": neck_front, "fit": fit, "off": off_t,
         "sleeve": g.get("sleeve", "short"), "ends": {}}
    for side, sg in SIDES:
        e = ends[side]
        a, b = e[1], e[2]
        ax = (b - a) / np.linalg.norm(b - a)
        L["ends"][side] = {"co": list(a + ax * e[3]), "no": list(ax)}
    return o, L


def cut_top(ctx, o, L, neck_hole=True):
    """Cuts the top's hem and sleeve ends (each sleeve's own faces only)."""
    z_hem = L["z_hem"]
    cut(o, (0, 0, z_hem), (0, 0, 1), lambda c: c.z < z_hem + 0.08, lambda c: c.z < z_hem, zone=0)
    for k, (side, sg) in enumerate(SIDES):
        e = L["ends"][side]
        co, no = Vector(e["co"]), Vector(e["no"])
        cut(o, co, no, lambda c: True, lambda c, co=co, no=no: no.dot(c - co) > 0, zone=k + 1)
    # a sleeve face on the torso's side of the hem plane (the forearm hangs past it) stays
    keep_largest_part(o)


def top_lips(ctx, o, L, hem, sleeve, neck=None):
    """Hems for a top's openings: (tag, thickness, depth) for the hem, sleeves and neck."""
    z_hem = L["z_hem"]

    def spec(pts):
        zc = pts[:, 2].mean()
        if abs(zc - z_hem) < 0.03 and np.ptp(pts[:, 0]) > 0.2:
            return ("hem",) + hem
        xc = pts[:, 0].mean()
        for side, sg in SIDES:
            e = L["ends"][side]
            if (xc * sg) > 0.1 and abs(np.mean((pts - np.array(e["co"])) @ np.array(e["no"]))) < 0.03:
                return ("sleeve_" + side,) + sleeve
        if neck is not None and zc > L["neck_front"] - 0.05:
            return ("neck",) + neck
        return None
    return add_lips(o, spec)


def tee(ctx, g, gid):
    B = ctx.body
    o, L = build_top_shell(ctx, g, gid, "tee")
    cut_top(ctx, o, L)
    axis, cut_z, radius, ring = neck_ring_fn(ctx, L["neck_back"], L["neck_front"], L["off"] + g.get("neck_flare", 0.008))
    NECK = B.B("neck")
    CHEST = B.B("Spine")
    cut_neck(o, axis, radius, L["neck_back"], L["neck_front"], NECK[1] + 0.06, NECK[1] - 0.07, CHEST[2] + 0.02)
    keep_largest_part(o)
    subdivide(o, 1)
    decimate(o, g.get("tris", 1900))
    clear_of(o, [B.bvh] + ([bvh_of(ctx.layers)] if ctx.layers else []), 0.005)
    L["hems"] = top_lips(ctx, o, L, hem=(0.003, 0.018), sleeve=(0.003, 0.016))
    smooth_weights(o, 6, where=lambda c: min((c - Vector(B.B("LeftArm"))).length, (c - Vector(B.B("RightArm"))).length) < 0.13,
                   names=["LeftShoulder", "RightShoulder", "LeftArm", "RightArm", "Spine", "Spine01", "neck"])
    off_the_head(o, 0.35)
    move_weight(o, list(LEG_UP), "Hips", 0.6)
    mark(o, "tee", "shell", "top", g.get("fabric", "jersey"), gid)
    edge_pts = neck_loop(o, CHEST[2])
    collar = collar_rib(ctx, "tee_collar", axis, edge_pts, g.get("collar_h", 0.017), gid, "tee", "top", g.get("fabric", "jersey"))
    L["neck_ring"] = {"axis": list(axis), "ring": ring}
    L["neck_cut"] = [L["neck_back"], L["neck_front"], NECK[1] + 0.06, NECK[1] - 0.07]
    ctx.layers.append(o)
    return [o, collar], L


# ---- bands on any edge, the shirt and the jacket ------------------------------------------------------
def boundary_points(o):
    """Every boundary loop of o as (centroid, points (n, 3))."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    out = []
    for loop in boundary_loops(bm):
        pts = np.array([v.co[:] for v in loop])
        out.append((pts.mean(0), pts))
    bm.free()
    return out


def loop_frames(pts, centre, axis, ref, n, smooth=2):
    """A closed edge loop round an axis (through `centre` along `axis`) resampled at n azimuths
    measured from `ref` (a direction square to the axis): per azimuth (radius, height along the
    axis), smoothed over `smooth` neighbours, and the radial unit vector."""
    axis = np.asarray(axis, np.float64) / np.linalg.norm(axis)
    e1 = np.asarray(ref, np.float64) - axis * (np.asarray(ref) @ axis)
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(axis, e1)
    d = np.asarray(pts) - centre
    h = d @ axis
    rv = d - np.outer(h, axis)
    az = np.arctan2(rv @ e2, rv @ e1) % (2 * math.pi)
    r = np.linalg.norm(rv, axis=1)
    o = np.argsort(az)
    az, r, h = az[o], r[o], h[o]
    azp = np.concatenate([az - 2 * math.pi, az, az + 2 * math.pi])
    q = np.arange(n) * 2 * math.pi / n
    R, Hh = np.interp(q, azp, np.tile(r, 3)), np.interp(q, azp, np.tile(h, 3))
    if smooth:
        k = np.ones(2 * smooth + 1) / (2 * smooth + 1)
        R = np.convolve(np.concatenate([R[-smooth:], R, R[:smooth]]), k, mode='valid')
        Hh = np.convolve(np.concatenate([Hh[-smooth:], Hh, Hh[:smooth]]), k, mode='valid')
    dirs = [e1 * math.cos(a) + e2 * math.sin(a) for a in q]
    return R, Hh, dirs, axis


def edge_band(ctx, name, loop_pts, centre, axis, ref, profile, n=40):
    """A closed band swept round an edge loop: profile(k, r_edge) -> [(radial, axial)] offsets
    from the axis point level with the edge (radial absolute, axial relative to the edge)."""
    R, Hh, dirs, ax = loop_frames(loop_pts, np.asarray(centre), axis, ref, n)
    frames, profs = [], []
    for k in range(n):
        c = Vector(np.asarray(centre) + ax * Hh[k])
        frames.append((c, Vector(dirs[k]), Vector(ax)))
        profs.append(profile(k, R[k], dirs[k], ax))
    o = sweep(ctx, name, frames, lambda i: profs[i], closed=True)
    return o


def rib_profile(r_e, length, pull, th=0.003, tuck=0.010):
    """A rib band hanging from an edge along +axial: tucked under the garment's edge, pulled in
    by `pull` toward its free end, rolled over there and back up inside."""
    return [(r_e - th * 1.4, -tuck), (r_e + th * 0.5, 0.0015), (r_e - pull * 0.5 + th * 0.4, length * 0.5),
            (r_e - pull + th * 0.3, length - th), (r_e - pull - th * 0.6, length), (r_e - pull - th * 1.4, length - th * 1.2),
            (r_e - th * 2.4, -tuck * 0.4)]


def finish_band(ctx, o, garment, part, region, fabric, gid, centre_fn, head=False, keep_neck=0.25):
    fix_winding(o, centre_fn)
    weights_from_body(ctx, o)
    if head:
        off_the_head(o, keep_neck)
    smooth_weights(o, 3)
    mark(o, garment, part, region, fabric, gid)
    return o


def cut_curve(o, centre_y_fn, zfn, z_lo, z_hi, zone=None, n=48, r_ref=0.15):
    """A hem that is not a plane (a shirt tail): faces between z_lo and z_hi bisected sector by
    sector (round the torso axis) by the plane tangent to the surface z = zfn(azimuth) there,
    and everything under the curve deleted."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    zl = bm.faces.layers.int.get("zone")

    def az(c):
        return math.atan2(c.x, -(c.y - centre_y_fn(c.z))) % (2 * math.pi)

    def inzone(f):
        return zone is None or zl is None or f[zl] == zone
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        am = 0.5 * (a0 + a1)
        faces = [f for f in bm.faces if inzone(f) and z_lo < f.calc_center_median().z < z_hi
                 and int(az(f.calc_center_median()) / (2 * math.pi) * n) % n == k]
        if not faces:
            continue
        yc = centre_y_fn(zfn(am))
        A = Vector((math.sin(a0) * r_ref, yc - math.cos(a0) * r_ref, zfn(a0)))
        Bp = Vector((math.sin(a1) * r_ref, yc - math.cos(a1) * r_ref, zfn(a1)))
        rad = Vector((math.sin(am), -math.cos(am), 0.0))
        no = (Bp - A).cross(rad).normalized()
        if no.z < 0:
            no = -no
        geom = list({v for f in faces for v in f.verts}) + list({e for f in faces for e in f.edges}) + faces
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(A + Bp) * 0.5, plane_no=no, dist=0.0002)
    kill = [f for f in bm.faces if inzone(f) and z_lo - 0.1 < f.calc_center_median().z < z_hi
            and f.calc_center_median().z < zfn(az(f.calc_center_median()))]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(o.data)
    bm.free()


def front_line(ctx, o, z_top, z_bot, x=0.0, step=0.012):
    """Points down the front of a shell at x (cast from in front), with its normals: [(p, n)]."""
    bvh = bvh_of([o])
    out = []
    z = z_top
    while z >= z_bot:
        hit = bvh.ray_cast(Vector((x, -0.6, z)), Vector((0.0, 1.0, 0.0)), 1.0)
        if hit[0] is not None:
            n = Vector(hit[1])
            if n.y > 0:
                n = -n
            out.append((np.array(hit[0]), np.array(n.normalized())))
        z -= step
    return out


def strip(ctx, name, line, width, lift, th=0.0016, caps=True):
    """A flat strip laid down a line of (point, normal) - a placket or a zip tape: `width` across
    (along x), raised `lift` off the surface, with rounded edges."""
    frames = []
    for p, n in line:
        ax = np.array([1.0, 0.0, 0.0])
        ax = ax - n * (ax @ n)
        ax /= np.linalg.norm(ax)
        frames.append((Vector(p), Vector(n), Vector(ax)))
    w = width * 0.5
    prof = [(-0.002, -w - 0.0005), (lift * 0.7, -w + 0.0008), (lift, -w * 0.4), (lift, w * 0.4), (lift * 0.7, w - 0.0008), (-0.002, w + 0.0005)]
    return sweep(ctx, name, frames, lambda i: prof, closed=False, caps=caps)


def discs(ctx, name, centres, normals, radius, thick, seg=10):
    """Small discs (buttons) at points on a surface, as one mesh with metric UVs."""
    verts, faces, fuv = [], [], []
    for c, n in zip(centres, normals):
        n = np.asarray(n) / np.linalg.norm(n)
        t = np.cross(n, [0.0, 0.0, 1.0])
        if np.linalg.norm(t) < 1e-6:
            t = np.array([1.0, 0.0, 0.0])
        t /= np.linalg.norm(t)
        b = np.cross(n, t)
        base = len(verts)
        top = np.asarray(c) + n * thick
        for k in range(seg):
            a = 2 * math.pi * k / seg
            off = (t * math.cos(a) + b * math.sin(a)) * radius
            verts.append(tuple(np.asarray(c) + off * 1.05))
            verts.append(tuple(top + off * 0.92))
        verts.append(tuple(top + n * 0.0003))
        ctr = len(verts) - 1
        for k in range(seg):
            a0, a1 = base + 2 * k, base + 2 * ((k + 1) % seg)
            faces.append((a0, a1, a1 + 1, a0 + 1))
            fuv.append([(k * 0.002, 0.0), ((k + 1) * 0.002, 0.0), ((k + 1) * 0.002, 0.002), (k * 0.002, 0.002)])
            faces.append((a0 + 1, a1 + 1, ctr))
            fuv.append([(k * 0.002, 0.002), ((k + 1) * 0.002, 0.002), (k * 0.002, 0.004)])
    return mesh_with_local_uv(ctx, name, verts, faces, fuv)


def sleeve_end_loop(o, L, side):
    """The boundary loop at one sleeve's end."""
    e = L["ends"][side]
    co, no = np.array(e["co"]), np.array(e["no"])
    best = None
    for c, pts in boundary_points(o):
        d = abs(float(np.mean((pts - co) @ no)))
        if (c[0] * (1 if side == "Left" else -1)) > 0.1 and (best is None or d < best[0]):
            best = (d, pts)
    return best[1] if best else None


def hem_loop(o, z_near):
    best = None
    for c, pts in boundary_points(o):
        if np.ptp(pts[:, 0]) > 0.2 and (best is None or abs(c[2] - z_near) < abs(best[0] - z_near)):
            best = (c[2], pts)
    return best[1] if best else None


def cuff_bands(ctx, o, L, g, gid, garment, kind, fabric, region="top"):
    """Shirt cuffs, rolled-up sleeves or rib cuffs round each sleeve end."""
    B = ctx.body
    out = []
    for side, sg in SIDES:
        pts = sleeve_end_loop(o, L, side)
        if pts is None:
            continue
        el, wr = B.B(side + "ForeArm"), B.B(side + "Hand")
        ax = (wr - el) / np.linalg.norm(wr - el)
        centre = el + ax * float(np.mean((pts - el) @ ax))
        if kind == "rib":
            prof = lambda k, r, d, a: rib_profile(r, g.get("cuff_len", 0.05), g.get("cuff_pull", 0.008))
        elif kind == "roll":
            w = g.get("roll_w", 0.045)
            prof = lambda k, r, d, a, w=w: [(r - 0.003, -0.008), (r + 0.004, 0.0), (r + 0.0085, 0.012), (r + 0.009, w * 0.6),
                                            (r + 0.0065, w), (r + 0.002, w + 0.002), (r - 0.003, w - 0.002), (r - 0.0035, 0.002)]
        else:
            w = g.get("cuff_len", 0.058)
            prof = lambda k, r, d, a, w=w: [(r - 0.003, -0.008), (r + 0.0005, 0.0), (r - 0.001, 0.004), (r - 0.0015, w - 0.003),
                                            (r - 0.0025, w), (r - 0.0045, w - 0.0015), (r - 0.0048, 0.002)]
        band = edge_band(ctx, "%s_cuff_%s" % (garment, side[0]), pts, centre, ax, np.array([0.0, -1.0, 0.0]), prof, n=28)
        finish_band(ctx, band, garment, "cuff", region, fabric, gid, lambda c, el=el, ax=ax: tuple(el + ax * ((np.array(c) - el) @ ax)))
        out.append(band)
    return out


def shirt(ctx, g, gid):
    """Button shirt: the shell with a shirt-tail hem, a turn-down collar (stand and fall, points
    at the front), the placket with its buttons, cuffs or sleeves rolled to the forearm."""
    B = ctx.body
    g = dict(g)
    g.setdefault("fit", "regular")
    rolled = g.get("sleeve", "long") == "rolled"
    if not rolled:
        g.setdefault("cuff_above_wrist", g.get("cuff_len", 0.058) + 0.004)
    g["sleeve"] = g.get("sleeve", "long")
    tail = g.get("tail", 0.055)
    g["hem"] = g.get("hem", 0.02) - tail - 0.01   # the shell reaches the tail's lowest point
    g.setdefault("neck_front", -0.062)
    g.setdefault("neck_back", -0.004)
    o, L = build_top_shell(ctx, g, gid, "shirt")
    hip_z = B.B("LeftUpLeg")[2]
    z_side = hip_z + g.get("hem", 0.0) + tail + 0.01

    def zfn(a, z_side=z_side):
        c = math.cos(a)
        return z_side - (tail if c > 0 else tail * 1.15) * abs(c) ** 1.6
    # the sleeve ends (planes) and the tail (a curve)
    for k, (side, sg) in enumerate(SIDES):
        e = L["ends"][side]
        co, no = Vector(e["co"]), Vector(e["no"])
        cut(o, co, no, lambda c: True, lambda c, co=co, no=no: no.dot(c - co) > 0, zone=k + 1)
    cut_curve(o, B_torso_y(B), zfn, z_side - tail * 1.3 - 0.03, z_side + 0.03, zone=0)
    keep_largest_part(o)
    axis, cut_z, radius, ring = neck_ring_fn(ctx, L["neck_back"], L["neck_front"], L["off"] + g.get("neck_flare", 0.012))
    NECK = B.B("neck")
    CHEST = B.B("Spine")
    cut_neck(o, axis, radius, L["neck_back"], L["neck_front"], NECK[1] + 0.06, NECK[1] - 0.07, CHEST[2] + 0.02)
    keep_largest_part(o)
    subdivide(o, 1)
    decimate(o, g.get("tris", 2000))
    clear_of(o, [B.bvh] + ([bvh_of(ctx.layers)] if ctx.layers else []), 0.005)
    P, nbr, bound = mesh_arrays(o)
    set_positions(o, smooth_edge(P, nbr, bound, P[:, 2] < CHEST[2] - 0.1, 6))
    L["z_side"] = z_side
    L["tail"] = tail
    L["z_hem"] = z_side - tail

    def spec(pts):
        if np.ptp(pts[:, 0]) > 0.2 and pts[:, 2].mean() < CHEST[2] - 0.1:
            return ("hem", 0.0025, 0.012)
        xc = pts[:, 0].mean()
        for side, sg in SIDES:
            e = L["ends"][side]
            if (xc * sg) > 0.1 and abs(np.mean((pts - np.array(e["co"])) @ np.array(e["no"]))) < 0.03:
                return ("sleeve_" + side, 0.0025, 0.012)
        return None
    L["hems"] = add_lips(o, spec)
    smooth_weights(o, 6, where=lambda c: min((c - Vector(B.B("LeftArm"))).length, (c - Vector(B.B("RightArm"))).length) < 0.13,
                   names=["LeftShoulder", "RightShoulder", "LeftArm", "RightArm", "Spine", "Spine01", "neck"])
    off_the_head(o, 0.35)
    move_weight(o, list(LEG_UP), "Hips", 0.6)
    fabric = g.get("fabric", "woven")
    mark(o, "shirt", "shell", "top", fabric, gid)
    parts = [o]
    # the collar: stand up the neck, folded over into the fall, points spread at the front
    edge_pts = neck_loop(o, CHEST[2])
    ax_, ay_ = axis
    edge = loop_by_azimuth(edge_pts, axis, 72, 2)
    gap = g.get("collar_gap", 0.18)     # radians either side of the front centre left open
    stand_h, th = g.get("stand_h", 0.03), 0.0018
    frames, profs = [], []
    nf = 46
    for j in range(nf):
        a = gap + (2 * math.pi - 2 * gap) * j / (nf - 1)
        t = a / (2 * math.pi) * 72
        k0 = int(t) % 72
        f = t - int(t)
        r_e = edge[k0][0] * (1 - f) + edge[(k0 + 1) % 72][0] * f
        z_e = edge[k0][1] * (1 - f) + edge[(k0 + 1) % 72][1] * f
        d = Vector((math.sin(a), -math.cos(a), 0.0))
        s_hi = B.skin_hit(np.array([ax_, ay_, z_e + stand_h]), np.array(d), 0.16)
        r_top = min((s_hi if s_hi is not None else r_e - 0.01) + 0.006, r_e + 0.004)
        # toward the front ends the fall drops further and spreads into the points
        fr = float(smoothstep(0.55, 0.0, min(a, 2 * math.pi - a)))
        fall = g.get("fall", 0.040) + 0.028 * fr
        spread = 0.008 + 0.022 * fr
        frames.append((Vector((ax_, ay_, z_e)), d, Vector((0, 0, 1))))
        profs.append([(r_e - 0.003, -0.006), (r_top - th, stand_h - 0.003), (r_top + th * 0.6, stand_h + th), (r_top + 0.006, stand_h - 0.004),
                      (r_e + spread, stand_h - fall), (r_e + spread - th, stand_h - fall - th), (r_e + spread - 0.004, stand_h - fall + 0.004),
                      (r_top + 0.0025, stand_h - 0.008)])
    collar = sweep(ctx, "shirt_collar", frames, lambda i: profs[i], closed=False, caps=True)
    finish_band(ctx, collar, "shirt", "collar", "top", fabric, gid, lambda c: (ax_, ay_, c.z), head=True, keep_neck=0.25)
    parts.append(collar)
    # placket and buttons down the front
    z_top = L["neck_front"] - 0.004
    line = front_line(ctx, o, z_top, z_side - tail + 0.004)
    if len(line) > 3:
        pl = strip(ctx, "shirt_placket", line, g.get("placket_w", 0.034), 0.0018)
        ty = B_torso_y(B)
        finish_band(ctx, pl, "shirt", "placket", "top", fabric, gid, lambda c: (0.0, ty(c.z), c.z))
        parts.append(pl)
        cs, ns = [], []
        spacing = g.get("button_spacing", 0.088)
        zb = z_top - 0.02
        while zb > z_side - tail + 0.04:
            best = min(line, key=lambda pn: abs(pn[0][2] - zb))
            cs.append(best[0] + best[1] * 0.0018)
            ns.append(best[1])
            zb -= spacing
        if cs:
            bt = discs(ctx, "shirt_buttons", cs, ns, 0.0055, 0.0018)
            weights_from_body(ctx, bt)
            mark(bt, "shirt", "buttons", "other", fabric, gid)
            parts.append(bt)
    L["placket"] = [list(p) for p, n in line]
    parts += cuff_bands(ctx, o, L, g, gid, "shirt", "roll" if rolled else "cuff", fabric)
    L["neck_ring"] = {"axis": list(axis), "ring": ring}
    L["neck_cut"] = [L["neck_back"], L["neck_front"], NECK[1] + 0.06, NECK[1] - 0.07]
    ctx.layers.append(o)
    return parts, L


def B_torso_y(B):
    """The torso's centre depth by height (between the hip, chest and neck joints)."""
    zs = np.array([B.B(n)[2] for n in ("Hips", "Spine01", "Spine", "neck")])
    ys = np.array([B.B(n)[1] for n in ("Hips", "Spine01", "Spine", "neck")])
    o = np.argsort(zs)
    return lambda z: float(np.interp(z, zs[o], ys[o]))


def jacket(ctx, g, gid):
    """Zip jacket: the shell to the waist, a rib hem band and rib cuffs, a stand collar, the zip
    (tapes, teeth, slider and pull) down the centre front."""
    B = ctx.body
    g = dict(g)
    g.setdefault("fit", "jacket")
    g["sleeve"] = "long"
    band = g.get("band_len", 0.055)
    g.setdefault("cuff_above_wrist", g.get("cuff_len", 0.05) - 0.004)
    g["hem"] = g.get("hem", 0.0) + band
    g.setdefault("neck_front", -0.046)
    g.setdefault("neck_back", -0.002)
    o, L = build_top_shell(ctx, g, gid, "jacket")
    cut_top(ctx, o, L)
    axis, cut_z, radius, ring = neck_ring_fn(ctx, L["neck_back"], L["neck_front"], L["off"] + g.get("neck_flare", 0.014))
    NECK = B.B("neck")
    CHEST = B.B("Spine")
    cut_neck(o, axis, radius, L["neck_back"], L["neck_front"], NECK[1] + 0.06, NECK[1] - 0.07, CHEST[2] + 0.02)
    keep_largest_part(o)
    subdivide(o, 1)
    decimate(o, g.get("tris", 2000))
    clear_of(o, [B.bvh] + ([bvh_of(ctx.layers)] if ctx.layers else []), 0.006)
    L["hems"] = top_lips(ctx, o, L, hem=(0.003, 0.012), sleeve=(0.003, 0.012))
    smooth_weights(o, 6, where=lambda c: min((c - Vector(B.B("LeftArm"))).length, (c - Vector(B.B("RightArm"))).length) < 0.13,
                   names=["LeftShoulder", "RightShoulder", "LeftArm", "RightArm", "Spine", "Spine01", "neck"])
    off_the_head(o, 0.35)
    move_weight(o, list(LEG_UP), "Hips", 0.6)
    fabric = g.get("fabric", "woven")
    rib = g.get("rib_fabric", "jersey")
    mark(o, "jacket", "shell", "top", fabric, gid)
    parts = [o]
    ty = B_torso_y(B)
    # rib hem band hanging from the shell's hem
    hp = hem_loop(o, L["z_hem"])
    if hp is not None:
        c0 = np.array([0.0, ty(L["z_hem"]), float(hp[:, 2].mean())])
        hb = edge_band(ctx, "jacket_band", hp, c0, np.array([0.0, 0.0, -1.0]), np.array([0.0, -1.0, 0.0]),
                       lambda k, r, d, a: rib_profile(r, band, g.get("band_pull", 0.012)), n=56)
        finish_band(ctx, hb, "jacket", "band", "top", rib, gid, lambda c: (0.0, ty(c.z), c.z))
        parts.append(hb)
    parts += cuff_bands(ctx, o, L, g, gid, "jacket", "rib", rib)
    # stand collar: up the neck clear of it, rolled over at the top and down inside
    edge_pts = neck_loop(o, CHEST[2])
    ax_, ay_ = axis
    edge = loop_by_azimuth(edge_pts, axis, 40, 1)
    ch = g.get("collar_h", 0.05)
    frames, profs = [], []
    for k in range(40):
        a = 2 * math.pi * k / 40
        d = Vector((math.sin(a), -math.cos(a), 0.0))
        r_e, z_e = edge[k]
        s_hi = B.skin_hit(np.array([ax_, ay_, z_e + ch]), np.array(d), 0.16)
        r_top = max((s_hi if s_hi is not None else r_e - 0.01) + 0.012, r_e - 0.012)
        frames.append((Vector((ax_, ay_, z_e)), d, Vector((0, 0, 1))))
        profs.append([(r_e - 0.004, -0.010), (r_e + 0.0012, 0.0015), (r_e * 0.5 + r_top * 0.5 + 0.0015, ch * 0.5),
                      (r_top + 0.001, ch - 0.003), (r_top - 0.002, ch), (r_top - 0.0045, ch - 0.003), (r_e - 0.006, -0.004)])
    collar = sweep(ctx, "jacket_collar", frames, lambda i: profs[i], closed=True)
    finish_band(ctx, collar, "jacket", "collar", "top", fabric, gid, lambda c: (ax_, ay_, c.z), head=True, keep_neck=0.25)
    parts.append(collar)
    # the zip: tapes and teeth from the collar's top to the band's bottom, slider and pull
    hem_bot = L["z_hem"] - band
    z_top = float(np.mean([p[1] for p in edge[:2] + edge[-1:]])) + ch - 0.002
    bvh = bvh_of([o, collar] + ([parts[1]] if hp is not None else []))
    line = []
    z = z_top
    while z >= hem_bot + 0.002:
        hit = bvh.ray_cast(Vector((0.0, -0.6, z)), Vector((0.0, 1.0, 0.0)), 1.0)
        if hit[0] is not None:
            n = Vector(hit[1])
            if n.y > 0:
                n = -n
            line.append((np.array(hit[0]), np.array(n.normalized())))
        z -= 0.012
    if len(line) > 3:
        tape = strip(ctx, "jacket_zip_tape", line, 0.026, 0.0012)
        finish_band(ctx, tape, "jacket", "zip_tape", "top", fabric, gid, lambda c: (0.0, ty(c.z), c.z))
        teeth = strip(ctx, "jacket_zip", line, 0.0065, 0.0028)
        finish_band(ctx, teeth, "jacket", "zip", "other", fabric, gid, lambda c: (0.0, ty(c.z), c.z))
        p0, n0 = line[1]
        sl = discs(ctx, "jacket_zip_pull", [p0 + n0 * 0.003, p0 + n0 * 0.004 - np.array([0, 0, 0.022])], [n0, n0], 0.0055, 0.0025, seg=8)
        weights_from_body(ctx, sl)
        mark(sl, "jacket", "zip_pull", "other", fabric, gid)
        parts += [tape, teeth, sl]
    L["zip"] = [list(p) for p, n in line]
    L["band"] = band
    L["neck_ring"] = {"axis": list(axis), "ring": ring}
    L["neck_cut"] = [L["neck_back"], L["neck_front"], NECK[1] + 0.06, NECK[1] - 0.07]
    ctx.layers.append(o)
    return parts, L


# ---- trousers ---------------------------------------------------------------------------------------
TROUSERS = {
    # hem opening radius, thigh ease, knee radius floor (over the body), roundness below the knee
    "jeans": {"hem_r": 0.064, "ease": 0.009, "knee_ease": 0.012, "round": 0.65, "fabric": "denim", "hem": (0.0045, 0.016)},
    "slim": {"hem_r": 0.056, "ease": 0.006, "knee_ease": 0.009, "round": 0.6, "fabric": "denim", "hem": (0.0045, 0.015)},
    "chinos": {"hem_r": 0.060, "ease": 0.011, "knee_ease": 0.014, "round": 0.7, "fabric": "woven", "hem": (0.0035, 0.02)},
    "leggings": {"hem_r": 0.0, "ease": 0.0025, "knee_ease": 0.0025, "round": 0.0, "fabric": "jersey", "hem": (0.0018, 0.008)},
    "shorts": {"hem_r": 0.088, "ease": 0.012, "knee_ease": 0.012, "round": 0.5, "fabric": "denim", "hem": (0.006, 0.03)},
}


def trousers(ctx, g, gid):
    B = ctx.body
    V, cent = B.V, B.cent
    st = dict(TROUSERS[g.get("style", "jeans")])
    st.update({k: v for k, v in g.items() if k in st})
    style = g.get("style", "jeans")
    hips = B.B("Hips")
    hip_z = B.B("LeftUpLeg")[2]
    z_waist = hips[2] + g.get("rise", 0.05)
    tilt = g.get("waist_tilt", 0.018)   # the waistband dips at the front
    crotch = B.crotch_z
    # where the legs end: full length just above the shoe's collar, shorts above the knee
    ends = {}
    collars = {}
    for side, sg in SIDES:
        hip, kn, an = B.B(side + "UpLeg"), B.B(side + "Leg"), B.B(side + "Foot")
        if style == "shorts":
            z_end = kn[2] + g.get("above_knee", 0.09)
            ends[side] = ("up", hip, kn, z_end)
        else:
            # Full length: the back of the hem at `hem_height` over the floor, or just over a low
            # shoe's heel collar, the front breaking over the instep (the leg is pushed clear of
            # the shoe below, out round a high-top's shaft). Some library shoes run a shaft up to
            # 23 cm behind the ankle (shoes05): a hem "just over the collar" stopped mid-shin
            # there. Leggings and cropped styles stop at "above_ankle" instead.
            col = ctx.shoe_collar(side, sg)
            collars[side] = col
            if style != "leggings" and "above_ankle" not in g:
                z_end = g.get("hem_height", 0.085)
                if col is not None:
                    z_end = max(min(z_end, col[0] - g.get("break", 0.014)), 0.035)
            else:
                z_end = an[2] + g.get("above_ankle", 0.035)
            ends[side] = ("lo", kn, an, z_end)

    def waist_z(y):
        return z_waist + np.clip((y - hips[1]) / 0.12, -1.0, 1.0) * tilt

    margin = 0.035
    mask = np.zeros(len(B.F), bool)
    for i, c in enumerate(cent):
        d = B.fdom[i]
        if d in FEET or d in HEAD_BONES or "Arm" in d or d.endswith("Hand"):
            continue
        if c[2] > waist_z(c[1]) + margin:
            continue
        side = "Left" if c[0] > 0 else "Right"
        if c[2] < ends[side][3] - margin:
            continue
        mask[i] = True
    o = shell_from_faces(ctx, "trousers", mask)
    orig = get_orig(o)
    P, nbr, bound = mesh_arrays(o)
    base = B.Vs[orig]
    nrm = B.VNs[orig]
    ease = st["ease"]
    Pn = base + nrm * ease
    # the seat and the hips: an envelope over the pelvis (bridged across the cleft of the seat
    # and the hollows by the hip bones), faded in above the crotch
    pel = B.Vs[np.array([(x in ("Hips", "Spine02") or x in LEG_UP) for x in B.vdom]) & (V[:, 2] > crotch - 0.02) & (V[:, 2] < z_waist + 0.06)]
    # down to the crotch itself: started 5 cm above it, the front between the thighs followed
    # the body into a valley up the fly
    z_bridge = crotch + 0.005
    env = Envelope(pel, z_bridge - 0.015, z_waist + 0.05, ease, blur=(2.0, 1.0))
    wt = smoothstep(z_bridge, z_bridge + 0.035, Pn[:, 2])
    for i in np.where(wt > 1e-3)[0]:
        q = env.place(Pn[i])
        c = env.centre(Pn[i, 2])
        # never inside the eased body: only ever out to the envelope
        if np.hypot(*(q[:2] - c)) > np.hypot(*(Pn[i, :2] - c)):
            Pn[i] = Pn[i] * (1.0 - wt[i]) + q * wt[i]
    # legs: tubes. The thigh keeps the body's shape (ease only); from above the knee the leg
    # rounds and, for anything but leggings, hangs straight or tapers to its hem opening.
    r_knees = {}
    for side, sg in SIDES:
        hip, kn, an = B.B(side + "UpLeg"), B.B(side + "Leg"), B.B(side + "Foot")
        sel = ((base[:, 0] * sg) > 0) & (base[:, 2] < crotch + 0.04)
        L1 = np.linalg.norm(kn - hip)
        L2 = np.linalg.norm(an - kn)
        s_th, _, _, _ = limb_frame(base, hip, kn)
        r_knee = 0.055
        on_th = sel & (s_th < L1)
        if style != "leggings":
            # the knee's opening: the body's radius there plus the knee ease
            _, _, rv, _ = limb_frame(base, hip, kn)
            near_k = on_th & (s_th > L1 - 0.05)
            r_knee = (float(np.linalg.norm(rv[near_k], axis=1).max()) if near_k.any() else 0.055) + st["knee_ease"]
            r_knees[side] = r_knee
            Pn = tube(Pn, on_th, hip, kn, lambda s: 0.0,
                      lambda s: st["round"] * 0.6 * float(smoothstep(L1 * 0.35, L1, s)),
                      lambda s: r_knee * float(smoothstep(L1 * 0.5, L1, s)))
        s_lo, _, _, _ = limb_frame(base, kn, an)
        on_lo = sel & (s_lo >= 0)
        if style == "leggings" or style == "shorts":
            continue
        r_hem = st["hem_r"]
        Pn = tube(Pn, on_lo, kn, an, lambda s: st["ease"] * 0.5,
                  lambda s: st["round"], lambda s: r_knee + (r_hem - r_knee) * float(np.clip(s / L2, 0, 1)))
    if style == "shorts":
        for side, sg in SIDES:
            hip, kn = B.B(side + "UpLeg"), B.B(side + "Leg")
            sel = ((base[:, 0] * sg) > 0) & (base[:, 2] < crotch + 0.04)
            L1 = np.linalg.norm(kn - hip)
            z_end = ends[side][3]
            s_end = (hip[2] - z_end) / (hip[2] - kn[2]) * L1
            Pn = tube(Pn, sel, hip, kn, lambda s: 0.004 + 0.012 * float(smoothstep(s_end * 0.4, s_end, s)),
                      lambda s: 0.6 * float(smoothstep(s_end * 0.3, s_end, s)), lambda s: st["hem_r"] * float(smoothstep(s_end * 0.55, s_end, s)))
    # keep the two legs apart at the crotch and the inner thighs
    for i in range(len(Pn)):
        if Pn[i, 2] < crotch + 0.03 and abs(Pn[i, 0]) < 0.012 and base[i, 2] < crotch - 0.02:
            Pn[i, 0] = math.copysign(0.012, base[i, 0])
    Pn = taubin(Pn, nbr, bound, 10)
    clear = np.full(len(Pn), 0.002 if style == "leggings" else 0.006)
    Pn = push_out(Pn, [B.bvh], clear, dirs=nrm)
    set_positions(o, Pn)
    # full-length legs carried on down to the shoe (the skin under its collar is gone)
    if style != "shorts":
        for side, sg in SIDES:
            kn, an = B.B(side + "Leg"), B.B(side + "Foot")
            L2 = np.linalg.norm(an - kn)
            s_t = (kn[2] - (ends[side][3] - 0.03)) / (kn[2] - an[2]) * L2
            if style == "leggings":
                rf = lambda s: 0.042
            else:
                rk = r_knees.get(side, 0.06)
                rf = lambda s, rk=rk, L2=L2: rk + (st["hem_r"] - rk) * float(np.clip(s / L2, 0, 1))
            extend_limb(o, sg, kn, an, s_t, rf, crotch)
    # cut: the waist (tilted plane, front lower) and the leg ends
    wz_front, wz_back = z_waist - tilt, z_waist + tilt
    no = Vector((0.0, -(wz_back - wz_front) / 0.24, 1.0)).normalized()
    co = Vector((0.0, hips[1], z_waist))
    cut(o, co, no, lambda c: c.z > crotch + 0.05, lambda c: no.dot(c - co) > 0)
    L = {"style": style, "z_waist": z_waist, "waist_co": list(co), "waist_no": list(no), "ends": {}, "crotch": crotch}
    for side, sg in SIDES:
        e = ends[side]
        a, b = e[1], e[2]
        ab = (b - a) / np.linalg.norm(b - a)
        t = (a[2] - e[3]) / (a[2] - b[2])
        pco = a + (b - a) * t
        L["ends"][side] = {"co": list(pco), "no": list(ab)}
        cut(o, pco, ab, lambda c, sg=sg, zc=e[3]: (c.x * sg) > 0 and c.z < zc + 0.12,
            lambda c, pco=Vector(pco), ab=Vector(ab): ab.dot(c - pco) > 0)
    keep_largest_part(o)
    subdivide(o, 1)
    decimate(o, g.get("tris", 1800))
    clear_of(o, [B.bvh], 0.004)
    if ctx.shoe_bvh is not None and style != "shorts":
        # the hem rests on the shoe: whatever of the lower leg is inside it goes out over it,
        # smoothed so the break is a roll, not a dent (the garments share the body's frame)
        P, nbr, bound = mesh_arrays(o)
        low = P[:, 2] < min(B.B("LeftLeg")[2], B.B("RightLeg")[2]) - 0.2

        def radial(P):
            out = np.zeros_like(P)
            for side, sg in SIDES:
                a, b = B.B(side + "Leg"), B.B(side + "Foot")
                ax = (b - a) / np.linalg.norm(b - a)
                m = (P[:, 0] * sg) > 0
                d = P[m] - a
                out[m] = d - np.outer(d @ ax, ax)
            return out
        cl = g.get("shoe_clear", 0.006)
        for _ in range(3):
            P = np.where(low[:, None], lift_over(P, ctx.shoe_bvh, cl, radial(P)), P)
            P = np.where(low[:, None], taubin(P, nbr, np.zeros(len(P), bool), 2), P)
        P = np.where(low[:, None], lift_over(P, ctx.shoe_bvh, cl, radial(P)), P)
        # the hem's own line smoothed along itself (single vertices lifted over the shoe left it
        # toothed), then held clear of the shoe by small moves out only
        P = smooth_edge(P, nbr, bound, low, 10)
        P = np.where(low[:, None], lift_over(P, ctx.shoe_bvh, cl * 0.5, radial(P), up=False), P)
        set_positions(o, P)

    def spec(pts):
        zc = pts[:, 2].mean()
        if zc > crotch + 0.04:
            return ("waist", 0.004 if style != "leggings" else 0.002, 0.012)
        return ("hem_" + ("Left" if pts[:, 0].mean() > 0 else "Right"),) + tuple(st["hem"])
    L["hems"] = add_lips(o, spec)
    mark(o, "trousers", "shell", "bottom", g.get("fabric", st["fabric"]), gid)
    ctx.layers.append(o)
    return [o], L


BUILDERS = {"tee": tee, "trousers": trousers, "shirt": shirt, "jacket": jacket}


def flatten_crotch(body, arm):
    """The male base mesh's bulge smoothed away (a membrane fill, Laplacian with the rim held):
    jeans grown off it printed it. That skin is always under the trousers and is deleted by
    build_character.py's cover test, so only the garments ever see the change."""
    me = body.data
    mw = body.matrix_world
    V = np.array([mw @ v.co for v in me.vertices])
    amw = arm.matrix_world
    hips = np.array(amw @ arm.data.bones["Hips"].head_local)
    up = np.array(amw @ arm.data.bones["LeftUpLeg"].head_local)
    z_c = up[2] - 0.07
    w = (1.0 - smoothstep(0.035, 0.085, np.abs(V[:, 0]))) * smoothstep(z_c - 0.09, z_c - 0.05, V[:, 2]) \
        * (1.0 - smoothstep(z_c + 0.08, z_c + 0.13, V[:, 2])) * (1.0 - smoothstep(hips[1] - 0.04, hips[1] + 0.01, V[:, 1]))
    if w.max() <= 0.0:
        return
    nbr = [[] for _ in V]
    for e in me.edges:
        a, c = e.vertices
        nbr[a].append(c)
        nbr[c].append(a)
    P = V.copy()
    for _ in range(60):
        avg = np.array([P[n].mean(0) if n else P[i] for i, n in enumerate(nbr)])
        P = P + 0.5 * w[:, None] * (avg - P)
    mwi = np.array(mw.inverted())
    loc = (np.c_[P, np.ones(len(P))] @ mwi.T)[:, :3]
    me.vertices.foreach_set("co", loc.astype(np.float32).ravel())
    me.update()
    print("CROWD crotch flattened (%d vertices moved, at most %.1f mm)" % (int((w > 0.01).sum()), np.linalg.norm(P - V, axis=1).max() * 1000))


def build(body, arm, cfg, name):
    """Builds the character's outfit (cfg["outfit"], bottoms first) on the bound body; returns
    the new objects, each carrying "crowd_own" (garment, part, region, fabric, gid)."""
    if cfg.get("phenotype", {}).get("gender", 0.5) > 0.5 and any(g["type"] == "trousers" for g in cfg["outfit"]):
        flatten_crotch(body, arm)
    ctx = Ctx(body, arm, cfg, name)
    order = sorted(range(len(cfg["outfit"])), key=lambda i: 0 if cfg["outfit"][i]["type"] == "trousers" else 1)
    for gid in order:
        g = cfg["outfit"][gid]
        objs, L = BUILDERS[g["type"]](ctx, g, gid)
        dens = shell_density(objs[0])
        for o in objs:
            triangulate(o)
            o["crowd_px_per_m"] = dens
            for g2 in [x for x in o.vertex_groups if x.name.startswith("Delete") or x.name in ("orig",)]:
                o.vertex_groups.remove(g2)
        ctx.parts += objs
        L["spec"] = g
        L["gid"] = gid
        L["type"] = g["type"]
        L["parts"] = [o.name for o in objs]
        ctx.meta["garments"].append(L)
        print("CROWD garment %s (%s): %s" % (g["type"], g.get("style", g.get("sleeve", "")),
                                               ", ".join("%s %d tris" % (o.name, tris(o)) for o in objs)))
    with open(C.work(name, "garments.json"), "w") as f:
        json.dump(ctx.meta, f)
    return ctx.parts
