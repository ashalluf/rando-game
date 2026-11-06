#!/usr/bin/env python3
"""Shrink the textures embedded in a .glb so game assets stay small.

    python3 tools/shrink_glb.py assets/models/car_sedan.glb [--size 1024] [--quality 85]

Every embedded image is resized to at most --size pixels and re-encoded as JPEG (PNG is kept
only when the image has transparency). The file is rewritten in place; the mesh is untouched.
--desaturate greys out the base color texture (used for cars, whose paint is a material tint).
"""
import argparse
import io
import json
import os
import struct

from PIL import Image

GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def pad4(b: bytes, fill: bytes) -> bytes:
    return b + fill * ((4 - len(b) % 4) % 4)


def base_color_views(gltf: dict) -> set:
    """Buffer views holding base color images (the ones a paint tint should apply to)."""
    views = set()
    for mat in gltf.get("materials", []):
        tex = mat.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if tex is None:
            continue
        image = gltf["textures"][tex["index"]].get("source")
        if image is not None and "bufferView" in gltf["images"][image]:
            views.add(gltf["images"][image]["bufferView"])
    return views


def shrink(path: str, size: int, quality: int, desaturate: bool = False) -> None:
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    assert magic == GLB_MAGIC, "not a glb"
    off = 12
    gltf = None
    blob = b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8 : off + 8 + clen]
        if ctype == JSON_CHUNK:
            gltf = json.loads(chunk)
        elif ctype == BIN_CHUNK:
            blob = chunk
        off += 8 + clen
    assert gltf is not None
    views = gltf.get("bufferViews", [])
    image_views = {im["bufferView"]: im for im in gltf.get("images", []) if "bufferView" in im}
    paint_views = base_color_views(gltf) if desaturate else set()

    # Rebuild the binary buffer view by view, replacing image views with re-encoded pixels.
    new_blob = bytearray()
    before = len(blob)
    for i, view in enumerate(views):
        start = view.get("byteOffset", 0)
        raw = blob[start : start + view["byteLength"]]
        if i in image_views:
            img = Image.open(io.BytesIO(raw))
            has_alpha = img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info)
            if max(img.size) > size:
                img.thumbnail((size, size), Image.LANCZOS)
            if i in paint_views:
                # Greyscale base color, stretched so the paint reads near white: the material
                # albedo tint then gives the car its color (windows and tires stay dark).
                grey = img.convert("L")
                hist = grey.histogram()
                total = sum(hist)
                acc = 0
                bright = 255
                for level, count in enumerate(hist):
                    acc += count
                    if acc >= total * 0.85:
                        bright = max(level, 1)
                        break
                grey = grey.point(lambda v, k=235.0 / bright: min(255, int(v * k)))
                img = grey.convert("RGB")
            out = io.BytesIO()
            if has_alpha:
                img.save(out, "PNG", optimize=True)
                image_views[i]["mimeType"] = "image/png"
            else:
                img.convert("RGB").save(out, "JPEG", quality=quality, optimize=True)
                image_views[i]["mimeType"] = "image/jpeg"
            raw = out.getvalue()
            print(f"  image view {i}: {img.size[0]}x{img.size[1]} {len(blob[start:start + view['byteLength']]) // 1024} KB -> {len(raw) // 1024} KB")
        while len(new_blob) % 4:
            new_blob.append(0)
        view["byteOffset"] = len(new_blob)
        view["byteLength"] = len(raw)
        new_blob += raw
    new_blob = pad4(bytes(new_blob), b"\0")
    gltf["buffers"][0]["byteLength"] = len(new_blob)
    json_bytes = pad4(json.dumps(gltf, separators=(",", ":")).encode(), b" ")
    total = 12 + 8 + len(json_bytes) + 8 + len(new_blob)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, total))
        f.write(struct.pack("<II", len(json_bytes), JSON_CHUNK))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(new_blob), BIN_CHUNK))
        f.write(new_blob)
    print(f"{os.path.basename(path)}: {before // 1024} KB -> {len(new_blob) // 1024} KB of binary data")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("files", nargs="+")
    p.add_argument("--size", type=int, default=1024)
    p.add_argument("--quality", type=int, default=85)
    p.add_argument("--desaturate", action="store_true", help="greyscale the base color (cars: paint comes from the tint)")
    args = p.parse_args()
    for f in args.files:
        shrink(f, args.size, args.quality, args.desaturate)


if __name__ == "__main__":
    main()
