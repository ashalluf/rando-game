#!/usr/bin/env python3
"""Download one Poly Haven model as a .gltf plus its .bin and textures.

    python3 tools/fetch_polyhaven.py jacaranda_tree scratch/ph [--res 1k]

Writes scratch/ph/<id>/<id>_<res>.gltf and every file the glTF references, keeping the
relative paths the glTF expects. Poly Haven's files API lists those under
gltf/<res>/gltf/include, keyed by the path relative to the glTF, which is exactly what
pack_gltf.py and decimate_tree.py want to see on disk.

Everything on Poly Haven is CC0. Add a row to docs/ASSETS.md for anything that ships.
"""
import argparse
import json
import os
import sys
import urllib.request

API = "https://api.polyhaven.com/files/%s"
# Poly Haven sits behind a CDN that 403s the default urllib agent.
HEADERS = {"User-Agent": "rando-game-asset-fetch/1.0"}


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("asset_id")
    ap.add_argument("out_dir")
    ap.add_argument("--res", default="1k")
    args = ap.parse_args()

    files = json.loads(get(API % args.asset_id))
    gltf = files.get("gltf", {}).get(args.res, {}).get("gltf")
    if gltf is None:
        have = sorted(files.get("gltf", {}).keys())
        print("no %s glTF for %s (have: %s)" % (args.res, args.asset_id, ", ".join(have)), file=sys.stderr)
        return 1

    root = os.path.join(args.out_dir, args.asset_id)
    os.makedirs(root, exist_ok=True)
    main_path = os.path.join(root, os.path.basename(gltf["url"]))
    with open(main_path, "wb") as f:
        f.write(get(gltf["url"]))
    total = os.path.getsize(main_path)

    # `include` is keyed by the path relative to the glTF: textures/foo.jpg, foo.bin, ...
    for rel, info in (gltf.get("include") or {}).items():
        dest = os.path.join(root, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(get(info["url"]))
        total += os.path.getsize(dest)

    print(main_path)
    print("%.1f MB in %d files" % (total / 1e6, 1 + len(gltf.get("include") or {})), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
