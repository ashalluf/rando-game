"""Facade detail kit: real moulded geometry for the buildings near the camera.

Run headless with Blender 4.2:

    blender -b --python tools/facade_kit.py -- [out.glb] [--no-bake]

Writes assets/models/facade_kit.glb (one mesh node per piece, named kit_<piece>). Then run
`godot --headless --path . --import` before rendering anything - Godot serves a cached import of
a .glb (CLAUDE.md, measurement traps) - and commit the .glb and its .import.

Every piece is modelled in GODOT space (x along the wall, y up, z out of the wall, metres) and
converted to Blender's Z-up on the way in (G() below), so the numbers here are the numbers
scripts/world/building.gd places them with. The glTF exporter turns Blender's Z-up back into Y-up.

How building.gd and shaders/facade_kit.gdshaderinc use the pieces - the rules the geometry has
to keep, or the shader moves the wrong vertices:

* Roofline runs (kit_cornice_*, kit_coping) are exactly 2.0 m long, x in [-1, 1], and NOTHING but
  the two end rings of vertices may sit at |x| > 0.999. The shader shears those end rings by
  z * tan(half the corner angle) from INSTANCE_CUSTOM.r / .g, so two runs meet in a true mitre
  at any corner, square or chamfered, and a run scaled along x to fit its wall stays mitred.
* Window surrounds are built round a 1 x 1 m opening centred on the origin. The shader
  "three-slices" them from INSTANCE_CUSTOM.b / .a: anything inside |x| < 0.5 (|y| < 0.5)
  stretches to the real opening, anything outside moves out with the edge but keeps its real
  size - so a sill's lugs, a lintel's height and a jamb's width stay true on every window
  size. A vertex exactly on 0.5 is fine (both branches agree there). The awning uses the x
  slice the same way (its cheeks sit exactly on x = +-0.5).
* Front-facing UVs are u = x, v = -y, in metres (so Godot's UV.y is 1 + y after the glTF V
  flip); the shader slices UV.x the same way as VERTEX.x. Moulding runs carry u = x and v =
  distance along the profile instead, which has no seam round a curved moulding.
* UV2.x carries baked ambient occlusion as OCCLUSION (0 = open, 1 = fully occluded), so a mesh
  without it reads as unoccluded rather than black.
* Material names pick the Godot material (PropFactory.kit_material()): kit_stone_run (the
  mitred runs), kit_stone, kit_paint (tinted by the instance colour), kit_iron (tinted from a
  palette by INSTANCE_CUSTOM.r), kit_dark, kit_fabric (double sided), kit_wood.

Budgets (triangles) are in PropFactory.TRI_BUDGET; this script prints each piece's count.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = next((a for a in ARGV if a.endswith(".glb")),
           os.path.join(HERE, "..", "assets", "models", "facade_kit.glb"))
BAKE = "--no-bake" not in ARGV


def G(x, y, z):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


def to_godot(v):
    return Vector((v.x, v.z, -v.y))


MATERIALS = {
    # name: (base colour, roughness, metallic, double sided)
    "kit_stone_run": ((0.78, 0.76, 0.72), 0.8, 0.0, False),
    "kit_stone": ((0.78, 0.76, 0.72), 0.8, 0.0, False),
    "kit_paint": ((0.80, 0.80, 0.78), 0.55, 0.2, False),
    "kit_iron": ((0.12, 0.12, 0.13), 0.5, 0.4, False),
    "kit_dark": ((0.05, 0.05, 0.05), 0.6, 0.3, False),
    "kit_fabric": ((0.60, 0.20, 0.18), 0.9, 0.0, True),
    "kit_wood": ((0.35, 0.28, 0.22), 0.85, 0.0, False),
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


# --- Building blocks ----------------------------------------------------------------------------
# Each primitive is made in its own small bmesh (so bevels and normal fixes only touch it), given
# its UVs there, then copied into the piece.

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
    """Box projection in metres, picked per face by its dominant normal. Front and side faces
    get v = -y so Godot's UV.y comes out as 1 + y (see the module docstring)."""
    uvl = t.loops.layers.uv.active
    for f in t.faces:
        n = to_godot(f.normal)
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            p = to_godot(loop.vert.co)
            if ax == 1:
                loop[uvl].uv = (p.x, -p.z)
            elif ax == 2:
                loop[uvl].uv = (p.x, -p.y)
            else:
                loop[uvl].uv = (p.z, -p.y)


def _signed_area(prof):
    a = 0.0
    for i in range(len(prof)):
        z0, y0 = prof[i]
        z1, y1 = prof[(i + 1) % len(prof)]
        a += z0 * y1 - z1 * y0
    return a * 0.5


class Piece:
    def __init__(self, name, occluder=None, ao_distance=0.35):
        self.name = name
        self.bm = _new_bm()
        self.mats = []
        self.occluder = occluder
        self.ao_distance = ao_distance

    def slot(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def add(self, t, mat):
        """Copies bmesh `t` (with its UVs, smoothing and sharp edges) into the piece."""
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

    # --- primitives --------------------------------------------------------------------------

    def extrude(self, prof, x0, x1, mat, closed=True, caps=False, smooth=38.0, uv="profile"):
        """A moulding: `prof` is a list of (z, y) points (out of the wall, up), swept along x
        from x0 to x1. Closed profiles are solids; with caps=False their ends stay open (the
        roofline runs butt into each other, so their end caps would never be seen)."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        n = len(prof)
        a = [t.verts.new(G(x0, y, z)) for (z, y) in prof]
        b = [t.verts.new(G(x1, y, z)) for (z, y) in prof]
        s = [0.0]
        for i in range(1, n):
            s.append(s[-1] + math.dist(prof[i], prof[i - 1]))
        total = s[-1] + (math.dist(prof[-1], prof[0]) if closed else 0.0)
        # Winding: the outward side of each profile edge, from the profile's own orientation.
        ccw = _signed_area(prof) > 0.0 if closed else True
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            quad = (a[i], b[i], b[j], a[j])
            f = t.faces.new(quad)
            sj = s[j] if j != 0 else total
            uvs = {a[i]: (x0, s[i]), b[i]: (x1, s[i]), b[j]: (x1, sj), a[j]: (x0, sj)}
            for loop in f.loops:
                loop[uvl].uv = uvs[loop.vert]
            # Desired outward normal in (z, y): for a CCW profile it is (dy, -dz).
            dz = prof[j][0] - prof[i][0]
            dy = prof[j][1] - prof[i][1]
            want = G(0.0, -dz, dy) if ccw else G(0.0, dz, -dy)
            f.normal_update()
            if f.normal.dot(want) < 0.0:
                f.normal_flip()
        if caps and closed:
            fa = t.faces.new(a)
            fb = t.faces.new(b)
            for f, xx in ((fa, x0), (fb, x1)):
                f.normal_update()
                want = Vector((1.0 if xx > (x0 + x1) * 0.5 else -1.0, 0.0, 0.0))
                if f.normal.dot(want) < 0.0:
                    f.normal_flip()
                for loop in f.loops:
                    p = to_godot(loop.vert.co)
                    loop[uvl].uv = (p.z, -p.y)
        if uv == "box":
            _box_uv(t)
        _smooth_by_angle(t, smooth)
        self.add(t, mat)

    def extrude_y(self, prof, y0, y1, mat, closed=True, smooth=38.0):
        """A vertical moulding (a jamb): `prof` is (x, z) points swept up from y0 to y1."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        n = len(prof)
        a = [t.verts.new(G(x, y0, z)) for (x, z) in prof]
        b = [t.verts.new(G(x, y1, z)) for (x, z) in prof]
        area = 0.0
        for i in range(n):
            x0_, z0_ = prof[i]
            x1_, z1_ = prof[(i + 1) % n]
            area += x0_ * z1_ - x1_ * z0_
        ccw = area > 0.0
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            f = t.faces.new((a[i], a[j], b[j], b[i]))
            dx = prof[j][0] - prof[i][0]
            dz = prof[j][1] - prof[i][1]
            # Outward in the (x, z) plane for a CCW (x, z) loop is (dz, -dx).
            want = G(dz, 0.0, -dx) if ccw else G(-dz, 0.0, dx)
            f.normal_update()
            if f.normal.dot(want) < 0.0:
                f.normal_flip()
        _box_uv(t)
        _smooth_by_angle(t, smooth)
        self.add(t, mat)

    def box(self, c, size, mat, bevel=0.0, front_only=False, drop=(), rot=None, smooth=40.0):
        """A box centred on Godot `c` with Godot `size`, optionally bevelled (all edges, or only
        the edges of its +z face), optionally without the faces listed in `drop` ('-z', '+y'...),
        optionally turned by `rot` (a Godot-space Matrix) about its centre."""
        t = _new_bm()
        bmesh.ops.create_cube(t, size=1.0)
        for v in t.verts:
            v.co = G(v.co.x * size[0], v.co.z * size[1], -v.co.y * size[2])
        if bevel > 0.0:
            if front_only:
                edges = [e for e in t.edges if all(to_godot(v.co).z > size[2] * 0.49 for v in e.verts)]
            else:
                edges = list(t.edges)
            bmesh.ops.bevel(t, geom=edges, offset=bevel, segments=1, profile=0.5, affect='EDGES',
                            clamp_overlap=True)
        t.normal_update()
        if drop:
            kill = []
            for f in t.faces:
                n = to_godot(f.normal)
                for d in drop:
                    axis = "xyz".index(d[1])
                    sgn = 1.0 if d[0] == "+" else -1.0
                    if n[axis] * sgn > 0.99:
                        kill.append(f)
            bmesh.ops.delete(t, geom=kill, context='FACES')
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

    def bar(self, p0, p1, w, d, mat, up=(0.0, 1.0, 0.0)):
        """A square-section bar (no end caps) from Godot p0 to p1, w x d in section."""
        p0 = Vector(p0)
        p1 = Vector(p1)
        axis = (p1 - p0)
        length = axis.length
        axis.normalize()
        upv = Vector(up)
        if abs(axis.dot(upv)) > 0.95:
            upv = Vector((0.0, 0.0, 1.0))
        side = axis.cross(upv).normalized()
        upv = side.cross(axis).normalized()
        rot = Matrix((side, upv, axis)).transposed()  # columns: side, up, along
        # box() takes size in local x, y, z = side, up, along.
        self.box(tuple((p0 + p1) * 0.5), (w, d, length), mat, drop=("-z", "+z"), rot=rot)

    def cyl(self, c, r, h, mat, segs=12, axis="y", r_top=None, caps=(True, True), smooth=50.0):
        """A cylinder (or cone) centred on Godot `c`, `h` long along the Godot `axis`."""
        t = _new_bm()
        r2 = r if r_top is None else r_top
        bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=segs,
                              radius1=r, radius2=r2, depth=h)
        # Built along Blender Z (Godot y).
        kill = []
        for f in t.faces:
            if abs(f.normal.z) > 0.99 and len(f.verts) == segs:
                top = f.calc_center_median().z > 0.0
                if (top and not caps[1]) or (not top and not caps[0]):
                    kill.append(f)
        if kill:
            bmesh.ops.delete(t, geom=kill, context='FACES')
        uvl = t.loops.layers.uv.active
        for f in t.faces:
            ring = abs(f.normal.z) < 0.99
            us = []
            for loop in f.loops:
                p = loop.vert.co
                if ring:
                    ang = math.atan2(p.y, p.x) % (2.0 * math.pi)
                    us.append([ang * r, -p.z])
                else:
                    us.append([p.x, p.y])
            if ring:
                if max(u[0] for u in us) - min(u[0] for u in us) > math.pi * r:
                    for u in us:
                        if u[0] < math.pi * r:
                            u[0] += 2.0 * math.pi * r
            for loop, u in zip(f.loops, us):
                loop[uvl].uv = u
        if axis == "x":
            m = Matrix.Rotation(math.radians(90.0), 4, 'Y')
        elif axis == "z":
            m = Matrix.Rotation(math.radians(90.0), 4, 'X')
        else:
            m = Matrix.Identity(4)
        for v in t.verts:
            v.co = (m @ v.co.to_4d()).to_3d() + G(*c)
        t.normal_update()
        _smooth_by_angle(t, smooth)
        self.add(t, mat)

    def polygon_prism(self, poly, x0, x1, mat, bevel=0.0, smooth=35.0):
        """A solid from a closed (z, y) polygon swept across x0..x1, with caps (a bracket, a
        console, a keystone seen from the side)."""
        t = _new_bm()
        a = [t.verts.new(G(x0, y, z)) for (z, y) in poly]
        b = [t.verts.new(G(x1, y, z)) for (z, y) in poly]
        n = len(poly)
        for i in range(n):
            j = (i + 1) % n
            t.faces.new((a[i], b[i], b[j], a[j]))
        t.faces.new(a)
        t.faces.new(b)
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        if bevel > 0.0:
            # Round off the long edges where the sides meet the front, not the wall contact.
            edges = [e for e in t.edges if abs(e.verts[0].co.x - e.verts[1].co.x) < 1e-6
                     and min(to_godot(v.co).z for v in e.verts) > 0.012]
            bmesh.ops.bevel(t, geom=edges, offset=bevel, segments=1, profile=0.5,
                            affect='EDGES', clamp_overlap=True)
        t.normal_update()
        _box_uv(t)
        _smooth_by_angle(t, smooth)
        self.add(t, mat)

    def hexa(self, corners, mat, bevel=0.0, smooth=40.0):
        """A six-sided solid from eight Godot corners, ordered bottom (y low) -z-x, -z+x, +z+x,
        +z-x, then the top four the same way (a tapered keystone, a sloped block). With `bevel`,
        the edges of its +z face are chamfered."""
        t = _new_bm()
        v = [t.verts.new(G(*c)) for c in corners]
        for f in ((0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            t.faces.new([v[i] for i in f])
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        if bevel > 0.0:
            zmax = max(c[2] for c in corners)
            edges = [e for e in t.edges if all(to_godot(x.co).z > zmax - 1e-4 for x in e.verts)]
            bmesh.ops.bevel(t, geom=edges, offset=bevel, segments=1, profile=0.5, affect='EDGES',
                            clamp_overlap=True)
        t.normal_update()
        _box_uv(t)
        _smooth_by_angle(t, smooth)
        self.add(t, mat)

    def sheet(self, pts_rows, mat, uv_rows=None):
        """An open surface (fabric) from a grid of Godot points: rows of equal length."""
        t = _new_bm()
        uvl = t.loops.layers.uv.active
        grid = [[t.verts.new(G(*p)) for p in row] for row in pts_rows]
        for r in range(len(grid) - 1):
            for c in range(len(grid[r]) - 1):
                f = t.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
                for loop in f.loops:
                    p = to_godot(loop.vert.co)
                    loop[uvl].uv = (p.x, -p.y)
        if uv_rows:
            for r in range(len(grid)):
                for c in range(len(grid[r])):
                    for loop in grid[r][c].link_loops:
                        loop[uvl].uv = uv_rows[r][c]
        t.normal_update()
        _smooth_by_angle(t, 40.0)
        self.add(t, mat)

    def tri_fan(self, pts, mat):
        """One flat polygon (a fabric cheek) from Godot points, box-projected."""
        t = _new_bm()
        vs = [t.verts.new(G(*p)) for p in pts]
        t.faces.new(vs)
        t.normal_update()
        _box_uv(t)
        _smooth_by_angle(t, 10.0)
        self.add(t, mat)


def _godot_matrix_to_blender(m3):
    """A Godot-space 3x3 rotation as a Blender-space 3x3 (conjugated by the axis swap)."""
    swap = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot -> Blender: (x, y, z) -> (x, -z, y)
    return swap @ m3 @ swap.inverted()


def arc(cz, cy, rz, ry, a0, a1, steps):
    """Points on an ellipse arc in the (z, y) plane, a0..a1 degrees, inclusive."""
    out = []
    for i in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * i / steps)
        out.append((cz + rz * math.cos(a), cy + ry * math.sin(a)))
    return out


def cyma(z0, y0, z1, y1, steps=6):
    """An ogee (cyma recta) from (z0, y0) up and out to (z1, y1): rises steep, sweeps out, and
    turns up again at the top, like a real crown moulding."""
    out = []
    for i in range(1, steps + 1):
        t = i / steps
        out.append((z0 + (z1 - z0) * (1.0 - math.cos(math.pi * t)) * 0.5, y0 + (y1 - y0) * t))
    return out


# --- The pieces -----------------------------------------------------------------------------------

def cornice_classic():
    """Classical crown cornice: bead, frieze, cove bed mould, dentils, ovolo, corona with a drip,
    cyma recta crown. 0.95 m deep down the wall, 0.63 m out."""
    p = Piece("kit_cornice_classic", occluder="cornice")
    prof = [(-0.10, -0.95), (0.0, -0.95), (0.035, -0.95), (0.035, -0.90)]
    prof += arc(0.035, -0.87, 0.03, 0.03, -60, 60, 4)
    prof += [(0.035, -0.84), (0.035, -0.62)]
    prof += [(0.13 - 0.095 * math.cos(math.radians(a)), -0.62 + 0.095 * math.sin(math.radians(a)))
             for a in (22.5, 45.0, 67.5, 90.0)]
    prof += [(0.15, -0.525), (0.15, -0.40), (0.16, -0.40)]
    prof += [(0.16 + 0.11 * math.sin(math.radians(a)), -0.30 - 0.10 * math.cos(math.radians(a)))
             for a in (22.5, 45.0, 67.5, 90.0)]
    prof += [(0.46, -0.30), (0.46, -0.315), (0.49, -0.315), (0.49, -0.14), (0.51, -0.14), (0.51, -0.12)]
    prof += cyma(0.51, -0.12, 0.63, 0.03, 6)
    prof += [(0.63, 0.05), (0.61, 0.07), (0.0, 0.09), (-0.10, 0.09)]
    p.extrude(prof, -1.0, 1.0, "kit_stone_run")
    # Dentils: twelve blocks under the ovolo, chamfered on their faces, backs left off (they sit
    # on the band). Kept clear of the run's end rings so the mitre shear never touches them.
    n = 12
    pitch = 2.0 / n
    for k in range(n):
        x = -1.0 + (k + 0.5) * pitch
        p.box((x, -0.45, 0.1975), (0.095, 0.10, 0.095), "kit_stone_run", bevel=0.009,
              front_only=True, drop=("-z",))
    return p


def cornice_bracket():
    """Italianate bracketed cornice: tall frieze, deep soffit on scroll consoles (four a run)."""
    p = Piece("kit_cornice_bracket", occluder="cornice")
    prof = [(-0.10, -1.05), (0.0, -1.05), (0.03, -1.05), (0.03, -1.00)]
    prof += arc(0.03, -0.975, 0.025, 0.025, -60, 60, 4)
    prof += [(0.03, -0.95), (0.03, -0.42)]
    prof += [(0.08 - 0.05 * math.cos(math.radians(a)), -0.42 + 0.05 * math.sin(math.radians(a)))
             for a in (30.0, 60.0, 90.0)]
    prof += [(0.08, -0.36), (0.60, -0.36), (0.60, -0.375), (0.635, -0.375), (0.635, -0.16),
             (0.655, -0.16), (0.655, -0.14)]
    prof += cyma(0.655, -0.14, 0.78, 0.03, 6)
    prof += [(0.78, 0.06), (0.76, 0.08), (0.0, 0.10), (-0.10, 0.10)]
    p.extrude(prof, -1.0, 1.0, "kit_stone_run")
    # Scroll console: a small curl at the foot, a waist, and a long sweep out to the soffit.
    console = [(0.03, -0.98), (0.075, -0.975), (0.105, -0.95), (0.11, -0.915), (0.095, -0.885),
               (0.085, -0.85), (0.10, -0.78), (0.15, -0.68), (0.23, -0.58), (0.33, -0.50),
               (0.44, -0.44), (0.54, -0.40), (0.585, -0.375), (0.59, -0.36), (0.03, -0.36)]
    for xc in (-0.75, -0.25, 0.25, 0.75):
        p.polygon_prism(console, xc - 0.065, xc + 0.065, "kit_stone_run", bevel=0.012)
    return p


def cornice_simple():
    """A plain stepped cornice for stucco and precast walls: fillets, a cove, a flat corona."""
    p = Piece("kit_cornice_simple", occluder="cornice")
    prof = [(-0.10, -0.52), (0.0, -0.52), (0.03, -0.52), (0.03, -0.46), (0.06, -0.46), (0.06, -0.42)]
    prof += [(0.15 - 0.09 * math.cos(math.radians(a)), -0.42 + 0.09 * math.sin(math.radians(a)))
             for a in (22.5, 45.0, 67.5, 90.0)]
    prof += [(0.17, -0.33), (0.17, -0.26), (0.19, -0.24), (0.26, -0.24), (0.28, -0.22),
             (0.28, -0.05), (0.26, -0.03), (0.26, 0.02), (0.24, 0.04), (0.0, 0.06), (-0.10, 0.06)]
    p.extrude(prof, -1.0, 1.0, "kit_stone_run")
    return p


def coping():
    """Parapet coping stone: overhangs both faces with drip grooves, top weathered to shed water.
    y = 0 is the top of the parapet wall, which runs z -0.42 .. 0.05 (Building's parapet box)."""
    p = Piece("kit_coping", occluder="coping")
    prof = [(0.05, -0.02), (-0.42, -0.02), (-0.42, 0.0), (-0.445, 0.0), (-0.445, 0.012),
            (-0.455, 0.012), (-0.455, 0.0), (-0.48, 0.0), (-0.49, 0.01), (-0.49, 0.09),
            (-0.48, 0.10), (-0.19, 0.14), (0.10, 0.10), (0.11, 0.09), (0.11, 0.01), (0.10, 0.0),
            (0.085, 0.0), (0.085, 0.012), (0.075, 0.012), (0.075, 0.0), (0.05, 0.0)]
    p.extrude(prof, -1.0, 1.0, "kit_stone_run", smooth=30.0)
    return p


def _stone_sill(p, lug=0.08, thick=0.11, out=0.08):
    """A stone sill under a 1 x 1 opening: weathered top, rounded nose, drip groove, lugs."""
    y = -0.5
    prof = [(-0.06, y), (0.0, y), (out - 0.01, y - 0.022), (out, y - 0.03), (out, y - thick + 0.01),
            (out - 0.01, y - thick), (out - 0.02, y - thick), (out - 0.02, y - thick + 0.013),
            (out - 0.03, y - thick + 0.013), (out - 0.03, y - thick), (-0.06, y - thick)]
    p.extrude(prof, -0.5 - lug, 0.5 + lug, "kit_stone", caps=True, uv="box")


def surround_brick_a():
    """Brick punched window: stone sill with lugs, flat stone lintel with a keystone."""
    p = Piece("kit_surround_brick_a", occluder="window")
    _stone_sill(p)
    # Lintel: into the brick 12 cm each side, 22 cm tall, proud of the wall by 3.5 cm.
    p.box((0.0, 0.61, -0.0025), (1.24, 0.22, 0.075), "kit_stone", bevel=0.012, front_only=True, drop=("-z",))
    # Keystone: wider at the top than at the bottom, standing proud of the lintel. It sits in
    # the stretched middle of the piece, so it widens a little with the window, as they do.
    lo, hi, zb, zf = 0.5, 0.765, -0.04, 0.062
    p.hexa([(-0.07, lo, zb), (0.07, lo, zb), (0.07, lo, zf), (-0.07, lo, zf),
            (-0.092, hi, zb), (0.092, hi, zb), (0.092, hi, zf), (-0.092, hi, zf)], "kit_stone", bevel=0.01)
    return p


def surround_brick_b():
    """Brick window, plainer: a slab sill and a lintel with raised end blocks (no keystone)."""
    p = Piece("kit_surround_brick_b", occluder="window")
    _stone_sill(p, lug=0.06, thick=0.09, out=0.065)
    p.box((0.0, 0.59, -0.005), (1.16, 0.18, 0.07), "kit_stone", bevel=0.01, front_only=True, drop=("-z",))
    for sx in (-1.0, 1.0):
        p.box((sx * 0.555, 0.60, 0.0), (0.13, 0.22, 0.08), "kit_stone", bevel=0.012, front_only=True, drop=("-z",))
    return p


def surround_stucco():
    """Stucco window: moulded architrave (jambs and head), frieze, hood cornice, sill on corbels."""
    p = Piece("kit_surround_stucco", occluder="window")
    # Jamb profile across the jamb (x, z): fascia, a step, a bead at the outer edge.
    jamb = [(-0.50, 0.0), (-0.50, 0.022), (-0.555, 0.022), (-0.56, 0.034), (-0.595, 0.034),
            (-0.605, 0.046), (-0.615, 0.040), (-0.62, 0.02), (-0.62, 0.0)]
    p.extrude_y(jamb, -0.5, 0.5, "kit_stone")
    p.extrude_y([(-x, z) for (x, z) in reversed(jamb)], -0.5, 0.5, "kit_stone")
    # Head of the architrave: the same moulding turned along x, sitting on the jambs.
    head = [(0.0, 0.62), (0.02, 0.62), (0.04, 0.615), (0.046, 0.605), (0.034, 0.595),
            (0.034, 0.56), (0.022, 0.555), (0.022, 0.5), (0.0, 0.5)]
    p.extrude(head, -0.62, 0.62, "kit_stone", caps=True, uv="box")
    # Frieze and hood cornice.
    p.box((0.0, 0.685, 0.005), (1.24, 0.13, 0.03), "kit_stone", drop=("-z",))
    hood = [(0.0, 0.75), (0.03, 0.75)]
    hood += [(0.08 - 0.05 * math.cos(math.radians(a)), 0.75 + 0.04 * math.sin(math.radians(a))) for a in (30, 60, 90)]
    hood += [(0.10, 0.79), (0.10, 0.845), (0.11, 0.845)]
    hood += cyma(0.11, 0.845, 0.145, 0.90, 4)
    hood += [(0.145, 0.915), (0.0, 0.93)]
    p.extrude(hood, -0.72, 0.72, "kit_stone", caps=True, uv="box")
    # Sill with a bullnose, on two small corbels.
    sill = [(-0.05, -0.5), (0.0, -0.5), (0.055, -0.505)]
    sill += arc(0.055, -0.54, 0.02, 0.035, 90, -90, 4)[1:]
    sill += [(0.0, -0.575), (-0.05, -0.575)]
    p.extrude(sill, -0.66, 0.66, "kit_stone", caps=True, uv="box")
    corbel = [(0.0, -0.575), (0.05, -0.575), (0.05, -0.61), (0.03, -0.66), (0.0, -0.69)]
    for sx in (-1.0, 1.0):
        p.polygon_prism(corbel, sx * 0.60 - 0.035, sx * 0.60 + 0.035, "kit_stone")
    return p


def ac_window():
    """A through-window air conditioner sitting on the sill: painted case, front louvres over a
    dark grille, side vents, two angle brackets to the wall. Origin at the middle of its bottom
    at the wall face; it pokes 0.18 m back into the opening."""
    p = Piece("kit_ac_window", occluder="window_low", ao_distance=0.25)
    p.box((0.0, 0.21, 0.09), (0.66, 0.42, 0.54), "kit_paint", bevel=0.014)
    # Front grille: dark panel, then louvre slats angled down.
    p.box((0.0, 0.205, 0.362), (0.58, 0.33, 0.01), "kit_dark", drop=("-z",))
    tilt = Matrix.Rotation(math.radians(-28.0), 3, 'X')
    for k in range(8):
        y = 0.065 + k * 0.04
        p.box((0.0, y, 0.372), (0.575, 0.012, 0.03), "kit_paint", rot=tilt)
    # Side vents: a dark panel with slots on each side.
    for sx in (-1.0, 1.0):
        p.box((sx * 0.332, 0.25, 0.20), (0.008, 0.20, 0.24), "kit_dark", drop=("-x" if sx > 0 else "+x",))
        for k in range(4):
            p.box((sx * 0.337, 0.25, 0.10 + k * 0.066), (0.008, 0.19, 0.018), "kit_paint")
    # Control panel strip and a drip spout.
    p.box((0.25, 0.40, 0.366), (0.10, 0.03, 0.006), "kit_dark")
    p.cyl((-0.26, -0.01, 0.30), 0.012, 0.05, "kit_dark", segs=6)
    # Angle brackets under the case: an arm under it and a diagonal strut back to the wall.
    for sx in (-0.24, 0.24):
        p.box((sx, -0.012, 0.17), (0.03, 0.024, 0.36), "kit_iron")
        p.bar((sx, -0.32, 0.005), (sx, -0.02, 0.31), 0.025, 0.02, "kit_iron")
        p.box((sx, -0.30, 0.006), (0.05, 0.08, 0.012), "kit_iron")
    return p


def awning():
    """Shop awning, 1 m nominal (the shader stretches the middle to the shop's width): canvas
    slope with a little sag, a hemmed valance, closed side cheeks, wall and front bars."""
    p = Piece("kit_awning", occluder="wall", ao_distance=0.5)
    reach, drop, val = 1.25, 0.80, 0.26
    slope = []
    for i in range(6):
        t = i / 5.0
        z = 0.03 + (reach - 0.03) * t
        y = -drop * t - 0.035 * math.sin(math.pi * t)
        slope.append((z, y))
    slope += [(reach + 0.01, -drop - 0.03), (reach + 0.015, -drop - val + 0.03), (reach + 0.02, -drop - val)]
    rows = [[(x, y, z) for (z, y) in slope] for x in (-0.5, 0.5)]
    # Rows run across x, points run down the slope: transpose to rows along the slope.
    grid = [[rows[0][i], rows[1][i]] for i in range(len(slope))]
    p.sheet(grid, "kit_fabric")
    for sx in (-0.5, 0.5):
        cheek = [(sx, 0.0, 0.03)] + [(sx, y, z) for (z, y) in slope[1:6]] + [(sx, -drop, 0.03)]
        p.tri_fan(cheek, "kit_fabric")
    # Frame: a bar along the wall at the top and one inside the front edge.
    p.cyl((0.0, 0.0, 0.03), 0.018, 1.0, "kit_iron", segs=6, axis="x", caps=(False, False))
    p.cyl((0.0, -drop + 0.01, reach - 0.02), 0.016, 1.0, "kit_iron", segs=6, axis="x", caps=(False, False))
    return p


def balcony():
    """A balcony, 2.2 m wide, 1.2 m deep, rail 1.1 m: slab with a moulded nosing on two stone
    corbels, iron railing with square balusters and corner posts."""
    p = Piece("kit_balcony", occluder="wall", ao_distance=0.45)
    slab = [(-0.05, 0.0), (1.17, 0.0), (1.20, -0.015), (1.22, -0.04), (1.22, -0.075), (1.20, -0.09),
            (1.16, -0.10), (1.14, -0.16), (-0.05, -0.16)]
    p.extrude(slab, -1.12, 1.12, "kit_stone", caps=True, uv="box")
    corbel = [(0.0, -0.16), (0.95, -0.16), (0.93, -0.22), (0.80, -0.26), (0.55, -0.30),
              (0.32, -0.38), (0.16, -0.50), (0.07, -0.62), (0.0, -0.66)]
    for xc in (-0.82, 0.82):
        p.polygon_prism(corbel, xc - 0.07, xc + 0.07, "kit_stone", bevel=0.012)
    # Railing. Only the top rail along the front is bevelled - it is the one that catches the
    # light; a balcony is on a hundred bays of a block, so every other member stays square.
    top, low = 1.08, 0.12
    p.box((0.0, top, 1.17), (2.18, 0.045, 0.06), "kit_iron", bevel=0.008)
    p.box((0.0, low, 1.17), (2.14, 0.03, 0.03), "kit_iron", drop=("-x", "+x"))
    p.box((0.0, top - 0.08, 1.17), (2.14, 0.02, 0.02), "kit_iron", drop=("-x", "+x"))
    for sx in (-1.08, 1.08):
        p.box((sx, top, 0.585), (0.045, 0.045, 1.17), "kit_iron", drop=("-z", "+z"))
        p.box((sx, low, 0.585), (0.03, 0.03, 1.13), "kit_iron", drop=("-z", "+z"))
        # Corner posts.
        p.box((sx, top * 0.5, 1.17), (0.05, top, 0.05), "kit_iron", drop=("-y", "+y"))
    for i in range(19):
        x = -0.99 + i * 0.11
        p.bar((x, low, 1.17), (x, top - 0.02, 1.17), 0.018, 0.018, "kit_iron")
    for sx in (-1.08, 1.08):
        for i in range(7):
            z = 0.10 + i * 0.15
            p.bar((sx, low, z), (sx, top - 0.02, z), 0.018, 0.018, "kit_iron")
    return p


def _fe_landing(p, ladder=False):
    """One fire-escape landing, 2.4 m wide and 1.3 m deep, deck at y = 0: angle frame, slatted
    deck, bearers, knee braces to the wall, railing."""
    w, d = 2.4, 1.3
    hw = w * 0.5
    for z in (0.045, d - 0.03):
        p.box((0.0, -0.04, z), (w, 0.08, 0.035), "kit_iron")
    for sx in (-hw + 0.02, hw - 0.02):
        p.box((sx, -0.04, d * 0.5), (0.035, 0.08, d - 0.05), "kit_iron")
    for k in range(12):
        z = 0.12 + k * (d - 0.22) / 11.0
        p.bar((-hw + 0.03, -0.012, z), (hw - 0.03, -0.012, z), 0.03, 0.022, "kit_iron")
    for x in (-0.6, 0.6):
        p.bar((x, -0.075, 0.03), (x, -0.075, d - 0.05), 0.03, 0.05, "kit_iron")
    for x in (-1.0, 1.0):
        p.bar((x, -0.95, 0.02), (x, -0.08, d - 0.12), 0.035, 0.035, "kit_iron")
        p.box((x, -0.95, 0.01), (0.12, 0.16, 0.02), "kit_iron")
    top, mid = 1.0, 0.52
    p.box((0.0, top, d - 0.02), (w, 0.035, 0.04), "kit_iron")
    p.box((0.0, mid, d - 0.02), (w - 0.04, 0.022, 0.022), "kit_iron")
    for sx in (-hw + 0.02, hw - 0.02):
        p.box((sx, top, d * 0.5), (0.035, 0.035, d), "kit_iron")
        p.box((sx, mid, d * 0.5), (0.022, 0.022, d - 0.04), "kit_iron")
        p.bar((sx, 0.0, d - 0.02), (sx, top, d - 0.02), 0.035, 0.035, "kit_iron")
    for i in range(13):
        x = -hw + 0.18 + i * (w - 0.36) / 12.0
        p.bar((x, 0.0, d - 0.02), (x, top - 0.02, d - 0.02), 0.016, 0.016, "kit_iron")
    for sx in (-hw + 0.02, hw - 0.02):
        for i in range(5):
            z = 0.2 + i * 0.2
            p.bar((sx, 0.0, z), (sx, top - 0.02, z), 0.016, 0.016, "kit_iron")
    if ladder:
        # A drop ladder, stowed: hanging from the front rail at one end, above the pavement.
        x0 = 0.55
        for x in (x0, x0 + 0.42):
            p.bar((x, top, d + 0.04), (x, -2.3, d + 0.04), 0.04, 0.02, "kit_iron")
        for k in range(11):
            y = -2.15 + k * 0.30
            p.bar((x0, y, d + 0.04), (x0 + 0.42, y, d + 0.04), 0.022, 0.022, "kit_iron")


def _fe_stair(p, sign):
    """The stair down to the landing below (3.5 m storey), in the outer half of the deck,
    descending toward `sign` * x."""
    rise = 3.5
    x_top, x_bot = -sign * 0.95, sign * 0.95
    for z in (0.66, 1.20):
        p.bar((x_top, -0.04, z), (x_bot, -rise + 0.02, z), 0.02, 0.16, "kit_iron")
    steps = 14
    for k in range(1, steps):
        t = k / steps
        x = x_top + (x_bot - x_top) * t
        y = -rise * t
        p.box((x, y, 0.93), (0.20, 0.022, 0.52), "kit_iron")
    p.bar((x_top, 0.95, 1.22), (x_bot, -rise + 0.95, 1.22), 0.03, 0.03, "kit_iron")
    for t in (0.33, 0.66):
        x = x_top + (x_bot - x_top) * t
        y = -rise * t
        p.bar((x, y, 1.21), (x, y + 0.93, 1.21), 0.02, 0.02, "kit_iron")


def fe_stair_l():
    p = Piece("kit_fe_stair_l", occluder="wall", ao_distance=0.4)
    _fe_landing(p)
    _fe_stair(p, -1.0)
    return p


def fe_stair_r():
    p = Piece("kit_fe_stair_r", occluder="wall", ao_distance=0.4)
    _fe_landing(p)
    _fe_stair(p, 1.0)
    return p


def fe_bottom():
    p = Piece("kit_fe_bottom", occluder="wall", ao_distance=0.4)
    _fe_landing(p, ladder=True)
    return p


def water_tank():
    """A timber rooftop water tank on a steel stand: staves, steel hoops, a conical roof with a
    finial, braced legs and a ladder. Origin at the roof deck, centred."""
    p = Piece("kit_water_tank", occluder="ground", ao_distance=1.2)
    leg_h = 2.6
    for sx in (-1.15, 1.15):
        for sz in (-1.15, 1.15):
            p.box((sx, leg_h * 0.5, sz), (0.12, leg_h, 0.12), "kit_iron", bevel=0.01)
            p.box((sx, 0.015, sz), (0.3, 0.03, 0.3), "kit_iron")
    for sz in (-1.15, 1.15):
        p.box((0.0, leg_h, sz), (2.44, 0.14, 0.12), "kit_iron")
    for sx in (-1.15, 1.15):
        p.box((sx, leg_h, 0.0), (0.12, 0.14, 2.3), "kit_iron")
    for sx in (-0.45, 0.45):
        p.box((sx, leg_h + 0.1, 0.0), (0.14, 0.08, 2.3), "kit_iron")
    # Cross bracing, an X on each of the four sides.
    for axis, c in (("z", 1.15), ("z", -1.15), ("x", 1.15), ("x", -1.15)):
        for flip in (-1.0, 1.0):
            if axis == "z":
                a, b = (-1.1 * flip, 0.25, c), (1.1 * flip, leg_h - 0.12, c)
            else:
                a, b = (c, 0.25, -1.1 * flip), (c, leg_h - 0.12, 1.1 * flip)
            p.bar(a, b, 0.035, 0.012, "kit_iron")
    # Tank.
    base = leg_h + 0.14
    tank_h, r = 3.2, 1.55
    p.cyl((0.0, base + tank_h * 0.5, 0.0), r, tank_h, "kit_wood", segs=24, caps=(True, False), smooth=20.0)
    for k in range(5):
        y = base + 0.25 + k * (tank_h - 0.5) / 4.0
        p.cyl((0.0, y, 0.0), r + 0.018, 0.05, "kit_iron", segs=24, caps=(False, False), smooth=20.0)
    # Roof: an eave ring and a shallow cone, a finial on top.
    p.cyl((0.0, base + tank_h + 0.04, 0.0), r + 0.06, 0.08, "kit_wood", segs=24, smooth=20.0)
    p.cyl((0.0, base + tank_h + 0.08 + 0.45, 0.0), r + 0.06, 0.9, "kit_wood", segs=24, r_top=0.06,
          caps=(False, False), smooth=20.0)
    p.cyl((0.0, base + tank_h + 1.05, 0.0), 0.07, 0.2, "kit_iron", segs=8)
    # Ladder up the side to the roof.
    for x in (-0.22, 0.22):
        p.bar((x, 0.0, 1.62), (x, base + tank_h + 0.3, 1.62), 0.04, 0.02, "kit_iron")
    for k in range(18):
        y = 0.3 + k * 0.34
        p.bar((-0.22, y, 1.62), (0.22, y, 1.62), 0.022, 0.022, "kit_iron")
    return p


def vent_mushroom():
    p = Piece("kit_vent_mushroom", occluder="ground", ao_distance=0.3)
    p.cyl((0.0, 0.03, 0.0), 0.26, 0.06, "kit_paint", segs=14)
    p.cyl((0.0, 0.30, 0.0), 0.17, 0.48, "kit_paint", segs=14, caps=(False, False))
    p.cyl((0.0, 0.575, 0.0), 0.17, 0.07, "kit_paint", segs=14, r_top=0.33, caps=(False, False))
    p.cyl((0.0, 0.64, 0.0), 0.33, 0.06, "kit_paint", segs=14, caps=(True, False))
    p.cyl((0.0, 0.72, 0.0), 0.33, 0.10, "kit_paint", segs=14, r_top=0.06, caps=(False, True))
    return p


def vent_turbine():
    p = Piece("kit_vent_turbine", occluder="ground", ao_distance=0.3)
    p.box((0.0, 0.05, 0.0), (0.5, 0.1, 0.5), "kit_paint", bevel=0.01)
    p.cyl((0.0, 0.32, 0.0), 0.16, 0.44, "kit_paint", segs=12, caps=(False, False))
    # Turbine head: ribbed drum and a dome.
    t = _new_bm()
    segs, r0, r1, y0, y1 = 32, 0.24, 0.27, 0.54, 0.84
    ring0, ring1 = [], []
    for i in range(segs):
        a = 2.0 * math.pi * i / segs
        rr = r1 if i % 2 == 0 else r0
        ring0.append(t.verts.new(G(rr * math.cos(a), y0, rr * math.sin(a))))
        ring1.append(t.verts.new(G(rr * math.cos(a + 0.35), y1, rr * math.sin(a + 0.35))))
    for i in range(segs):
        j = (i + 1) % segs
        t.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
    bmesh.ops.recalc_face_normals(t, faces=t.faces)
    for f in t.faces:
        c = to_godot(f.calc_center_median())
        n = to_godot(f.normal)
        if Vector((c.x, 0.0, c.z)).dot(Vector((n.x, 0.0, n.z))) < 0.0:
            f.normal_flip()
    _box_uv(t)
    _smooth_by_angle(t, 30.0)
    p.add(t, "kit_paint")
    p.cyl((0.0, 0.93, 0.0), 0.27, 0.18, "kit_paint", segs=16, r_top=0.05, caps=(True, False))
    p.cyl((0.0, 0.545, 0.0), 0.25, 0.03, "kit_paint", segs=16)
    return p


def hvac():
    """A packaged rooftop unit, 2.4 x 1.15 x 1.3 m: bevelled case on two base rails, two fans
    under guards in the top, a louvred condenser side, service doors with handles."""
    p = Piece("kit_hvac", occluder="ground", ao_distance=0.6)
    L, H, D = 2.4, 1.15, 1.3
    for z in (-0.5, 0.5):
        p.box((0.0, 0.05, z), (L + 0.1, 0.1, 0.12), "kit_iron")
    p.box((0.0, 0.1 + H * 0.5, 0.0), (L, H, D), "kit_paint", bevel=0.02)
    top = 0.1 + H
    for xc in (-0.55, 0.55):
        p.cyl((xc, top + 0.004, 0.0), 0.42, 0.012, "kit_dark", segs=20)
        p.cyl((xc, top + 0.03, 0.0), 0.44, 0.05, "kit_paint", segs=20, caps=(False, False))
        p.cyl((xc, top + 0.05, 0.0), 0.07, 0.06, "kit_dark", segs=10)
        for k in range(4):
            rot = Matrix.Rotation(math.radians(45.0 * k + 10.0), 3, 'Y') @ Matrix.Rotation(math.radians(18.0), 3, 'X')
            p.box((xc, top + 0.03, 0.0), (0.72, 0.008, 0.13), "kit_dark", rot=rot)
        for k in range(5):
            p.box((xc, top + 0.06, -0.36 + k * 0.18), (0.86, 0.01, 0.012), "kit_iron")
    # Louvred condenser side (+z).
    p.box((0.35, 0.1 + H * 0.5, D * 0.5 + 0.004), (1.4, 0.8, 0.01), "kit_dark", drop=("-z",))
    tilt = Matrix.Rotation(math.radians(-30.0), 3, 'X')
    for k in range(10):
        p.box((0.35, 0.33 + k * 0.075, D * 0.5 + 0.02), (1.38, 0.01, 0.04), "kit_paint", rot=tilt)
    # Service doors on the other half (-x) of the +z side, and on the -z side.
    for sz in (1.0, -1.0):
        for xc in (-0.95, -0.55):
            p.box((xc, 0.1 + H * 0.5, sz * (D * 0.5 + 0.004)), (0.36, 0.9, 0.008), "kit_paint", bevel=0.003)
            p.box((xc + 0.12, 0.1 + H * 0.55, sz * (D * 0.5 + 0.016)), (0.03, 0.12, 0.02), "kit_dark")
    return p


PIECES = [cornice_classic, cornice_bracket, cornice_simple, coping, surround_brick_a,
          surround_brick_b, surround_stucco, ac_window, awning, balcony, fe_stair_l, fe_stair_r,
          fe_bottom, water_tank, vent_mushroom, vent_turbine, hvac]


# --- Occluders for the AO bake --------------------------------------------------------------------

def _plane(name, corners):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([G(*c) for c in corners], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def make_occluders(kind):
    """What stands round a piece in the city, so the bake darkens it where the wall is."""
    out = []
    if kind in ("wall", "window", "window_low", "cornice"):
        top = 0.0 if kind == "cornice" else 4.0
        if kind in ("window", "window_low"):
            # A wall with the 1 x 1 opening left open.
            out.append(_plane("occ_l", [(-4, -4, 0), (-0.5, -4, 0), (-0.5, 4, 0), (-4, 4, 0)]))
            out.append(_plane("occ_r", [(0.5, -4, 0), (4, -4, 0), (4, 4, 0), (0.5, 4, 0)]))
            out.append(_plane("occ_b", [(-0.5, -4, 0), (0.5, -4, 0), (0.5, -0.5, 0), (-0.5, -0.5, 0)]))
            out.append(_plane("occ_t", [(-0.5, 0.5, 0), (0.5, 0.5, 0), (0.5, 4, 0), (-0.5, 4, 0)]))
        else:
            out.append(_plane("occ_wall", [(-4, -6, 0), (4, -6, 0), (4, top, 0), (-4, top, 0)]))
        if kind == "cornice":
            out.append(_plane("occ_roof", [(-4, 0, 0), (-4, 0, -4), (4, 0, -4), (4, 0, 0)]))
    elif kind == "coping":
        out.append(_plane("occ_po", [(-4, -3, 0.05), (4, -3, 0.05), (4, 0, 0.05), (-4, 0, 0.05)]))
        out.append(_plane("occ_pi", [(-4, -3, -0.42), (-4, 0, -0.42), (4, 0, -0.42), (4, -3, -0.42)]))
    elif kind == "ground":
        out.append(_plane("occ_ground", [(-8, 0, -8), (8, 0, -8), (8, 0, 8), (-8, 0, 8)]))
    return out


def bake_ao(obj, piece):
    """Cycles AO into a corner colour attribute, then into UV2.x as occlusion (1 - AO)."""
    mesh = obj.data
    attr = mesh.color_attributes.new("ao", 'FLOAT_COLOR', 'CORNER')
    mesh.color_attributes.active_color = attr
    occ = make_occluders(piece.occluder)
    for o in bpy.context.scene.objects:
        o.hide_render = not (o == obj or o in occ)
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
    for o in occ:
        bpy.data.objects.remove(o, do_unlink=True)
    for o in bpy.context.scene.objects:
        o.hide_render = False


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 48
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
        xs = [v.co.x for v in mesh.vertices]
        report.append("%-22s %5d tris  x %.3f..%.3f  mats %s" % (piece.name, tris, min(xs), max(xs), ",".join(piece.mats)))
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
    print("facade kit ->", os.path.abspath(OUT))
    for line in report:
        print("  " + line)


main()
