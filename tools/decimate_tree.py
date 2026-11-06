#!/usr/bin/env python3
"""Turn a Poly Haven tree (millions of triangles) into a game tree of a few tens of thousands.

    python3 tools/decimate_tree.py scratch/ph/island_tree_01/island_tree_01.gltf out/island_tree_01.gltf \
        [--leaf-keep 0.16] [--leaf-scale 2.5] [--trunk-tris 6000] [--branch-tris 24000] [--branch-keep 0.35]

Poly Haven trees have three primitives: trunk, branches (thousands of twig segments) and leaves
(tens of thousands of separate 24-triangle leaves sharing one atlas texture). The trunk and the
branches go through pymeshlab's texture-preserving quadric decimation. Every kept leaf becomes
one two-triangle card in the leaf's best-fit plane, textured with the atlas region that leaf
used, and scaled up so the canopy stays as full as before. Any primitive whose material name
does not contain "leaves" or "branches" is treated as trunk. Writes a .gltf next to a .bin with
the original materials and images (copy the textures folder along; pack with pack_gltf.py).
Also works for rocks (everything is "trunk": --trunk-tris sets the count) and bushes with
"twigs" and "leaves" materials. --node picks one variant out of a file that ships several.
Needs: numpy, scipy, pymeshlab.
"""
import argparse
import json
import os
import shutil
import struct

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

CT = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(g: dict, buf: bytes, index: int) -> np.ndarray:
    a = g["accessors"][index]
    bv = g["bufferViews"][a["bufferView"]]
    n = NC[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return np.frombuffer(buf, dtype=CT[a["componentType"]], count=a["count"] * n, offset=off).reshape(a["count"], n).copy()


def components(faces: np.ndarray, nverts: int) -> np.ndarray:
    rows = np.concatenate([faces[:, 0], faces[:, 1], faces[:, 2]])
    cols = np.concatenate([faces[:, 1], faces[:, 2], faces[:, 0]])
    m = coo_matrix((np.ones(len(rows)), (rows, cols)), shape=(nverts, nverts))
    return connected_components(m, directed=False)[1]


def decimate(pos: np.ndarray, uv: np.ndarray, faces: np.ndarray, target: int, quality: float = 0.3):
    import pymeshlab
    ms = pymeshlab.MeshSet()
    ms.add_mesh(pymeshlab.Mesh(vertex_matrix=pos.astype(np.float64), face_matrix=faces.astype(np.int32), v_tex_coords_matrix=uv.astype(np.float64)))
    ms.compute_texcoord_transfer_vertex_to_wedge()
    ms.meshing_decimation_quadric_edge_collapse_with_texture(targetfacenum=int(target), qualitythr=quality, preserveboundary=False, planarquadric=True)
    ms.compute_texcoord_transfer_wedge_to_vertex()
    ms.compute_normal_per_vertex()
    m = ms.current_mesh()
    return m.vertex_matrix().astype(np.float32), m.vertex_normal_matrix().astype(np.float32), m.vertex_tex_coord_matrix().astype(np.float32), m.face_matrix().astype(np.uint32)


def biggest_components(pos: np.ndarray, uv: np.ndarray, faces: np.ndarray, keep: float):
    """Keeps the largest `keep` fraction of connected pieces (by bounding box diagonal)."""
    labels = components(faces, len(pos))
    count = labels.max() + 1
    lo = np.full((count, 3), np.inf)
    hi = np.full((count, 3), -np.inf)
    np.minimum.at(lo, labels, pos)
    np.maximum.at(hi, labels, pos)
    size = np.linalg.norm(hi - lo, axis=1)
    cutoff = np.quantile(size, 1.0 - keep)
    keep_comp = size >= cutoff
    face_ok = keep_comp[labels[faces[:, 0]]]
    faces = faces[face_ok]
    used = np.unique(faces)
    remap = np.full(len(pos), -1, np.int64)
    remap[used] = np.arange(len(used))
    return pos[used], uv[used], remap[faces]


def leaf_cards(pos: np.ndarray, uv: np.ndarray, faces: np.ndarray, keep: float, scale: float, seed: int):
    labels = components(faces, len(pos))
    count = labels.max() + 1
    rng = np.random.default_rng(seed)
    kept = np.flatnonzero(rng.random(count) < keep)
    order = np.argsort(labels)
    starts = np.searchsorted(labels[order], np.arange(count + 1))
    verts, norms, uvs, tris = [], [], [], []
    for c in kept:
        vi = order[starts[c]:starts[c + 1]]
        p = pos[vi]
        centroid = p.mean(axis=0)
        q = p - centroid
        # Best-fit plane by PCA: the two main axes span the card, the third is the normal.
        _, _, vt = np.linalg.svd(q, full_matrices=False)
        ax, ay, normal = vt[0], vt[1], vt[2]
        x = q @ ax
        y = q @ ay
        hx = max(x.max(), -x.min()) * scale
        hy = max(y.max(), -y.min()) * scale
        u0, v0 = uv[vi].min(axis=0)
        u1, v1 = uv[vi].max(axis=0)
        base = len(verts)
        for sx, sy, uu, vv in ((-1, -1, u0, v1), (1, -1, u1, v1), (1, 1, u1, v0), (-1, 1, u0, v0)):
            verts.append(centroid + ax * (sx * hx) + ay * (sy * hy))
            norms.append(normal)
            uvs.append((uu, vv))
        tris.append((base, base + 1, base + 2))
        tris.append((base, base + 2, base + 3))
    return np.array(verts, np.float32), np.array(norms, np.float32), np.array(uvs, np.float32), np.array(tris, np.uint32)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--leaf-keep", type=float, default=0.16, help="fraction of leaves kept")
    ap.add_argument("--leaf-scale", type=float, default=2.5, help="size multiplier for kept leaves")
    ap.add_argument("--trunk-tris", type=int, default=6000)
    ap.add_argument("--branch-tris", type=int, default=24000)
    ap.add_argument("--branch-keep", type=float, default=0.35, help="fraction of twig pieces kept (the biggest ones)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--quality", type=float, default=0.3, help="decimation triangle quality threshold (lower collapses more)")
    ap.add_argument("--node", default="", help="only nodes whose name contains this (and drop their offset)")
    args = ap.parse_args()
    base = os.path.dirname(args.src)
    with open(args.src) as f:
        g = json.load(f)
    buf = open(os.path.join(base, g["buffers"][0]["uri"]), "rb").read()
    out_prims = []
    blob = b""
    views, accessors = [], []

    def add_view(arr: np.ndarray, target: int) -> int:
        nonlocal blob
        data = arr.tobytes()
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob += data + b"\0" * ((4 - len(data) % 4) % 4)
        return len(views) - 1

    def add_accessor(arr: np.ndarray, target: int, ctype: int, atype: str, minmax: bool = False) -> int:
        acc = {"bufferView": add_view(arr, target), "componentType": ctype, "count": int(arr.shape[0]), "type": atype}
        if minmax:
            acc["min"] = [float(x) for x in arr.min(axis=0)]
            acc["max"] = [float(x) for x in arr.max(axis=0)]
        accessors.append(acc)
        return len(accessors) - 1

    for node in g["nodes"]:
        if "mesh" not in node or (args.node and args.node.lower() not in node.get("name", "").lower()):
            continue
        # Bake the node's transform (files that ship several variants side by side).
        tr = np.array(node.get("translation", [0.0, 0.0, 0.0]), np.float32)
        sc = np.array(node.get("scale", [1.0, 1.0, 1.0]), np.float32)
        qx, qy, qz, qw = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
        rot = np.array([
            [1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
            [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
            [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)]], np.float32)
        if args.node:
            tr = np.zeros(3, np.float32)
        for prim in g["meshes"][node["mesh"]]["primitives"]:
            mat = g["materials"][prim["material"]]["name"].lower()
            pos = (read_accessor(g, buf, prim["attributes"]["POSITION"]) * sc) @ rot.T + tr
            uv = read_accessor(g, buf, prim["attributes"]["TEXCOORD_0"])
            faces = read_accessor(g, buf, prim["indices"]).reshape(-1, 3).astype(np.int64)
            if "leaves" in mat or "leaf" in mat:
                v, n, t, f = leaf_cards(pos, uv, faces, args.leaf_keep, args.leaf_scale, args.seed)
            elif "branch" in mat or "twig" in mat:
                pos, uv, faces = biggest_components(pos, uv, faces, args.branch_keep)
                v, n, t, f = decimate(pos, uv, faces, args.branch_tris, args.quality)
            else:
                v, n, t, f = decimate(pos, uv, faces, args.trunk_tris, args.quality)
            print(f"{mat}: {len(faces)} -> {len(f)} triangles, {len(v)} vertices")
            out_prims.append({
                "attributes": {
                    "POSITION": add_accessor(v, 34962, 5126, "VEC3", True),
                    "NORMAL": add_accessor(n, 34962, 5126, "VEC3"),
                    "TEXCOORD_0": add_accessor(t, 34962, 5126, "VEC2"),
                },
                "indices": add_accessor(f.reshape(-1).astype(np.uint32), 34963, 5125, "SCALAR"),
                "material": prim["material"],
            })
    name = os.path.splitext(os.path.basename(args.dst))[0]
    out = {
        "asset": {"version": "2.0", "generator": "rando-game decimate_tree.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": out_prims}],
        "materials": g["materials"], "textures": g.get("textures", []), "images": g.get("images", []),
        "samplers": g.get("samplers", []),
        "buffers": [{"uri": name + ".bin", "byteLength": len(blob)}],
        "bufferViews": views, "accessors": accessors,
    }
    os.makedirs(os.path.dirname(args.dst) or ".", exist_ok=True)
    with open(os.path.join(os.path.dirname(args.dst), name + ".bin"), "wb") as f:
        f.write(blob)
    with open(args.dst, "w") as f:
        json.dump(out, f)
    src_tex = os.path.join(base, "textures")
    if os.path.isdir(src_tex):
        dst_tex = os.path.join(os.path.dirname(args.dst), "textures")
        os.makedirs(dst_tex, exist_ok=True)
        for img in g.get("images", []):
            shutil.copy(os.path.join(base, img["uri"]), os.path.join(os.path.dirname(args.dst), img["uri"]))
    print("wrote", args.dst)


if __name__ == "__main__":
    main()
