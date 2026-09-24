#!/usr/bin/env python3
"""The concert hall of the civic centre (landmark `concert_hall`, "SYMPHONY HALL"), built in Blender.

    blender -b --factory-startup --python tools/make_concert_hall.py
    blender -b --factory-startup --python tools/make_concert_hall.py -- --out some/other.glb

Writes assets/models/concert_hall.glb. Run `godot --headless --path . --import` after it, before
any render: Godot serves a cached import of a .glb (CLAUDE.md, measurement traps).

WHAT IT IS
----------
The FORM of downtown's steel concert hall - an auditorium box wrapped in curving stainless steel
sails that bow out and curl back as they rise, opening like petals over the entrance at the
corner that faces the park and downtown, lower and tighter round a garden side, glazing in the
gaps between them at street level. The composition, sail count, curves and proportions are this
game's own; nothing was traced from drawings of the real building.

HOW IT IS BUILT
---------------
Each sail is one structured grid: a foot curve on the podium (a chord from `a` to `b` bowed out
by `bulge`), a height that runs from h0 to h1 along it with a `crest`, and a displacement
outward from the foot that grows as `lean * v^2` (the curl) plus `billow * sin(pi u) sin(pi v)`
(the belly). Solidified to real thickness, bevelled on its edges so the rims catch the light,
weighted normals. UV is METRES - u along the foot, v up the sail - because the game's
brushed_steel shader lays the panel seams and the brushing in those metres.

CONTRACT WITH THE GAME (scripts/world/landmark_civic_center.gd)
---------------------------------------------------------------
Game frame: X east, Y up, Z south (Blender X, -Y, Z). Origin at the centre of the site on top of
the podium; the entrance faces south-west. Materials by name, which the game replaces:
  steel  -> shaders/brushed_steel.gdshader     glass -> shaders/curtain_glass.gdshader
  stone  -> landmark_facade (the auditorium's base)
One extra object, `Collision`: the sails at low resolution plus the core, which the game turns
into a trimesh shape and never draws (model_mesh() excludes names containing "collision").
Footprint about 72 x 66 m, top about 38 m; the game scales it down to fit a smaller block.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[ARGS.index("--out") + 1]) if "--out" in ARGS else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "concert_hall.glb")

# Sails: foot a -> b (game x, z), bulge of the foot, height at a / at b, crest in the middle,
# curl, belly. Listed round the building from the entrance, anticlockwise seen from above.
SAILS = [
    # The entrance petals over the south-west corner: the tallest, curling out over the doors.
    ((-35.0, 16.0), (-24.0, 31.0), 4.0, 20.0, 31.0, 3.0, 7.0, 2.5),
    ((-20.0, 32.0), (-3.0, 30.0), 3.0, 32.0, 25.0, 3.0, 6.0, 2.0),
    ((-27.0, 7.0), (-9.0, 22.0), 3.5, 33.0, 38.0, 2.0, 8.5, 3.0),
    # The south face and the south-east corner.
    ((1.0, 31.0), (21.0, 28.0), 2.5, 22.0, 27.0, 2.0, 3.5, 2.0),
    ((20.0, 27.0), (35.0, 11.0), 4.0, 27.0, 33.0, 3.0, 7.5, 2.5),
    ((11.0, 19.0), (27.0, 3.0), 2.0, 35.0, 36.0, 3.0, 5.5, 2.0),
    # The long east face.
    ((36.0, 7.0), (35.0, -15.0), 3.0, 29.0, 27.0, 3.0, 3.0, 3.0),
    # North-east, north.
    ((33.0, -19.0), (18.0, -32.0), 3.5, 30.0, 22.0, 2.0, 5.0, 2.0),
    ((14.0, -33.0), (-8.0, -33.0), 2.0, 24.0, 24.0, 2.0, 2.5, 1.5),
    # The garden side: lower, tighter sails round the north-west.
    ((-12.0, -32.0), (-29.0, -19.0), 3.0, 18.0, 14.0, 2.0, 4.5, 2.0),
    ((-24.0, -24.0), (-12.0, -12.0), 2.5, 23.0, 27.0, 2.0, 5.0, 1.5),
    # The west face.
    ((-36.0, -13.0), (-36.0, 11.0), 3.0, 22.0, 20.0, 2.5, 3.5, 2.5),
]
# The auditorium box the sails wrap: centre (x, z), size (x, y, z) - game frame.
CORE = ((4.0, -4.0), (30.0, 27.0, 38.0))
# Street-level glazing between the entrance sails: a polyline (x, z) and its height.
GLASS_LINE = [(-31.0, 13.0), (-27.0, 22.0), (-20.0, 27.5), (-11.0, 28.5), (-2.0, 27.0)]
GLASS_H = 9.5
THICK = 0.35
# Grid resolution per sail: along the foot, up the sail. The collision copy is much coarser.
NU, NV = 28, 18
NU_COL, NV_COL = 7, 4


def G(x, y, z):
    """Game frame (x east, y up, z south) to Blender (x, y north, z up)."""
    return Vector((x, -z, y))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, metallic, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return m


def sail_grid(a, b, bulge, h0, h1, crest, lean, belly, nu, nv):
    """Vertices [i][j] (game frame) and the foot length, for one sail."""
    ax, az = a
    bx, bz = b
    tx, tz = bx - ax, bz - az
    length = math.hypot(tx, tz)
    px, pz = -tz / length, tx / length
    mx, mz = (ax + bx) * 0.5, (az + bz) * 0.5
    # Outward: away from the centre of the building.
    if px * (mx - CORE[0][0] * 0.3) + pz * (mz - CORE[0][1] * 0.3) < 0.0:
        px, pz = -px, -pz
    grid = []
    for i in range(nu + 1):
        u = i / nu
        s = math.sin(math.pi * u)
        fx = ax + tx * u + px * bulge * s
        fz = az + tz * u + pz * bulge * s
        h = h0 + (h1 - h0) * u + crest * s
        col = []
        for j in range(nv + 1):
            v = j / nv
            d = lean * v * v + belly * s * math.sin(math.pi * v)
            col.append((fx + px * d, h * v, fz + pz * d))
        grid.append(col)
    return grid, length, (px, pz)


def grid_object(name, grid, length, out_dir, mat, uv=True):
    """A bmesh surface from a vertex grid, faces facing out, UVs in metres."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap") if uv else None
    nu = len(grid) - 1
    nv = len(grid[0]) - 1
    verts = [[bm.verts.new(G(*grid[i][j])) for j in range(nv + 1)] for i in range(nu + 1)]
    ox, oz = out_dir
    for i in range(nu):
        for j in range(nv):
            quad = [verts[i][j], verts[i + 1][j], verts[i + 1][j + 1], verts[i][j + 1]]
            f = bm.faces.new(quad)
            f.normal_update()
            # Face the outward side (Blender: game z is -y).
            outward = Vector((ox, -oz, 0.0))
            if f.normal.dot(outward) < 0.0:
                f.normal_flip()
            if uv_layer:
                for loop in f.loops:
                    vi = None
                    for ii in (i, i + 1):
                        for jj in (j, j + 1):
                            if verts[ii][jj] == loop.vert:
                                vi = (ii, jj)
                    u_m = length * vi[0] / nu
                    v_m = grid[vi[0]][vi[1]][1]
                    loop[uv_layer].uv = (u_m, v_m)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def finish(obj, thick, bevel=0.07):
    """Solidify, bevel the rims, weight the normals, apply."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    sol = obj.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = thick
    sol.offset = -1.0
    sol.use_even_offset = True
    bev = obj.modifiers.new("bevel", "BEVEL")
    bev.width = bevel
    bev.segments = 2
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(35.0)
    wn = obj.modifiers.new("wn", "WEIGHTED_NORMAL")
    wn.keep_sharp = True
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    obj.select_set(False)


def box_object(name, center, size, mat, bevel=0.15):
    """A box in the game frame: center (x, y, z) of its base... centre, size (x, y, z)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        x, y, z = v.co.x * size[0], v.co.z * size[1], -v.co.y * size[2]
        v.co = G(center[0] + x, center[1] + y, center[2] + z)
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        n = f.normal
        for loop in f.loops:
            p = loop.vert.co
            # Metres: along the face horizontally, up by height (Blender z).
            if abs(n.z) > 0.5:
                loop[uv_layer].uv = (p.x, p.y)
            elif abs(n.x) > 0.5:
                loop[uv_layer].uv = (p.y, p.z)
            else:
                loop[uv_layer].uv = (p.x, p.z)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        b = obj.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
        bpy.ops.object.modifier_apply(modifier=b.name)
        obj.select_set(False)
    return obj


def glass_strip(name, line, h, mat):
    grid = []
    for (x, z) in line:
        grid.append([(x, 0.0, z), (x, h, z)])
    # Outward for the entrance glazing is south-west.
    length = sum(math.hypot(line[k + 1][0] - line[k][0], line[k + 1][1] - line[k][1]) for k in range(len(line) - 1))
    obj = grid_object(name, grid, length, (-0.7, 0.7), mat)
    return obj


def main():
    reset()
    steel = material("steel", (0.78, 0.79, 0.80), 1.0, 0.25)
    glass = material("glass", (0.16, 0.19, 0.21), 0.0, 0.05)
    stone = material("stone", (0.78, 0.72, 0.64), 0.0, 0.8)
    colmat = material("collision", (1.0, 0.0, 1.0), 0.0, 1.0)
    parts = []
    col_parts = []
    report = []
    for k, (a, b, bulge, h0, h1, crest, lean, belly) in enumerate(SAILS):
        grid, length, out = sail_grid(a, b, bulge, h0, h1, crest, lean, belly, NU, NV)
        obj = grid_object("Sail_%02d" % k, grid, length, out, steel)
        finish(obj, THICK)
        parts.append(obj)
        cg, cl, co = sail_grid(a, b, bulge, h0, h1, crest, lean, belly, NU_COL, NV_COL)
        col_parts.append(grid_object("ColSail_%02d" % k, cg, cl, co, colmat, uv=False))
        report.append("sail %2d  foot %5.1f m  height %4.1f-%4.1f m" % (k, length, h0, h1))
    (cx, cz), (sx, sy, sz) = CORE
    # The auditorium: a steel box (its roof shows between the sails from above) on a stone base.
    parts.append(box_object("Core", (cx, sy * 0.5 + 2.5, cz), (sx, sy - 5.0, sz), steel, 0.2))
    parts.append(box_object("CoreBase", (cx, 1.25, cz), (sx + 2.0, 2.5, sz + 2.0), stone, 0.1))
    col_parts.append(box_object("ColCore", (cx, sy * 0.5, cz), (sx, sy, sz), colmat, 0.0))
    g = glass_strip("Glazing", GLASS_LINE, GLASS_H, glass)
    parts.append(g)
    # Join the drawn parts into one object and the collision into another.
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    hall = bpy.context.view_layer.objects.active
    hall.name = "ConcertHall"
    bpy.ops.object.select_all(action="DESELECT")
    for o in col_parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = col_parts[0]
    bpy.ops.object.join()
    col = bpy.context.view_layer.objects.active
    col.name = "Collision"
    tris = sum(len(p.vertices) - 2 for p in hall.data.polygons)
    col_tris = sum(len(p.vertices) - 2 for p in col.data.polygons)
    bb = [hall.matrix_world @ Vector(c) for c in hall.bound_box]
    lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True,
                              export_apply=True, export_texcoords=True, export_normals=True,
                              export_tangents=False, export_materials="EXPORT",
                              export_vertex_color="NONE", export_animations=False,
                              export_cameras=False, export_lights=False)
    for line in report:
        print(line)
    print("concert hall: %d triangles, collision %d, bounds x %.1f..%.1f  z(game) %.1f..%.1f  top %.1f" % (
        tris, col_tris, lo.x, hi.x, -hi.y, -lo.y, hi.z))
    print("concert hall ->", OUT)


main()
