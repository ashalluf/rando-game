#!/usr/bin/env python3
"""The tors' welded meshes (RockKit.mid_mesh): a Poly Haven rock scan welded and cut to ~1,800
triangles, geometry only (positions and normals, no UVs, no material). Godot generates its LODs
on import (down to a couple of hundred triangles), and rock_outcrop.gdshader textures it
triplanar in world space (`far_mode`): what RockFar draws past its near cells, what a near tor
casts its shadow with, and what it collides with.

    python3 tools/rocks/make_rock_lods.py <scan>.gltf assets/models/rock_<name>_mid.glb [--tris 1800]

Why not the scan's own LODs: texture-preserving decimation (tools/decimate_tree.py, and Godot's
own LOD generator on the scan) keeps every UV seam open, and past a few thousand triangles that
shreds a scan into loose flakes floating round the rock; welded, the collapse keeps it one lump.
Needs numpy and pymeshlab.
"""
import argparse
import json
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from decimate_tree import read_accessor  # noqa: E402


def load(path: str):
    g = json.load(open(path))
    buf = open(os.path.join(os.path.dirname(path), g["buffers"][0]["uri"]), "rb").read()
    pos_all, faces_all = [], []
    base = 0
    for m in g["meshes"]:
        for p in m["primitives"]:
            pos = read_accessor(g, buf, p["attributes"]["POSITION"])
            idx = read_accessor(g, buf, p["indices"]).reshape(-1, 3)
            pos_all.append(pos)
            faces_all.append(idx + base)
            base += len(pos)
    return np.concatenate(pos_all).astype(np.float64), np.concatenate(faces_all).astype(np.int32)


def write_glb(dst: str, pos: np.ndarray, nrm: np.ndarray, faces: np.ndarray) -> None:
    pos = pos.astype(np.float32)
    nrm = nrm.astype(np.float32)
    idx = faces.astype(np.uint16 if len(pos) < 65536 else np.uint32).reshape(-1)
    blobs = [pos.tobytes(), nrm.tobytes(), idx.tobytes()]
    views, offset = [], 0
    data = b""
    for b in blobs:
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(b)})
        data += b + b"\0" * ((4 - len(b) % 4) % 4)
        offset = len(data)
    g = {
        "asset": {"version": "2.0", "generator": "rando-game make_rock_lods.py"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"name": os.path.splitext(os.path.basename(dst))[0], "mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "indices": 2, "material": 0}]}],
        "materials": [{"name": "rock_mid", "pbrMetallicRoughness": {"baseColorFactor": [0.5, 0.45, 0.4, 1], "metallicFactor": 0, "roughnessFactor": 1}}],
        "buffers": [{"byteLength": len(data)}],
        "bufferViews": views,
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5123 if idx.dtype == np.uint16 else 5125, "count": len(idx), "type": "SCALAR"},
        ],
    }
    js = json.dumps(g).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    out = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(data))
    out += struct.pack("<I", len(js)) + b"JSON" + js + struct.pack("<I", len(data)) + b"BIN\0" + data
    open(dst, "wb").write(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--tris", type=int, default=1800)
    a = ap.parse_args()
    import pymeshlab
    pos, faces = load(a.src)
    ms = pymeshlab.MeshSet()
    ms.add_mesh(pymeshlab.Mesh(vertex_matrix=pos, face_matrix=faces))
    ms.meshing_merge_close_vertices(threshold=pymeshlab.PercentageValue(0.2))
    ms.meshing_remove_duplicate_faces()
    ms.meshing_remove_unreferenced_vertices()
    ms.meshing_decimation_quadric_edge_collapse(targetfacenum=a.tris, preservenormal=True, preservetopology=False, planarquadric=True, qualitythr=0.4)
    ms.meshing_remove_unreferenced_vertices()
    ms.compute_normal_per_vertex()
    m = ms.current_mesh()
    write_glb(a.dst, m.vertex_matrix(), m.vertex_normal_matrix(), m.face_matrix())
    print("%s: %d triangles, %d vertices" % (a.dst, len(m.face_matrix()), len(m.vertex_matrix())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
