#!/usr/bin/env python3
"""Generate game-ready GLB models with the Meshy API and drop them into assets/models/.

Usage (the key never goes in the repo; put it in MESHY_API_KEY or a file named by MESHY_KEY_FILE):

    python3 tools/meshy.py gen pedestrian_a "low-poly casual pedestrian..." --polycount 3000 \
        --rig 1.75 --anims 0,613,659
    python3 tools/meshy.py gen sedan "low-poly sedan car, clean flat colors" --polycount 4000
    python3 tools/meshy.py balance

Each asset gets `assets/models/<name>.glb` (textured, PBR), optionally `<name>_anim.glb` (rigged
with one animation clip per action id) and `<name>.json` (task ids, credits, prompt) so
docs/ASSETS.md can credit it. Pipeline: Smart Topology preview (5 credits, clean low-poly at the
requested face count) -> refine with PBR (10) -> rig (5) -> animations (3 per clip).
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.meshy.ai"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "models")


def key() -> str:
    k = os.environ.get("MESHY_API_KEY", "")
    if not k and os.environ.get("MESHY_KEY_FILE"):
        with open(os.environ["MESHY_KEY_FILE"]) as f:
            k = f.read().strip()
    if not k:
        sys.exit("Set MESHY_API_KEY or MESHY_KEY_FILE")
    return k


def call(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + key())
    if data is not None:
        req.add_header("Content-Type", "application/json")
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")
            if e.code in (429, 500, 502, 503) and attempt < 4:
                time.sleep(5 * (attempt + 1))
                continue
            sys.exit(f"Meshy {method} {path} failed: {e.code} {msg}")
        except urllib.error.URLError as e:
            if attempt < 4:
                time.sleep(5 * (attempt + 1))
                continue
            sys.exit(f"Meshy {method} {path} unreachable: {e}")
    return {}


def wait(path: str, task_id: str, label: str) -> dict:
    started = time.time()
    last = -1
    while True:
        t = call("GET", f"{path}/{task_id}")
        status = t.get("status")
        progress = t.get("progress", 0)
        if progress != last:
            print(f"  {label}: {status} {progress}%  ({int(time.time() - started)} s)", flush=True)
            last = progress
        if status == "SUCCEEDED":
            return t
        if status in ("FAILED", "EXPIRED", "CANCELED"):
            sys.exit(f"{label} {status}: {t.get('task_error')}")
        time.sleep(8)


def download(url: str, dest: str) -> None:
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
        f.write(r.read())
    print(f"  saved {os.path.relpath(dest, ROOT)} ({os.path.getsize(dest) // 1024} KB)", flush=True)


def cmd_balance(_args) -> None:
    print(call("GET", "/openapi/v1/balance"))


def cmd_gen(args) -> None:
    manifest = {"name": args.name, "prompt": args.prompt, "credits": 0, "tasks": {}, "source": "Meshy (generated for this project)"}
    body = {
        "mode": "preview",
        "prompt": args.prompt,
        "model_type": "smart-topology",
        "ai_model": "meshy-t2",
        "target_polycount": args.polycount,
        "topology": "triangle",
    }
    if args.rig:
        body["pose_mode"] = "a-pose"
    print(f"[{args.name}] preview: {args.prompt}", flush=True)
    preview_id = call("POST", "/openapi/v2/text-to-3d", body)["result"]
    preview = wait("/openapi/v2/text-to-3d", preview_id, "preview")
    manifest["tasks"]["preview"] = preview_id
    manifest["credits"] += preview.get("consumed_credits", 0)

    refine_body = {"mode": "refine", "preview_task_id": preview_id, "enable_pbr": True, "texture_resolution": "2k"}
    if args.texture_prompt:
        refine_body["texture_prompt"] = args.texture_prompt
    print(f"[{args.name}] refine (textures)", flush=True)
    refine_id = call("POST", "/openapi/v2/text-to-3d", refine_body)["result"]
    refine = wait("/openapi/v2/text-to-3d", refine_id, "refine")
    manifest["tasks"]["refine"] = refine_id
    manifest["credits"] += refine.get("consumed_credits", 0)
    download(refine["model_urls"]["glb"], os.path.join(OUT_DIR, f"{args.name}.glb"))
    if refine.get("thumbnail_url"):
        download(refine["thumbnail_url"], os.path.join(OUT_DIR, "thumbs", f"{args.name}.png"))

    if args.rig:
        print(f"[{args.name}] rig (height {args.rig} m)", flush=True)
        rig_id = call("POST", "/openapi/v1/rigging", {"input_task_id": refine_id, "height_meters": args.rig})["result"]
        rig = wait("/openapi/v1/rigging", rig_id, "rig")
        manifest["tasks"]["rig"] = rig_id
        manifest["credits"] += rig.get("consumed_credits", 0)
        if args.anims:
            ids = [int(a) for a in args.anims.split(",") if a.strip()]
            print(f"[{args.name}] animations {ids}", flush=True)
            anim_id = call("POST", "/openapi/v1/animations", {"rig_task_id": rig_id, "action_ids": ids})["result"]
            anim = wait("/openapi/v1/animations", anim_id, "animations")
            manifest["tasks"]["animations"] = anim_id
            manifest["credits"] += anim.get("consumed_credits", 0)
            url = anim.get("result", {}).get("animation_glb_url") or anim.get("animation_glb_url")
            if not url:
                sys.exit(f"no animation glb in {json.dumps(anim)[:500]}")
            download(url, os.path.join(OUT_DIR, f"{args.name}_anim.glb"))
            manifest["animations"] = ids
        else:
            download(rig["result"]["rigged_character_glb_url"], os.path.join(OUT_DIR, f"{args.name}_anim.glb"))

    with open(os.path.join(OUT_DIR, f"{args.name}.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"[{args.name}] done, {manifest['credits']} credits", flush=True)


def cmd_task(args) -> None:
    print(json.dumps(call("GET", f"{args.path}/{args.id}"), indent=2)[:4000])


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance").set_defaults(fn=cmd_balance)
    g = sub.add_parser("gen")
    g.add_argument("name")
    g.add_argument("prompt")
    g.add_argument("--polycount", type=int, default=4000, help="faces (100-15000)")
    g.add_argument("--texture-prompt", default="")
    g.add_argument("--rig", type=float, default=0.0, help="character height in meters; 0 = no rig")
    g.add_argument("--anims", default="", help="comma-separated Meshy action ids (needs --rig)")
    g.set_defaults(fn=cmd_gen)
    t = sub.add_parser("task")
    t.add_argument("path")
    t.add_argument("id")
    t.set_defaults(fn=cmd_task)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
