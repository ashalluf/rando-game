# Rando Game — Claude session guide

Read this file, `docs/GAME_PLAN.md` and `docs/HANDOFF.md` at the start of every session. The first
two are the source of truth; the handoff is the narrative (state, workflow, gotchas, next steps)
for a session on any account. Update all of them whenever a design decision changes. Every
session starts with no memory.

## Project summary

A 3D open-world chaos sandbox built in **Godot 4.7.2** (GDScript, Forward+ renderer).
No story, no missions, no economy. The player is overpowered: super-high jumps, fast movement,
unlimited guns with no ammo, and a big physics playground to wreck. Tone is silly and over the top.
Visual style is **realistic and high-poly** (owner's decision 2026-09-19: no low-poly look, the
target is console quality). Real models and PBR textures for everything the player gets close to;
primitives only for far LOD boxes and tiny repeated bits (dashes, stripes, grass).

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

**Always put screenshots in the chat** (web build via the harness below, `SendUserFile`) for
every visual change, before and after pushing, so the owner never has to fetch just to look.
Tell the owner the build number or link at the end of every push. A push is not "done" until the
workflow has published its release; check the Actions run if in doubt.

Claude can see the web build: export it locally, then `tools/webshot/webshot.js` (Playwright,
headless Chromium with `--use-angle=swiftshader`) serves `build/web` and screenshots it. Use this
to sanity-check visuals.
It runs at about 1 FPS there and Godot clamps frame time, so never press movement keys in the
harness (a 1 ms tap walks the player meters); place the camera with `?spawn=x,z,yaw,pitch` and use
`?showroom` to line up generated assets. Lighting is flat on the web; judge materials, not light.

## Opening the project in the editor (optional)

1. Install Godot 4.7.2 (standard build, not .NET) from godotengine.org.
2. Clone the repo with GitHub Desktop (or `git clone`). The repo root *is* the Godot project.
3. Open Godot, click **Import**, pick `project.godot`, then **Import & Edit**. This is a one-time step.
4. Press **Play** (F5). After that, "Fetch origin" in GitHub Desktop updates the project in place.

## Headless check (run before every commit)

```
GODOT=/path/to/godot tests/headless_check.sh
```

That runs `--import` and then `tests/smoke_test.tscn` (a scene, so autoloads exist before the
test script compiles), which loads the test room, drives the player
with simulated input (movement, boost, jumps, every weapon), checks buildings, then loads the city
scene and checks streaming, re-centering, destruction persistence, cars, pedestrians and traffic.
It fails on any script error or NaN warning in the output. Gotchas: the test script is compiled before autoloads exist, so never name an
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
- Buildings, lamps, signs and trees are still primitives and code (next in line for real assets).
  Street props are CC0 Poly Haven models: download the 1K glTF from `api.polyhaven.com/files/<id>`,
  pack it with `python3 tools/pack_gltf.py <id>.gltf assets/models/prop_<name>.glb`, get the mesh
  through `PropFactory.model_<name>()` (which uses `PropFactory.model_mesh()` to pick the variant
  nodes, move them to the origin and merge them into one ArrayMesh with LODs, so they batch like
  primitives), commit the `.glb`, the extracted textures and every `.import`, add a row to
  `docs/ASSETS.md`. Physics ones use `PhysicsProp` (`scripts/world/physics_prop.gd`).
  Trees, bushes and rocks come from Poly Haven too but must go through
  `tools/decimate_tree.py` first (leaf cards, decimated trunks and twigs; see its docstring).
  **Meshy is retired (owner, 2026-09-19): do not generate new Meshy models.** The existing
  cars, pedestrians and jets were made with the owner's Meshy account: `python3 tools/meshy.py gen <name> "<prompt>"
  [--rig h --anims ids]` (key from `MESHY_API_KEY` or `MESHY_KEY_FILE`, never in the repo), then
  `python3 tools/shrink_glb.py assets/models/<name>.glb`, commit the `.glb`, its `.json`, the
  extracted `_N.jpg` textures and all `.import` files, and add a row to `docs/ASSETS.md`.
  **Owner's rule: every Meshy prompt asks for the most ultra-realistic result possible** (the
  tool appends that wording itself; never pass `--plain` or ask for cartoon / low-poly looks).
  Rigged models: skeleton in cm under a 0.01 armature, so set `custom_aabb` on the skinned mesh
  (see `Pedestrian._add_model()`); they face +Z. `?showroom` on the web (`-- --showroom` on
  desktop) lines up every car type, pedestrian model and street prop model at the spawn (`&nohud` hides
  the HUD for screenshots).
  Textures are allowed too (owner asked for the
  realism pass): only CC0 / free-for-commercial-use sources (ambientCG, Poly Haven, Kenney,
  Quaternius), 1K JPG, Color + NormalGL + Roughness only, recorded in `docs/ASSETS.md`. Get
  materials through `PropFactory.pbr(set_key, meters_per_tile, tint)` and `PropFactory.texture()`;
  set keys are in `PropFactory.TEXTURE_SETS`. New texture `.import` files must be switched to
  `compress/mode=2`, `mipmaps/generate=true`, `detect_3d/compress_to=0` (and `compress/normal_map=1`
  for normal maps) and committed.
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
assets/                textures/ (CC0 sets) and models/ (Meshy .glb + .json)
tests/                 headless smoke test and check script
tools/                 meshy.py, shrink_glb.py, webshot/ (screenshot harness)
```

## Conventions

- GDScript style: tabs, `snake_case` files and functions, `PascalCase` class names, typed variables
  (`var x: int = 0` or `:=` when the type is inferable). Private members start with `_`.
- Scenes are hand-written `.tscn` text. Prefer building content in code from a seed over placing
  nodes in scene files. Scene files hold structure (lights, environment, player instance), scripts
  hold content.
- Physics layers: 1 `world` (static), 2 `player`, 3 `props` (rigid bodies), 4 `npc` (pedestrians),
  5 `terrain` (hill heightmaps, in addition to world). Player mask = world+props.
  Crates: layer props, mask all three. The camera spring arm collides with `world` only.
- Node groups: `player` (the player body), `physics_prop` (every rigid prop PhysicsBudget manages),
  `debris` (short-lived props that get freed after a timeout).
- Autoloads: `PhysicsBudget` (`scripts/util/physics_budget.gd`), `WorldState`
  (`scripts/util/world_state.gd`), `Sfx` (`scripts/util/sfx.gd`, synthesized sounds:
  `Sfx.play(name, position)`, `Sfx.loop_player(name)`).
- Day/night: `DayNight` node in the city scene drives the sun, the sky (`shaders/sky.gdshader`,
  a ShaderMaterial on the Environment's Sky: gradient, sun disc, FBM clouds, stars; colors set per
  hour via `set_shader_parameter`) and the `night_factor` shader global (`[shader_globals]` in
  project.godot). Shaders that should react to night read it with
  `global uniform float night_factor;`.
- Weather: `Weather` node in the city scene (`scripts/world/weather.gd`): states clear, overcast,
  rain, storm; drives DayNight (`cloud_extra`, `weather_darken`), fog, rain particles, wet roads
  (`PropFactory.set_wetness`), the `wind_factor`, `wave_scale` and `tsunami_scale` shader globals,
  lightning (sky `flash` uniform, sun meta `weather_flash`) and thunder. The ocean is
  `shaders/ocean.gdshader` on a subdivided plane per water chunk. Debug `?weather=storm`.
- HUD: `scenes/ui/debug_hud.tscn` holds the stats, weapon list, crosshair and the round minimap
  (`MinimapFrame/Minimap`, `scripts/ui/minimap.gd`, drawn from `CityPlan` data, rotates with the
  camera heading, light map palette). Lighting and post-processing
  live in the city scene's Environment (SDFGI, SSAO, SSR, glow, ACES, volumetric fog); keep the
  distance fog too, it is what the web build sees.
- Pause menu (`scenes/ui/pause_menu.tscn`) owns Esc: pause, mouse release, seed rebuild via
  `WorldState.pending_seed` + `reload_current_scene()`.
- Input actions live in `project.godot` under `[input]`. Current actions: `move_forward/back/left/right`,
  `jump`, `boost` (Shift / gamepad B), `look_left/right/up/down` (right stick), `fire`, `alt_fire`,
  `next_weapon`, `prev_weapon`, `weapon_1..3`, `interact` (E / gamepad Y), `respawn`,
  `toggle_mouse`, `toggle_hud`. Add new actions there. There is no sprint; boost replaced it. In a
  jet: boost = throttle up, alt_fire = throttle down, move axes = pitch and roll.
- NPCs: `Pedestrian` (wanders a block's sidewalk ring, `knock(impulse)` turns it into a `Ragdoll`
  debris) and `TrafficManager` (kinematic `Vehicle`s with `traffic` state driving the lanes).
  Never freeze a VehicleBody3D and never give a kinematic one VehicleWheel3D nodes: NaN.
  Population (owner, 2026-09-20: "an actual very populated city", densest downtown, thinning
  outward, the airport jam-packed): `"people"` and `"parked"` per block live in
  `CityPlan.DISTRICTS` (the downtown core doubles people via `skyline_boost`), the caps are
  `CityStreamer.max_pedestrians` / `traffic_cars` (web values lower). Traffic count and speed
  follow `TrafficManager.density_at()` (1.0 downtown core, `edge_density` at the edges, 1.0
  again around the terminal). The airport drop-off is `MacroMap.terminal_curb` (crowd from the
  airport chunk, `airport_crowd`) plus `MacroMap.terminal_loops`, two closed lane paths that
  `TrafficManager` fills bumper to bumper (`loop_cars`, `max_loop_cars`) while the player is
  within `loop_active_distance`; the road itself is built by `Landmarks._build_dropoff()`.
- Vehicles: `Vehicle` (`scripts/vehicles/vehicle.gd`), a VehicleBody3D built in code;
  `Vehicle.random_car(rng)` for a seeded one. Handling numbers are exports at the top. The player's
  `enter_vehicle()` / `exit_vehicle()` handle riding; the car reads input while `driver` is set.
  Space jumps the car, right click is the handbrake. Parked cars live under the city root (not
  their chunk) so a driven one survives chunk unloads; never `reparent()` a VehicleBody3D (wheels
  re-read their animated transform as the mount point and the car sinks). `Player` recovers from
  falling through the world (below `fall_through_y`) or ending up under hill terrain (a body with
  meta `terrain` above it) via `CityStreamer.surface_height_at()`; skip world queries for two
  frames after an origin shift (`_query_hold`), the broadphase lags.
- Aircraft: `Aircraft` (`scripts/vehicles/aircraft.gd`) extends `Vehicle`; kinds PRIVATE and
  AIRLINER, flight numbers are exports at the top, models in `MODELS`. Jets spawn at
  `MacroMap.apron_spots` from the airport chunk. Terrain bodies carry `CityChunk.TERRAIN_LAYER`
  (bit 5) and the player's under-terrain ray uses only that layer.
- Weapons: subclass `Weapon` (`scripts/weapons/weapon.gd`), build the model in `_build_model()` with
  the `_box` / `_cylinder` helpers, call `_make_muzzle()`, implement `_fire(aim)`. Register it in
  `WeaponManager._ready()`. Effects go through `WeaponFX` static functions. `Player.get_aim()` is
  the crosshair ray (origin, direction, point, normal, collider). Explosions: `Explosion.blast()`.
- City: `CityPlan` (lazy, endless data: `road_pos()`, `road_width()`, `block()`, `intersection()`,
  `block_index_at()`, `district_at()`; `DISTRICTS` holds the parameter ranges for DOWNTOWN,
  MIDTOWN, SUBURBS, INDUSTRIAL and CAMPUS), `CityStreamer`
  (scene root of `scenes/levels/city.tscn`: streams chunks, ground follow, origin re-centering) and
  `CityChunk` (builds one block at FULL or LOD level). Small repeated props go through
  `MultiMeshBatch` with meshes from `PropFactory`. Breakable props are registered with
  `CityChunk._add_prop()` (instances + shapes + health); their shapes live on the chunk's
  `StreetProps` body, which routes `take_hit()` to the chunk. Physics props (trash cans) are
  `TrashCan` RigidBody3D nodes in the `physics_prop` group. Street furniture and markings live in
  `StreetDetail` (`scripts/world/street_detail.gd`, static, seeded per block and intersection);
  street names come from `CityPlan.road_name()`.
  Shopping plazas, big-box stores, fast-food and gas-station pads are `Commercial`
  (`scripts/world/commercial.gd`); block kinds `MALL` and `BIGBOX` and the `pads` odds live in
  `CityPlan.DISTRICTS`. Shop names are original, never brands.
- Map: `MacroMap` (`scripts/world/macro_map.gd`) decides zone (city, beach, ocean, hills, airport,
  port), land height and district for any world XZ. The city itself rolls: `relief_at()` is the
  gentle height field under the blocks (zero on beaches, flat zones, mountain hills and around
  landmarks) and `height_at()` includes it. In a chunk, sample it only through `_gy()`: the
  multimesh batch adds it to every instance, `_add_slab()` builds relief-following grids for thin
  city ground, `_add_prop()` lifts shapes; nodes you add yourself (bodies, buildings) need
  `+ _gy(x, z)` explicitly. Never add it twice. `CityPlan.macro` holds it; `zone_at()` / `height_at()` on
  the plan go through it. `height_at()` is the terrain with hill roads and mansion pads carved in
  (`raw_height_at()` is the noise alone); `MacroMap.hill_roads` (`HillRoads`, seeded polylines
  with grade-limited height profiles, `carve()`, `segments_in()`, `mansions_in()`) is what hill
  chunks build asphalt strips and estates from. Chunks build water, sand or terrain for non-city
  zones; the water surface is at y 0.15 (above the ground follower plane). To start
  somewhere else for testing: web `?spawn=x,z,yaw,pitch[,y]`, desktop `-- --spawn=x,z,yaw,pitch[,y]`.
- Landmarks: `Landmarks.all()` lists them (id, world anchor, radius); `Landmarks.build()` makes
  one, detailed (with a StaticBody3D for shapes) or far (no collision). Add a new one by adding an
  entry and a `_build_<id>()` function. Everything original: no real names, logos or copies.
- Autoload `WorldState`: `world_offset` (local + offset = true world position, use `to_world()` /
  `to_local()`) and the destroyed-prop registry (`mark_destroyed`, `is_destroyed`).
- Anything that must survive origin re-centering has to be a 3D child of the scene root (the
  streamer shifts every Node3D child). Store true world positions only via `WorldState.to_world()`.
- Buildings: `Building` (`scripts/world/building.gd`, scene `scenes/props/building.tscn`) is a
  StaticBody3D. Set `seed`, `lot_size`, `min_height`, `max_height` before adding it to the tree; it
  generates in `_ready()`. Every box part uses `shaders/building.gdshader` with its own
  ShaderMaterial (see the decisions log for why). Rooftop props are primitives built in code.
- Player body: `Avatar` (`scripts/player/avatar.gd`, built by `Player._build_avatar()` from
  `avatar_model`, one of `Pedestrian.MODELS`): idle / walk / run clips picked by speed, frozen or
  slowed stride in the air, forward lean while boosting. The orange capsule in `player.tscn` is
  only the fallback when the model file is missing. `Pedestrian.prepare_rig()` is the shared fix
  for every instantiated rig (AABB, materials). Knocked pedestrians become `Ragdoll`s that keep
  the same rigged model as one tumbling body (`build_from_rig`); far pedestrians move and animate
  every 3rd / 6th physics frame (`Pedestrian.lod_mid` / `lod_far`).
- Performance: `Quality` node in the city scene (`scripts/util/quality.gd`) measures the frame
  rate after start-up and steps HIGH -> MEDIUM (no SDFGI, no volumetric fog) -> LOW (no SSR, no
  SSAO, 0.8 render scale) when it drops under `min_fps`; the HUD shows the level; force one with
  `-- --quality=N`. Building window frames are flat quads drawn out to `Building.FRAME_DRAW_DISTANCE`.
- Native screenshots without a browser: `tools/glshot/building_shot.gd` (one building) and
  `tools/glshot/city_shot.gd` (the city at a `--spawn`) render with the real OpenGL renderer under
  Xvfb + llvmpipe in ~20 s; usage lines in the files. Use these before the web harness.
- Physics masks as constants on `Player`: `AIM_MASK` (world + props) and `BLAST_MASK` (player + props).
- Forward is -Z. Yaw for a facing direction `d` is `atan2(-d.x, -d.z)`.
- Commit messages: short imperative subject, body explains why and how to test. One task per
  commit (or a few), pushed straight to `main`.
