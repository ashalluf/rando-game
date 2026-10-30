#!/usr/bin/env python3
"""Pack a .gltf with external .bin and texture files into one .glb.

    python3 tools/pack_gltf.py path/to/model.gltf assets/models/prop_name.glb

Used for CC0 models from Poly Haven (their glTF download is a .gltf + .bin + textures/ folder).
Buffers and images are embedded in the binary chunk; nothing else changes. Run
`tools/shrink_glb.py` afterwards if the textures are larger than 1K.
"""
import json
import os
import struct
import sys

MIME = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}


def pad4(b: bytes, fill: bytes) -> bytes:
    return b + fill * ((4 - len(b) % 4) % 4)


def pack(src: str, dst: str) -> None:
    base = os.path.dirname(src)
    with open(src) as f:
        gltf = json.load(f)
    blob = b""
    offsets = []
    for buf in gltf.get("buffers", []):
        with open(os.path.join(base, buf["uri"]), "rb") as f:
            data = f.read()
        offsets.append(len(blob))
        blob = pad4(blob + data, b"\0")
    for view in gltf.get("bufferViews", []):
        view["byteOffset"] = view.get("byteOffset", 0) + offsets[view.get("buffer", 0)]
        view["buffer"] = 0
    for image in gltf.get("images", []):
        uri = image.pop("uri")
        with open(os.path.join(base, uri), "rb") as f:
            data = f.read()
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)})
        image["bufferView"] = len(gltf["bufferViews"]) - 1
        image["mimeType"] = MIME[os.path.splitext(uri)[1].lower()]
        # Godot extracts embedded images as <glb name>_<image name>.jpg, so keep the name short:
        # "fire_hydrant_aged_diff_1k" becomes "aged_diff".
        name = os.path.splitext(os.path.basename(uri))[0]
        model = os.path.splitext(os.path.basename(src))[0].lower()
        if name.lower().startswith(model + "_"):
            name = name[len(model) + 1:]
        for suffix in ("_1k", "_2k", "_4k"):
            if name.lower().endswith(suffix):
                name = name[: -len(suffix)]
        image["name"] = name
        blob = pad4(blob + data, b"\0")
    gltf["buffers"] = [{"byteLength": len(blob)}]
    gltf.setdefault("asset", {})["generator"] = "rando-game pack_gltf.py"
    js = pad4(json.dumps(gltf, separators=(",", ":")).encode(), b" ")
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + blob)
    print(f"{dst}: {total / 1e6:.1f} MB")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    pack(sys.argv[1], sys.argv[2])
