"""Encampment kit: the tents, tarps, carts and belongings of a sidewalk encampment.

Run headless with Blender 4.2 (on a shared box, under the render lock):

    blender -b --factory-startup --python tools/encampment_kit.py -- [out.glb] [--no-bake]

or, where bpy 4.2 is installed as a Python module, `python3 tools/encampment_kit.py -- [out.glb]`.

Writes assets/models/encampment_kit.glb, one mesh node per piece, named camp_<piece>. Then run
`godot --headless --path . --import` before rendering anything (Godot serves a CACHED import of a
.glb - CLAUDE.md, measurement traps) and `python3 tools/fix_texture_imports.py` is not needed:
the kit carries no textures of its own, its materials are PropFactory.camp_material() by name.

Placed by scripts/world/encampment.gd (downtown sidewalks) through PropFactory.encampment(), so
the numbers in here are the numbers it places them with. Everything is street realism modelled
from the real objects: a cheap two-pole dome tent pulled out of shape, a poly tarp strung as a
lean-to on two sticks or thrown over a pile, a shopping cart built wire by wire, knotted trash
bags, a warped twin mattress, flattened boxes, a rumpled sleeping bag, a folding camp chair and a
bicycle with its spokes - and what people carry: a cart loaded with sacks and a roped blanket
roll (pushed along the pavement by RoughSleeper's PUSH), and a blanket bundle.

Conventions (the Godot side depends on them):

* Modelled in GODOT space (x right, y up, z toward the FRONT - the street side of a camp, the
  door of a tent, the nose of a cart), metres, origin on the ground at the piece's centre, and
  converted to Blender's Z-up on the way in (G() below).
* UVs are in METRES (box- or surface-projected), because shaders/encampment.gdshaderinc tiles
  every texture by `tile_m` metres; a texture never stretches with a piece.
* UV2.x is baked ambient occlusion as OCCLUSION (0 open, 1 fully occluded), from a Cycles AO
  bake against a ground plane - the dark where a tent meets the pavement and the inside of a
  cart's basket are most of what stops these reading as props dropped on a floor.
* Material names pick the Godot material (PropFactory.CAMP_MATERIALS): camp_nylon (tent fly,
  camp chair sling; instance tint), camp_door (the zipped door panel, darker), camp_tub (the
  floor tub), camp_pole (aluminium poles, tube steel), camp_tarp (instance tint), camp_rope,
  camp_stick (a broom handle), camp_chrome (cart wire, spokes), camp_plastic (cart grip),
  camp_rubber (wheels, tyres), camp_bag (trash-bag plastic, instance tint), camp_canvas (duffel,
  instance tint), camp_mattress, camp_cardboard, camp_quilt (sleeping bag and blanket, instance
  tint), camp_frame (bike paint, instance tint), camp_saddle.
* Node names must not be prefixes of one another: PropFactory.model_mesh() picks a node by
  substring, so "camp_bike" would also pick "camp_bike_wheel". Hence camp_bicycle.

Budgets (triangles) are in PropFactory.TRI_BUDGET, keyed encampment_kit.glb:camp_<piece>; this
script prints each piece's count.
"""
import math
import os
import random
import sys

import bpy  # first: as a Python module, bpy is what makes bmesh and mathutils importable
import bmesh
from mathutils import Matrix, Vector, noise

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = next((a for a in ARGV if a.endswith(".glb")),
           os.path.join(HERE, "..", "assets", "models", "encampment_kit.glb"))
BAKE = "--no-bake" not in ARGV


def G(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


def to_godot(v):
    return Vector((v.x, v.z, -v.y))


MATERIALS = {
    # name: (preview colour, roughness, metallic, double sided). Godot swaps all of these for
    # PropFactory.camp_material(name); the preview colours are only for looking at the .glb.
    "camp_nylon": ((0.25, 0.42, 0.55), 0.7, 0.0, True),
    "camp_door": ((0.18, 0.30, 0.40), 0.7, 0.0, True),
    "camp_tub": ((0.12, 0.12, 0.13), 0.6, 0.0, True),
    "camp_pole": ((0.55, 0.56, 0.58), 0.4, 0.8, False),
    "camp_tarp": ((0.12, 0.28, 0.62), 0.55, 0.0, True),
    "camp_rope": ((0.62, 0.55, 0.40), 0.9, 0.0, False),
    "camp_stick": ((0.48, 0.36, 0.22), 0.8, 0.0, False),
    "camp_chrome": ((0.70, 0.71, 0.72), 0.3, 1.0, False),
    "camp_plastic": ((0.60, 0.10, 0.08), 0.5, 0.0, False),
    "camp_rubber": ((0.05, 0.05, 0.05), 0.85, 0.0, False),
    "camp_bag": ((0.03, 0.03, 0.035), 0.3, 0.0, True),
    "camp_canvas": ((0.25, 0.28, 0.20), 0.85, 0.0, False),
    "camp_mattress": ((0.78, 0.76, 0.70), 0.9, 0.0, False),
    "camp_cardboard": ((0.55, 0.42, 0.28), 0.9, 0.0, True),
    "camp_quilt": ((0.30, 0.22, 0.35), 0.85, 0.0, True),
    "camp_frame": ((0.20, 0.30, 0.55), 0.45, 0.3, False),
    "camp_saddle": ((0.06, 0.06, 0.06), 0.6, 0.0, False),
    # Trash-bag plastic that is always black (a loaded cart's sacks: its instance colour is the
    # blanket's, camp_quilt).
    "camp_sack": ((0.03, 0.03, 0.035), 0.3, 0.0, True),
}


def material(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    col, rough, metal, double = MATERIALS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.use_backface_culling = not double
    return m


def _new_bm():
    t = bmesh.new()
    t.loops.layers.uv.new("UVMap")
    return t


def _smooth_by_angle(t, degrees):
    limit = math.radians(degrees)
    for f in t.faces:
        f.smooth = True
    for e in t.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(math.pi) < limit
        else:
            e.smooth = True


def _box_uv(t):
    """Box projection in metres, picked per face by its dominant (Godot) normal."""
    uvl = t.loops.layers.uv.active
    for f in t.faces:
        n = to_godot(f.normal)
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            p = to_godot(loop.vert.co)
            if ax == 1:
                loop[uvl].uv = (p.x, p.z)
            elif ax == 2:
                loop[uvl].uv = (p.x, -p.y)
            else:
                loop[uvl].uv = (p.z, -p.y)


def _frame(axis):
    """Two unit vectors perpendicular to `axis` (Godot space)."""
    a = axis.normalized()
    up = Vector((0.0, 1.0, 0.0)) if abs(a.y) < 0.9 else Vector((1.0, 0.0, 0.0))
    s = a.cross(up).normalized()
    u = s.cross(a).normalized()
    return s, u


class Piece:
    def __init__(self, name, ao_distance=0.5):
        self.name = name
        self.bm = _new_bm()
        self.mats = []
        self.ao_distance = ao_distance

    def slot(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def add(self, t, mat):
        """Copies bmesh `t` (with its UVs and smoothing) into the piece."""
        idx = self.slot(mat)
        uv_s = t.loops.layers.uv.active
        uv_d = self.bm.loops.layers.uv.active
        vmap = {}
        for v in t.verts:
            vmap[v] = self.bm.verts.new(v.co)
        for f in t.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = idx
            nf.smooth = f.smooth
            for ls, ld in zip(f.loops, nf.loops):
                ld[uv_d].uv = ls[uv_s].uv
        for e in t.edges:
            ne = self.bm.edges.get([vmap[v] for v in e.verts])
            if ne:
                ne.smooth = e.smooth
        t.free()

    # --- primitives (all points in Godot space) -----------------------------------------------

    def grid(self, rows, mat, uv="auto", smooth=60.0, flip=False):
        """A surface through a grid of Godot points (rows of equal length). UVs are metres along
        the grid (u accumulated along each row, v down the columns) unless uv="box"."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        grid = [[t.verts.new(G(*p)) for p in row] for row in rows]
        nr = len(rows)
        nc = len(rows[0])
        # Arc-length UVs: u along the row, v along the column, both in metres.
        us = [[0.0] * nc for _ in range(nr)]
        vs = [[0.0] * nc for _ in range(nr)]
        for r in range(nr):
            for c in range(1, nc):
                us[r][c] = us[r][c - 1] + (Vector(rows[r][c]) - Vector(rows[r][c - 1])).length
        for c in range(nc):
            for r in range(1, nr):
                vs[r][c] = vs[r - 1][c] + (Vector(rows[r][c]) - Vector(rows[r - 1][c])).length
        for r in range(nr - 1):
            for c in range(nc - 1):
                quad = (grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c])
                if flip:
                    quad = tuple(reversed(quad))
                try:
                    f = t.faces.new(quad)
                except ValueError:
                    continue
                for loop in f.loops:
                    for rr in (r, r + 1):
                        for cc in (c, c + 1):
                            if grid[rr][cc] == loop.vert:
                                loop[uvl].uv = (us[rr][cc], vs[rr][cc])
        t.normal_update()
        if uv == "box":
            _box_uv(t)
        _smooth_by_angle(t, smooth)
        self.add(t, mat)

    def tube(self, pts, r, mat, sides=6, closed=False, caps=False, smooth=70.0):
        """A round tube swept along a polyline of Godot points (poles, wire, rope, frames)."""
        pts = [Vector(p) for p in pts]
        if len(pts) < 2:
            return
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        n = len(pts)
        rings = []
        along = [0.0]
        for i in range(1, n):
            along.append(along[-1] + (pts[i] - pts[i - 1]).length)
        prev_s = None
        for i in range(n):
            if closed:
                d = pts[(i + 1) % n] - pts[i - 1]
            else:
                d = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
            if d.length < 1e-6:
                d = Vector((0.0, 0.0, 1.0))
            s, u = _frame(d)
            if prev_s is not None and s.dot(prev_s) < 0.0:
                s, u = -s, -u
            prev_s = s
            ring = []
            for k in range(sides):
                a = 2.0 * math.pi * k / sides
                ring.append(t.verts.new(G(*(pts[i] + (s * math.cos(a) + u * math.sin(a)) * r))))
            rings.append(ring)
        segs = n if closed else n - 1
        for i in range(segs):
            a_ring = rings[i]
            b_ring = rings[(i + 1) % n]
            for k in range(sides):
                k2 = (k + 1) % sides
                try:
                    f = t.faces.new((a_ring[k], b_ring[k], b_ring[k2], a_ring[k2]))
                except ValueError:
                    continue
                va = along[i]
                vb = along[i + 1] if i + 1 < n else along[-1] + (pts[0] - pts[-1]).length
                for loop, uv in zip(f.loops, ((k, va), (k, vb), (k + 1, vb), (k + 1, va))):
                    loop[uvl].uv = (uv[0] * 2.0 * math.pi * r / sides, uv[1])
        if caps and not closed:
            for ring in (rings[0], rings[-1]):
                try:
                    t.faces.new(ring)
                except ValueError:
                    pass
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        _smooth_by_angle(t, smooth)
        self.add(t, mat)

    def box(self, c, size, mat, bevel=0.0, rot=None, smooth=35.0):
        """A box centred on Godot `c` with Godot `size`, optionally bevelled and turned by `rot`
        (a Godot-space 3x3 Matrix) about its centre."""
        t = _new_bm()
        bmesh.ops.create_cube(t, size=1.0)
        for v in t.verts:
            v.co = G(v.co.x * size[0], v.co.z * size[1], -v.co.y * size[2])
        if bevel > 0.0:
            bmesh.ops.bevel(t, geom=list(t.edges), offset=bevel, segments=1, profile=0.5,
                            affect='EDGES', clamp_overlap=True)
        if rot is not None:
            m = _godot_matrix_to_blender(rot)
            for v in t.verts:
                v.co = m @ v.co
        for v in t.verts:
            v.co += G(*c)
        t.normal_update()
        _box_uv(t)
        _smooth_by_angle(t, smooth)
        self.add(t, mat)

    def torus(self, c, axis, R, r, mat, seg=32, sides=8, smooth=80.0, profile=None):
        """A ring round Godot `c` about Godot `axis` (tyres, rims). `profile` (optional) is a list
        of (radial, axial) offsets for the section instead of a circle of radius r."""
        ax = Vector(axis).normalized()
        s, u = _frame(ax)
        if profile is None:
            profile = [(math.cos(2.0 * math.pi * k / sides) * r, math.sin(2.0 * math.pi * k / sides) * r)
                       for k in range(sides)]
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        rings = []
        for i in range(seg):
            a = 2.0 * math.pi * i / seg
            radial = s * math.cos(a) + u * math.sin(a)
            ring = []
            for (dr, da) in profile:
                ring.append(t.verts.new(G(*(Vector(c) + radial * (R + dr) + ax * da))))
            rings.append(ring)
        m = len(profile)
        for i in range(seg):
            a_ring = rings[i]
            b_ring = rings[(i + 1) % seg]
            for k in range(m):
                k2 = (k + 1) % m
                f = t.faces.new((a_ring[k], a_ring[k2], b_ring[k2], b_ring[k]))
                for loop, uv in zip(f.loops, ((i, k), (i, k + 1), (i + 1, k + 1), (i + 1, k))):
                    loop[uvl].uv = (uv[0] * 2.0 * math.pi * R / seg, uv[1] * 0.02)
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        # recalc can point a torus's normals inward; outward is away from the section centre.
        for f in t.faces:
            fc = to_godot(f.calc_center_median())
            rel = fc - Vector(c)
            rad = rel - ax * rel.dot(ax)
            centre = Vector(c) + rad.normalized() * R + ax * sum(p[1] for p in profile) / m
            if to_godot(f.normal).dot(fc - centre) < 0.0:
                f.normal_flip()
        t.normal_update()
        _smooth_by_angle(t, smooth)
        self.add(t, mat)

    def blob(self, c, radii, mat, seg=16, rings=10, shape=None, smooth=80.0):
        """A deformed ellipsoid (bags, pillows, a saddle). `shape(p, n)` returns the displaced
        Godot point for unit-sphere direction n and base point p."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        verts = []
        for j in range(rings + 1):
            lat = math.pi * j / rings - math.pi * 0.5
            row = []
            for i in range(seg):
                lon = 2.0 * math.pi * i / seg
                n = Vector((math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon)))
                p = Vector(c) + Vector((n.x * radii[0], n.y * radii[1], n.z * radii[2]))
                if shape:
                    p = shape(p, n)
                row.append(t.verts.new(G(*p)))
            verts.append(row)
        for j in range(rings):
            for i in range(seg):
                i2 = (i + 1) % seg
                if j == 0:
                    quad = (verts[j][i], verts[j + 1][i2], verts[j + 1][i])
                elif j == rings - 1:
                    quad = (verts[j][i], verts[j][i2], verts[j + 1][i])
                else:
                    quad = (verts[j][i], verts[j][i2], verts[j + 1][i2], verts[j + 1][i])
                try:
                    f = t.faces.new(quad)
                except ValueError:
                    continue
                for loop in f.loops:
                    p = to_godot(loop.vert.co) - Vector(c)
                    loop[uvl].uv = (math.atan2(p.z, p.x) * max(radii[0], radii[2]), p.y)
        bmesh.ops.remove_doubles(t, verts=t.verts, dist=1e-5)
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        _smooth_by_angle(t, smooth)
        self.add(t, mat)


def _godot_matrix_to_blender(m3):
    swap = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
    return swap @ m3 @ swap.inverted()


def nz(p, scale, seed=0.0):
    """Signed Perlin noise at a Godot point, roughly -1..1."""
    return noise.noise(Vector((p[0] * scale + seed, p[1] * scale + seed * 0.37, p[2] * scale - seed * 0.61)))


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


# --- Tents ------------------------------------------------------------------------------------

def _dome_point(s, a, L, W, H, p, sag, dent, seed):
    """Where the fly of a two-pole dome tent is at radial parameter s (0 apex, 1 hem) and angle
    a. The hem is a superellipse, the profile a dome that is steep near the ground (the walls of
    a cheap tent), the panels between the diagonal poles sag, `dent` pushes the +x half down
    (a bent pole) and the whole thing is crumpled by two octaves of noise."""
    ca = math.cos(a)
    sa = math.sin(a)
    hx = math.copysign(abs(ca) ** (2.0 / p), ca) * L * 0.5
    hz = math.copysign(abs(sa) ** (2.0 / p), sa) * W * 0.5
    panel = math.cos(2.0 * a) ** 2  # 0 on the diagonal poles, 1 mid-panel
    belly = math.sin(math.pi * s)
    x = hx * s * (1.0 - 0.05 * panel * belly)
    z = hz * s * (1.0 - 0.05 * panel * belly)
    y = H * (max(0.0, 1.0 - s * s)) ** 0.6
    y -= sag * H * panel * belly
    if dent > 0.0:
        side = smoothstep(-0.2, 0.9, x / (L * 0.5))
        y *= 1.0 - dent * side * (0.5 + 0.5 * belly)
    q = (x, y, z)
    crumple = 0.018 * nz(q, 5.0, seed) + 0.008 * nz(q, 13.0, seed + 3.0)
    crumple *= 0.4 + 0.6 * panel
    return Vector((x + crumple * ca * 0.6, max(0.0, y + crumple), z + crumple * sa * 0.6))


def _tent(name, L, W, H, p, sag, dent, seed, guys=True):
    pc = Piece(name, ao_distance=0.6)
    ns, na = 14, 48
    rows_by_mat = {"camp_nylon": [], "camp_door": [], "camp_tub": []}
    pts = [[_dome_point(i / ns, 2.0 * math.pi * j / na, L, W, H, p, sag, dent, seed) for j in range(na + 1)]
           for i in range(ns + 1)]
    # The apex row collapses to a point; start at a tiny s instead so the grid has no zero faces.
    pts[0] = [_dome_point(0.035, 2.0 * math.pi * j / na, L, W, H, p, sag, dent, seed) for j in range(na + 1)]
    # Material per quad: the bottom band is the floor tub, the front panel is the zipped door.
    t = _new_bm()
    uvl = t.loops.layers.uv.active
    grid = [[t.verts.new(G(*q)) for q in row] for row in pts]
    faces = {"camp_nylon": [], "camp_door": [], "camp_tub": []}
    for i in range(ns):
        for j in range(na):
            a = 2.0 * math.pi * (j + 0.5) / na
            s = (i + 0.5) / ns
            quad = (grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
            f = t.faces.new(quad)
            mid = (Vector(pts[i][j]) + Vector(pts[i + 1][j + 1])) * 0.5
            mat = "camp_nylon"
            if mid.y < 0.09:
                mat = "camp_tub"
            elif math.sin(a) > 0.62 and 0.3 < s < 0.97 and mid.y < H * 0.82:
                mat = "camp_door"
            faces[mat].append(f)
            for loop in f.loops:
                q = to_godot(loop.vert.co)
                ang = math.atan2(q.z, q.x)
                loop[uvl].uv = (ang * (L + W) * 0.25, math.hypot(q.x, q.z) + q.y)
    # Make the outside the front face (the dome's outward normal points away from its axis).
    for f in t.faces:
        f.normal_update()
        c = to_godot(f.calc_center_median())
        if to_godot(f.normal).dot(Vector((c.x, c.y * 0.5, c.z))) < 0.0:
            f.normal_flip()
    t.normal_update()
    _smooth_by_angle(t, 70.0)
    # Split into one bmesh per material.
    for mat, flist in faces.items():
        sub = _new_bm()
        suv = sub.loops.layers.uv.active
        vmap = {}
        for f in flist:
            vs = []
            for v in f.verts:
                if v not in vmap:
                    vmap[v] = sub.verts.new(v.co)
                vs.append(vmap[v])
            try:
                nf = sub.faces.new(vs)
            except ValueError:
                continue
            nf.smooth = True
            for ls, ld in zip(f.loops, nf.loops):
                ld[suv].uv = ls[uvl].uv
        sub.normal_update()
        pc.add(sub, mat)
    t.free()
    # The two poles, in sleeves along the diagonals just proud of the fly.
    corner = math.atan2(1.0, 1.0)
    for a0 in (corner, math.pi - corner):
        line = []
        for k in range(-24, 25):
            s = abs(k) / 24.0
            a = a0 if k >= 0 else a0 + math.pi
            q = _dome_point(max(s, 0.02), a, L, W, H, p, 0.0, dent, seed)
            line.append((q.x * 1.01, q.y + 0.012, q.z * 1.01))
        pc.tube(line, 0.009, "camp_pole", sides=6)
    # The zip round the door: a dark cord along the door panel's edge.
    zip_line = []
    a0 = math.asin(0.62)
    for k in range(17):
        a = a0 + (math.pi - 2.0 * a0) * k / 16.0
        s = 0.33 + 0.64 * abs(a - math.pi * 0.5) / (math.pi * 0.5 - a0)
        q = _dome_point(min(0.97, s), a, L, W, H, p, sag, dent, seed)
        n = Vector((q.x, q.y * 0.4, q.z)).normalized()
        zip_line.append(tuple(q + n * 0.006))
    pc.tube(zip_line, 0.006, "camp_tub", sides=4)
    if guys:
        for a in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):
            q = _dome_point(0.55, a, L, W, H, p, sag, dent, seed)
            hem = _dome_point(1.0, a, L, W, H, p, sag, dent, seed)
            flat = Vector((hem.x, 0.0, hem.z))
            stake = flat + flat.normalized() * 0.45
            pc.tube([tuple(q), (stake.x, 0.04, stake.z)], 0.0025, "camp_rope", sides=3)
            pc.box((stake.x, 0.03, stake.z), (0.012, 0.06, 0.012), "camp_pole")
    return pc


def tent_dome():
    return _tent("camp_tent_dome", 2.10, 1.50, 1.08, 2.4, 0.07, 0.0, 1.7)


def tent_pop():
    # A smaller, rounder tent that has been pitched and re-pitched until one pole bent: its +x
    # end sags, and nobody has put its guy lines out.
    return _tent("camp_tent_pop", 1.95, 1.25, 0.92, 2.0, 0.11, 0.34, 7.3, guys=False)


# --- Tarps ------------------------------------------------------------------------------------

def tarp_canopy():
    """A poly tarp strung as a lean-to: tied to the wall (or a fence) at the back, held up at the
    front by two sticks lashed to whatever is there, sagging in the middle, the sides hanging."""
    pc = Piece("camp_tarp_canopy", ao_distance=0.8)
    nx, nzs = 30, 22
    half_x, half_z = 1.72, 1.25
    back_y, front_y = 1.88, 1.38
    rows = []
    for j in range(nzs + 1):
        tz = j / nzs
        z = -half_z + 2.0 * half_z * tz
        row = []
        for i in range(nx + 1):
            x = -half_x + 2.0 * half_x * (i / nx)
            y = back_y + (front_y - back_y) * tz
            # Across the tarp: 1 in the middle, 0 at the tie lines (x = +-1.42).
            across = math.cos(math.pi * 0.5 * min(1.0, abs(x) / 1.42)) ** 2
            # The cloth sags between its four ties, most in the middle of the span.
            y -= 0.26 * across * math.sin(math.pi * tz)
            # The unsupported front edge droops between its two sticks.
            y -= 0.14 * across * smoothstep(0.7, 1.0, tz)
            if abs(x) > 1.42:
                # Past the ties the sides hang down, drawing in as they fall.
                d = (abs(x) - 1.42) / (half_x - 1.42)
                y -= (d ** 1.4) * 0.62
                x = math.copysign(1.42 + (abs(x) - 1.42) * (1.0 - 0.35 * d), x)
            q = (x, y, z)
            y += 0.035 * nz(q, 2.2, 4.1) + 0.012 * nz(q, 7.0, 1.3)
            # Tension creases fanning in from the four tie points.
            for cx, cz in ((-1.42, -half_z), (1.42, -half_z), (-1.42, half_z), (1.42, half_z)):
                dd = math.hypot(x - cx, z - cz)
                y += 0.012 * math.sin(dd * 22.0) * math.exp(-dd * 2.2)
            row.append((x, y, z))
        rows.append(row)
    pc.grid(rows, "camp_tarp", smooth=70.0)
    # Back ties to the wall, front sticks and their lashings.
    for sx in (-1.0, 1.0):
        pc.tube([(sx * 1.42, back_y, -half_z), (sx * 1.46, back_y + 0.12, -half_z - 0.18)], 0.004, "camp_rope", sides=3)
        base = (sx * 1.45, 0.0, half_z + 0.05)
        top = (sx * 1.42, front_y + 0.08, half_z)
        pc.tube([base, top], 0.013, "camp_stick", sides=6, caps=True)
        wrap = []
        for k in range(13):
            a = k * 1.2
            wrap.append((top[0] + math.cos(a) * 0.017, front_y - 0.05 + k * 0.006, top[2] + math.sin(a) * 0.017))
        pc.tube(wrap, 0.003, "camp_rope", sides=3)
    return pc


def tarp_mound():
    """A tarp thrown over a pile - a cart and a couple of boxes - and roped down."""
    pc = Piece("camp_tarp_mound", ao_distance=0.7)
    boxes = [((-0.18, 0.0), (0.46, 0.34), 1.02), ((0.46, 0.12), (0.30, 0.30), 0.62), ((-0.62, -0.1), (0.24, 0.28), 0.48)]

    def support(x, z):
        best = 0.02
        for (cx, cz), (hx, hz), top in boxes:
            dx = max(0.0, abs(x - cx) - hx)
            dz = max(0.0, abs(z - cz) - hz)
            d = math.hypot(dx, dz)
            best = max(best, top - 2.6 * d * d - 0.35 * d)
        return best

    n = 30
    rows = []
    for j in range(n + 1):
        z = -0.95 + 1.9 * j / n
        row = []
        for i in range(n + 1):
            x = -1.2 + 2.4 * i / n
            y = support(x, z)
            # Blur the support a little by averaging a ring round the point: cloth bridges gaps.
            ring = sum(support(x + 0.12 * math.cos(k), z + 0.12 * math.sin(k)) for k in (0.0, 1.6, 3.1, 4.7)) * 0.25
            y = max(y * 0.55 + ring * 0.45, 0.012)
            q = (x, y, z)
            if y > 0.05:
                y += 0.028 * nz(q, 3.0, 2.2) + 0.01 * nz(q, 9.0, 5.1)
            row.append((x, max(0.01, y), z))
        rows.append(row)
    pc.grid(rows, "camp_tarp", smooth=70.0)
    # Two bungee cords over the top, laid on the cloth.
    for zc in (-0.22, 0.26):
        line = []
        for i in range(25):
            x = -1.05 + 2.1 * i / 24
            line.append((x, support(x, zc) * 0.55 + sum(support(x + 0.12 * math.cos(k), zc + 0.12 * math.sin(k)) for k in (0.0, 1.6, 3.1, 4.7)) * 0.25 * 0.45 + 0.025, zc))
        pc.tube(line, 0.006, "camp_plastic", sides=5)
    return pc


# --- Shopping cart ----------------------------------------------------------------------------

def cart():
    """A supermarket cart, wire by wire: tapered basket, top rim, back gate, bottom tray, the
    chassis and four casters. Nose toward +z, handle at -z."""
    pc = Piece("camp_cart", ao_distance=0.35)
    _cart_parts(pc)
    return pc


def _cart_parts(pc):
    """The cart itself, into `pc` (cart() and loaded_cart())."""
    top_y, bot_y = 1.0, 0.58
    top = {"x": 0.285, "z0": -0.47, "z1": 0.50}
    bot = {"x": 0.225, "z0": -0.36, "z1": 0.46}
    wire = 0.0026

    def side_point(side, t, h):
        """Point on the side wall: t 0 back to 1 front, h 0 bottom to 1 top."""
        zb = bot["z0"] + (bot["z1"] - bot["z0"]) * t
        zt = top["z0"] + (top["z1"] - top["z0"]) * t
        return (side * (bot["x"] + (top["x"] - bot["x"]) * h), bot_y + (top_y - bot_y) * h, zb + (zt - zb) * h)

    for side in (-1.0, 1.0):
        for k in range(20):
            t = k / 19.0
            pc.tube([side_point(side, t, 0.0), side_point(side, t, 1.0)], wire, "camp_chrome", sides=4)
        for h in (0.3, 0.62):
            pc.tube([side_point(side, 0.0, h), side_point(side, 1.0, h)], wire, "camp_chrome", sides=4)
    # Front and back panels.
    for t_end, name in ((1.0, "front"), (0.0, "back")):
        for k in range(12):
            u = -1.0 + 2.0 * k / 11.0
            a = side_point(1.0, t_end, 0.0)
            b = side_point(1.0, t_end, 1.0)
            pc.tube([(u * a[0], a[1], a[2]), (u * b[0], b[1], b[2])], wire, "camp_chrome", sides=4)
        for h in (0.3, 0.62):
            a = side_point(1.0, t_end, h)
            pc.tube([(-a[0], a[1], a[2]), (a[0], a[1], a[2])], wire, "camp_chrome", sides=4)
    # Basket bottom.
    for k in range(9):
        u = -1.0 + 2.0 * k / 8.0
        pc.tube([(u * bot["x"], bot_y, bot["z0"]), (u * bot["x"], bot_y, bot["z1"])], wire, "camp_chrome", sides=4)
    for k in range(4):
        z = bot["z0"] + (bot["z1"] - bot["z0"]) * (k + 0.5) / 4.0
        pc.tube([(-bot["x"], bot_y, z), (bot["x"], bot_y, z)], wire, "camp_chrome", sides=4)
    # Rims: the rolled top edge and the bottom frame.
    rim = [side_point(-1.0, 0.0, 1.0), side_point(-1.0, 1.0, 1.0), side_point(1.0, 1.0, 1.0), side_point(1.0, 0.0, 1.0)]
    pc.tube(rim, 0.0065, "camp_chrome", sides=8, closed=True)
    brim = [side_point(-1.0, 0.0, 0.0), side_point(-1.0, 1.0, 0.0), side_point(1.0, 1.0, 0.0), side_point(1.0, 0.0, 0.0)]
    pc.tube(brim, 0.0045, "camp_chrome", sides=6, closed=True)
    # Chassis: rear legs up into the handle posts, front legs, and the base frame.
    for side in (-1.0, 1.0):
        pc.tube([(side * 0.215, 0.105, -0.33), (side * 0.24, 0.55, -0.38), (side * 0.29, 1.03, -0.52)], 0.011, "camp_chrome", sides=8)
        pc.tube([(side * 0.19, 0.105, 0.40), (side * 0.20, 0.56, 0.44)], 0.011, "camp_chrome", sides=8)
        pc.tube([(side * 0.215, 0.14, -0.33), (side * 0.19, 0.14, 0.40)], 0.010, "camp_chrome", sides=8)
    # Handle bar with its plastic grip.
    pc.tube([(-0.30, 1.04, -0.535), (0.30, 1.04, -0.535)], 0.012, "camp_chrome", sides=8)
    pc.tube([(-0.25, 1.04, -0.535), (0.25, 1.04, -0.535)], 0.019, "camp_plastic", sides=10, caps=True)
    # Bottom tray.
    for k in range(7):
        u = -1.0 + 2.0 * k / 6.0
        pc.tube([(u * 0.20, 0.17, -0.30), (u * 0.18, 0.17, 0.36)], wire, "camp_chrome", sides=4)
    pc.tube([(-0.2, 0.17, -0.30), (0.2, 0.17, -0.30)], wire * 1.6, "camp_chrome", sides=4)
    pc.tube([(-0.18, 0.17, 0.36), (0.18, 0.17, 0.36)], wire * 1.6, "camp_chrome", sides=4)
    # Casters: fork and wheel.
    for (cx, cz) in ((-0.215, -0.33), (0.215, -0.33), (-0.19, 0.40), (0.19, 0.40)):
        pc.box((cx, 0.085, cz - 0.015), (0.045, 0.04, 0.03), "camp_chrome", bevel=0.004)
        pc.torus((cx, 0.062, cz - 0.03), (1.0, 0.0, 0.0), 0.047, 0.014, "camp_rubber", seg=16, sides=6)
        pc.box((cx, 0.062, cz - 0.03), (0.03, 0.05, 0.05), "camp_plastic", bevel=0.01)


# --- Bags -------------------------------------------------------------------------------------

def _sack(pc, c, radii, seed, lean=0.0, mat="camp_bag"):
    """A knotted trash bag sitting on the ground: flat underneath, gathered to a neck and a knot,
    creased where the plastic is pulled toward the neck."""
    neck = Vector((c[0] + lean, c[1] + radii[1] * 1.12, c[2]))

    def shape(p, n):
        q = Vector(p)
        # Radial creases converging on the neck, stronger toward the top.
        lon = math.atan2(n.z, n.x) if abs(n.y) < 0.999 else 0.0
        up = max(0.0, n.y)
        crease = 0.035 * math.sin(lon * 7.0 + seed) * up ** 1.5
        wobble = 0.05 * nz(q, 4.0, seed) + 0.02 * nz(q, 11.0, seed + 1.0)
        r = 1.0 + crease + wobble
        q = Vector(c) + (q - Vector(c)) * r
        # Pinch the top into the neck.
        pinch = smoothstep(0.55, 1.0, n.y)
        q = q.lerp(neck, pinch * 0.85)
        # Sat down: flattened on the ground, bulging out at the bottom.
        if q.y < c[1] - radii[1] * 0.55:
            q.y = c[1] - radii[1] * 0.55 + (q.y - (c[1] - radii[1] * 0.55)) * 0.15
        return q
    pc.blob(c, radii, mat, seg=16, rings=11, shape=shape)
    # The knot and its two ears.
    pc.blob(tuple(neck + Vector((0.0, 0.02, 0.0))), (0.03, 0.035, 0.03), mat, seg=8, rings=5)
    for s in (-1.0, 1.0):
        pc.blob(tuple(neck + Vector((s * 0.045, 0.06, 0.01 * s))), (0.035, 0.012, 0.02), mat, seg=8, rings=4)


def bag_trash():
    pc = Piece("camp_bag_trash", ao_distance=0.3)
    _sack(pc, (0.0, 0.26 * 0.55 + 0.002, 0.0), (0.27, 0.26, 0.25), 1.3)
    return pc


def _duffel(pc, c, length, r, yaw, seed):
    """A slumped canvas duffel with two handles and a zip."""
    rot = Matrix.Rotation(yaw, 3, 'Y')

    def shape(p, n):
        q = Vector(p) - Vector(c)
        q.y *= 0.72 if q.y > 0 else 0.55
        q.y += 0.04 * nz(p, 5.0, seed)
        return Vector(c) + rot @ q
    pc.blob(c, (length * 0.5, r, r), "camp_canvas", seg=14, rings=9, shape=shape)
    for s in (-0.12, 0.12):
        arc_pts = []
        for k in range(9):
            a = math.pi * k / 8.0
            q = Vector((s + math.cos(a) * 0.06, r * 0.72 + math.sin(a) * 0.08, 0.0))
            arc_pts.append(tuple(Vector(c) + rot @ q))
        pc.tube(arc_pts, 0.008, "camp_rope", sides=4)
    zipl = [tuple(Vector(c) + rot @ Vector((x, r * 0.72 + 0.005, 0.03))) for x in (-length * 0.36, 0.0, length * 0.36)]
    pc.tube(zipl, 0.005, "camp_tub", sides=4)


def bag_duffel():
    pc = Piece("camp_bag_duffel", ao_distance=0.3)
    _duffel(pc, (0.0, 0.1, 0.0), 0.64, 0.17, 0.0, 2.9)
    return pc


def bags_pile():
    """Three trash bags and a duffel heaped together (one instance instead of four)."""
    pc = Piece("camp_bags_pile", ao_distance=0.45)
    _sack(pc, (-0.22, 0.14, -0.05), (0.26, 0.25, 0.24), 3.1, lean=0.03)
    _sack(pc, (0.24, 0.12, 0.08), (0.23, 0.22, 0.22), 5.7, lean=-0.02)
    _sack(pc, (0.02, 0.40, -0.02), (0.22, 0.19, 0.20), 8.9, lean=0.05)
    _duffel(pc, (0.05, 0.1, 0.34), 0.58, 0.15, 0.25, 4.4)
    return pc


# --- Bedding ----------------------------------------------------------------------------------

def mattress():
    """A second-hand twin mattress lying on the pavement: rounded edges, sagging in the middle,
    one end curling up off the ground, a piping cord round its top edge. Long along x."""
    pc = Piece("camp_mattress", ao_distance=0.35)
    L, W, T = 1.9, 0.96, 0.19
    nx, nw = 22, 8

    def warp(x, z):
        tx = (x + L * 0.5) / L
        y = 0.07 * smoothstep(0.78, 1.0, tx) ** 1.5 - 0.02 * math.sin(math.pi * tx) * math.sin(math.pi * (z + W * 0.5) / W)
        return y + 0.008 * nz((x, 0.0, z), 3.0, 6.6)

    def section(k, x):
        """The cross-section at x: a rounded rectangle (a superellipse), k round it."""
        th = 2.0 * math.pi * k / (4 * nw)
        c, sn = math.cos(th), math.sin(th)
        z = math.copysign(abs(c) ** (2.0 / 9.0), c) * W * 0.5
        y = math.copysign(abs(sn) ** (2.0 / 9.0), sn) * T * 0.5 + T * 0.5
        return (x, y + warp(x, z), z)

    ring_n = 4 * nw
    rows = []
    for i in range(nx + 1):
        x = -L * 0.5 + L * i / nx
        rows.append([section(k, x) for k in range(ring_n + 1)])
    pc.grid(rows, "camp_mattress", smooth=50.0)
    # End caps.
    for x in (-L * 0.5, L * 0.5):
        cap = [section(k, x) for k in range(ring_n)]
        t = _new_bm()
        vs = [t.verts.new(G(*p)) for p in cap]
        f = t.faces.new(vs)
        f.normal_update()
        if to_godot(f.normal).x * x < 0.0:
            f.normal_flip()
        _box_uv(t)
        pc.add(t, "camp_mattress")
    # Piping round the top edge.
    edge = []
    for i in range(nx + 1):
        x = -L * 0.5 + L * i / nx
        edge.append((x, T + warp(x, W * 0.5) - 0.01, W * 0.5 - 0.005))
    for i in range(nx, -1, -1):
        x = -L * 0.5 + L * i / nx
        edge.append((x, T + warp(x, -W * 0.5) - 0.01, -W * 0.5 + 0.005))
    pc.tube(edge, 0.008, "camp_tub", sides=5, closed=True)
    return pc


def bedding():
    """A rumpled sleeping bag with a blanket pulled half over it and a balled-up pillow, lying
    flat on the ground. Long along x, head (the pillow) at -x. Somebody lies on it."""
    pc = Piece("camp_bedding", ao_distance=0.3)
    L, W = 1.95, 0.84
    n, m = 30, 14
    rows = []
    for j in range(m + 1):
        z = -W * 0.5 + W * j / m
        row = []
        for i in range(n + 1):
            x = -L * 0.5 + L * i / n
            tz = abs(z) / (W * 0.5)
            y = 0.075 * (1.0 - tz ** 3)
            y += 0.02 * math.sin(x * 9.0 + z * 4.0) * (1.0 - tz)
            y += 0.018 * nz((x, 0.0, z), 4.0, 2.4)
            row.append((x, max(0.005, y), z * (1.0 + 0.05 * nz((x, 0.0, z), 2.0, 9.0))))
        rows.append(row)
    pc.grid(rows, "camp_quilt", smooth=70.0)
    # The blanket: a thinner sheet over the lower two thirds, folded back at its top edge.
    rows = []
    for j in range(m + 1):
        z = -W * 0.62 + W * 1.24 * j / m
        row = []
        for i in range(19):
            x = -0.15 + 1.2 * i / 18
            tz = min(1.0, abs(z) / (W * 0.5))
            y = 0.09 * (1.0 - tz ** 2.5) + 0.012
            y -= max(0.0, abs(z) - W * 0.5) * 0.6
            y += 0.025 * math.sin(x * 7.0 - z * 6.0) + 0.012 * nz((x, 0.0, z), 6.0, 1.1)
            if i == 0:
                y += 0.03
            row.append((x, max(0.006, y), z))
        rows.append(row)
    pc.grid(rows, "camp_canvas", smooth=70.0)
    pc.blob((-0.8, 0.07, 0.02), (0.2, 0.07, 0.3), "camp_mattress", seg=12, rings=7,
            shape=lambda p, nn: Vector(p) + Vector((0.0, 0.02 * nz(p, 6.0, 3.3), 0.0)))
    return pc


# --- Cardboard --------------------------------------------------------------------------------

def _sheet(pc, c, sx, sz, yaw, curl, seed):
    """One flattened box: a board 7 mm thick lying on the ground, curled a little, with the
    crease where it used to fold."""
    rot = Matrix.Rotation(yaw, 3, 'Y')
    nx = 8
    top, bot = [], []
    for i in range(nx + 1):
        u = -0.5 + i / nx
        lift = curl * (2.0 * abs(u)) ** 2 + (0.006 if abs(u) < 0.07 else 0.0)
        row_t, row_b = [], []
        for zz in (-0.5, 0.5):
            y = c[1] + lift + 0.004 * nz((u, 0, zz), 3.0, seed)
            q = Vector((u * sx, 0.0, zz * sz))
            p = Vector(c) + rot @ q
            row_t.append((p.x, y + 0.007, p.z))
            row_b.append((p.x, y, p.z))
        top.append(row_t)
        bot.append(row_b)
    pc.grid([list(r) for r in zip(*top)], "camp_cardboard", uv="box", smooth=30.0)
    edge = []
    for i in range(nx + 1):
        edge.append([bot[i][1], top[i][1]])
    pc.grid(edge, "camp_cardboard", uv="box", smooth=30.0)
    edge = []
    for i in range(nx + 1):
        edge.append([top[i][0], bot[i][0]])
    pc.grid(edge, "camp_cardboard", uv="box", smooth=30.0)


def cardboard():
    pc = Piece("camp_cardboard", ao_distance=0.2)
    _sheet(pc, (0.0, 0.002, 0.0), 1.15, 0.78, 0.06, 0.03, 1.0)
    _sheet(pc, (0.38, 0.012, 0.18), 0.92, 0.62, -0.32, 0.05, 2.0)
    _sheet(pc, (-0.45, 0.012, -0.12), 0.7, 0.55, 0.5, 0.02, 3.0)
    return pc


def box():
    """An open cardboard box, a bit crushed, its flaps standing open."""
    pc = Piece("camp_box", ao_distance=0.3)
    sx, sy, sz = 0.52, 0.36, 0.40
    t = 0.006
    for x in (-sx * 0.5, sx * 0.5):
        pc.box((x, sy * 0.5, 0.0), (t, sy, sz), "camp_cardboard", rot=Matrix.Rotation(0.03 * (1 if x > 0 else -1), 3, 'Z'))
    for z in (-sz * 0.5, sz * 0.5):
        pc.box((0.0, sy * 0.5 - (0.02 if z > 0 else 0.0), z), (sx, sy - (0.04 if z > 0 else 0.0), t), "camp_cardboard")
    pc.box((0.0, 0.004, 0.0), (sx, t, sz), "camp_cardboard")
    # The four flaps, hinged on the top edges and standing open at their own angles.
    top = sy
    for hinge_a, hinge_b, out, ang, depth in (
            ((-sx * 0.5, top, -sz * 0.5), (sx * 0.5, top, -sz * 0.5), (0.0, 0.0, -1.0), 1.05, 0.18),
            ((-sx * 0.5, top - 0.04, sz * 0.5), (sx * 0.5, top - 0.04, sz * 0.5), (0.0, 0.0, 1.0), 0.55, 0.16),
            ((-sx * 0.5, top, -sz * 0.5), (-sx * 0.5, top, sz * 0.5), (-1.0, 0.0, 0.0), 0.8, 0.2),
            ((sx * 0.5, top, -sz * 0.5), (sx * 0.5, top, sz * 0.5), (1.0, 0.0, 0.0), 1.35, 0.2)):
        d = Vector(out) * math.cos(ang) + Vector((0.0, 1.0, 0.0)) * math.sin(ang)
        a = Vector(hinge_a)
        b = Vector(hinge_b)
        pc.grid([[tuple(a), tuple(b)], [tuple(a + d * depth), tuple(b + d * depth)]], "camp_cardboard", uv="box", smooth=10.0)
    return pc


# --- Camp chair -------------------------------------------------------------------------------

def chair():
    """A folding quad camp chair: tube-steel X frame front, back and sides, a sagging sling seat
    and back, fabric arm rests. Faces +z."""
    pc = Piece("camp_chair", ao_distance=0.35)
    w, d, seat, arm, back = 0.27, 0.24, 0.42, 0.62, 0.9
    r = 0.0085
    # Legs.
    for x in (-w, w):
        pc.tube([(x, 0.0, d), (x, arm, d - 0.02)], r, "camp_pole", sides=6)
        pc.tube([(x, 0.0, -d), (x * 1.02, back, -d - 0.1)], r, "camp_pole", sides=6)
        # Side X-brace.
        pc.tube([(x, 0.03, d), (x, seat, -d)], r * 0.8, "camp_pole", sides=6)
        pc.tube([(x, 0.03, -d), (x, seat, d)], r * 0.8, "camp_pole", sides=6)
        # Arm rest rail.
        pc.tube([(x, arm, d - 0.02), (x, arm - 0.02, -d - 0.04)], r, "camp_pole", sides=6)
    # Front and back X-braces.
    for z in (d, -d):
        pc.tube([(-w, 0.03, z), (w, seat, z)], r * 0.8, "camp_pole", sides=6)
        pc.tube([(w, 0.03, z), (-w, seat, z)], r * 0.8, "camp_pole", sides=6)
    # Seat sling.
    rows = []
    for j in range(9):
        z = -d + 2.0 * d * j / 8
        row = []
        for i in range(11):
            x = -w + 2.0 * w * i / 10
            y = seat - 0.06 * math.sin(math.pi * i / 10) * math.sin(math.pi * j / 8) - 0.01
            row.append((x, y, z))
        rows.append(row)
    pc.grid(rows, "camp_nylon", smooth=70.0)
    # Back sling, leaning back.
    rows = []
    for j in range(9):
        tt = j / 8
        y = seat + (back - 0.05 - seat) * tt
        zb = -d - 0.1 * tt
        row = []
        for i in range(11):
            x = -w * 1.01 + 2.02 * w * i / 10
            row.append((x, y, zb - 0.045 * math.sin(math.pi * i / 10) * (0.3 + 0.7 * math.sin(math.pi * tt))))
        rows.append(row)
    pc.grid(rows, "camp_nylon", smooth=70.0)
    # Arm rests: fabric bands.
    for x in (-w, w):
        rows = []
        for k in range(5):
            z = d - 0.02 - (2.0 * d + 0.02) * k / 4
            rows.append([(x - 0.035, arm - 0.004 - 0.02 * k / 4, z), (x + 0.035, arm - 0.004 - 0.02 * k / 4, z)])
        pc.grid(rows, "camp_nylon", smooth=60.0)
    # Feet.
    for (x, z) in ((-w, d), (w, d), (-w, -d), (w, -d)):
        pc.box((x, 0.008, z), (0.03, 0.016, 0.03), "camp_rubber", bevel=0.004)
    return pc


# --- Bicycles ---------------------------------------------------------------------------------

WHEEL_R = 0.338
RIM_R = 0.305
BIKE = {
    "rear": Vector((0.0, WHEEL_R, -0.52)), "front": Vector((0.0, WHEEL_R, 0.53)),
    "bb": Vector((0.0, 0.30, -0.08)), "seat": Vector((0.0, 0.84, -0.22)),
    "head_top": Vector((0.0, 0.90, 0.40)), "head_bot": Vector((0.0, 0.74, 0.445)),
}


def _wheel(pc, c, axis=(1.0, 0.0, 0.0), spokes=20):
    c = Vector(c)
    ax = Vector(axis).normalized()
    pc.torus(c, ax, WHEEL_R - 0.026, 0.026, "camp_rubber", seg=32, sides=8)
    rim_prof = [(-0.013, -0.011), (0.013, -0.009), (0.013, 0.009), (-0.013, 0.011)]
    pc.torus(c, ax, RIM_R - 0.004, 0.0, "camp_chrome", seg=32, profile=rim_prof, smooth=30.0)
    s, u = _frame(ax)
    for k in range(spokes):
        a = 2.0 * math.pi * k / spokes
        side = 1.0 if k % 2 == 0 else -1.0
        hub = c + ax * (0.028 * side) + (s * math.cos(a + 0.35 * side) + u * math.sin(a + 0.35 * side)) * 0.02
        rim = c + (s * math.cos(a) + u * math.sin(a)) * (RIM_R - 0.012)
        pc.tube([tuple(hub), tuple(rim)], 0.0012, "camp_chrome", sides=3)
    pc.tube([tuple(c - ax * 0.05), tuple(c + ax * 0.05)], 0.018, "camp_chrome", sides=8, caps=True)


def _frame_tubes(pc, fork=True, bars=True):
    b = BIKE
    t = 0.0165
    pc.tube([tuple(b["bb"]), tuple(b["head_bot"])], t * 1.15, "camp_frame", sides=8)
    pc.tube([tuple(b["seat"]), tuple(b["head_top"] + Vector((0, -0.02, -0.01)))], t, "camp_frame", sides=8)
    pc.tube([tuple(b["bb"]), tuple(b["seat"] + Vector((0, 0.04, -0.015)))], t, "camp_frame", sides=8)
    pc.tube([tuple(b["head_bot"]), tuple(b["head_top"] + Vector((0, 0.03, -0.007)))], 0.02, "camp_frame", sides=8)
    for s in (-1.0, 1.0):
        pc.tube([tuple(b["bb"] + Vector((s * 0.02, 0, 0))), tuple(b["rear"] + Vector((s * 0.065, 0, 0)))], 0.009, "camp_frame", sides=6)
        pc.tube([tuple(b["seat"] + Vector((s * 0.015, -0.02, 0))), tuple(b["rear"] + Vector((s * 0.065, 0.01, 0)))], 0.008, "camp_frame", sides=6)
        if fork:
            pc.tube([tuple(b["head_bot"] + Vector((s * 0.03, 0, 0))), tuple(b["head_bot"].lerp(b["front"], 0.5) + Vector((s * 0.055, 0, 0.02))),
                     tuple(b["front"] + Vector((s * 0.055, 0, 0)))], 0.011, "camp_chrome", sides=6)
    # Seat post and saddle.
    post_top = b["seat"] + Vector((0, 0.14, -0.05))
    pc.tube([tuple(b["seat"]), tuple(post_top)], 0.013, "camp_chrome", sides=8)
    def saddle(p, n):
        # Narrow toward the nose (+z): a saddle, not an egg.
        q = Vector(p)
        if n.z > 0.2:
            q.x = post_top.x + (q.x - post_top.x) * (1.0 - 0.6 * (n.z - 0.2) / 0.8)
        return q
    pc.blob(tuple(post_top + Vector((0, 0.03, -0.02))), (0.075, 0.03, 0.14), "camp_saddle", seg=12, rings=6, shape=saddle)
    if bars:
        stem_top = b["head_top"] + Vector((0, 0.07, 0.05))
        pc.tube([tuple(b["head_top"]), tuple(stem_top)], 0.014, "camp_chrome", sides=8)
        bar = [(-0.32, stem_top.y + 0.01, stem_top.z - 0.03), (-0.12, stem_top.y + 0.02, stem_top.z), (0.12, stem_top.y + 0.02, stem_top.z), (0.32, stem_top.y + 0.01, stem_top.z - 0.03)]
        pc.tube(bar, 0.011, "camp_chrome", sides=8)
        for s in (-1.0, 1.0):
            pc.tube([(s * 0.23, stem_top.y + 0.015, stem_top.z - 0.015), (s * 0.32, stem_top.y + 0.01, stem_top.z - 0.03)], 0.016, "camp_rubber", sides=8, caps=True)
    # Cranks, chainring, pedals.
    bb = b["bb"]
    pc.tube([tuple(bb + Vector((-0.07, 0, 0))), tuple(bb + Vector((0.07, 0, 0)))], 0.018, "camp_chrome", sides=8, caps=True)
    pc.torus(bb + Vector((0.055, 0, 0)), (1.0, 0.0, 0.0), 0.085, 0.0, "camp_chrome", seg=24,
             profile=[(-0.012, -0.002), (0.012, -0.002), (0.012, 0.002), (-0.012, 0.002)], smooth=20.0)
    for s, a in ((1.0, 0.6), (-1.0, 0.6 + math.pi)):
        end = bb + Vector((s * 0.075, -math.cos(a) * 0.17, math.sin(a) * 0.17))
        pc.tube([tuple(bb + Vector((s * 0.075, 0, 0))), tuple(end)], 0.009, "camp_chrome", sides=6)
        pc.box(tuple(end + Vector((s * 0.05, 0, 0))), (0.09, 0.02, 0.06), "camp_rubber", bevel=0.004)
    # Chain: a loop from the ring to the rear sprocket, as a thin tube.
    chain = []
    for k in range(12):
        a = math.pi * 0.5 + math.pi * k / 11.0
        chain.append(tuple(bb + Vector((0.055, math.sin(a) * 0.087, math.cos(a) * 0.087))))
    rear = b["rear"]
    for k in range(12):
        a = -math.pi * 0.5 + math.pi * k / 11.0
        chain.append(tuple(rear + Vector((0.055, math.sin(a) * 0.035, math.cos(a) * 0.035))))
    pc.tube(chain, 0.003, "camp_tub", sides=4, closed=True)


def bicycle():
    pc = Piece("camp_bicycle", ao_distance=0.3)
    _wheel(pc, BIKE["rear"])
    _wheel(pc, BIKE["front"])
    _frame_tubes(pc)
    return pc


def bike_wheel():
    """A loose wheel lying flat on the ground (a bike taken apart)."""
    pc = Piece("camp_bike_wheel", ao_distance=0.25)
    _wheel(pc, (0.0, 0.027, 0.0), axis=(0.0, 1.0, 0.0))
    return pc


def bike_frame():
    """A frame with its fork and bars, no wheels, lying on its left side."""
    pc = Piece("camp_bike_frame", ao_distance=0.3)
    _frame_tubes(pc)
    # Lay it down: rotate everything a quarter turn about z and sit it on the ground.
    rot = Matrix.Rotation(math.radians(-90.0), 3, 'Z')
    bm = pc.bm
    lowest = 1e9
    for v in bm.verts:
        g = to_godot(v.co)
        g = rot @ g
        v.co = G(*g)
        lowest = min(lowest, g.y)
    xs = [to_godot(v.co).x for v in bm.verts]
    mid_x = (min(xs) + max(xs)) * 0.5
    for v in bm.verts:
        g = to_godot(v.co)
        g.y -= lowest
        g.x -= mid_x
        v.co = G(*g)
    return pc


# --- What people carry (2026-09-25) --------------------------------------------------------------

def _ellipse_band(pc, c, rx, ry, plane, mat, r=0.007):
    """A rope pulled tight round a bundle: a closed loop on an ellipse about Godot `c`, in the
    x-y plane ("xy") or the z-y plane ("zy")."""
    pts = []
    for k in range(20):
        a = 2.0 * math.pi * k / 20
        if plane == "xy":
            pts.append((c[0] + rx * math.cos(a), c[1] + ry * math.sin(a), c[2]))
        else:
            pts.append((c[0], c[1] + ry * math.sin(a), c[2] + rx * math.cos(a)))
    pc.tube(pts, r, mat, sides=4, closed=True)


def _blanket_roll(pc, c, length, r, seed):
    """A blanket rolled up along x and roped at both ends of the roll."""
    def shape(p, n):
        q = Vector(p)
        q.y += 0.015 * nz(q, 6.0, seed)
        # Squashed a little where it sits.
        if q.y < c[1] - r * 0.6:
            q.y = c[1] - r * 0.6 + (q.y - (c[1] - r * 0.6)) * 0.3
        return q
    pc.blob(c, (length * 0.5, r, r * 1.05), "camp_quilt", seg=14, rings=9, shape=shape)
    for sx in (-0.3, 0.3):
        _ellipse_band(pc, (c[0] + sx * length, c[1], c[2]), r * 1.03, r * 0.99, "zy", "camp_rope", r=0.006)


def loaded_cart():
    """A cart somebody lives out of: black sacks packed into the basket and heaped over the rim, a
    blanket rolled and roped on top, a sheet of cardboard stood up inside the front, a sack on the
    bottom tray. The same cart as cart() (nose toward +z, handle at -z); pushed along the pavement
    by RoughSleeper's PUSH, or parked at a camp. Its instance colour is the blanket's."""
    pc = Piece("camp_loaded_cart", ao_distance=0.35)
    _cart_parts(pc)
    bottom = 0.58
    _sack(pc, (-0.1, bottom + 0.21 * 0.55, 0.22), (0.2, 0.21, 0.2), 1.7, lean=0.02, mat="camp_sack")
    _sack(pc, (0.11, bottom + 0.22 * 0.55, -0.17), (0.19, 0.22, 0.21), 6.1, lean=-0.03, mat="camp_sack")
    _sack(pc, (0.03, 0.93, 0.02), (0.22, 0.19, 0.24), 2.2, lean=0.04, mat="camp_sack")
    _blanket_roll(pc, (0.0, 1.17, -0.12), 0.62, 0.12, 3.7)
    pc.box((0.0, 0.93, 0.40), (0.44, 0.62, 0.008), "camp_cardboard", bevel=0.002)
    _sack(pc, (0.0, 0.18 + 0.1 * 0.55, 0.03), (0.15, 0.1, 0.2), 4.2, mat="camp_sack")
    return pc


def bundle():
    """A blanket knotted round somebody's things and roped both ways: set down at their feet."""
    pc = Piece("camp_bundle", ao_distance=0.3)
    c = (0.0, 0.17, 0.0)
    rx, ry, rz = 0.3, 0.18, 0.21

    def shape(p, n):
        q = Vector(p)
        q += Vector((0.0, 0.02 * nz(q, 5.0, 7.3), 0.0)) + n * 0.02 * nz(q, 9.0, 1.9)
        if q.y < 0.03:
            q.y = 0.03 + (q.y - 0.03) * 0.15
        return q
    pc.blob(c, (rx, ry, rz), "camp_quilt", seg=16, rings=10, shape=shape)
    # The blanket's corners knotted on top, and the rope both ways round it.
    for s in (-1.0, 1.0):
        pc.blob((s * 0.07, 0.35, 0.03 * s), (0.08, 0.045, 0.05), "camp_quilt", seg=10, rings=6)
    _ellipse_band(pc, c, rx * 1.01, ry * 1.02, "xy", "camp_rope")
    _ellipse_band(pc, c, rz * 1.02, ry * 1.02, "zy", "camp_rope")
    pc.blob((0.0, 0.37, 0.0), (0.03, 0.025, 0.03), "camp_rope", seg=8, rings=5)
    return pc


PIECES = [tent_dome, tent_pop, tarp_canopy, tarp_mound, cart, bag_trash, bag_duffel, bags_pile,
          mattress, bedding, cardboard, box, chair, bicycle, bike_wheel, bike_frame,
          loaded_cart, bundle]


# --- Bake and export -----------------------------------------------------------------------------

def _plane(name, corners):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([G(*c) for c in corners], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def bake_ao(obj, piece):
    """Cycles AO against a ground plane into a corner colour attribute, then into UV2.x as
    occlusion (1 - AO)."""
    mesh = obj.data
    attr = mesh.color_attributes.new("ao", 'FLOAT_COLOR', 'CORNER')
    mesh.color_attributes.active_color = attr
    ground = _plane("occ_ground", [(-6, 0, -6), (6, 0, -6), (6, 0, 6), (-6, 0, 6)])
    for o in bpy.context.scene.objects:
        o.hide_render = not (o == obj or o == ground)
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.context.scene.world.light_settings.distance = piece.ao_distance
    ok = True
    try:
        bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
    except Exception as e:  # keep going without AO rather than failing the kit
        print("  AO bake failed on %s: %s" % (obj.name, e))
        ok = False
    uv2 = mesh.uv_layers.new(name="AO")
    for loop in mesh.loops:
        v = attr.data[loop.index].color[0] if ok else 1.0
        uv2.data[loop.index].uv = (max(0.0, min(1.0, 1.0 - v)), 0.0)
    mesh.color_attributes.remove(attr)
    bpy.data.objects.remove(ground, do_unlink=True)
    for o in bpy.context.scene.objects:
        o.hide_render = False


def main():
    random.seed(1)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 32
    scene.render.bake.target = 'VERTEX_COLORS'
    world = bpy.data.worlds.new("kit_world")
    scene.world = world
    objects = []
    report = []
    for make in PIECES:
        piece = make()
        mesh = bpy.data.meshes.new(piece.name)
        piece.bm.to_mesh(mesh)
        piece.bm.free()
        for m in piece.mats:
            mesh.materials.append(material(m))
        obj = bpy.data.objects.new(piece.name, mesh)
        scene.collection.objects.link(obj)
        tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
        xs = [to_godot(v.co) for v in mesh.vertices]
        lo = Vector((min(p.x for p in xs), min(p.y for p in xs), min(p.z for p in xs)))
        hi = Vector((max(p.x for p in xs), max(p.y for p in xs), max(p.z for p in xs)))
        report.append("%-20s %5d tris  box (%.2f %.2f %.2f)..(%.2f %.2f %.2f)  mats %s" % (
            piece.name, tris, lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, ",".join(piece.mats)))
        objects.append((obj, piece))
    if BAKE:
        for obj, piece in objects:
            bake_ao(obj, piece)
    else:
        for obj, _piece in objects:
            uv2 = obj.data.uv_layers.new(name="AO")
            for loop in obj.data.loops:
                uv2.data[loop.index].uv = (0.0, 0.0)
    for obj, _piece in objects:
        obj.data.uv_layers.active = obj.data.uv_layers["UVMap"]
        obj.data.uv_layers["UVMap"].active_render = True
    bpy.ops.object.select_all(action='DESELECT')
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(OUT), export_format='GLB', export_yup=True,
                              export_apply=True, export_texcoords=True, export_normals=True,
                              export_tangents=False, export_materials='EXPORT',
                              export_vertex_color='NONE', export_animations=False,
                              export_cameras=False, export_lights=False)
    print("encampment kit ->", os.path.abspath(OUT))
    for line in report:
        print("  " + line)


main()
# As a Python module (python3 tools/encampment_kit.py), bpy crashes tearing itself down after the
# file is written; leave without the teardown so the exit code says whether the kit was made.
sys.stdout.flush()
os._exit(0)
