#!/usr/bin/env python3
"""Re-smooth a .glb's vertex normals by angle and weld the vertices that then match.

    python3 tools/smooth_normals.py assets/models/car_pickup.glb [--angle 45] [--material paint]
    python3 tools/smooth_normals.py assets/models/car_pickup.glb --report

Why: the Meshy car bodies are ~8,000-triangle remeshes exported with their normals split at a
30 degree crease angle AND along every UV seam. On a mesh that coarse the bend between two big
triangles across a curved panel is often 30-50 degrees, so a wing or a bumper corner came out
as a set of flat-shaded facets with a hard line between each (and a hard line down every UV
seam, even where the surface is flat). The clearcoat, which mirrors the sky, shows every one.

What it does: an edge whose two triangles bend more than --angle is a crease; round each
POSITION (UV seams and the old splits are ignored, so seams stop showing) the triangles joined
through non-crease edges form one smooth fan and share one angle-weighted normal. Bends
sharper than that - the edge of a window frame, a panel's turn onto the sill, the wheel arch
lip - stay hard. The
triangles and the UVs are untouched; corners that now agree on position, UV and normal are
welded into one vertex, so the vertex count goes down, never up. The file is rewritten in
place (textures and every other primitive are copied through unchanged).

After running it: `godot --headless --path . --import` (Godot serves a cached import of a .glb
until then), commit the .glb. --report prints the crease statistics and changes nothing.
"""
import argparse
import json
import math
import struct

import numpy as np

GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    assert magic == GLB_MAGIC, "not a glb"
    off = 12
    gltf, blob = None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == JSON_CHUNK:
            gltf = json.loads(chunk)
        elif ctype == BIN_CHUNK:
            blob = chunk
        off += 8 + clen
    return gltf, blob


def read_accessor(gltf, blob, index):
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    width = WIDTH[acc["type"]]
    dtype = np.dtype(COMPONENT[acc["componentType"]])
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", 0)
    count = acc["count"]
    if stride and stride != width * dtype.itemsize:
        rows = np.frombuffer(blob, np.uint8, count=stride * count, offset=start).reshape(count, stride)
        arr = np.frombuffer(rows[:, : width * dtype.itemsize].tobytes(), dtype).reshape(count, width)
    else:
        arr = np.frombuffer(blob, dtype, count=count * width, offset=start).reshape(count, width)
    return arr.copy(), acc


def weld_ids(pos):
    """One id per distinct position (to a millionth of the model's size)."""
    extent = float(np.ptp(pos, axis=0).max()) or 1.0
    q = np.round(pos / (extent * 1e-6)).astype(np.int64)
    _, ids = np.unique(q, axis=0, return_inverse=True)
    return ids.reshape(-1)


def face_data(pos, tris):
    a, b, c = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    n = np.cross(b - a, c - a)
    length = np.linalg.norm(n, axis=1)
    good = length > 1e-12
    n = n / np.maximum(length, 1e-30)[:, None]
    # Interior angle at each corner: the weight of that face in the corner's normal.
    ang = np.zeros(tris.shape, np.float64)
    for k in range(3):
        p = pos[tris[:, k]]
        e1 = pos[tris[:, (k + 1) % 3]] - p
        e2 = pos[tris[:, (k + 2) % 3]] - p
        l1 = np.linalg.norm(e1, axis=1)
        l2 = np.linalg.norm(e2, axis=1)
        cosang = np.einsum("ij,ij->i", e1, e2) / np.maximum(l1 * l2, 1e-30)
        ang[:, k] = np.arccos(np.clip(cosang, -1.0, 1.0))
    ang[~good] = 0.0
    return n, good, ang


def crease_report(pos, normals, tris, label):
    ids = weld_ids(pos)
    fn, good, _ = face_data(pos, tris)
    edges = {}
    for t in range(len(tris)):
        for k in range(3):
            a, c = tris[t, k], tris[t, (k + 1) % 3]
            key = (min(ids[a], ids[c]), max(ids[a], ids[c]))
            edges.setdefault(key, []).append((t, a, c))
    rows = []
    for key, lst in edges.items():
        if len(lst) != 2:
            continue
        (t1, a1, c1), (t2, a2, c2) = lst
        if not (good[t1] and good[t2]):
            continue
        dih = math.degrees(math.acos(max(-1.0, min(1.0, float(fn[t1] @ fn[t2])))))
        m1 = {ids[a1]: a1, ids[c1]: c1}
        m2 = {ids[a2]: a2, ids[c2]: c2}
        split = max(math.degrees(math.acos(max(-1.0, min(1.0, float(normals[m1[u]] @ normals[m2[u]]))))) for u in key)
        rows.append((dih, split > 2.0))
    rows = np.array(rows) if rows else np.zeros((0, 2))
    print(f"{label}: {len(pos)} vertices, {len(tris)} triangles, {ids.max() + 1} positions")
    for lo, hi in [(0, 15), (15, 30), (30, 45), (45, 60), (60, 90), (90, 181)]:
        sel = (rows[:, 0] >= lo) & (rows[:, 0] < hi)
        hard = rows[sel, 1].mean() * 100 if sel.any() else 0.0
        print(f"  bend {lo:3d}-{hi:3d} deg: {int(sel.sum()):5d} edges, {hard:3.0f}% shaded hard")


def smooth(pos, tris, angle_deg):
    """Per-corner normals, the way a modelling package's smooth-by-angle does it: an edge whose
    two triangles bend more than angle_deg (or that is shared by other than two) is a crease;
    round each position, the triangles joined through non-crease edges form one smooth fan and
    share one angle-weighted normal. Fans are transitive, so the two sides of an edge that is
    not a crease always get the same normal (a per-corner "neighbours within the angle" test is
    not, and leaves faint seams wherever a fan wraps further than the angle)."""
    ids = weld_ids(pos)
    fn, good, ang = face_data(pos, tris)
    limit = math.cos(math.radians(angle_deg))
    n_corner = tris.size
    parent = np.arange(n_corner)

    def find(i):
        root = i
        while parent[root] != root:
            root = parent[root]
        while parent[i] != root:
            parent[i], i = root, parent[i]
        return root

    edges = {}
    for t in range(len(tris)):
        for k in range(3):
            u, v = ids[tris[t, k]], ids[tris[t, (k + 1) % 3]]
            if u == v:
                continue
            key = (u, v) if u < v else (v, u)
            edges.setdefault(key, []).append(t)
    corner_of = lambda t, u: t * 3 + int(np.flatnonzero(ids[tris[t]] == u)[0])
    for (u, v), faces in edges.items():
        # Usually two triangles; where more meet (a fin standing on a panel), each pair that
        # agrees within the angle joins, so a panel is not creased where something touches it.
        for i in range(len(faces)):
            for j in range(i + 1, len(faces)):
                f1, f2 = faces[i], faces[j]
                if not (good[f1] and good[f2]) or float(fn[f1] @ fn[f2]) < limit:
                    continue
                for w in (u, v):
                    a, b = find(corner_of(f1, w)), find(corner_of(f2, w))
                    if a != b:
                        parent[a] = b
    # Corners that already shared a vertex stay together: the model was smooth there, and it
    # keeps the vertex count from ever going up.
    first_use = {}
    for c, vert in enumerate(tris.reshape(-1)):
        if vert in first_use:
            a, b = find(c), find(first_use[vert])
            if a != b:
                parent[a] = b
        else:
            first_use[vert] = c
    roots = np.array([find(i) for i in range(n_corner)])
    weighted = (np.repeat(fn, 3, axis=0) * (ang.reshape(-1) * np.repeat(good, 3))[:, None])
    sums = np.zeros((n_corner, 3), np.float64)
    np.add.at(sums, roots, weighted)
    out = sums[roots]
    length = np.linalg.norm(out, axis=1)
    # A degenerate triangle with no smooth neighbour: its own normal.
    fallback = np.repeat(fn, 3, axis=0)
    bad = length < 1e-12
    out[~bad] /= length[~bad, None]
    out[bad] = fallback[bad]
    return out  # one normal per corner, in tris.reshape(-1) order


def pack(arr, dtype):
    return np.ascontiguousarray(arr.astype(dtype)).tobytes()


def process(path, angle, material, report):
    gltf, blob = read_glb(path)
    replaced = {}  # accessor index -> (bytes, count, componentType, type, minmax)
    new_accessors = []
    touched = 0
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            if prim.get("mode", 4) != 4 or "indices" not in prim or "NORMAL" not in prim["attributes"]:
                continue
            mat_name = ""
            if "material" in prim:
                mat_name = gltf["materials"][prim["material"]].get("name", "")
            if material and not mat_name.startswith(material):
                continue
            if "targets" in prim:
                print(f"  skipping a primitive with morph targets ({mat_name})")
                continue
            attrs = prim["attributes"]
            data = {name: read_accessor(gltf, blob, i)[0] for name, i in attrs.items()}
            idx, _ = read_accessor(gltf, blob, prim["indices"])
            tris = idx.reshape(-1, 3).astype(np.int64)
            pos = data["POSITION"].astype(np.float64)
            normals = data["NORMAL"].astype(np.float64)
            label = f"{path} [{mat_name or 'unnamed'}]"
            if report:
                crease_report(pos, normals, tris, label)
                continue
            corner_n = smooth(pos, tris, angle)
            corners = tris.reshape(-1)
            # A corner's vertex: its original vertex's attributes with the new normal. Weld the
            # ones that agree on every attribute (the key is quantised; the values are the
            # first corner's own).
            cols = [np.round(corner_n * 1e4).astype(np.int64)]
            for name, arr in data.items():
                if name == "NORMAL" or name == "TANGENT":
                    continue
                vals = arr[corners]
                if vals.dtype.kind == "f":
                    cols.append(np.round(vals.astype(np.float64) * 1e6).astype(np.int64))
                else:
                    cols.append(vals.astype(np.int64))
            key = np.concatenate(cols, axis=1)
            _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
            inverse = inverse.reshape(-1)
            new_data = {}
            for name, arr in data.items():
                if name == "TANGENT":
                    continue  # stale once the normals move; Godot regenerates them on import
                new_data[name] = arr[corners[first]]
            new_data["NORMAL"] = corner_n[first].astype(np.float32)
            before = len(pos)
            print(f"{label}: {before} -> {len(first)} vertices, {len(tris)} triangles, smoothed under {angle:g} deg")
            for name, arr in new_data.items():
                old = gltf["accessors"][attrs[name]]
                acc = {"componentType": old["componentType"], "type": old["type"], "count": int(len(arr))}
                if old.get("normalized"):
                    acc["normalized"] = True
                if name == "POSITION":
                    acc["min"] = [float(v) for v in arr.min(axis=0)]
                    acc["max"] = [float(v) for v in arr.max(axis=0)]
                new_accessors.append((acc, pack(arr, COMPONENT[old["componentType"]]), 34962))
                attrs[name] = len(gltf["accessors"]) + len(new_accessors) - 1
            attrs.pop("TANGENT", None)
            idx_type = 5123 if len(first) < 65536 else 5125
            acc = {"componentType": idx_type, "type": "SCALAR", "count": int(len(inverse))}
            new_accessors.append((acc, pack(inverse, COMPONENT[idx_type]), 34963))
            prim["indices"] = len(gltf["accessors"]) + len(new_accessors) - 1
            touched += 1
    if report:
        return
    if not touched:
        print(f"{path}: no primitive matched, nothing written")
        return
    # Rebuild the binary chunk from only what is still referenced, in the original order, plus
    # the new accessors, so the replaced data does not ride along in the file.
    views = gltf["bufferViews"]
    view_bytes = []
    for v in views:
        s = v.get("byteOffset", 0)
        view_bytes.append(blob[s: s + v["byteLength"]])
    for acc, raw, target in new_accessors:
        acc["bufferView"] = len(views)
        views.append({"buffer": 0, "byteLength": len(raw), "target": target})
        view_bytes.append(raw)
        gltf["accessors"].append(acc)
    used_acc = set()
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            used_acc.update(prim["attributes"].values())
            if "indices" in prim:
                used_acc.add(prim["indices"])
            for tgt in prim.get("targets", []):
                used_acc.update(tgt.values())
    for key in ("skins",):
        for sk in gltf.get(key, []):
            if "inverseBindMatrices" in sk:
                used_acc.add(sk["inverseBindMatrices"])
    for anim in gltf.get("animations", []):
        for smp in anim.get("samplers", []):
            used_acc.add(smp["input"])
            used_acc.add(smp["output"])
    acc_map = {}
    accessors = []
    for i, acc in enumerate(gltf["accessors"]):
        if i in used_acc:
            acc_map[i] = len(accessors)
            accessors.append(acc)
    gltf["accessors"] = accessors
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            prim["attributes"] = {k: acc_map[v] for k, v in prim["attributes"].items()}
            if "indices" in prim:
                prim["indices"] = acc_map[prim["indices"]]
            prim["targets"] = [{k: acc_map[v] for k, v in t.items()} for t in prim.get("targets", [])] or None
            if prim["targets"] is None:
                del prim["targets"]
    for sk in gltf.get("skins", []):
        if "inverseBindMatrices" in sk:
            sk["inverseBindMatrices"] = acc_map[sk["inverseBindMatrices"]]
    for anim in gltf.get("animations", []):
        for smp in anim.get("samplers", []):
            smp["input"] = acc_map[smp["input"]]
            smp["output"] = acc_map[smp["output"]]
    used_views = {a["bufferView"] for a in gltf["accessors"] if "bufferView" in a}
    used_views.update(im["bufferView"] for im in gltf.get("images", []) if "bufferView" in im)
    view_map = {}
    new_views = []
    out = bytearray()
    for i, v in enumerate(views):
        if i not in used_views:
            continue
        raw = view_bytes[i]
        while len(out) % 4:
            out.append(0)
        nv = dict(v)
        nv["byteOffset"] = len(out)
        nv["byteLength"] = len(raw)
        out.extend(raw)
        view_map[i] = len(new_views)
        new_views.append(nv)
    while len(out) % 4:
        out.append(0)
    gltf["bufferViews"] = new_views
    for a in gltf["accessors"]:
        if "bufferView" in a:
            a["bufferView"] = view_map[a["bufferView"]]
    for im in gltf.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = view_map[im["bufferView"]]
    gltf["buffers"] = [{"byteLength": len(out)}]
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, total))
        f.write(struct.pack("<II", len(js), JSON_CHUNK))
        f.write(js)
        f.write(struct.pack("<II", len(out), BIN_CHUNK))
        f.write(bytes(out))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--angle", type=float, default=45.0, help="bends sharper than this stay hard (degrees)")
    ap.add_argument("--material", default="", help="only primitives whose material name starts with this")
    ap.add_argument("--report", action="store_true", help="print crease statistics, change nothing")
    args = ap.parse_args()
    for p in args.paths:
        process(p, args.angle, args.material, args.report)


if __name__ == "__main__":
    main()
