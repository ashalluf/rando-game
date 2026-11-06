"""Traffic signal hardware: mast-arm poles, arms, vehicle and pedestrian heads, push buttons and
the controller cabinet, for the signalised intersections (owner, 2026-09-24: "GTA-level street
life").

Run headless with Blender 4.2:

    blender -b --factory-startup --python tools/make_signals.py -- [out.glb]

Writes assets/models/traffic_signal.glb, one mesh node per piece (sig_pole, sig_arm, sig_head,
sig_bracket, sig_ped, sig_button, sig_cabinet). Then run `godot --headless --path . --import`
before rendering anything - Godot serves a cached import of a .glb (CLAUDE.md, measurement traps)
- and commit the .glb and its .import.

Everything is modelled in GODOT space (x, y up, z, metres) and converted to Blender's Z-up on the
way in (G() below); the glTF exporter turns it back. The numbers the placing code needs are
PropFactory's SIGNAL_* constants (scripts/world/prop_factory.gd); the smoke test checks them
against this model's bounds, so change both or neither:

* sig_pole: origin on the pavement at the pole's axis, 7.6 m tall, the arm collar centred at
  y 6.55.
* sig_arm: origin on the pole axis at the collar, runs along +x to exactly x = 8.0 (the tip).
  The placing code scales it along x to the length an approach needs, so nothing on it may care
  about its length: a round tapered tube, a flange at the root, a cap at the tip.
* sig_head: a three-lamp vehicle head, lenses facing +z, hanging from its origin (the mast arm's
  axis): hanger 0.30 m, then 1.10 m of housing, so its bottom is at y -1.40.
* sig_bracket: the side-mount arm for a head on the pole itself: origin on the pole axis, the
  head hangs from its end at x = +0.55.
* sig_ped: a pedestrian head (hand / walking figure beside a countdown), origin on the pole
  axis, facing +z, face centred at y 0.
* sig_button: the push-button station, origin on the pole axis, facing +z.
* sig_cabinet: the controller cabinet on its pad, origin on the pavement, door facing +z.

Lenses are one material, sig_lens, and each lens says which lamp it is in its SECOND UV channel
(Godot UV2.x = (id + 0.5) / 8: 0 red, 1 amber, 2 green, 3 the pedestrian glyph, 4 the countdown),
with its own 0..1 square in the first channel (0,0 top left), which is what
shaders/traffic_signal.gdshader draws the LED pattern, the glyphs and the digits in. Every
other material is named for what PropFactory.signal_part() puts on it.

Every hard edge is bevelled and the normals are face-area weighted (the WeightedNormal
modifier), so flats stay flat and the bevels catch the light - which is most of what separates
a modelled pole from a primitive one.
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
           os.path.join(HERE, "..", "assets", "models", "traffic_signal.glb"))

POLE_H = 7.6
ARM_Y = 6.55
ARM_LEN = 8.0
HANGER = 0.30
HEAD_W = 0.36
HEAD_D = 0.22
SECTION = 1.10 / 3.0
LENS_R = 0.147
BRACKET_REACH = 0.55

MATERIALS = {
    # name: (base colour, roughness, metallic)
    "sig_steel": ((0.52, 0.53, 0.54), 0.45, 0.6),
    "sig_steel_dark": ((0.16, 0.16, 0.17), 0.5, 0.5),
    "sig_housing": ((0.035, 0.037, 0.034), 0.42, 0.0),
    "sig_reflect": ((0.95, 0.72, 0.06), 0.35, 0.0),
    "sig_lens": ((0.05, 0.05, 0.05), 0.12, 0.0),
    "sig_sign": ((0.88, 0.88, 0.86), 0.5, 0.0),
    "sig_cabinet": ((0.60, 0.62, 0.58), 0.5, 0.3),
    "sig_concrete": ((0.60, 0.59, 0.56), 0.9, 0.0),
}


def G(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


def to_godot(v):
    return Vector((v.x, v.z, -v.y))


def material(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    col, rough, metal = MATERIALS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


# --- Temporary meshes ----------------------------------------------------------------------------

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
    """Box projection in metres, picked per face by its dominant normal."""
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


class Piece:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.uv2 = self.bm.loops.layers.uv.new("LensID")
        self.mats = []

    def slot(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def add(self, t, mat, lens=-1):
        """Copies bmesh `t` (UVs, smoothing, sharp edges) into the piece; `lens` >= 0 writes the
        lamp id into the second UV channel."""
        idx = self.slot(mat)
        uv_s = t.loops.layers.uv.active
        code = ((lens + 0.5) / 8.0) if lens >= 0 else 0.0
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
                ld[self.uv].uv = ls[uv_s].uv
                ld[self.uv2].uv = (code, 0.0)
        for e in t.edges:
            ne = self.bm.edges.get([vmap[v] for v in e.verts])
            if ne:
                ne.smooth = e.smooth
        t.free()

    # --- primitives --------------------------------------------------------------------------

    def box(self, c, size, mat, bevel=0.0, segments=2, smooth=35.0, axes=None):
        """A box centred on Godot `c`, `size` along its own axes (Godot unit vectors `axes`,
        default the world ones), bevelled on every edge."""
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
        self.add(t, mat)

    def lathe(self, prof, origin, axis, mat, segs=24, smooth=40.0, a0=0.0, a1=360.0, lens=-1):
        """A solid of revolution: `prof` is (radius, distance along `axis`) points, revolved about
        the Godot-space line through `origin` along `axis`. A full turn is closed; a partial one
        (a0..a1 degrees, 0 on the frame's first perpendicular) is left open at its ends."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        A = Vector(axis).normalized()
        U = Vector((0, 1, 0)).cross(A)
        if U.length < 0.1:
            U = Vector((1, 0, 0)).cross(A)
        U.normalize()
        V = A.cross(U).normalized()
        full = abs((a1 - a0) - 360.0) < 1e-6
        steps = segs if full else max(2, int(round(segs * (a1 - a0) / 360.0)))
        rings = []
        for i in range(steps if full else steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            ring = []
            for (r, d) in prof:
                p = Vector(origin) + A * d + (U * math.cos(a) + V * math.sin(a)) * r
                ring.append(t.verts.new(G(p.x, p.y, p.z)))
            rings.append(ring)
        n = len(prof)
        cols = steps if full else steps
        s = [0.0]
        for k in range(1, n):
            s.append(s[-1] + math.dist(prof[k], prof[k - 1]))
        for i in range(cols):
            ra = rings[i]
            rb = rings[(i + 1) % len(rings)]
            ua = math.radians(a0 + (a1 - a0) * i / steps)
            ub = math.radians(a0 + (a1 - a0) * (i + 1) / steps)
            for k in range(n - 1):
                quad = [ra[k], rb[k], rb[k + 1], ra[k + 1]]
                # A point on the axis collapses its two corners: make that face a triangle.
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
                    u = (ua if j in (0, 3) else ub) * rr
                    v = s[k] if j in (0, 1) else s[k + 1]
                    loop[uvl].uv = (u, v)
        bmesh.ops.remove_doubles(t, verts=t.verts, dist=1e-6)
        if full:
            bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        _smooth_by_angle(t, smooth)
        self.add(t, mat, lens)

    def visor(self, c, r, depth, thick, mat, a_open=100.0, segs=24):
        """A tunnel visor: a cylinder shell `thick` thick along +z from `c`, `depth` long, open
        over `a_open` degrees at the bottom so rain and the eye get through."""
        half = a_open * 0.5
        a0 = -90.0 + half
        a1 = 270.0 - half
        prof = [(r, 0.0), (r + thick, 0.0), (r + thick, depth), (r, depth), (r, 0.0)]
        self.lathe_closed_partial(prof, c, (0, 0, 1), mat, segs, a0, a1)

    def lathe_closed_partial(self, prof, origin, axis, mat, segs, a0, a1):
        """A partial revolution of a CLOSED profile, capped at both cut ends (a visor's edges)."""
        t = _new_bm()
        A = Vector(axis).normalized()
        # The frame for axis +z: angle 0 on +x, 90 on +y (up), so the open wedge sits at -90.
        U = Vector((1, 0, 0))
        V = Vector((0, 1, 0))
        steps = max(2, int(round(segs * (a1 - a0) / 360.0)))
        rings = []
        for i in range(steps + 1):
            a = math.radians(a0 + (a1 - a0) * i / steps)
            ring = []
            for (r, d) in prof[:-1]:
                p = Vector(origin) + A * d + (U * math.cos(a) + V * math.sin(a)) * r
                ring.append(t.verts.new(G(p.x, p.y, p.z)))
            rings.append(ring)
        n = len(prof) - 1
        for i in range(steps):
            for k in range(n):
                k2 = (k + 1) % n
                t.faces.new([rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k2]])
        t.faces.new(rings[0])
        t.faces.new(list(reversed(rings[-1])))
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        t.normal_update()
        _box_uv(t)
        _smooth_by_angle(t, 40.0)
        self.add(t, mat)

    def disc(self, c, r, dome, mat, lens, segs=24, normal=(0, 0, 1), up=(0, 1, 0)):
        """A lens: a shallow dome of radius `r` facing `normal`, its own 0..1 UV square (0,0 at
        the top left as Godot reads it), the lamp id in the second channel."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        N = Vector(normal).normalized()
        UP = Vector(up).normalized()
        R = UP.cross(N).normalized()  # right, seen from the front
        centre = Vector(c)
        rings = 3
        verts = [[t.verts.new(G(*(centre + N * dome)))]]
        for k in range(1, rings + 1):
            rr = r * k / rings
            h = dome * (1.0 - (k / rings) ** 2)
            ring = []
            for i in range(segs):
                a = 2.0 * math.pi * i / segs
                p = centre + N * h + (R * math.cos(a) + UP * math.sin(a)) * rr
                ring.append(t.verts.new(G(p.x, p.y, p.z)))
            verts.append(ring)
        for k in range(1, rings + 1):
            for i in range(segs):
                j = (i + 1) % segs
                if k == 1:
                    t.faces.new([verts[0][0], verts[1][i], verts[1][j]])
                else:
                    t.faces.new([verts[k - 1][i], verts[k][i], verts[k][j], verts[k - 1][j]])
        for f in t.faces:
            f.normal_update()
            if to_godot(f.normal).dot(N) < 0.0:
                f.normal_flip()
            for loop in f.loops:
                p = to_godot(loop.vert.co) - centre
                # Blender v runs up; the glTF export flips it, so Godot's UV.y runs down.
                loop[uvl].uv = (p.dot(R) / (2.0 * r) + 0.5, p.dot(UP) / (2.0 * r) + 0.5)
        t.normal_update()
        for f in t.faces:
            f.smooth = True
        self.add(t, mat, lens)

    def panel(self, x0, x1, y0, y1, z, mat, lens):
        """A flat lens face (the pedestrian head's), x0..x1 by y0..y1 at depth z facing +z,
        subdivided so the shader's glyph has vertices to light, with its own 0..1 UV square."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        nx, ny = 6, 10
        grid = []
        for j in range(ny + 1):
            row = []
            for i in range(nx + 1):
                x = x0 + (x1 - x0) * i / nx
                y = y1 - (y1 - y0) * j / ny
                row.append(t.verts.new(G(x, y, z)))
            grid.append(row)
        for j in range(ny):
            for i in range(nx):
                f = t.faces.new([grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1]])
                f.normal_update()
                if to_godot(f.normal).z < 0.0:
                    f.normal_flip()
                for loop in f.loops:
                    p = to_godot(loop.vert.co)
                    loop[uvl].uv = ((p.x - x0) / (x1 - x0), (p.y - y0) / (y1 - y0))
        t.normal_update()
        for f in t.faces:
            f.smooth = False
        self.add(t, mat, lens)


# --- The pieces -----------------------------------------------------------------------------------

def pole():
    """Galvanised tapered pole on a bolted base plate with a cast base cover, a handhole, the arm
    collar and a domed cap."""
    p = Piece("sig_pole")
    p.box((0.0, 0.022, 0.0), (0.58, 0.044, 0.58), "sig_steel", bevel=0.008)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            x, z = sx * 0.215, sz * 0.215
            p.lathe([(0.0, 0.044), (0.019, 0.044), (0.019, 0.13), (0.012, 0.142), (0.0, 0.142)],
                    (x, 0.0, z), (0, 1, 0), "sig_steel_dark", segs=10)
            p.lathe([(0.0, 0.044), (0.036, 0.044), (0.036, 0.078), (0.028, 0.086), (0.0, 0.086)],
                    (x, 0.0, z), (0, 1, 0), "sig_steel_dark", segs=6, smooth=20.0)
    # The base cover: a flared casting over the bolts' footprint.
    p.lathe([(0.0, 0.044), (0.255, 0.044), (0.255, 0.07), (0.235, 0.09), (0.2, 0.26), (0.185, 0.42),
             (0.19, 0.44), (0.175, 0.46), (0.0, 0.46)], (0, 0, 0), (0, 1, 0), "sig_steel", segs=28)
    # The shaft, tapered, with a domed cap.
    p.lathe([(0.0, 0.44), (0.168, 0.44), (0.118, POLE_H - 0.06), (0.1, POLE_H - 0.01),
             (0.06, POLE_H + 0.03), (0.0, POLE_H + 0.045)], (0, 0, 0), (0, 1, 0), "sig_steel", segs=24)
    # Handhole cover on the side away from the street.
    p.box((0.0, 0.95, -0.163), (0.13, 0.28, 0.03), "sig_steel", bevel=0.01)
    # Arm collar and its two bands.
    p.lathe([(0.0, ARM_Y - 0.26), (0.152, ARM_Y - 0.26), (0.168, ARM_Y - 0.24), (0.168, ARM_Y + 0.24),
             (0.152, ARM_Y + 0.26), (0.0, ARM_Y + 0.26)], (0, 0, 0), (0, 1, 0), "sig_steel", segs=24)
    return p


def arm():
    """The mast arm: a round tapered tube from a bolted flange on the collar to a capped tip."""
    p = Piece("sig_arm")
    # Flange plate against the collar, and its bolts.
    p.box((0.186, 0.0, 0.0), (0.035, 0.42, 0.40), "sig_steel", bevel=0.008)
    for sy in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            p.lathe([(0.0, 0.2), (0.02, 0.2), (0.02, 0.24), (0.0, 0.24)],
                    (0.0, sy * 0.15, sz * 0.14), (1, 0, 0), "sig_steel_dark", segs=6, smooth=20.0)
    # The tube, root to tip, with a gusset collar at the root and a cap at the end.
    p.lathe([(0.0, 0.195), (0.135, 0.195), (0.135, 0.3), (0.125, 0.32), (0.066, ARM_LEN - 0.03),
             (0.05, ARM_LEN - 0.005), (0.0, ARM_LEN)], (0, 0, 0), (1, 0, 0), "sig_steel", segs=20)
    return p


def _head_body(p, y_top):
    """Three sections, backplate with its reflective border, bezels, visors and lenses, from
    y_top down; lenses at z = +HEAD_D / 2."""
    h = SECTION * 3.0
    cy = y_top - h * 0.5
    front = HEAD_D * 0.5
    p.box((0.0, cy, 0.0), (HEAD_W, h, HEAD_D), "sig_housing", bevel=0.022, segments=3)
    # The joints between sections: slim raised bands round the housing.
    for k in (1, 2):
        y = y_top - SECTION * k
        p.box((0.0, y, 0.0), (HEAD_W + 0.012, 0.018, HEAD_D + 0.012), "sig_housing", bevel=0.005, segments=1)
    # Backplate: a black louvred plate round the head with a yellow retroreflective border, set
    # in the middle of the housing's depth.
    bw, bh = HEAD_W + 0.30, h + 0.26
    p.box((0.0, cy, -0.005), (bw, bh, 0.012), "sig_housing", bevel=0.004, segments=1)
    border = 0.05
    for (x, y, w, hh) in ((0.0, cy + bh * 0.5 - border * 0.5, bw, border),
                          (0.0, cy - bh * 0.5 + border * 0.5, bw, border),
                          (-bw * 0.5 + border * 0.5, cy, border, bh - border * 2.0),
                          (bw * 0.5 - border * 0.5, cy, border, bh - border * 2.0)):
        p.box((x, y, 0.004), (w, hh, 0.004), "sig_reflect", bevel=0.0)
    for k in range(3):
        y = y_top - SECTION * (k + 0.5)
        # Bezel ring, then the visor, then the lens behind it.
        p.lathe([(LENS_R - 0.004, front - 0.004), (LENS_R + 0.022, front - 0.004),
                 (LENS_R + 0.022, front + 0.012), (LENS_R + 0.012, front + 0.02),
                 (LENS_R - 0.004, front + 0.02)] + [(LENS_R - 0.004, front - 0.004)],
                (0.0, y, 0.0), (0, 0, 1), "sig_housing", segs=24, smooth=35.0)
        p.visor((0.0, y, front + 0.018), LENS_R + 0.012, 0.25, 0.006, "sig_housing")
        p.disc((0.0, y, front + 0.002), LENS_R, 0.012, "sig_lens", k)


def head():
    """A three-lamp vehicle head hanging from the mast arm, lenses toward +z."""
    p = Piece("sig_head")
    # Hanger: a clamp on the arm and a stem down to the head's top.
    p.box((0.0, 0.0, 0.0), (0.16, 0.2, 0.2), "sig_steel_dark", bevel=0.02)
    p.lathe([(0.0, -HANGER - 0.01), (0.032, -HANGER - 0.01), (0.032, -0.08), (0.0, -0.08)],
            (0, 0, 0), (0, 1, 0), "sig_steel_dark", segs=12)
    p.box((0.0, -HANGER + 0.012, 0.0), (0.14, 0.024, 0.14), "sig_steel_dark", bevel=0.006)
    _head_body(p, -HANGER)
    return p


def bracket():
    """Side-mount bracket: a clamp band round the pole and an arm out to x = BRACKET_REACH, where
    a sig_head hangs by its own clamp."""
    p = Piece("sig_bracket")
    p.lathe([(0.0, -0.06), (0.17, -0.06), (0.17, 0.06), (0.0, 0.06)], (0, 0, 0), (0, 1, 0),
            "sig_steel_dark", segs=20)
    p.lathe([(0.0, 0.1), (0.035, 0.1), (0.035, BRACKET_REACH), (0.0, BRACKET_REACH)],
            (0, 0, 0), (1, 0, 0), "sig_steel_dark", segs=12)
    return p


def ped():
    """Pedestrian head: a square housing with a hood, hand / figure on the left, countdown on the
    right, on clamshell brackets off the pole."""
    p = Piece("sig_ped")
    for sy in (-1.0, 1.0):
        p.box((0.0, sy * 0.12, 0.15), (0.08, 0.05, 0.16), "sig_steel_dark", bevel=0.01)
    p.lathe([(0.0, -0.035), (0.165, -0.035), (0.165, 0.035), (0.0, 0.035)], (0, 0.12, 0), (0, 1, 0),
            "sig_steel_dark", segs=20)
    p.lathe([(0.0, -0.035), (0.165, -0.035), (0.165, 0.035), (0.0, 0.035)], (0, -0.12, 0), (0, 1, 0),
            "sig_steel_dark", segs=20)
    p.box((0.0, 0.0, 0.31), (0.46, 0.46, 0.2), "sig_housing", bevel=0.02, segments=3)
    # Hood: top and two cheeks, 16 cm deep, 8 mm thick.
    p.box((0.0, 0.226, 0.49), (0.46, 0.008, 0.16), "sig_housing", bevel=0.003, segments=1)
    for sx in (-1.0, 1.0):
        p.box((sx * 0.226, 0.03, 0.49), (0.008, 0.40, 0.16), "sig_housing", bevel=0.003, segments=1)
    # Recessed face frame and the two lens panels.
    p.box((0.0, 0.0, 0.412), (0.43, 0.43, 0.012), "sig_housing", bevel=0.004, segments=1)
    p.panel(-0.2, -0.012, -0.19, 0.19, 0.4195, "sig_lens", 3)
    p.panel(0.012, 0.2, -0.19, 0.19, 0.4195, "sig_lens", 4)
    return p


def button():
    """Push-button station: a clamp band, a housing with a round button, a small sign above."""
    p = Piece("sig_button")
    p.lathe([(0.0, -0.1), (0.165, -0.1), (0.165, -0.06), (0.0, -0.06)], (0, 0, 0), (0, 1, 0),
            "sig_steel_dark", segs=20)
    p.box((0.0, -0.02, 0.2), (0.11, 0.17, 0.08), "sig_housing", bevel=0.012)
    p.lathe([(0.0, 0.24), (0.028, 0.24), (0.028, 0.252), (0.02, 0.258), (0.0, 0.26)],
            (0.0, -0.035, 0.0), (0, 0, 1), "sig_steel", segs=16)
    p.box((0.0, 0.17, 0.178), (0.13, 0.19, 0.008), "sig_sign", bevel=0.002, segments=1)
    return p


def cabinet():
    """The signal controller: a vented steel cabinet with a rain cap on a concrete pad."""
    p = Piece("sig_cabinet")
    p.box((0.0, 0.06, 0.0), (1.0, 0.12, 0.72), "sig_concrete", bevel=0.02)
    p.box((0.0, 0.12 + 0.72, 0.0), (0.78, 1.44, 0.52), "sig_cabinet", bevel=0.014)
    p.box((0.0, 1.585, 0.0), (0.84, 0.035, 0.58), "sig_cabinet", bevel=0.008)
    # Door: its seam, the handle, the lock and a row of louvres near the bottom.
    for (x, y, w, h) in ((0.0, 1.49, 0.66, 0.008), (0.0, 0.25, 0.66, 0.008),
                         (-0.33, 0.87, 0.008, 1.24), (0.33, 0.87, 0.008, 1.24)):
        p.box((x, y, 0.263), (w, h, 0.006), "sig_steel_dark")
    p.box((0.26, 0.95, 0.275), (0.03, 0.16, 0.03), "sig_steel_dark", bevel=0.006)
    p.lathe([(0.0, 0.26), (0.018, 0.26), (0.018, 0.275), (0.0, 0.277)], (0.26, 1.08, 0.0), (0, 0, 1),
            "sig_steel", segs=10)
    for k in range(5):
        p.box((0.0, 0.36 + k * 0.045, 0.268), (0.44, 0.012, 0.018), "sig_cabinet", bevel=0.003, segments=1)
    return p


PIECES = [pole, arm, head, bracket, ped, button, cabinet]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    report = []
    for make in PIECES:
        piece = make()
        mesh = bpy.data.meshes.new(piece.name)
        piece.bm.normal_update()
        piece.bm.to_mesh(mesh)
        piece.bm.free()
        for m in piece.mats:
            mesh.materials.append(material(m))
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
        report.append("%-12s %5d tris  x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f  mats %s" % (
            piece.name, tris, min(xs), max(xs), min(ys), max(ys), min(zs), max(zs), ",".join(piece.mats)))
        mesh.uv_layers.active = mesh.uv_layers["UVMap"]
        mesh.uv_layers["UVMap"].active_render = True
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(OUT), export_format='GLB', export_yup=True,
                              export_apply=True, export_texcoords=True, export_normals=True,
                              export_tangents=False, export_materials='EXPORT',
                              export_vertex_color='NONE', export_animations=False,
                              export_cameras=False, export_lights=False)
    print("traffic signal ->", os.path.abspath(OUT))
    for line in report:
        print("  " + line)


main()
