#!/usr/bin/env python3
"""Generate game-ready GLB models with the Meshy API and drop them into assets/models/.

Usage (the key never goes in the repo; put it in MESHY_API_KEY or a file named by MESHY_KEY_FILE):

    python3 tools/meshy.py gen pedestrian_a "adult man pedestrian, casual clothes..." \
        --rig 1.75 --anims 0,613,659
    python3 tools/meshy.py gen sedan "modern four-door sedan car, white paint"
    python3 tools/meshy.py balance

Each asset gets `assets/models/<name>.glb` (textured, PBR), optionally `<name>_anim.glb` (rigged
with one animation clip per action id) and `<name>.json` (task ids, credits, prompt) so
docs/ASSETS.md can credit it. Pipeline: Smart Topology preview (5 credits, clean low-poly at the
requested face count) -> refine with PBR (10) -> rig (5) -> animations (3 per clip).
Owner's rule: every prompt asks for the most realistic result possible (REALISM is appended
automatically; --plain turns it off). Default engine is Meshy's latest standard model (20
credits per preview); --engine smart is the cheap low-poly option.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.meshy.ai"
# Owner's standing rule (2026-09-19): every prompt asks for the most realistic result possible.
REALISM = (", ultra realistic, photorealistic, highly detailed, physically accurate materials"
           " and proportions, real-world scale, no cartoon or stylized look")
TEXTURE_REALISM = "photorealistic PBR materials, true-to-life colors, fine surface detail, no cartoon look"
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
    prompt = args.prompt if args.plain else args.prompt + REALISM
    manifest = {"name": args.name, "prompt": prompt, "credits": 0, "tasks": {}, "source": "Meshy (generated for this project)"}
    if args.engine == "smart":
        body = {"mode": "preview", "prompt": prompt, "model_type": "smart-topology", "ai_model": "meshy-t2",
                "target_polycount": args.polycount, "topology": "triangle"}
    else:
        body = {"mode": "preview", "prompt": prompt, "model_type": "standard", "ai_model": "latest",
                "should_remesh": True, "target_polycount": args.polycount, "topology": "triangle"}
    if args.rig:
        body["pose_mode"] = "a-pose"
    print(f"[{args.name}] preview ({args.engine}): {prompt}", flush=True)
    preview_id = call("POST", "/openapi/v2/text-to-3d", body)["result"]
    preview = wait("/openapi/v2/text-to-3d", preview_id, "preview")
    manifest["tasks"]["preview"] = preview_id
    manifest["credits"] += preview.get("consumed_credits", 0)

    refine_body = {"mode": "refine", "preview_task_id": preview_id, "enable_pbr": True, "texture_resolution": "2k"}
    # The refine pass paints the textures from texture_prompt ALONE when one is given, so a
    # texture prompt that does not describe the subject throws the description away: a Black man
    # in a grey hoodie, a Latino man in navy and a worker in an orange vest all came back pale
    # and in grey, because all the refine pass was told was "photorealistic PBR materials".
    # Without --texture-prompt the subject is carried.
    texture_prompt = args.texture_prompt or args.prompt
    if not args.plain:
        texture_prompt = (texture_prompt + ", " if texture_prompt else "") + TEXTURE_REALISM
    if texture_prompt:
        refine_body["texture_prompt"] = texture_prompt
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
    g.add_argument("--polycount", type=int, default=8000, help="target faces after remesh")
    g.add_argument("--engine", choices=["standard", "smart"], default="standard",
                   help="standard = Meshy latest, most detail (20 credits); smart = Smart Topology low-poly (5 credits)")
    g.add_argument("--plain", action="store_true", help="do not append the realism wording to the prompts")
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
