# Rando Game — Claude session guide

Read this file and `docs/GAME_PLAN.md` at the start of every session. They are the source of truth.
Update both whenever a design decision changes. Every session starts with no memory.

## Project summary

A 3D open-world chaos sandbox built in **Godot 4.7.2** (GDScript, Forward+ renderer).
No story, no missions, no economy. The player is overpowered: super-high jumps, fast movement,
unlimited guns with no ammo, and a big physics playground to wreck. Tone is silly and over the top.
Visual style is clean low-poly.

All characters, names, vehicles, and art are original. Do not reference or imitate any existing
game's characters, logos, or map.

## How the owner works (important)

- They prompt from a phone and usually cannot open the Godot editor. Everything must be buildable
  by editing text files: `.gd`, `.tscn`, `.tres`, `.gdshader`, `project.godot`. Never leave a step
  that requires clicking something in the editor. If something truly needs the editor, say exactly
  what to do in one or two sentences.
- They playtest on a Mac by pulling from GitHub and pressing Play. Claude cannot see the game run;
  the owner is the eyes. When they report a feel problem ("jump feels floaty"), fix it by tuning
  values and tell them exactly what changed.
- **Push directly to `main`, always.** No feature branches, no pull requests (owner's decision,
  2026-09-19). Keep each push small enough that the test steps fit in a couple of sentences. Put
  "How to test" steps and the tunable values most likely to need changing in the final chat
  message, and a short version in the commit body.
- Before committing, run the headless check (below). Never push a project that fails to load.

## How the owner plays a build (no Terminal, no Godot needed)

Every push to `main` runs `.github/workflows/godot-check.yml`, which runs the headless check,
exports a macOS app (universal, ad-hoc signed, no notarization) and publishes it as a GitHub
Release. The owner downloads the newest zip from
https://github.com/ashalluf/rando-game/releases/latest and double-clicks `Rando Game.app`.
First launch of each download may need System Settings > Privacy & Security > **Open Anyway**.
The export preset lives in `export_presets.cfg` (committed, contains no credentials).

The same workflow also exports a **web build** (single-threaded, Compatibility renderer, no
special headers needed) and, when the repo is public, deploys it to GitHub Pages at
https://ashalluf.github.io/rando-game/ so the owner can play in a browser with nothing installed.
While the repo is private the deploy job is skipped and the web build is only a workflow artifact.
One-time setup already done by the owner: repo Settings > Pages > Source = "GitHub Actions". The
workflow token cannot create the Pages site itself, so if the deploy job ever fails with "Resource
not accessible by integration", that setting was lost and the owner has to set it again.

Tell the owner the build number or link at the end of every push. A push is not "done" until the
workflow has published its release; check the Actions run if in doubt.

Claude can see the web build: export it locally, serve `build/web`, load it in headless Chromium
with Playwright (`--use-angle=swiftshader`), and screenshot it. Use this to sanity-check visuals.

## Opening the project in the editor (optional)

1. Install Godot 4.7.2 (standard build, not .NET) from godotengine.org.
2. Clone the repo with GitHub Desktop (or `git clone`). The repo root *is* the Godot project.
3. Open Godot, click **Import**, pick `project.godot`, then **Import & Edit**. This is a one-time step.
4. Press **Play** (F5). After that, "Fetch origin" in GitHub Desktop updates the project in place.

## Headless check (run before every commit)

```
GODOT=/path/to/godot tests/headless_check.sh
```

That runs `--import` and then `tests/smoke_test.gd`, which loads the test room, drives the player
with simulated input (movement, boost, jumps, every weapon), checks buildings, then loads the city
scene and checks streaming, re-centering and destruction persistence. It fails on any script error
in the output. Gotchas: the test script is compiled before autoloads exist, so never name an
autoload or a class that uses one (`CityChunk`, `CityStreamer`) as a type there (look them up with
`root.get_node("/root/WorldState")` and untyped vars); and `root.add_child()` from `_initialize()`
is deferred, so await a frame before using the scene.
Download a Linux headless-capable build with:

```
curl -sSL -o godot.zip "https://downloads.godotengine.org/?version=4.7.2&flavor=stable&slug=linux.x86_64.zip"
unzip -q godot.zip && chmod +x Godot_v4.7.2-stable_linux.x86_64
```

CI (`.github/workflows/godot-check.yml`) runs the same check on every push, then exports the Mac
build. To export locally, install the macOS template from the 4.7.2 `export_templates.tpz` into
`~/.local/share/godot/export_templates/4.7.2.stable/` and run
`godot --headless --path . --export-release "macOS" build/RandoGame-macOS.zip`.

## Technical rules

- Godot 4.7.2, GDScript, Forward+ on desktop. The web build uses the Compatibility renderer
  (Godot picks it automatically for web), so any effect must degrade gracefully there: avoid
  Forward+-only features (SDFGI, volumetric fog, SSR, compute shaders) or gate them on
  `OS.has_feature("web")`. On web the mouse is only captured after a click.
- All feel-related numbers (jump height, gravity, speed, air control, camera distance, gun force,
  explosion radius, ...) are `@export` variables grouped at the top of each script with a one-line
  `##` doc comment so they are easy to find and tune.
- Built-in primitive meshes and CSG only (greybox). No external assets until asked. When assets are
  added later, only CC0 / free-for-commercial-use packs (Kenney, Quaternius); record source and
  license in `docs/ASSETS.md`.
- The world is generated by code from a single integer seed, never hand-placed. Same seed, same city.
- Performance guardrails from the start (see `scripts/util/physics_budget.gd`): cap active physics
  bodies, despawn debris after a timeout, only simulate physics near the player.
- Never commit secrets or API keys. `.godot/` and `build/` stay ignored. Commit `*.uid`,
  `*.import` and `export_presets.cfg`.
- `textures/vram_compression/import_etc2_astc=true` must stay on: the universal macOS export
  (Apple Silicon) refuses to build without it.

## Folder structure

```
project.godot
CLAUDE.md
docs/GAME_PLAN.md      roadmap, checkboxes, decisions log
docs/ASSETS.md         asset sources and licenses
scenes/                player, levels, props, vehicles, ui
scripts/               player, weapons, world, vehicles, npc, util, ui
shaders/
assets/                empty for now
tests/                 headless smoke test and check script
```

## Conventions

- GDScript style: tabs, `snake_case` files and functions, `PascalCase` class names, typed variables
  (`var x: int = 0` or `:=` when the type is inferable). Private members start with `_`.
- Scenes are hand-written `.tscn` text. Prefer building content in code from a seed over placing
  nodes in scene files. Scene files hold structure (lights, environment, player instance), scripts
  hold content.
- Physics layers: 1 `world` (static), 2 `player`, 3 `props` (rigid bodies). Player mask = world+props.
  Crates: layer props, mask all three. The camera spring arm collides with `world` only.
- Node groups: `player` (the player body), `physics_prop` (every rigid prop PhysicsBudget manages),
  `debris` (short-lived props that get freed after a timeout).
- Autoloads: `PhysicsBudget` (`scripts/util/physics_budget.gd`), `WorldState`
  (`scripts/util/world_state.gd`).
- Input actions live in `project.godot` under `[input]`. Current actions: `move_forward/back/left/right`,
  `jump`, `boost` (Shift / gamepad B), `look_left/right/up/down` (right stick), `fire`, `alt_fire`,
  `next_weapon`, `prev_weapon`, `weapon_1..3`, `respawn`, `toggle_mouse`, `toggle_hud`. Add new
  actions there. There is no sprint; boost replaced it.
- Weapons: subclass `Weapon` (`scripts/weapons/weapon.gd`), build the model in `_build_model()` with
  the `_box` / `_cylinder` helpers, call `_make_muzzle()`, implement `_fire(aim)`. Register it in
  `WeaponManager._ready()`. Effects go through `WeaponFX` static functions. `Player.get_aim()` is
  the crosshair ray (origin, direction, point, normal, collider). Explosions: `Explosion.blast()`.
- City: `CityPlan` (lazy, endless data: `road_pos()`, `road_width()`, `block()`, `intersection()`,
  `block_index_at()`, `district_at()`; `DISTRICTS` holds the parameter ranges), `CityStreamer`
  (scene root of `scenes/levels/city.tscn`: streams chunks, ground follow, origin re-centering) and
  `CityChunk` (builds one block at FULL or LOD level). Small repeated props go through
  `MultiMeshBatch` with meshes from `PropFactory`. Breakable props are registered with
  `CityChunk._add_prop()` (instances + shapes + health); their shapes live on the chunk's
  `StreetProps` body, which routes `take_hit()` to the chunk. Physics props (trash cans) are
  `TrashCan` RigidBody3D nodes in the `physics_prop` group.
- Map: `MacroMap` (`scripts/world/macro_map.gd`) decides zone (city, beach, ocean, hills), land
  height and district for any world XZ. `CityPlan.macro` holds it; `zone_at()` / `height_at()` on
  the plan go through it. Chunks build water, sand or terrain for non-city zones. To start
  somewhere else for testing: web `?spawn=x,z`, desktop `-- --spawn=x,z`.
- Autoload `WorldState`: `world_offset` (local + offset = true world position, use `to_world()` /
  `to_local()`) and the destroyed-prop registry (`mark_destroyed`, `is_destroyed`).
- Anything that must survive origin re-centering has to be a 3D child of the scene root (the
  streamer shifts every Node3D child). Store true world positions only via `WorldState.to_world()`.
- Buildings: `Building` (`scripts/world/building.gd`, scene `scenes/props/building.tscn`) is a
  StaticBody3D. Set `seed`, `lot_size`, `min_height`, `max_height` before adding it to the tree; it
  generates in `_ready()`. Every box part uses `shaders/building.gdshader` with its own
  ShaderMaterial (see the decisions log for why). Rooftop props are primitives built in code.
- Physics masks as constants on `Player`: `AIM_MASK` (world + props) and `BLAST_MASK` (player + props).
- Forward is -Z. Yaw for a facing direction `d` is `atan2(-d.x, -d.z)`.
- Commit messages: short imperative subject, body explains why and how to test. One task per
  commit (or a few), pushed straight to `main`.
