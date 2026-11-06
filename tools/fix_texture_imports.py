#!/usr/bin/env python3
"""Put newly generated texture .import files on the project's required settings.

    python3 tools/fix_texture_imports.py assets/models

Godot writes a fresh .import for every texture it sees, with compress/mode=0 (lossless VRAM
off) and detect_3d/compress_to=1 (which makes the editor silently re-import the texture the
first time it is used in 3D, so the committed file and the built file disagree). The project
needs every texture at:

    compress/mode=2            VRAM compressed
    mipmaps/generate=true      or distant foliage aliases into noise
    detect_3d/compress_to=0    stop the editor rewriting it behind our backs
    compress/normal_map=1      only for normal maps

A texture can also be held under a size by tools/texture_budget/budget.txt (written here as
process/size_limit; every other texture gets 0, no limit).

Normal maps are detected by filename: Poly Haven names them *_nor_gl / *_nor_dx, and the
project's own sets use *_NormalGL. Run this after importing any new texture, then commit the
.import files - CI exports from them and a wrong one costs a whole build.
"""
import os
import re
import sys

WANT = {
    "compress/mode": "2",
    "mipmaps/generate": "true",
    "detect_3d/compress_to": "0",
}
BUDGET_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "texture_budget", "budget.txt")


def load_budget():
    rules = []
    if os.path.exists(BUDGET_FILE):
        for line in open(BUDGET_FILE, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#"):
                pattern, limit = line.rsplit(None, 1)
                rules.append((re.compile(pattern), int(limit)))
    return rules


BUDGET = load_budget()


def size_limit(res_path: str) -> int:
    for pattern, limit in BUDGET:
        if pattern.search(res_path):
            return limit
    return 0


NORMAL_HINTS = ("_nor_gl", "_nor_dx", "_normalgl", "_normal", "_nrm")


def fix(path: str) -> bool:
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if "importer=\"texture\"" not in text:
        return False
    base = os.path.basename(path).lower()
    want = dict(WANT)
    want["compress/normal_map"] = "1" if any(h in base for h in NORMAL_HINTS) else "0"
    m = re.search(r'^source_file="(.*)"$', text, re.MULTILINE)
    want["process/size_limit"] = str(size_limit(m.group(1) if m else ""))
    out = text
    for key, value in want.items():
        pattern = re.compile(r"^%s=.*$" % re.escape(key), re.MULTILINE)
        if pattern.search(out):
            out = pattern.sub("%s=%s" % (key, value), out)
        else:
            # Keys Godot left out entirely: append to the [params] block.
            out = re.sub(r"(\[params\]\n)", r"\1%s=%s\n" % (key, value), out, count=1)
    if out == text:
        return False
    with open(path, "w", encoding="utf-8") as f:
        f.write(out)
    return True


def main() -> int:
    roots = sys.argv[1:] or ["assets"]
    changed = 0
    seen = 0
    for root in roots:
        for dirpath, _dirs, names in os.walk(root):
            for name in names:
                if not name.endswith(".import"):
                    continue
                path = os.path.join(dirpath, name)
                seen += 1
                if fix(path):
                    changed += 1
                    print("fixed", path)
    print("%d of %d .import files changed" % (changed, seen))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
