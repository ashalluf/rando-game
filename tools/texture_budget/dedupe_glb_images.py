#!/usr/bin/env python3
"""Drop duplicate embedded images from .glb files, so Godot loads each picture once.

Godot's glTF importer extracts every embedded image to its own `<glb>_<name>.jpg` and loads each
as a separate texture, even when two images hold the same bytes. Poly Haven packs repeat a map
inside one model (plant_rooibos, tree_searsia, prop_lamp, prop_streetlamp carry the same diffuse
two or three times) and across models (tree_b and tree_jacaranda reuse tree_a's bark and leaf
maps), which cost video memory for nothing (docs/HANDOFF.md, "Texture budget").

    python3 tools/texture_budget/dedupe_glb_images.py [--dry] assets/models/*.glb

Inside one file a repeated image is removed and every texture pointing at it points at the first
copy. Across files, an image identical to one an EARLIER file (in the order given) embeds becomes
an external reference (`"uri"`) to that file's extracted texture, `<earlier glb>_<name>.<ext>`,
which Godot's importer loads as the same Texture2D resource (GLTFDocument resolves a relative uri
through the ResourceLoader). The binary chunk is rebuilt with only the buffer views still used;
meshes, materials and animations are untouched (same accessors, same bytes). Then run
`godot --headless --path . --import` and delete the extracted copies nothing extracts any more
(the script prints them).
"""
import hashlib
import json
import os
import struct
import sys


def read_glb(path):
    b = open(path, "rb").read()
    magic, version, length = struct.unpack("<III", b[:12])
    assert magic == 0x46546C67, path
    off = 12
    js = None
    binc = b""
    while off < length:
        clen, ctype = struct.unpack("<II", b[off:off + 8])
        data = b[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(data)
        elif ctype == 0x004E4942:
            binc = data
        off += 8 + clen
    return js, binc


def write_glb(path, js, binc):
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * ((4 - len(jb) % 4) % 4)
    binc += b"\0" * ((4 - len(binc) % 4) % 4)
    total = 12 + 8 + len(jb) + (8 + len(binc) if binc else 0)
    out = struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(jb), 0x4E4F534A) + jb
    if binc:
        out += struct.pack("<II", len(binc), 0x004E4942) + binc
    open(path, "wb").write(out)


def image_bytes(js, binc, im):
    if "bufferView" not in im:
        return None
    bv = js["bufferViews"][im["bufferView"]]
    o = bv.get("byteOffset", 0)
    return binc[o:o + bv["byteLength"]]


def extracted_name(glb_path, im, index):
    # Godot (gltf naming v2) extracts `<glb basename>_<image name>.<ext>`.
    base = os.path.splitext(os.path.basename(glb_path))[0]
    ext = ".png" if im.get("mimeType") == "image/png" else ".jpg"
    name = im.get("name") or str(index)
    return base + "_" + name + ext


def compact(js, binc):
    used = set()
    for a in js.get("accessors", []):
        if "bufferView" in a:
            used.add(a["bufferView"])
        sp = a.get("sparse")
        if sp:
            used.add(sp["indices"]["bufferView"])
            used.add(sp["values"]["bufferView"])
    for im in js.get("images", []):
        if "bufferView" in im:
            used.add(im["bufferView"])
    remap = {}
    views = []
    out = bytearray()
    for i, bv in enumerate(js.get("bufferViews", [])):
        if i not in used:
            continue
        o = bv.get("byteOffset", 0)
        data = binc[o:o + bv["byteLength"]]
        while len(out) % 8:
            out.append(0)
        nbv = dict(bv)
        nbv["byteOffset"] = len(out)
        out += data
        remap[i] = len(views)
        views.append(nbv)
    js["bufferViews"] = views
    for a in js.get("accessors", []):
        if "bufferView" in a:
            a["bufferView"] = remap[a["bufferView"]]
        sp = a.get("sparse")
        if sp:
            sp["indices"]["bufferView"] = remap[sp["indices"]["bufferView"]]
            sp["values"]["bufferView"] = remap[sp["values"]["bufferView"]]
    for im in js.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = remap[im["bufferView"]]
    if js.get("buffers"):
        js["buffers"][0]["byteLength"] = len(out)
    return bytes(out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry" in sys.argv
    known = {}  # md5 -> extracted file name of the first file that embeds it
    stale = []
    for path in args:
        js, binc = read_glb(path)
        images = js.get("images", [])
        if not images:
            continue
        local = {}
        image_map = {}
        keep = []
        changed = False
        for i, im in enumerate(images):
            data = image_bytes(js, binc, im)
            if data is None:
                image_map[i] = len(keep)
                keep.append(im)
                continue
            h = hashlib.md5(data).hexdigest()
            if h in local:
                image_map[i] = local[h]
                # A repeated name is extracted with the image's index appended (`_diff_3.jpg`).
                stale.append(os.path.join(os.path.dirname(path), os.path.splitext(
                    extracted_name(path, im, i))[0] + "_%d" % i + os.path.splitext(
                    extracted_name(path, im, i))[1]))
                changed = True
                print("%s: image %d (%s) is image %d" % (path, i, im.get("name"), local[h]))
                continue
            if h in known:
                print("%s: image %d (%s) -> %s" % (path, i, im.get("name"), known[h]))
                stale.append(os.path.join(os.path.dirname(path), extracted_name(path, im, i)))
                im = {"uri": known[h], "mimeType": im.get("mimeType", "image/jpeg"),
                      "name": im.get("name", "")}
                changed = True
            else:
                known[h] = extracted_name(path, im, i)
            local[h] = len(keep)
            image_map[i] = len(keep)
            keep.append(im)
        if not changed:
            continue
        js["images"] = keep
        for t in js.get("textures", []):
            if "source" in t:
                t["source"] = image_map[t["source"]]
            for ext in t.get("extensions", {}).values():
                if isinstance(ext, dict) and "source" in ext:
                    ext["source"] = image_map[ext["source"]]
        nb = compact(js, binc)
        print("%s: %d -> %d images, %d -> %d bytes of binary" % (
            path, len(images), len(keep), len(binc), len(nb)))
        if not dry:
            write_glb(path, js, nb)
    for s in stale:
        print("STALE", s)


if __name__ == "__main__":
    main()
