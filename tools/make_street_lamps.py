"""Los Angeles street lights at real size, for the city's pavements (fleet task "street-lamps",
2026-10-05: lamps were the last primitive-and-scan prop on every street).

Run headless with Blender 4.2:

    blender -b --factory-startup --python tools/make_street_lamps.py -- [out.glb]

(no Blender install? `pip install bpy==4.2.0` gives the same Blender as a Python module; then
`python3 -c "import bpy, runpy, sys; sys.argv=['x','--']; runpy.run_path('tools/make_street_lamps.py', run_name='__main__')"`.)

Writes assets/models/street_lamps.glb, one mesh node per lamp type. Then run
`godot --headless --path . --import` before rendering anything (Godot serves a cached import of a
.glb) and commit the .glb and its .import.

The five types (StreetLamps.TYPES in scripts/world/street_lamps.gd holds the numbers the placing
code needs - light point, collision box - and the smoke test checks them against this model's
bounds, so change both or neither):

* sl_cobra: the cobra-head. A tapered round galvanised pole, 8.4 m, on a bolted base plate under a
  flared base cover, an upswept arm reaching 2.4 m out along +x, a die-cast cobra head with a
  drop-glass refractor and a photocell. Light at (2.55, 8.62).
* sl_twin: the downtown twin-globe ornamental. A fluted cast-iron post on an octagonal plinth, a
  leaf collar, a scrolled cross-arm along x and two frosted globes at x = +-0.62, a finial. Lights
  at (+-0.62, 4.95).
* sl_lantern: the midtown single-lantern ornamental. A fluted post with a ring collar and a
  hexagonal lantern on top: six panes of seeded glass between ribs, a hipped roof and a finial.
  Light at (0, 4.35).
* sl_post: the residential post-top. A spun-concrete pole (exposed aggregate) with a cylindrical
  prismatic post-top luminaire under a dark cap. Light at (0, 4.62).
* sl_mast: the mast-arm LED. A tapered galvanised pole, 9.4 m, a straight mast arm rising slightly
  to 3.3 m out along +x, a thin flat LED head with heat-sink fins. Light at (3.35, 9.38).

Every arm reaches along +x: the placing code turns +x toward the street. Origins on the pavement
at the pole's axis, y up, metres, all in GODOT space (G() converts on the way in).

ONE material, `street_lamp`, so a lamp type is one surface and one draw: what a face is rides in
its SECOND UV channel (Godot UV2.x = (part + 0.5) / 8; shaders/street_lamp.gdshader):
0 galvanised steel, 1 painted cast iron (takes the instance colour), 2 die-cast aluminium,
3 spun concrete, 4 lens (drop glass, lit), 5 diffuser (globes, lantern glass, prismatic refractor,
lit soft), 6 dark (gaskets, bolts, photocell), 7 LED array (lit, dotted). UV2.y is where a lit
face sits in its diffuser, 0 bottom .. 1 top, the glow's falloff. UV1 is metres (along a lathe:
round x down), which the shader's detail reads.

Every hard edge is bevelled or rolled and the normals are face-area weighted (WeightedNormal), so
flats stay flat and edges catch the light.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = next((a for a in ARGV if a.endswith(".glb")),
           os.path.join(HERE, "..", "assets", "models", "street_lamps.glb"))

GALV, PAINT, ALU, CONCRETE, LENS, DIFFUSER, DARK, LED = range(8)


def G(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


def to_godot(v):
    return Vector((v.x, v.z, -v.y))


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
            e.smooth = False


def _box_uv(t):
    uvl = t.loops.layers.uv.active
    for f in t.faces:
        n = to_godot(f.normal)
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            p = to_godot(loop.vert.co)
            if ax == 1:
                loop[uvl].uv = (p.x, p.z)
            elif ax == 0:
                loop[uvl].uv = (p.z, p.y)
            else:
                loop[uvl].uv = (p.x, p.y)


def _frame(axis):
    A = Vector(axis).normalized()
    U = Vector((0, 1, 0)).cross(A)
    if U.length < 0.1:
        U = Vector((1, 0, 0)).cross(A)
    U.normalize()
    V = A.cross(U).normalized()
    return A, U, V


class Piece:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.uv2 = self.bm.loops.layers.uv.new("Part")

    def add(self, t, part, glow=None):
        """Copies bmesh `t` into the piece with `part` in UV2.x; `glow` (lo, hi) maps the Godot y
        of each vertex to UV2.y 0..1 (a lit part's falloff), else 1."""
        uv_s = t.loops.layers.uv.active
        code = (part + 0.5) / 8.0
        vmap = {v: self.bm.verts.new(v.co) for v in t.verts}
        for f in t.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            nf.smooth = f.smooth
            for ls, ld in zip(f.loops, nf.loops):
                ld[self.uv].uv = ls[uv_s].uv
                g = 1.0
                if glow:
                    y = to_godot(ls.vert.co).y
                    g = max(0.0, min(1.0, (y - glow[0]) / max(glow[1] - glow[0], 1e-4)))
                ld[self.uv2].uv = (code, g)
        for e in t.edges:
            ne = self.bm.edges.get([vmap[v] for v in e.verts])
            if ne:
                ne.smooth = e.smooth
        t.free()

    # --- primitives ------------------------------------------------------------------------

    def box(self, c, size, part, bevel=0.0, segments=2, smooth=35.0, axes=None):
        t = _new_bm()
        bmesh.ops.create_cube(t, size=1.0)
        ax, ay, az = axes if axes else (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
        for v in t.verts:
            gx, gy, gz = v.co.x * size[0], v.co.z * size[1], -v.co.y * size[2]
            p = Vector(c) + ax * gx + ay * gy + az * gz
            v.co = G(p.x, p.y, p.z)
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        if bevel > 0.0:
            bmesh.ops.bevel(t, geom=list(t.edges), offset=bevel, segments=segments, profile=0.5,
                            affect='EDGES', clamp_overlap=True)
        t.normal_update()
        _box_uv(t)
        _smooth_by_angle(t, smooth)
        self.add(t, part)

    def lathe(self, prof, origin, axis, part, segs=24, smooth=40.0, flutes=0, flute_depth=0.0,
              flute_span=None, glow=None, phase=0.0):
        """A closed solid of revolution: `prof` is (radius, distance along `axis`) points revolved
        about the Godot line through `origin`. `flutes` > 0 cuts that many rounded grooves of
        `flute_depth` (share of the radius) between distances flute_span (lo, hi)."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        A, U, V = _frame(axis)
        rings = []
        for i in range(segs):
            a = math.radians(phase) + math.tau * i / segs
            ring = []
            for (r, d) in prof:
                f = 1.0
                if flutes and flute_span and flute_span[0] <= d <= flute_span[1]:
                    # Rounded grooves: |cos| gives a scalloped section, eased at the span's ends.
                    ease = min(1.0, (d - flute_span[0]) / 0.06, (flute_span[1] - d) / 0.06)
                    f = 1.0 - flute_depth * ease * max(0.0, math.cos(a * flutes)) ** 2
                p = Vector(origin) + A * d + (U * math.cos(a) + V * math.sin(a)) * r * f
                ring.append(t.verts.new(G(p.x, p.y, p.z)))
            rings.append(ring)
        n = len(prof)
        s = [0.0]
        for k in range(1, n):
            s.append(s[-1] + math.dist(prof[k], prof[k - 1]))
        for i in range(segs):
            ra = rings[i]
            rb = rings[(i + 1) % segs]
            for k in range(n - 1):
                quad = [ra[k], rb[k], rb[k + 1], ra[k + 1]]
                uniq = []
                for v in quad:
                    if all((v.co - w.co).length > 1e-7 for w in uniq):
                        uniq.append(v)
                if len(uniq) < 3:
                    continue
                try:
                    f = t.faces.new(uniq)
                except ValueError:
                    continue
                rr = max(0.02, (prof[k][0] + prof[k + 1][0]) * 0.5)
                for loop in f.loops:
                    j = quad.index(loop.vert) if loop.vert in quad else 0
                    ii = i if j in (0, 3) else i + 1
                    u = math.tau * ii / segs * rr
                    v = s[k] if j in (0, 1) else s[k + 1]
                    loop[uvl].uv = (u, v)
        bmesh.ops.remove_doubles(t, verts=t.verts, dist=1e-6)
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        _smooth_by_angle(t, smooth)
        self.add(t, part, glow)

    def sweep(self, path, radii, part, segs=12, smooth=50.0, cap=True):
        """A tube along the Godot polyline `path` with a radius per point, framed by parallel
        transport so it never twists, capped at both ends."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        pts = [Vector(p) for p in path]
        tans = []
        for i in range(len(pts)):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            tans.append((b - a).normalized())
        _, U, _ = _frame(tans[0])
        rings = []
        for i, p in enumerate(pts):
            T = tans[i]
            U = (U - T * U.dot(T)).normalized()
            V = T.cross(U).normalized()
            ring = []
            for k in range(segs):
                a = math.tau * k / segs
                q = p + (U * math.cos(a) + V * math.sin(a)) * radii[i]
                ring.append(t.verts.new(G(q.x, q.y, q.z)))
            rings.append(ring)
        dist = [0.0]
        for i in range(1, len(pts)):
            dist.append(dist[-1] + (pts[i] - pts[i - 1]).length)
        for i in range(len(pts) - 1):
            for k in range(segs):
                quad = [rings[i][k], rings[i][(k + 1) % segs], rings[i + 1][(k + 1) % segs], rings[i + 1][k]]
                f = t.faces.new(quad)
                for loop in f.loops:
                    j = quad.index(loop.vert)
                    kk = k if j in (0, 3) else k + 1
                    loop[uvl].uv = (math.tau * kk / segs * radii[i], dist[i] if j < 2 else dist[i + 1])
        if cap:
            for ring in (rings[0], rings[-1]):
                c = t.verts.new(sum((v.co for v in ring), Vector()) / len(ring))
                for k in range(segs):
                    f = t.faces.new([ring[k], ring[(k + 1) % segs], c])
                    for loop in f.loops:
                        loop[uvl].uv = (loop.vert.co.x, loop.vert.co.y)
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        _smooth_by_angle(t, smooth)
        self.add(t, part)

    def loft(self, sections, part, ring=16, exp=2.5, smooth=50.0, cap0=True, cap1=True, glow=None,
             axis=(1, 0, 0)):
        """A body lofted through superellipse sections along `axis` (x by default): each section
        is (d along the axis, centre y, half-width z, half-height up, half-height down). `exp` is
        the superellipse exponent: 2 an ellipse, higher squarer."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        A = Vector(axis).normalized()
        side = Vector((0, 0, 1)) if abs(A.z) < 0.9 else Vector((1, 0, 0))
        rings = []
        for (d, cy, hw, hu, hd) in sections:
            r = []
            for k in range(ring):
                a = math.tau * k / ring
                c, s = math.cos(a), math.sin(a)
                ex = 2.0 / exp
                zz = math.copysign(abs(c) ** ex, c) * hw
                yy = math.copysign(abs(s) ** ex, s) * (hu if s >= 0 else hd)
                p = A * d + side * zz + Vector((0, cy + yy, 0))
                r.append(t.verts.new(G(p.x, p.y, p.z)))
            rings.append(r)
        for i in range(len(rings) - 1):
            for k in range(ring):
                quad = [rings[i][k], rings[i][(k + 1) % ring], rings[i + 1][(k + 1) % ring], rings[i + 1][k]]
                f = t.faces.new(quad)
                for loop in f.loops:
                    p = to_godot(loop.vert.co)
                    loop[uvl].uv = (p.dot(A), p.y + p.z)
        for i, ok in ((0, cap0), (len(rings) - 1, cap1)):
            if not ok:
                continue
            rr = rings[i]
            c = t.verts.new(sum((v.co for v in rr), Vector()) / len(rr))
            for k in range(ring):
                f = t.faces.new([rr[k], rr[(k + 1) % ring], c])
                for loop in f.loops:
                    p = to_godot(loop.vert.co)
                    loop[uvl].uv = (p.z, p.y)
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        _smooth_by_angle(t, smooth)
        self.add(t, part, glow)


# --- Shared hardware ---------------------------------------------------------------------------

def anchor_base(p, plate=0.48, cover_r=0.24, cover_h=0.42, pole_r=0.16, segs=28):
    """Bolted base plate, four anchor bolts with nuts and a flared base cover up to the shaft."""
    p.box((0.0, 0.02, 0.0), (plate, 0.04, plate), GALV, bevel=0.008)
    off = plate * 0.37
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            x, z = sx * off, sz * off
            p.lathe([(0.0, 0.04), (0.016, 0.04), (0.016, 0.11), (0.01, 0.12), (0.0, 0.12)],
                    (x, 0.0, z), (0, 1, 0), DARK, segs=8)
            p.lathe([(0.0, 0.04), (0.03, 0.04), (0.03, 0.07), (0.024, 0.077), (0.0, 0.077)],
                    (x, 0.0, z), (0, 1, 0), DARK, segs=6, smooth=20.0)
    p.lathe([(0.0, 0.04), (cover_r, 0.04), (cover_r, 0.062), (cover_r - 0.018, 0.08),
             (pole_r + 0.035, cover_h * 0.62), (pole_r + 0.018, cover_h - 0.02),
             (pole_r + 0.024, cover_h), (pole_r + 0.008, cover_h + 0.015), (0.0, cover_h + 0.015)],
            (0, 0, 0), (0, 1, 0), GALV, segs=segs)


def handhole(p, y, r, part=GALV):
    """The wiring handhole cover on the pole's back (-x), curved onto the shaft."""
    p.box((-r - 0.008, y, 0.0), (0.03, 0.26, 0.12), part, bevel=0.012, segments=3)
    for dy in (-0.1, 0.1):
        p.lathe([(0.0, 0.0), (0.009, 0.0), (0.009, 0.014), (0.0, 0.016)],
                (-r - 0.022, y + dy, 0.0), (-1, 0, 0), DARK, segs=6, smooth=20.0)


def tag(p, y, r):
    """The pole's numbered ID plate, facing the street (+x)."""
    p.box((r + 0.004, y, 0.0), (0.006, 0.11, 0.08), ALU, bevel=0.002)


def bez(a, b, c, d, n):
    out = []
    for i in range(n + 1):
        u = i / n
        w = 1.0 - u
        out.append(Vector(a) * w * w * w + Vector(b) * 3 * w * w * u + Vector(c) * 3 * w * u * u + Vector(d) * u * u * u)
    return out


# --- The lamps -------------------------------------------------------------------------------

COBRA_H = 8.4


def cobra():
    p = Piece("sl_cobra")
    anchor_base(p, plate=0.5, cover_r=0.25, cover_h=0.44, pole_r=0.165)
    # Tapered round pole, 0.33 m at the foot to 0.17 m at the top, a cap.
    p.lathe([(0.0, 0.44), (0.165, 0.44), (0.142, 3.0), (0.1, COBRA_H - 0.35),
             (0.088, COBRA_H - 0.3), (0.05, COBRA_H - 0.27), (0.0, COBRA_H - 0.26)], (0, 0, 0), (0, 1, 0),
            GALV, segs=20)
    handhole(p, 0.95, 0.158)
    tag(p, 2.4, 0.146)
    # Arm clamp: a band round the pole's head that the arm leaves from.
    p.lathe([(0.0, 7.72), (0.112, 7.72), (0.118, 7.74), (0.118, 8.0), (0.112, 8.02), (0.0, 8.02)],
            (0, 0, 0), (0, 1, 0), GALV, segs=20)
    # The arm: out of the clamp rising, easing to level at the head (a davit). Tapered 6.5 -> 3.8 cm.
    path = bez((0.06, 7.86, 0.0), (0.75, 8.36, 0.0), (1.35, 8.66, 0.0), (2.2, 8.68, 0.0), 16)
    radii = [0.062 - 0.024 * i / (len(path) - 1) for i in range(len(path))]
    p.sweep(path, radii, GALV, segs=12)
    # A brace under the rise, from the pole into the arm.
    end = path[6]
    br = bez((0.09, 7.15, 0.0), (0.3, 7.45, 0.0), (end.x - 0.25, end.y - 0.32, 0.0), (end.x, end.y - 0.02, 0.0), 6)
    p.sweep(br, [0.022] * len(br), GALV, segs=8)
    # The cobra head: a long teardrop body, slipfitter at the back, nose forward along +x.
    x0, cy = 2.12, 8.70
    secs = [(x0 + 0.00, cy, 0.055, 0.050, 0.050),
            (x0 + 0.06, cy + 0.005, 0.085, 0.070, 0.060),
            (x0 + 0.18, cy + 0.012, 0.150, 0.100, 0.060),
            (x0 + 0.34, cy + 0.016, 0.185, 0.115, 0.058),
            (x0 + 0.52, cy + 0.012, 0.180, 0.105, 0.056),
            (x0 + 0.68, cy + 0.004, 0.150, 0.082, 0.050),
            (x0 + 0.78, cy - 0.006, 0.100, 0.055, 0.040),
            (x0 + 0.82, cy - 0.012, 0.040, 0.025, 0.020)]
    p.loft(secs, ALU, ring=20, exp=2.4)
    # The door's seam round the body, a dark gasket line.
    p.loft([(x0 + 0.325, cy + 0.016, 0.189, 0.118, 0.061), (x0 + 0.345, cy + 0.016, 0.189, 0.118, 0.061)],
           DARK, ring=20, exp=2.4, cap0=False, cap1=False)
    # Drop-glass refractor under the body: a shallow dome, lit.
    lx = x0 + 0.42
    lens = [(lx - 0.24, cy - 0.050, 0.120, 0.004, 0.004),
            (lx - 0.18, cy - 0.058, 0.150, 0.006, 0.035),
            (lx - 0.06, cy - 0.060, 0.165, 0.006, 0.070),
            (lx + 0.06, cy - 0.060, 0.162, 0.006, 0.072),
            (lx + 0.18, cy - 0.058, 0.140, 0.006, 0.050),
            (lx + 0.27, cy - 0.050, 0.090, 0.004, 0.012)]
    p.loft(lens, LENS, ring=20, exp=2.2, glow=(cy - 0.14, cy - 0.05))
    # Lens frame.
    p.loft([(lx - 0.25, cy - 0.046, 0.130, 0.008, 0.012), (lx + 0.28, cy - 0.046, 0.100, 0.008, 0.012)],
           DARK, ring=20, exp=3.0)
    # Photocell on its twist-lock on top.
    p.lathe([(0.0, 0.0), (0.034, 0.0), (0.034, 0.022), (0.04, 0.026), (0.04, 0.07), (0.03, 0.082),
             (0.0, 0.086)], (x0 + 0.40, cy + 0.12, 0.0), (0, 1, 0), DARK, segs=12)
    # Slipfitter clamp bolts on the tail.
    for sz in (-1.0, 1.0):
        p.lathe([(0.0, 0.0), (0.012, 0.0), (0.012, 0.018), (0.0, 0.02)], (x0 + 0.1, cy + 0.03, sz * 0.09),
                (0, 0, sz), DARK, segs=6)
    return p


TWIN_H = 4.62


def twin():
    """Downtown's twin-globe ornamental (an original design in the LA idiom)."""
    p = Piece("sl_twin")
    # Octagonal plinth with mouldings.
    p.lathe([(0.0, 0.0), (0.34, 0.0), (0.34, 0.05), (0.31, 0.08), (0.3, 0.42), (0.32, 0.45),
             (0.32, 0.49), (0.27, 0.53), (0.24, 0.62), (0.0, 0.62)], (0, 0, 0), (0, 1, 0), PAINT,
            segs=8, smooth=10.0, phase=22.5)
    # Plinth panels (raised, one a side).
    for k in range(8):
        a = math.tau * (k + 0.5) / 8 + math.radians(22.5)
        c = Vector((math.cos(a), 0.0, math.sin(a)))
        n = Vector((math.cos(a), 0.0, math.sin(a)))
        t = Vector((-math.sin(a), 0.0, math.cos(a)))
        p.box(tuple(c * 0.293 + Vector((0, 0.25, 0))), (0.02, 0.24, 0.13), PAINT, bevel=0.006, segments=1,
              axes=(n, Vector((0, 1, 0)), t))
    # Base torus and the fluted shaft with entasis, a necking and a capital.
    sh = [(0.0, 0.62), (0.2, 0.62), (0.21, 0.66), (0.2, 0.7), (0.165, 0.74), (0.16, 0.8),
          (0.15, 2.4), (0.128, 3.9), (0.122, 3.98), (0.138, 4.0), (0.138, 4.05), (0.125, 4.08)]
    p.lathe(sh, (0, 0, 0), (0, 1, 0), PAINT, segs=32, flutes=16, flute_depth=0.08,
            flute_span=(0.8, 3.92), smooth=60.0)
    # Leaf collar (an acanthus band as a ring of lobes) and the capital.
    for k in range(8):
        a = math.tau * k / 8
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        leaf = [tuple(d * 0.125 + Vector((0, 4.08, 0))), tuple(d * 0.17 + Vector((0, 4.18, 0))),
                tuple(d * 0.2 + Vector((0, 4.27, 0))), tuple(d * 0.19 + Vector((0, 4.32, 0)))]
        p.sweep(leaf, [0.032, 0.04, 0.032, 0.016], PAINT, segs=7)
    p.lathe([(0.0, 4.08), (0.13, 4.08), (0.14, 4.32), (0.2, 4.36), (0.2, 4.42), (0.16, 4.44),
             (0.1, 4.46), (0.0, 4.46)], (0, 0, 0), (0, 1, 0), PAINT, segs=24)
    # The cross-arm: two scrolled arms out to the globe holders at +-0.62.
    for sx in (-1.0, 1.0):
        arm = bez((0.0, 4.4, 0.0), (sx * 0.25, 4.38, 0.0), (sx * 0.5, 4.5, 0.0), (sx * 0.62, 4.66, 0.0), 10)
        p.sweep(arm, [0.04 - 0.012 * i / 10 for i in range(11)], PAINT, segs=10)
        # The scroll under each arm: a spiral curling back toward the post.
        sc = []
        for i in range(17):
            u = i / 16
            ang = math.pi * 1.6 * u
            rad = 0.15 * (1.0 - 0.7 * u)
            sc.append((sx * (0.42 - rad * math.sin(ang)), 4.5 - rad * (1.0 - math.cos(ang)) - 0.04 * u, 0.0))
        p.sweep([(sx * 0.12, 4.22, 0.0), (sx * 0.28, 4.32, 0.0)] + sc[1:], [0.018] * 18, PAINT, segs=8)
        gx = sx * 0.62
        # Globe holder (a cup on a short neck), the globe and its cap.
        p.lathe([(0.0, 4.6), (0.03, 4.6), (0.034, 4.68), (0.07, 4.72), (0.095, 4.74), (0.1, 4.76),
                 (0.09, 4.78), (0.0, 4.78)], (gx, 0, 0), (0, 1, 0), PAINT, segs=16)
        prof = [(0.0, 4.77)]
        for i in range(1, 10):
            a = math.pi * i / 10
            prof.append((0.215 * math.sin(a) * (1.0 - 0.18 * (1 - math.sin(a))), 4.77 + 0.215 * (1 - math.cos(a)) * 0.98))
        prof.append((0.075, 5.18))
        prof.append((0.0, 5.18))
        p.lathe([(r, d) for r, d in prof], (gx, 0, 0), (0, 1, 0), DIFFUSER, segs=18, smooth=70.0,
                glow=(4.77, 5.18))
        p.lathe([(0.0, 5.17), (0.085, 5.17), (0.085, 5.2), (0.05, 5.24), (0.02, 5.3), (0.012, 5.36),
                 (0.0, 5.37)], (gx, 0, 0), (0, 1, 0), PAINT, segs=12)
    # Finial over the post.
    p.lathe([(0.0, 4.46), (0.04, 4.46), (0.03, 4.56), (0.055, 4.62), (0.03, 4.7), (0.008, 4.8),
             (0.0, 4.82)], (0, 0, 0), (0, 1, 0), PAINT, segs=12)
    return p


def lantern():
    """The midtown single-lantern ornamental: fluted post, hexagonal lantern."""
    p = Piece("sl_lantern")
    p.lathe([(0.0, 0.0), (0.24, 0.0), (0.24, 0.05), (0.22, 0.08), (0.2, 0.3), (0.215, 0.33),
             (0.215, 0.37), (0.17, 0.42), (0.0, 0.42)], (0, 0, 0), (0, 1, 0), PAINT, segs=24)
    p.lathe([(0.0, 0.42), (0.13, 0.42), (0.14, 0.46), (0.12, 0.5), (0.11, 0.56), (0.1, 2.0),
             (0.082, 3.5), (0.08, 3.55), (0.095, 3.58), (0.095, 3.63), (0.0, 3.63)], (0, 0, 0),
            (0, 1, 0), PAINT, segs=28, flutes=14, flute_depth=0.09, flute_span=(0.56, 3.5), smooth=60.0)
    # Ring collar and the lantern's seat.
    p.lathe([(0.0, 3.63), (0.13, 3.63), (0.13, 3.67), (0.08, 3.72), (0.07, 3.8), (0.15, 3.86),
             (0.16, 3.9), (0.0, 3.9)], (0, 0, 0), (0, 1, 0), PAINT, segs=24)
    # Six panes, wider at the top, between six ribs.
    y0, y1 = 3.9, 4.72
    r0, r1 = 0.15, 0.22
    p.lathe([(0.0, y0), (r0 * 0.98, y0), (r1 * 0.98, y1), (0.0, y1)], (0, 0, 0), (0, 1, 0), DIFFUSER,
            segs=6, smooth=5.0, glow=(y0, y1))
    for k in range(6):
        a = math.tau * k / 6
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        p.sweep([tuple(d * (r0 + 0.004) + Vector((0, y0, 0))), tuple(d * (r1 + 0.004) + Vector((0, y1, 0)))],
                [0.016, 0.016], PAINT, segs=6, smooth=30.0)
    # Bottom ring, top ring, hipped roof and finial.
    p.lathe([(0.0, y0 - 0.02), (r0 + 0.03, y0 - 0.02), (r0 + 0.03, y0 + 0.03), (0.0, y0 + 0.03)],
            (0, 0, 0), (0, 1, 0), PAINT, segs=6, smooth=10.0)
    p.lathe([(0.0, y1 - 0.03), (r1 + 0.03, y1 - 0.03), (r1 + 0.045, y1 + 0.03), (0.0, y1 + 0.03)],
            (0, 0, 0), (0, 1, 0), PAINT, segs=6, smooth=10.0)
    p.lathe([(0.0, y1 + 0.03), (r1 + 0.07, y1 + 0.03), (r1 + 0.07, y1 + 0.05), (0.12, y1 + 0.17),
             (0.05, y1 + 0.27), (0.0, y1 + 0.29)], (0, 0, 0), (0, 1, 0), PAINT, segs=6, smooth=10.0)
    p.lathe([(0.0, y1 + 0.27), (0.03, y1 + 0.28), (0.04, y1 + 0.33), (0.02, y1 + 0.38),
             (0.008, y1 + 0.46), (0.0, y1 + 0.47)], (0, 0, 0), (0, 1, 0), PAINT, segs=10)
    # The lamp inside (seen through the glass by day as a dark socket).
    p.lathe([(0.0, y0 + 0.03), (0.04, y0 + 0.03), (0.04, y0 + 0.2), (0.0, y0 + 0.2)], (0, 0, 0),
            (0, 1, 0), DARK, segs=8)
    return p


POST_H = 4.3


def post_top():
    """The residential post-top: a spun-concrete pole and a cylindrical prismatic luminaire."""
    p = Piece("sl_post")
    # Spun concrete: straight taper from the ground (it is set in a footing), a chamfered top.
    p.lathe([(0.0, 0.0), (0.13, 0.0), (0.13, 0.03), (0.122, 0.06), (0.085, POST_H - 0.04),
             (0.075, POST_H), (0.0, POST_H)], (0, 0, 0), (0, 1, 0), CONCRETE, segs=18)
    # A ring of mortar round the foot where it meets the pavement.
    p.lathe([(0.0, 0.0), (0.2, 0.0), (0.17, 0.025), (0.13, 0.035), (0.0, 0.035)], (0, 0, 0), (0, 1, 0),
            CONCRETE, segs=18)
    handhole(p, 0.7, 0.122, CONCRETE)
    tag(p, 2.1, 0.105)
    # The luminaire: a cast fitter, the prismatic cylinder, a dark ventilated cap.
    y = POST_H
    p.lathe([(0.0, y), (0.085, y), (0.09, y + 0.05), (0.075, y + 0.1), (0.13, y + 0.13),
             (0.15, y + 0.16), (0.0, y + 0.16)], (0, 0, 0), (0, 1, 0), DARK, segs=20)
    p.lathe([(0.0, y + 0.16), (0.155, y + 0.16), (0.16, y + 0.2), (0.17, y + 0.48), (0.175, y + 0.53),
             (0.0, y + 0.53)], (0, 0, 0), (0, 1, 0), DIFFUSER, segs=24, smooth=60.0, glow=(y + 0.16, y + 0.53))
    for k in range(4):
        a = math.tau * k / 4 + math.pi / 4
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        p.sweep([tuple(d * 0.162 + Vector((0, y + 0.17, 0))), tuple(d * 0.178 + Vector((0, y + 0.52, 0)))],
                [0.01, 0.01], DARK, segs=6, smooth=30.0)
    p.lathe([(0.0, y + 0.52), (0.2, y + 0.52), (0.205, y + 0.55), (0.19, y + 0.6), (0.12, y + 0.68),
             (0.05, y + 0.72), (0.03, y + 0.76), (0.0, y + 0.77)], (0, 0, 0), (0, 1, 0), DARK, segs=24)
    return p


MAST_H = 9.4


def mast():
    """The mast-arm LED: a tall tapered galvanised pole and a straight arm with a slim head."""
    p = Piece("sl_mast")
    anchor_base(p, plate=0.56, cover_r=0.28, cover_h=0.5, pole_r=0.185)
    p.lathe([(0.0, 0.5), (0.185, 0.5), (0.155, 3.5), (0.11, MAST_H - 0.05), (0.095, MAST_H),
             (0.06, MAST_H + 0.035), (0.0, MAST_H + 0.045)], (0, 0, 0), (0, 1, 0), GALV, segs=20)
    handhole(p, 1.0, 0.178)
    tag(p, 2.5, 0.165)
    # Arm flange on the pole and the arm: a straight tapered tube rising 2 degrees.
    p.box((0.118, 9.05, 0.0), (0.03, 0.34, 0.3), GALV, bevel=0.008)
    for sy in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            p.lathe([(0.0, 0.0), (0.016, 0.0), (0.016, 0.03), (0.0, 0.032)],
                    (0.13, 9.05 + sy * 0.12, sz * 0.1), (1, 0, 0), DARK, segs=6)
    arm = [(0.13, 9.05, 0.0), (1.2, 9.09, 0.0), (2.4, 9.13, 0.0), (3.0, 9.15, 0.0)]
    p.sweep(arm, [0.07, 0.062, 0.052, 0.048], GALV, segs=14)
    # The head: a slim rounded slab, 0.7 x 0.34 x 0.1, its fins on top and the LED panel under.
    hx, hy = 3.33, 9.16
    secs = [(hx - 0.36, hy, 0.06, 0.04, 0.04), (hx - 0.32, hy + 0.005, 0.15, 0.055, 0.045),
            (hx - 0.22, hy + 0.008, 0.17, 0.06, 0.045), (hx + 0.24, hy + 0.006, 0.17, 0.05, 0.045),
            (hx + 0.33, hy + 0.002, 0.155, 0.04, 0.042), (hx + 0.37, hy, 0.12, 0.025, 0.035),
            (hx + 0.385, hy - 0.005, 0.06, 0.012, 0.02)]
    p.loft(secs, ALU, ring=20, exp=4.0)
    for k in range(9):
        z = -0.12 + 0.03 * k
        p.box((hx + 0.02, hy + 0.08, z), (0.48, 0.03, 0.006), ALU, bevel=0.002, segments=1)
    # LED panel: a flat lens recessed in the underside, the shader dots it.
    p.box((hx + 0.03, hy - 0.043, 0.0), (0.5, 0.008, 0.26), LED, bevel=0.003, segments=1)
    p.box((hx + 0.03, hy - 0.04, 0.0), (0.54, 0.008, 0.29), DARK, bevel=0.003, segments=1)
    # Photocell / node on top at the back.
    p.lathe([(0.0, 0.0), (0.036, 0.0), (0.04, 0.03), (0.04, 0.06), (0.02, 0.075), (0.0, 0.078)],
            (hx - 0.25, hy + 0.055, 0.0), (0, 1, 0), DARK, segs=12)
    return p


PIECES = [cobra, twin, lantern, post_top, mast]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    mat = bpy.data.materials.new("street_lamp")
    mat.use_nodes = True
    report = []
    for make in PIECES:
        piece = make()
        mesh = bpy.data.meshes.new(piece.name)
        piece.bm.normal_update()
        piece.bm.to_mesh(mesh)
        piece.bm.free()
        mesh.materials.append(mat)
        obj = bpy.data.objects.new(piece.name, mesh)
        scene.collection.objects.link(obj)
        wn = obj.modifiers.new("weighted", 'WEIGHTED_NORMAL')
        wn.mode = 'FACE_AREA'
        wn.weight = 50
        wn.keep_sharp = True
        tris = sum(len(poly.vertices) - 2 for poly in mesh.polygons)
        xs = [v.co.x for v in mesh.vertices]
        ys = [v.co.z for v in mesh.vertices]
        zs = [-v.co.y for v in mesh.vertices]
        report.append("%-11s %5d tris  x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % (
            piece.name, tris, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
        mesh.uv_layers.active = mesh.uv_layers["UVMap"]
        mesh.uv_layers["UVMap"].active_render = True
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(OUT), export_format='GLB', export_yup=True,
                              export_apply=True, export_texcoords=True, export_normals=True,
                              export_tangents=False, export_materials='EXPORT',
                              export_vertex_color='NONE', export_animations=False,
                              export_cameras=False, export_lights=False)
    print("street lamps ->", os.path.abspath(OUT))
    for line in report:
        print("  " + line)


main()
