#!/usr/bin/env python3
"""What a car is made of underneath and inside its arches, for every lofted road body: a separate
`assets/models/road_<name>_under.glb` the game hangs under the body (CarUnderside), so the body
.glb, its LODs and its far twin are untouched.

    pip: python3.11 -m venv v && v/bin/pip install bpy==4.2.0     (or Blender 4.2 -b -P)
    v/bin/python tools/make_car_undersides.py -- sedan crossover ...   (no names: every body)

then `godot --headless --path . --import` and commit the .glb and its .import.

WHY. At arm's length - and every time the player flips or flies a car - the body was a painted
shell over a black void: the arches were bare black pockets (the boolean cutter's walls), there
was no exhaust, and under the sills was the decimated floor of the loft, one flat dark plane. A
real car shows, through the gap over the tyre, a ribbed plastic arch liner and the strut's coil
spring; under the rear bumper the exhaust tips; and from below the subframes, control arms, the
exhaust run with its resonator, silencer and heat shields, the fuel tank and the rear axle.

HOW. Each body is rebuilt WITHOUT its details (`rc.build(spec, False)`: the loft and the arch
pockets, two seconds) only to raycast against it: the floor height under any point
(`floor_at()`), the tail's face (`tail_at()`), the skin round each arch. Everything is laid in the
body's own coordinates (X lateral, Y along with the nose at +Y, Z up, ground at 0; the same
export, so the parts land on the body in the game with no transform of their own). Parts are
plain code primitives - tubes swept along polylines, boxes, a helix, the liner as a shell swept
round the pocket - in ONE surface: its vertex colour carries what each face is (`K_*` in r as
kind / 16, a variant in g) and its UV metres along / across, read by shaders/car_underside.gdshader.
Every part stays inside the body's bounding box and above the far wheels' bottom, so the body's
centring (Vehicle._add_body_model measures the box) is unchanged. ~4-6k triangles a car.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_road_cars as rc  # noqa: E402
import make_more_cars  # noqa: E402,F401  (registers hatchback, suv, minivan, beater, taxi)
import make_cars_3 as c3  # noqa: E402
import make_lowriders  # noqa: E402,F401

# Kinds (vertex colour r = kind / 16; shaders/car_underside.gdshader K_*).
K_LINER, K_STEEL, K_EXHAUST, K_TIP, K_RUBBER, K_SPRING, K_ALU, K_TANK, K_SOOT, K_SHIELD = range(10)

BODIES = ["sedan", "crossover", "pickup", "van", "hatchback", "suv", "minivan", "taxi", "beater",
          "ev_hatch", "lux_sedan", "compact_suv", "work_truck", "coupe", "lowrider_hardtop",
          "lowrider_coupe"]

# Exhaust per body: tips as (x, radius) pairs ([] = none: the EV), and the chassis kind:
# "unibody" (front struts, twist beam / multilink rear) or "frame" (ladder frame, live axle on
# leaf springs: the trucks, the van, the lowriders).
EXHAUST = {
    "sedan": [(0.42, 0.036)], "crossover": [(0.44, 0.038)], "pickup": [(0.55, 0.042)],
    "van": [(0.50, 0.040)], "hatchback": [(0.36, 0.032)], "suv": [(0.52, 0.042), (-0.52, 0.042)],
    "minivan": [(0.42, 0.036)], "taxi": [(0.42, 0.036)], "beater": [(0.40, 0.030)],
    "ev_hatch": [], "lux_sedan": [(0.50, 0.040), (-0.50, 0.040)],
    "compact_suv": [(0.40, 0.034)], "work_truck": [(0.55, 0.042)],
    "coupe": [(0.46, 0.036), (0.37, 0.036), (-0.37, 0.036), (-0.46, 0.036)],
    "lowrider_hardtop": [(0.48, 0.034), (-0.48, 0.034)],
    "lowrider_coupe": [(0.46, 0.034), (-0.46, 0.034)],
}
FRAME_BODIES = {"pickup", "work_truck", "van", "lowrider_hardtop", "lowrider_coupe"}
# A share of cars wear red / yellow springs; the rest painted black. Per body, fixed.
SPRING_VARIANT = {"coupe": 0.5, "lux_sedan": 0.0, "lowrider_hardtop": 1.0, "lowrider_coupe": 1.0}

CLEAR = 0.006          # a part's top stands this far under the floor it hangs from


class Geo:
    """Faces with a kind, a variant and UVs in metres; one bmesh at the end."""

    def __init__(self):
        self.faces = []    # (verts [Vector], uvs [(u, v)], kind, variant, smooth, ref)

    def face(self, vs, uvs, kind, var=0.0, smooth=False, want=None):
        """`want`: a direction the face should look toward (it is turned round if not)."""
        if want is not None and len(vs) >= 3:
            n = (vs[1] - vs[0]).cross(vs[2] - vs[0])
            if n.length > 1e-12 and n.dot(want) < 0.0:
                vs = list(reversed(vs))
                uvs = list(reversed(uvs))
        self.faces.append((vs, uvs, kind, var, smooth))

    def tube(self, path, r, kind, var=0.0, sides=8, caps=True, r_end=None):
        """A round tube along a polyline (parallel-transport frames), UV u = metres along."""
        path = [Vector(p) for p in path]
        if len(path) < 2:
            return
        fr = rc.frames(path)
        rings = []
        along = 0.0
        for i, p in enumerate(path):
            if i > 0:
                along += (p - path[i - 1]).length
            t, up, side = fr[i]
            rr = r if r_end is None else r + (r_end - r) * (i / (len(path) - 1))
            ring = []
            for k in range(sides):
                a = 2.0 * math.pi * k / sides
                ring.append(p + (up * math.cos(a) + side * math.sin(a)) * rr)
            rings.append((ring, along))
        circ = 2.0 * math.pi * r
        for i in range(len(rings) - 1):
            (ra, ua), (rb, ub) = rings[i], rings[i + 1]
            for k in range(sides):
                k2 = (k + 1) % sides
                c = (path[i] + path[i + 1]) * 0.5
                quad = [ra[k], ra[k2], rb[k2], rb[k]]
                mid = (ra[k] + ra[k2] + rb[k2] + rb[k]) * 0.25
                self.face(quad, [(ua, circ * k / sides), (ua, circ * (k + 1) / sides),
                                 (ub, circ * (k + 1) / sides), (ub, circ * k / sides)],
                          kind, var, True, mid - c)
        if caps:
            for (ring, u), p, s in ((rings[0], path[0], -1.0), (rings[-1], path[-1], 1.0)):
                t = (path[1] - path[0]) if s < 0 else (path[-1] - path[-2])
                self.face(list(ring), [(u, 0.0)] * len(ring), kind, var, False, t * s)

    def box(self, c, size, kind, var=0.0, axes=None):
        """An oriented box: `axes` (ax, ay, az) unit vectors, default the world's."""
        c = Vector(c)
        ax, ay, az = axes or (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
        hx, hy, hz = (s * 0.5 for s in size)
        for n, a, b, ha, hb, hn in ((ax, ay, az, hy, hz, hx), (-ax, ay, az, hy, hz, hx),
                                   (ay, ax, az, hx, hz, hy), (-ay, ax, az, hx, hz, hy),
                                   (az, ax, ay, hx, hy, hz), (-az, ax, ay, hx, hy, hz)):
            o = c + n * hn
            vs = [o - a * ha - b * hb, o + a * ha - b * hb, o + a * ha + b * hb, o - a * ha + b * hb]
            self.face(vs, [(0, 0), (2 * ha, 0), (2 * ha, 2 * hb), (0, 2 * hb)], kind, var, False, n)

    def beam(self, a, b, w, h, kind, var=0.0):
        """A box section from a to b, `w` across and `h` tall (its up kept toward +Z)."""
        a, b = Vector(a), Vector(b)
        ay = (b - a)
        L = ay.length
        ay.normalize()
        up = Vector((0, 0, 1))
        if abs(ay.dot(up)) > 0.95:
            up = Vector((1, 0, 0))
        ax = ay.cross(up).normalized()
        az = ax.cross(ay).normalized()
        self.box((a + b) * 0.5, (w, L, h), kind, var, (ax, ay, az))

    def plate(self, pts, kind, var=0.0, want=Vector((0, 0, -1))):
        """A flat polygon (convex, ordered) facing `want`, UV = its x, y in metres."""
        pts = [Vector(p) for p in pts]
        self.face(pts, [(p.x, p.y) for p in pts], kind, var, False, want)

    def build(self, name):
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new("UVMap")
        col = bm.loops.layers.float_color.new("Col")
        for vs, uvs, kind, var, smooth in self.faces:
            verts = [bm.verts.new(v) for v in vs]
            try:
                f = bm.faces.new(verts)
            except ValueError:
                continue
            f.smooth = smooth
            for lp, uv in zip(f.loops, uvs):
                lp[uvl].uv = uv
                lp[col] = (kind / 16.0 + 1.0 / 32.0, var, 0.0, 1.0)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.color_attributes.active_color = me.color_attributes["Col"]
        mat = bpy.data.materials.new("underside")
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


class Fit:
    """Questions asked of the rebuilt body."""

    def __init__(self, surf, spec):
        self.surf = surf
        self.s = spec

    def floor_at(self, x, y, default=0.15):
        """The underside of the body over (x, y): a ray up from under the road."""
        loc, _n = self.surf.ray((x, y, -0.5), (0.0, 0.0, 1.0), 3.0)
        return loc.z if loc is not None else default

    def tail_at(self, x, z):
        loc, _n = self.surf.ray((x, -6.0, z), (0.0, 1.0, 0.0), 8.0)
        return loc.y if loc is not None else None

    def tail_face(self, x):
        """Where the tail's lowest face is, at x: the bumper's bottom edge found by walking the
        floor back until it ends, then a ray from behind just over that edge."""
        y = self.s["rear_axle"] - self.s["arch_r_rear"]
        last = None
        while y > -6.0:
            loc, _n = self.surf.ray((x, y, -0.5), (0.0, 0.0, 1.0), 3.0)
            if loc is None:
                break
            last = loc.z
            y -= 0.02
        if last is None:
            return None
        return self.tail_at(x, last + 0.025)

    def skin_x(self, y, z, side):
        loc, _n = self.surf.side_hit(y, z, side)
        return abs(loc.x) if loc is not None else None


def liner(g, fit, f_c, R, side):
    """The arch liner: a ribbed plastic shell just inside the arch pocket (radius R - 1.4 cm), from
    the pocket's inner wall out to 2 cm short of the body's skin, swept from the bottom of the
    pocket's front wall over the top and down the rear one; and its back, a half disc on the
    inner wall. Ribs and the felt are the shader's (UV: metres round the arc, metres across)."""
    s = fit.s
    az = s["axle_z"]
    x_in = s["arch_in"] + 0.006
    r = R - 0.014
    low = max(0.06, az - 0.20)
    # The profile: straight up the front wall, the half circle, straight down the rear one.
    pts = []
    for z in (low, low + (az - low) * 0.5):
        pts.append((f_c + r, z))
    n = 20
    for k in range(n + 1):
        a = math.pi * k / n
        pts.append((f_c + r * math.cos(a), az + r * math.sin(a)))
    for z in (low + (az - low) * 0.5, low):
        pts.append((f_c - r, z))
    arc = 0.0
    prev = None
    rows = []
    for (y, z) in pts:
        if prev is not None:
            arc += math.hypot(y - prev[0], z - prev[1])
        prev = (y, z)
        sk = fit.skin_x(y + (0.02 if y > f_c else -0.02), z, side)
        x_out = (sk - 0.022) if sk is not None else s["wheel_x"] + s["wheel_w"] * 0.5
        x_out = max(x_out, x_in + 0.05)
        rows.append((y, z, x_out, arc))
    for i in range(len(rows) - 1):
        ya, za, xa, ua = rows[i]
        yb, zb, xb, ub = rows[i + 1]
        mid = Vector((side * (x_in + xa) * 0.5, (ya + yb) * 0.5, (za + zb) * 0.5))
        centre = Vector((mid.x, f_c, az))
        vs = [Vector((side * x_in, ya, za)), Vector((side * xa, ya, za)),
              Vector((side * xb, yb, zb)), Vector((side * x_in, yb, zb))]
        g.face(vs, [(ua, 0.0), (ua, xa - x_in), (ub, xb - x_in), (ub, 0.0)], K_LINER, 0.0, True,
               centre - mid)
    # The back: a fan on the inner wall, looking out at the wheel.
    c = Vector((side * x_in, f_c, az))
    for i in range(len(rows) - 1):
        ya, za, _xa, _ua = rows[i]
        yb, zb, _xb, _ub = rows[i + 1]
        if za < az - 0.01 and zb < az - 0.01:
            continue
        g.face([c, Vector((side * x_in, ya, max(za, az))), Vector((side * x_in, yb, max(zb, az)))],
               [(f_c, az), (ya, za), (yb, zb)], K_LINER, 0.5, False, Vector((side, 0, 0)))
    # Push-in clips along the liner's outer edge, three over the top.
    for a in (0.45, 1.57, 2.69):
        y, z = f_c + r * math.cos(a), az + r * math.sin(a)
        sk = fit.skin_x(y, z, side)
        if sk is None:
            continue
        x = sk - 0.045
        p = Vector((side * x, y, z))
        inward = Vector((0, f_c - y, az - z)).normalized()
        g.tube([p - inward * 0.004, p + inward * 0.006], 0.009, K_RUBBER, 0.0, 6)


def helix(g, base, top, r_coil, r_wire, turns, kind, var):
    steps = int(turns * 12)
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a = 2.0 * math.pi * turns * t
        p = base.lerp(top, t)
        pts.append(p + Vector((math.cos(a) * r_coil, math.sin(a) * r_coil, 0.0)))
    g.tube(pts, r_wire, kind, var, 5, caps=True)


def strut(g, fit, f_c, side, front, var):
    """Inside the arch, behind the tyre: the damper and (front) its coil spring and top mount."""
    s = fit.s
    az = s["axle_z"]
    R = s["arch_r"] if front else s["arch_r_rear"]
    x = side * (s["arch_in"] + 0.058)
    y = f_c + (-0.03 if front else 0.10)
    z0 = az - 0.04
    z1 = az + R - 0.05
    g.tube([(x, y, z0), (x, y, z0 + (z1 - z0) * 0.55)], 0.026, K_STEEL, 0.3, 8)
    g.tube([(x, y, z0 + (z1 - z0) * 0.5), (x, y, z1)], 0.012, K_ALU, 0.0, 6)
    if front:
        helix(g, Vector((x, y, z0 + (z1 - z0) * 0.30)), Vector((x, y, z1 - 0.04)), 0.058, 0.0075,
              4.0, K_SPRING, var)
        g.tube([(x, y, z0 + (z1 - z0) * 0.28), (x, y, z0 + (z1 - z0) * 0.32)], 0.072, K_STEEL,
               0.3, 10)
        g.tube([(x, y, z1 - 0.045), (x, y, z1 + 0.01)], 0.078, K_RUBBER, 0.0, 10)
        # The knuckle's bottom and the bump stop / boot.
        g.tube([(x, y, z0 + (z1 - z0) * 0.55), (x, y, z0 + (z1 - z0) * 0.7)], 0.02, K_RUBBER,
               0.0, 6, r_end=0.017)


def tip(g, fit, x, r, y_face):
    """One exhaust tip: a polished barrel with a rolled lip, its sooty bore, poking 2.5 cm out from
    under the tail; a tailpipe and hanger back to the silencer."""
    y_end = y_face - 0.022
    z = fit.floor_at(x, y_face + 0.05) - r - 0.010
    z = max(z, fit.s["axle_z"] - fit.s["wheel_r"] + r + 0.09)
    L = 0.20
    print("   tip x %.3f r %.3f: face y %.3f, end y %.3f, z %.3f (floor over it %.3f)"
          % (x, r, y_face, y_end, z, fit.floor_at(x, y_face + 0.05)))
    a = Vector((x, y_end + L, z))
    b = Vector((x, y_end, z))
    g.tube([a, b], r, K_TIP, 0.0, 14, caps=False)
    g.tube([b + Vector((0, 0.01, 0)), b + Vector((0, 0.003, 0))], r * 1.06, K_TIP, 0.0, 14, caps=False)
    # The bore: a darker inner tube just inside, closed at the far end.
    g.tube([b + Vector((0, 0.002, 0)), a + Vector((0, -0.02, 0))], r * 0.86, K_SOOT, 0.0, 12, caps=True)
    # The end face ring between the lip and the bore.
    ring_o, ring_i = [], []
    for k in range(14):
        ang = 2.0 * math.pi * k / 14
        ring_o.append(b + Vector((math.cos(ang) * r * 1.06, 0.003, math.sin(ang) * r * 1.06)))
        ring_i.append(b + Vector((math.cos(ang) * r * 0.86, 0.003, math.sin(ang) * r * 0.86)))
    for k in range(14):
        k2 = (k + 1) % 14
        g.face([ring_o[k], ring_o[k2], ring_i[k2], ring_i[k]], [(0, 0)] * 4, K_TIP, 0.0, False,
               Vector((0, -1, 0)))
    return a


def frame_rails(g, fit, x, y0, y1, var=0.0):
    """A ladder-frame rail: a C-channel box under the floor, kicked up over the rear axle."""
    s = fit.s
    ra = s["rear_axle"]
    pts = []
    n = 12
    for i in range(n + 1):
        y = y1 + (y0 - y1) * i / n
        zf = fit.floor_at(x, y) - CLEAR
        pts.append(Vector((x, y, zf - 0.05)))
    for i in range(len(pts) - 1):
        g.beam(pts[i], pts[i + 1], 0.07, 0.10, K_STEEL, var)


def floor_pan(g, fit, y_min, y_max, half_w):
    """The floor seen from below is the loft's own floor, in the PAINT slot: a car-coloured
    underside. A sheet of black underseal 4 mm under it on a ~9 x 10 cm grid, wherever the ray up
    finds a floor that faces the road; cells reaching up into an arch pocket or off the floor's
    edge are left out."""
    s = fit.s
    nx, ny = 20, 48
    y0, y1 = y_min + 0.02, y_max - 0.02
    x0 = half_w - 0.01
    med = fit.floor_at(0.0, (s["front_axle"] + s["rear_axle"]) * 0.5)
    pts = {}
    for j in range(ny + 1):
        y = y1 + (y0 - y1) * j / ny
        for i in range(nx + 1):
            x = -x0 + 2.0 * x0 * i / nx
            loc, nor = fit.surf.ray((x, y, -0.5), (0.0, 0.0, 1.0), 3.0)
            if loc is None or nor.z > -0.55 or loc.z > med + 0.16:
                continue
            pts[(i, j)] = Vector((x, y, loc.z - 0.004))
    for j in range(ny):
        for i in range(nx):
            c = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            if not all(k in pts for k in c):
                continue
            vs = [pts[k] for k in c]
            zs = [v.z for v in vs]
            if max(zs) - min(zs) > 0.06:
                continue
            g.face(vs, [(v.x, v.y) for v in vs], K_STEEL, 0.0, True, Vector((0, 0, -1)))


def build_under(spec):
    name = spec["name"]
    ob = rc.build(spec, False)
    if "post_scale" in spec:
        c3.apply_post_scale(ob, spec)
    sec = rc.Section(spec)
    surf = rc.Surface(ob, sec)
    fit = Fit(surf, spec)
    s = spec
    g = Geo()
    fa, ra = s["front_axle"], s["rear_axle"]
    az, wr = s["axle_z"], s["wheel_r"]
    wx = s["wheel_x"]
    x_in = s["arch_in"]
    ground_min = az - wr + 0.10       # nothing hangs lower than 10 cm off the road
    frame = name in FRAME_BODIES
    var = SPRING_VARIANT.get(name, 0.0)
    xs = [v.co.x for v in ob.data.vertices]
    ys = [v.co.y for v in ob.data.vertices]
    y_min, y_max = min(ys), max(ys)
    half_w = max(xs)

    def hang(x, y, depth):
        """z of a part's bottom hanging `depth` under the floor at (x, y), never too low."""
        return max(fit.floor_at(x, y) - CLEAR - depth, ground_min)

    floor_pan(g, fit, y_min, y_max, half_w)
    # Arch liners and struts.
    for f_c, R, front in ((fa, s["arch_r"], True), (ra, s["arch_r_rear"], False)):
        for side in (1.0, -1.0):
            liner(g, fit, f_c, R, side)
            strut(g, fit, f_c, side, front, var)
    # Front: a subframe (two rails and two cross members), lower control arms out to the hubs,
    # the steering rack and its tie rods, the sump and the gearbox, and a splash shield.
    sf_x = min(0.40, x_in - 0.10)
    sf_y0, sf_y1 = fa - 0.42, fa + 0.30
    for side in (1.0, -1.0):
        a = Vector((side * sf_x, sf_y1, hang(side * sf_x, sf_y1, 0.06) + 0.03))
        b = Vector((side * sf_x, sf_y0, hang(side * sf_x, sf_y0, 0.06) + 0.03))
        g.beam(a, b, 0.07, 0.06, K_STEEL)
        hub = Vector((side * (wx - 0.13), fa, az - 0.10))
        g.tube([Vector((side * sf_x, fa + 0.16, a.z)), hub], 0.017, K_STEEL, 0.6, 6)
        g.tube([Vector((side * sf_x, fa - 0.22, b.z)), hub], 0.017, K_STEEL, 0.6, 6)
        g.tube([hub + Vector((0, 0, -0.012)), hub + Vector((0, 0, 0.03))], 0.028, K_RUBBER, 0.0, 8)
        # Tie rod from the rack to the knuckle's steering arm, with its boot.
        rack_end = Vector((side * 0.30, fa - 0.12, az - 0.02))
        g.tube([rack_end, Vector((side * (wx - 0.15), fa - 0.13, az - 0.02))], 0.011, K_STEEL, 0.6, 6)
        g.tube([rack_end, rack_end + Vector((side * 0.09, 0, 0))], 0.022, K_RUBBER, 0.0, 8,
               r_end=0.015)
    for y in (sf_y0, sf_y1):
        z = hang(0.0, y, 0.05) + 0.025
        g.beam((-sf_x, y, z), (sf_x, y, z), 0.06, 0.05, K_STEEL)
    g.tube([(-0.30, fa - 0.12, az - 0.02), (0.30, fa - 0.12, az - 0.02)], 0.024, K_ALU, 0.0, 8)
    if name != "ev_hatch":
        zs = hang(0.0, fa + 0.15, 0.09)
        g.box((0.05, fa + 0.12, zs + 0.06), (0.36, 0.30, 0.12), K_ALU, 0.5)
        g.box((0.05, fa + 0.12, zs + 0.004), (0.06, 0.06, 0.012), K_STEEL, 0.6)   # drain plug boss
        zg = hang(0.0, fa - 0.45, 0.10)
        g.box((0.0, fa - 0.45, zg + 0.07), (0.30, 0.40, 0.14), K_ALU, 0.3)
    else:
        # The EV: a battery tray filling the floor between the axles, ribbed and bolted.
        y0, y1 = ra + s["arch_r_rear"] + 0.12, fa - s["arch_r"] - 0.12
        zb = max(fit.floor_at(0.0, (y0 + y1) * 0.5) - CLEAR - 0.035, ground_min)
        g.box((0.0, (y0 + y1) * 0.5, zb + 0.018), (2.0 * (x_in - 0.02), y1 - y0, 0.036), K_TANK, 0.6)
        for k in range(7):
            y = y0 + 0.08 + (y1 - y0 - 0.16) * k / 6
            g.beam((-(x_in - 0.06), y, zb - 0.004), (x_in - 0.06, y, zb - 0.004), 0.028, 0.012,
                   K_ALU, 0.8)
    nose_y = min(y_max - 0.35, fa + s["arch_r"] + 0.35)
    shield_y0 = fa + 0.32
    if nose_y > shield_y0 + 0.08:
        zl = fit.floor_at(0.0, (nose_y + shield_y0) * 0.5) - 0.004
        zl = max(zl, ground_min)
        w = x_in - 0.06
        g.plate([(-w, shield_y0, zl), (w, shield_y0, zl), (w * 0.9, nose_y, zl), (-w * 0.9, nose_y, zl)],
                K_SHIELD, 0.0)

    # The exhaust: from the front pipe down the tunnel, through a resonator, over the rear axle,
    # into a transverse silencer behind it and out through the tips.
    tips = EXHAUST.get(name, [])
    if tips:
        px = 0.06
        path = [Vector((px + 0.04, fa - 0.30, hang(px, fa - 0.30, 0.0) + 0.10))]
        y_res0, y_res1 = (fa + ra) * 0.5 + 0.25, (fa + ra) * 0.5 - 0.15
        ys_run = [fa - 0.55, fa - 0.85, y_res0 + 0.10, y_res0, y_res1, y_res1 - 0.10,
                  ra + 0.55, ra + 0.35]
        for y in ys_run:
            path.append(Vector((px, y, hang(px, y, 0.05) + 0.025)))
        r_pipe = 0.025
        g.tube(path[:5], r_pipe, K_EXHAUST, 0.0, 8)
        res_z = hang(px, (y_res0 + y_res1) * 0.5, 0.11) + 0.055
        g.tube([(px, y_res0, res_z), (px, y_res1, res_z)], 0.055, K_EXHAUST, 0.3, 10)
        g.tube(path[4:], r_pipe, K_EXHAUST, 0.0, 8)
        # Heat shield: a dimpled aluminium strip over the run, against the floor.
        for y0, y1 in ((fa - 0.55, y_res0 + 0.05), (y_res1 - 0.05, ra + 0.50)):
            if y0 - y1 < 0.1:
                continue
            zt = fit.floor_at(px, (y0 + y1) * 0.5) - 0.003
            g.plate([(px - 0.12, y1, zt), (px + 0.12, y1, zt), (px + 0.12, y0, zt),
                     (px - 0.12, y0, zt)], K_SHIELD, 0.5)
        # Over the axle and into the silencer.
        y_sil = ra - 0.32
        y_face_c = fit.tail_face(0.0)
        y_face_c = y_face_c if y_face_c is not None else y_min + 0.05
        if y_sil < y_face_c + 0.28:
            y_sil = (ra + y_face_c) * 0.5
        zs = hang(0.0, y_sil, 0.13) + 0.065
        over = Vector((px, ra, max(hang(px, ra, 0.03), az - 0.02)))
        g.tube([path[-1], over, Vector((0.12, y_sil + 0.12, zs))], r_pipe, K_EXHAUST, 0.0, 8)
        sil_w = 0.30 if len(tips) == 1 else min(0.48, max(abs(t[0]) for t in tips) - 0.04)
        sil_c = (max(t[0] for t in tips) * 0.5) if len(tips) == 1 else 0.0
        sil_c = max(-x_in + sil_w + 0.08, min(x_in - sil_w - 0.08, sil_c))
        g.tube([(sil_c - sil_w, y_sil, zs), (sil_c + sil_w, y_sil, zs)], 0.075, K_EXHAUST, 0.6, 12)
        for k in (-1.0, 1.0):
            hz = zs + 0.07
            g.tube([(sil_c + k * (sil_w - 0.05), y_sil, hz), (sil_c + k * (sil_w - 0.05), y_sil,
                    fit.floor_at(sil_c + k * (sil_w - 0.05), y_sil))], 0.006, K_STEEL, 0.6, 4)
        for (tx, tr) in tips:
            y_face = fit.tail_face(tx)
            if y_face is None:
                y_face = y_min + 0.04
            start = tip(g, fit, tx, tr, y_face)
            sx = sil_c + (sil_w - 0.02) * (1.0 if tx >= sil_c else -1.0)
            if abs(tx - sx) > sil_w + 0.1:
                sx = sil_c + (sil_w - 0.02) * (1.0 if tx >= 0 else -1.0)
            # Sideways at the silencer's level, then straight back to the tip, kept up under
            # the floor so only the tip shows under the bumper.
            back = Vector((tx, y_sil - 0.10, zs))
            g.tube([Vector((sx, y_sil - 0.03, zs)), back, start + Vector((0.0, 0.10, 0.0)), start],
                   tr * 0.72, K_EXHAUST, 0.3, 8)

    # The fuel tank (not on the EV): a moulded black tank ahead of the rear axle, strapped up.
    if name != "ev_hatch":
        ty0, ty1 = ra + 0.32, ra + 0.88
        tx0, tx1 = -min(0.62, x_in - 0.04), -0.08
        zt = hang((tx0 + tx1) * 0.5, (ty0 + ty1) * 0.5, 0.055)
        g.box(((tx0 + tx1) * 0.5, (ty0 + ty1) * 0.5, zt + 0.06), (tx1 - tx0, ty1 - ty0, 0.12), K_TANK)
        for y in (ty0 + 0.10, ty1 - 0.10):
            g.box(((tx0 + tx1) * 0.5, y, zt - 0.002), (tx1 - tx0 + 0.02, 0.035, 0.008), K_STEEL, 0.6)
        g.tube([(tx1 - 0.05, ty1 - 0.05, zt + 0.02), (0.0, fa - 0.5, hang(0.0, fa - 0.5, 0.0) + 0.012)],
               0.006, K_ALU, 0.5, 4)

    # Rear axle.
    if frame:
        # Ladder frame, a live axle with the diff, leaf springs and dampers.
        rail_x = min(0.52, x_in - 0.06)
        for side in (1.0, -1.0):
            frame_rails(g, fit, side * rail_x, y_min + 0.35, y_max - 0.45)
        for y in (fa - 0.6, (fa + ra) * 0.5, ra - 0.55):
            z = hang(0.0, y, 0.06) + 0.03
            g.beam((-rail_x, y, z), (rail_x, y, z), 0.06, 0.06, K_STEEL)
        za = az
        g.tube([(-(wx - 0.12), ra, za), (wx - 0.12, ra, za)], 0.040, K_STEEL, 0.3, 10)
        g.tube([(0.0, ra + 0.10, za), (0.0, ra - 0.08, za)], 0.11, K_STEEL, 0.3, 12)   # the diff
        g.tube([(0.0, ra + 0.10, za), (0.0, fa - 0.6, hang(0.0, fa - 0.6, 0.04) + 0.02)], 0.032,
               K_STEEL, 0.6, 8)                                                         # driveshaft
        for side in (1.0, -1.0):
            x = side * rail_x
            leaf = []
            for i in range(9):
                t = i / 8.0
                y = ra + 0.62 - 1.24 * t
                sag = 0.07 * math.sin(math.pi * t)
                leaf.append(Vector((x, y, za - 0.045 - sag + 0.07)))
            for i in range(len(leaf) - 1):
                g.beam(leaf[i], leaf[i + 1], 0.065, 0.028, K_STEEL, 0.9)
            g.tube([(x * 0.94, ra - 0.18, za - 0.03), (x * 0.94, ra - 0.24, za + 0.30)], 0.024,
                   K_STEEL, 0.3, 8)
    else:
        # A twist beam (or the multilink's crossmember), trailing arms to the hubs, coil springs.
        zb = max(az - 0.06, hang(0.0, ra + 0.12, 0.05))
        g.beam((-(x_in - 0.02), ra + 0.12, zb), (x_in - 0.02, ra + 0.12, zb), 0.10, 0.07, K_STEEL)
        for side in (1.0, -1.0):
            piv = Vector((side * (x_in - 0.04), ra + 0.62, hang(side * (x_in - 0.04), ra + 0.62, 0.03)
                          + 0.015))
            hub = Vector((side * (wx - 0.14), ra, az - 0.02))
            g.beam(piv, hub, 0.06, 0.07, K_STEEL)
            g.tube([piv + Vector((side * 0.04, 0, 0)), piv - Vector((side * 0.04, 0, 0))], 0.035,
                   K_RUBBER, 0.0, 8)
            sp = Vector((side * (x_in - 0.10), ra + 0.06, zb + 0.03))
            helix(g, sp, Vector((sp.x, sp.y, max(sp.z + 0.12, fit.floor_at(sp.x, sp.y) + 0.02))),
                  0.055, 0.0075, 3.5, K_SPRING, var)
    # Body pinch welds and jacking points along each sill, between the arches.
    for side in (1.0, -1.0):
        y0, y1 = ra + s["arch_r_rear"] + 0.06, fa - s["arch_r"] - 0.06
        x = side * min(half_w - 0.10, x_in + 0.20)
        for y in (y0 + 0.08, y1 - 0.08):
            z = fit.floor_at(x, y) - CLEAR
            g.box((x, y, z - 0.012), (0.06, 0.10, 0.025), K_RUBBER)
    me_ob = g.build("road_%s_under" % name)
    me_ob.data.calc_loop_triangles()
    zs_all = [v.co.z for v in me_ob.data.vertices]
    ys_all = [v.co.y for v in me_ob.data.vertices]
    xs_all = [v.co.x for v in me_ob.data.vertices]
    print("== %s underside: %d triangles, x %.3f..%.3f, y %.3f..%.3f (body %.3f..%.3f), z %.3f..%.3f"
          % (name, len(me_ob.data.loop_triangles), min(xs_all), max(xs_all), min(ys_all),
             max(ys_all), y_min, y_max, min(zs_all), max(zs_all)))
    bpy.data.objects.remove(ob, do_unlink=True)
    return me_ob


def export(ob, path):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
              export_materials='EXPORT', export_yup=True, export_normals=True,
              export_texcoords=True, export_tangents=False, export_skins=False,
              export_animations=False, export_cameras=False, export_lights=False)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kw)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or BODIES
    for name in names:
        spec = rc.SPECS[name]()
        rc.reset_scene()
        rc.MATS.clear()
        rc.MATS.extend(rc.make_materials())
        ob = build_under(spec)
        if "--noexport" not in argv:
            path = os.path.join(rc.OUT_DIR, "road_%s_under.glb" % name)
            export(ob, path)
            print("wrote", path)


if __name__ == "__main__":
    main()
