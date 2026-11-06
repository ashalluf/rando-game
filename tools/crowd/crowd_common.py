"""Paths and config for the crowd pipeline (tools/crowd/build.sh).

The crowd is built with the hero's tools (tools/hero/: Blender 4.2, MPFB 2 and the CC0 MakeHuman
asset pack, fetched by tools/hero/setup.sh into build/hero_src). Runs inside Blender and in plain
python3, so it only uses the standard library.
"""
import json
import os
import sys

CROWD_DIR = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(CROWD_DIR))
sys.path.insert(0, os.path.join(REPO, "tools", "hero"))
import common as hero_common  # noqa: E402

OUT = hero_common.OUT
MPFB_DATA = hero_common.MPFB_DATA
ASSETS = hero_common.ASSETS
ANIM_SOURCE = hero_common.ANIM_SOURCE
WORK = os.path.join(OUT, "crowd")
os.makedirs(WORK, exist_ok=True)


def config() -> dict:
    with open(os.path.join(CROWD_DIR, "crowd_config.json")) as f:
        return json.load(f)


def character(name: str) -> dict:
    """One character's settings with the defaults filled in (nested dicts merged one level)."""
    cfg = config()
    base = dict(cfg["defaults"])
    for c in cfg["characters"]:
        if c["name"] == name:
            out = dict(base)
            for k, v in c.items():
                if isinstance(v, dict) and isinstance(base.get(k), dict):
                    merged = dict(base[k])
                    merged.update(v)
                    out[k] = merged
                else:
                    out[k] = v
            out["garments"] = cfg.get("garments", {})
            return out
    raise KeyError(name)


def names() -> list:
    return [c["name"] for c in config()["characters"]]


def work(name: str, file: str) -> str:
    d = os.path.join(WORK, name)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, file)


def blender_args() -> list:
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
