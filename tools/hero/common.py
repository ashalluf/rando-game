"""Paths and helpers shared by every step of the hero pipeline (tools/hero/build.sh).

Runs inside Blender (the modelling steps) and in plain python3 (the texture step), so it only
uses the standard library. Everything big - Blender itself, MPFB and its asset pack, the work
.blend files, the raw bakes - lives in HERO_BUILD (default build/hero_src, git-ignored); only
the finished hero.glb and the extra maps the game shader reads are written into assets/models.
"""
import json
import os

HERO_DIR = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERO_DIR))
OUT = os.environ.get("HERO_BUILD", os.path.join(REPO, "build", "hero_src"))
WORK = os.path.join(OUT, "work")
TEX = os.path.join(OUT, "tex")
RENDERS = os.path.join(OUT, "renders")
ASSETS = os.path.join(REPO, "assets", "models")
GLB = os.environ.get("HERO_GLB", os.path.join(ASSETS, "hero.glb"))
# MPFB keeps its user data (the MakeHuman asset pack) here once the extension is installed
# into BLENDER_USER_RESOURCES=OUT/blender_user (tools/hero/setup.sh).
MPFB_DATA = os.path.join(OUT, "blender_user", "extensions", ".user", "user_default", "mpfb", "data")
ANIM_SOURCE = os.path.join(ASSETS, "pedestrian_d_anim.glb")

for d in (WORK, TEX, RENDERS):
    os.makedirs(d, exist_ok=True)
# Godot scans the whole project folder: keep it out of Blender, the packs and the work files.
open(os.path.join(OUT, ".gdignore"), "a").close()


def config() -> dict:
    with open(os.path.join(HERO_DIR, "hero_config.json")) as f:
        return json.load(f)


def work(name: str) -> str:
    return os.path.join(WORK, name)


def tex(name: str) -> str:
    return os.path.join(TEX, name)


def blender_args() -> list:
    """Arguments after Blender's `--`."""
    import sys
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
