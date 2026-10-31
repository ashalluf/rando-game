# Rando Game fleet brief, wave 4 (shared rules for every parallel session; 2026-10-31)

You are a fresh Claude Code session on "Rando Game" (github.com/ashalluf/rando-game), a Godot 4.7.2 open-world chaos sandbox set in a seeded, LA-like city. You are one of about 40 sessions working in parallel, one area each. A lead session reviews your branch and merges it into main. Nobody is watching to answer questions: work autonomously to the end.

FIRST read, in full: CLAUDE.md (the rulebook), the top of docs/HANDOFF.md (section 000000000 first, then 00000000, then the newest 9xx sections), VISUAL_ROADMAP.md and the docs sections your task points to. They are the source of truth. The owner's bar (2026-10-29): "this needs to start looking like GTA 6". AAA, like a real 2026 game. Realistic and high-poly, never low-poly or cartoon. Tone of the game: silly, over the top, overpowered player; the WORLD is realistic.

## Your starting point
- **Start from `origin/main`** (2026-10-31, build 395+: wave 3 merged through batch 25, the golden-hour review). `git fetch origin main && git checkout -b wt/<slug> origin/main`. Ignore any older line that says fleet/base or a build number.
- Resuming a branch (your task says "resume wt/<slug>"): `git fetch origin wt/<slug> main && git checkout -b wt/<slug> origin/wt/<slug>`, then MERGE `origin/main` into it first thing (read every conflict hunk, keep both sides' intent). The repo clone may be shallow: `git fetch --unshallow` if a merge cannot find a base. Also fetch `shots/<slug>` if it exists and add to it.
- Read docs/HANDOFF.md section 000000000 (the state when wave 3 stopped) and 00000000, then CLAUDE.md's bullet nearest your area and the 9xx HANDOFF section it names.

## Setup (nothing is preinstalled)
- Godot (downloads.godotengine.org is BLOCKED by the network policy; use GitHub):
  `curl -sSL -o godot.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip && unzip -q godot.zip && chmod +x Godot_v4.7.2-stable_linux.x86_64` (keep it OUTSIDE the repo).
- Run `godot --headless --path . --import` once before anything else (about 10 minutes the first time), and again after you add or rebuild any asset.
- Stills need Xvfb and Mesa: `apt-get install -y xvfb mesa-utils libgl1-mesa-dri` if `xvfb-run` is missing. Python: `pip install pillow numpy`.
- Stills: tools/glshot/still_shot.gd (EYE=x,y,z,yaw,pitch for a free camera; SHOTS= for several from one load; --hour=), city_shot.gd, block_shot.tscn (usage in their headers). Frame cost: tools/geo_count.gd under opengl3 + Xvfb, never --headless (every monitor reads 0 there).
- Memory: the box has about 15 GB. Never run two Godot cities at once (a city is ~3 GB headless, 6-7 GB rendered). Never render the whole city on lavapipe (Forward+); small scenes only.
- Colours: read CLAUDE.md's colour-space measurement trap. Use shaders/color_space.gdshaderinc for colour arithmetic in a shader. opengl3 stills are the Compatibility renderer, not what the owner's Mac draws.

## Rules
- Stay in your own area (the list of all 100 is at the end). Prefer NEW files. Where you must touch a shared file (city_chunk.gd, smoke_test.gd, prop_factory.gd, pedestrian.gd, vehicle.gd, traffic_manager.gd, building.gd, landmarks.gd, city_plan.gd, macro_map.gd, player.gd, city.tscn, project.godot), keep the change small and local (a hook line or two, at the END of a list) so the lead can merge 100 branches.
- Every roll is a hash of seed + place, never a chunk / block / Building rng: nothing a seed already builds outside your feature may move. If you claim blocks or lots, do it AFTER every existing roll and override, and skip blocks other features already claim (site, grounds, hospital, school, ...).
- Every new system gets an environment switch `<NAME>=0` that turns it off (the A/B), like the existing ones.
- Measure frame cost before and after with tools/geo_count.gd at a bookmark near your feature; keep it close to flat. FULL chunks real, LOD chunks and the far city cheap. Respect Quality levels and the web build (Compatibility renderer: no Forward+-only features without a fallback).
- The gate must pass before every push of code: `SHARDS=3 GODOT=... tests/headless_check.sh` (~20 min, three processes of ~2.5 GB; ~4,300 checks). Put your checks in a new tests/<slug>_checks.gd loaded by ONE line in tests/smoke_test.gd. Run it at most once an hour; iterate with small probes and tools/shader_check.gd.
- **The gate on main:** `tests/headless_check.sh` already allows the smoke test 2400 s; `SHARDS=3 tests/headless_check.sh` runs it in three processes (~10 min, ~2.4 GB each) and is the fast way to gate. A full run is ~2,375 checks. While you iterate, `SMOKE_PARTS=<part>,<file>_checks` runs just those parts (the names are in tests/smoke_test.gd). A timeout is not a pass.
- **Live systems act on what your checks place** (main's CI failed four times on this): street errands park traffic cars and pull parked ones out, CarLights re-picks every 0.15 s, birds and crowd life roll on their own clocks. Stage your scene (`TrafficManager.staged`, place_car(), the env switches) and wait on conditions, not on fixed frame counts.
- Assets: CC0 / free-for-commercial-use only (Poly Haven, ambientCG, Kenney, Quaternius, CC0 freesound), recorded in docs/ASSETS.md; or built in code / Blender scripts (tools/). Meshy is retired. Never commit secrets.
- Original only: no real brand, company, team, artist, person, building, venue or agency name or logo anywhere (invent names). Public street names may appear. No children in the crowd.
- Places of worship and cemeteries get the Sanctuary zone (CLAUDE.md, the masjid note): no shooting at or into them.
- Docs: a new section at the END of docs/HANDOFF.md ("## 9d?. <title>"; the lead numbers it), one row at the end of VISUAL_ROADMAP.md's table ("| ? |"), one decisions-log entry in docs/GAME_PLAN.md, one new bullet in CLAUDE.md's Technical rules next to the closest topic. Keep the CLAUDE.md bullet short.
- Commit early and often. End every commit message with the attribution lines your own harness gives you (a Co-Authored-By line and the Claude-Session link). Never put a model name in code, docs or commit subjects.
- PUSH ONLY to your own branch wt/<slug>; never to main, fleet/*, or anyone else's branch. Push your code branch as soon as you have a first working commit, and again at least every hour (the last fleet lost four sessions' code that was never pushed). Before your final push MERGE origin/main into it (never rebase, never force-push).

## Screenshots (the owner follows along through them)
- Put stills (jpg, 1280 px wide or less, under about 1 MB each) and a README.md listing them on an ORPHAN branch `shots/<slug>`: `git checkout --orphan shots/<slug>`, clear the tree, commit the images, push; then switch back to wt/<slug>. If that branch already exists from an earlier session, fetch it and add commits on top.
- Push a FIRST batch as soon as you have something to show (a before and a first after), then the final set at the end. Name files so they read on their own (`01_before_street_noon.jpg`, `02_after_street_noon.jpg`, `03_after_night_2100.jpg`).
- If pushing that branch is refused, commit the stills instead in ONE separate last commit on your own branch under .shots/<slug>/, with the subject "SHOTS (lead drops this commit)".

## When you are done
Finish your last message with: branch head, check result (number of checks passed and failed), peak memory of the check if you measured it, frame-cost numbers, the still names, and what is not done or not verified.

## Wave 4's areas (one session each; stay out of the others')
The list is `tasks.tsv` on this branch (wave 2's list is `tasks_w2.tsv`) (slug, kind, task). Kinds: `resume` (finish a paused branch), `refcam` (one of the ten reference cameras: judge that ONE view against a 2026 AAA game, list what reads fake in it, fix the worst three to five things, prove each with a before/after of that camera), `new`, `infra`.

## Refcam sessions, how to work
`tools/refcams/` (README there) shoots the ten reference cameras from one city load: `GODOT=... python3 tools/refcams/refcams.py run build/refcams/<label> --only <camera>` (~6 min for one camera, ~3.5 GB) gives the PNG and its numbers. Shoot the camera on main FIRST (the before). Then look at it the way an art director would: what gives it away as a game? (flat shading, tiling, repeated props, floating things, hard edges where there should be a bevel, lights that do not light anything, people stood still, empty roads, a sky that does not match the light.) Fix the worst things in order of what the eye lands on first. Every fix must hold on the other nine cameras: run the whole set once before your final push and compare with `compare`. Remember the two renderers (opengl3 stills are not the Mac): a colour or lighting change is proved on a SMALL Forward+ scene under lavapipe (CLAUDE.md, the measurement traps), never on the opengl3 still alone.
