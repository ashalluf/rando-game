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
  **Meshy is retired (owner, 2026-09-19) EXCEPT for characters (owner, 2026-09-22: "we need
  entirely new assets for the humans").** Cars, jets, props and scenery stay Poly Haven / code.
  People are the one exception because no CC0 source has realistic rigged humans: Poly Haven
  has none and Quaternius' are stylised low-poly, which breaks the realism rule. Generate
  characters at `--polycount 16000` - the default 8000 is what made the first three look
  blocky - with a `--texture-prompt` for skin and fabric. The existing
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
  **Masks are what the physics engine pairs on, so they cost CPU.** GodotPhysics makes a pair
  for every two overlapping objects where either one's mask has the other's layer, and re-pairs
  a moving body against everything its bounds cross, whether or not the pair can ever collide.
  So: static bodies (buildings, street props, the ground) have mask **0** - a static body never
  detects anything, and every moving body that must hit the world already has world in its own
  mask. Detector `Area3D`s (car bumpers, pedestrian hit zones) are `monitorable = false`, which
  moves them to the broadphase's static tree so moving one is not tested against the whole
  city. Kinematic bodies that are placed rather than simulated drop their mask: traffic cars
  (`Vehicle._mask()`, restored when one drops out of traffic) and pedestrians past
  `Pedestrian.physics_range` (whose hit zone also leaves the broadphase). Queries - bullets,
  blasts, bumpers - test layers, not masks, so none of this changes what can be hit.
- Node groups: `player` (the player body), `physics_prop` (every rigid prop PhysicsBudget manages),
  `debris` (short-lived props that get freed after a timeout).
- Autoloads: `PhysicsBudget` (`scripts/util/physics_budget.gd`), `WorldState`
  (`scripts/util/world_state.gd`), `Sfx` (`scripts/util/sfx.gd`:
  `Sfx.play(name, position)`, `Sfx.loop_player(name)`).
  Sound is **real CC0 recordings** (`assets/audio/`, 32 clips, sources in `docs/ASSETS.md`) with
  the old synthesis kept as the fallback: `_build_synth()` fills every name first and
  `_load_samples()` replaces only the names whose files load, so a missing or unimported file
  degrades to a tone rather than to silence. A name holds several takes and `play()` picks one at
  random, which is what stops the rifle and the footsteps sounding like one file on repeat. Loop
  flags are set on the stream **in code**, never in the `.import`: a regenerated `.import` can
  silently drop the flag, and a non-looping ambience is very hard to diagnose. Only the clips
  named in `Sfx.SAMPLES` ship - do not leave working downloads in `assets/audio/`, this builds
  into a macOS app and a web page.
- Day/night: `DayNight` node in the city scene drives the sun, the sky (`shaders/sky.gdshader`,
  a ShaderMaterial on the Environment's Sky: gradient, sun disc, FBM clouds, stars; colors set per
  hour via `set_shader_parameter`) and the `night_factor` shader global (`[shader_globals]` in
  project.godot). Shaders that should react to night read it with
  `global uniform float night_factor;`. Clouds are lit by stepping the same noise field toward
  the sun and darkening where there is more of it in the way, which is what gives them bright
  shoulders and grey undersides; above them is a sheared cirrus deck. Both cost three extra
  noise taps, so `Quality` clears `cloud_detail` on the web and below MEDIUM.
- Weather: `Weather` node in the city scene (`scripts/world/weather.gd`): states clear, overcast,
  rain, storm; drives DayNight (`cloud_extra`, `weather_darken`), fog, rain particles, wet roads
  (`PropFactory.set_wetness`), the `wind_factor`, `wave_scale` and `tsunami_scale` shader globals,
  lightning (sky `flash` uniform, sun meta `weather_flash`) and thunder. The ocean is
  `shaders/ocean.gdshader` on a subdivided plane per water chunk: Gerstner swells in the vertex
  shader, foam on the crests, and the sky mixed in by fresnel with a glare path to the sun,
  taken from the `sky_tint` and `sun_direction` shader globals that `DayNight` publishes (water
  is mostly the sky seen in it, and leaving that to reflections gives nothing on the web). Debug `?weather=storm`.
  Rain at night is judged by the wet street, so: `Weather` starts as wet as the weather it
  starts in (soaking from dry spent the first 16 s on dry tarmac under a downpour); a soaked
  road is roughness 0.07 with mirror puddles at 0.02 (`road.gdshader`, spreading as it soaks),
  because at 0.18 SSR only gave a smear and the lit windows standing in the street are the
  whole look; drops are lit (with a faint glow of their own) and fade out within 5 m of the
  lens, splashes are lit like the road, and the lens rain is a few dozen drops at the frame
  edges - at 1,800 evenly spread it read as television static over the picture.
- Look (owner, 2026-09-20: "as realistic as possible, like an industry giant made it"). The
  realism settings are deliberate, not defaults: **AgX** filmic tonemapping (not ACES, which
  clips highlights hard), **sky-source ambient** so shadows take the sky's colour instead of a
  flat grey fill (`DayNight` sets it every frame; never put it back to `AMBIENT_SOURCE_COLOR`),
  **SSIL** indirect bounce, **aerial-perspective fog** (`fog_aerial_perspective`, which tints
  distance haze with the sky per direction) plus **height fog** so haze pools in the streets and
  towers rise out of it, and **auto exposure** on the player camera. Antialiasing is temporal at
  every level: TAA at native resolution, FSR 2.2 when `Quality` upscales. MSAA stays off (it
  costs a lot and does nothing for shader aliasing). Car paint is a metallic basecoat under a
  clearcoat lobe with flake (`shaders/car_paint.gdshader`); `Vehicle.PAINTS` is weighted the way
  a real car park looks (mostly white/black/grey/silver). Grass is tapered curved blades whose
  normals are bent toward up so a lawn lights as a carpet, not as a pile of lit slivers.
- Vignette: `CityStreamer._build_vignette()` puts `shaders/vignette.gdshader` on a full-rect
  `ColorRect` in its own CanvasLayer at layer -1, so it sits under the HUD, survives F1 and
  shows up in screenshots. `CityStreamer.vignette_strength` (0 turns it off). Every lens does
  this; keep it subtle enough that you cannot point at it.
- HUD: `scenes/ui/debug_hud.tscn` holds the stats, weapon list, crosshair and the round minimap.
  F1 cycles three modes (`DebugHud.Mode`): CLEAN (crosshair, minimap, weapons - the default, and
  what the game looks like while playing), FULL (plus the stats line, the frame-time breakdown
  and the control hints) and HIDDEN. `-- --nohud` starts HIDDEN (the screenshot harness),
  `-- --stats` starts FULL
  (`MinimapFrame/Minimap`, `scripts/ui/minimap.gd`, drawn from `CityPlan` data, rotates with the
  camera heading, light map palette). Lighting and post-processing
  live in the city scene's Environment (SDFGI, SSAO, SSR, glow, AgX, volumetric fog) along with
  the **look LUT** - a `Gradient` / `GradientTexture1D` pair wired to
  `adjustment_color_correction`, which Godot runs each channel through after tonemapping. AgX
  expects a contrast curve on the other side of it and without one every frame comes out as the
  flat middle of the AgX ramp; that LUT is it, so `adjustment_contrast` stays at 1.0 rather than
  stacking a second curve on top. `DayNight` drives `tonemap_exposure` (`day_exposure` /
  `night_exposure`) off `moonlight`, a slower ramp than `night_factor` - night_factor is 1.0
  three degrees after sunset, which is right for the lamps and wrong for the light. Note the
  player camera ALSO runs auto exposure (`player.tscn`, `CameraAttributesPractical`, sensitivity
  200..620), so `tonemap_exposure` stacks on top of an adaptation that is already happening -
  which is why a night value that looks right at 21:00 can be a stop hot at 18:30. Keep the
  distance fog too, it is what the web build sees. Judge any of this with
  `tools/glshot/forward_shot.sh`, never the opengl3 path, and measure it rather than squinting:
  `python3 -c "from PIL import Image; import numpy as np; g=np.asarray(Image.open('shot.png').convert('L')).astype(float); print([round(float(np.percentile(g,p))) for p in (1,5,50,95,99)])"`.
  A midday city frame wants a p5/p50/p95 spread like 87/123/175; 78/103/137 is the washed-out
  look the grade was added to fix.
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
  Building a car is ~35 ms on a slow machine, so `TrafficManager` never builds more than
  `builds_per_frame` a frame: the half-second upkeep queues its spawns (streets, loop, freeway,
  served in turn) and cars that drive out of range go to a pool (`pool_size`) to be reused
  rather than freed and rebuilt. The upkeep used to build up to 34 in one tick. Parked cars
  are one chunk build step each for the same reason. Walkers spend the crowd cap through
  `CityStreamer.take_crowd_room()`, one city-wide count a frame (redone whenever the cap
  moves or a chunk leaves): a chunk that counted its own room when its crowd began kept that
  number for frames, so it went on filling a cap `Quality` had lowered in the meantime.
- Cars fly (owner, 2026-09-20: "easily fly cars around the way I fly the main character"). A
  car that leaves the ground goes into stabilised flight (`Vehicle._fly()`): it holds itself
  level instead of tumbling, the stick aims it (W/S nose down/up, A/D turn with a bank), and
  holding boost thrusts it along the camera direction with almost no gravity, like the player's
  boost. There is no flip torque any more. A jump pushes straight up in world space and zeroes
  the spin, because pushing along the car's own up axis while the suspension unloads is what
  tipped the nose over. Thrust must be an impulse scaled by the step, not `apply_central_force`:
  VehicleBody3D clears the per-step force accumulator while solving its wheels, so plain forces
  do nothing.
- Vehicles: `Vehicle` (`scripts/vehicles/vehicle.gd`), a VehicleBody3D built in code;
  `Vehicle.random_car(rng)` for a seeded one. Handling numbers are exports at the top. The player's
  `enter_vehicle()` / `exit_vehicle()` handle riding; the car reads input while `driver` is set.
  Space jumps the car, right click is the handbrake. Parked cars live under the city root (not
  their chunk) so a driven one survives chunk unloads; never `reparent()` a VehicleBody3D (wheels
  re-read their animated transform as the mount point and the car sinks). `Player` recovers from
  falling through the world (below `fall_through_y`) or ending up under hill terrain (a body with
  meta `terrain` above it) via `CityStreamer.surface_height_at()`; skip world queries for two
  frames after an origin shift (`_query_hold`), the broadphase lags.
  **A VehicleBody3D never sleeps on its own in Godot Physics**: it is sent to sleep inside the
  step, then its state callback runs and the suspension's `apply_impulse` wakes it again, while
  its `sleeping` flag reads true. So every parked car was simulated every step, four wheel rays
  each (16 % of all CPU). `Vehicle.settle()`, called from PhysicsBudget's *physics* tick (between
  the callbacks and the next step, the only place it sticks), sleeps an empty car at rest on its
  wheels; check `PhysicsServer3D.body_get_state(rid, BODY_STATE_SLEEPING)`, never the flag. Empty
  cars hold `parking_brake` below `parking_speed` - the old 2.0 let them roll down every slope.
  Parking and traffic lanes come from `CityPlan.parking_offset()` / `lane_center()`: the parking
  lane was 4.4 m wide and the kerb-side traffic lane ran 13 cm from the parked cars, so traffic
  plowed through them.
- Aircraft: `Aircraft` (`scripts/vehicles/aircraft.gd`) extends `Vehicle`; kinds PRIVATE and
  AIRLINER, flight numbers are exports at the top, models in `MODELS`. Jets spawn at
  `MacroMap.apron_spots` from the airport chunk. Terrain bodies carry `CityChunk.TERRAIN_LAYER`
  (bit 5) and the player's under-terrain ray uses only that layer.
- Shop signs: storefront sign bands carry real names. `Building` picks how many window bays
  make one shop per face (`_shop_spans()`, hashed from the seed, never from `_rng`) and passes
  it to the shader as `shop_span`, so the bands the shader draws and the `TextMesh` names the
  script places line up. One `MeshInstance3D` per name, shadows off, stops drawing past
  `Building.SIGN_DRAW_DISTANCE`, and skipped entirely on web. Names are in
  `Building.SHOP_NAMES` and are original, never a real brand. Note the shader measures its `u`
  the opposite way round the box from the script's `a` on every face, so a run's centre has to
  be mirrored.
- Night lighting: the city has no real lights except the sun, so at night it was pitch black.
  Every street lamp now carries an `OmniLight3D` in the `lamp_light` group (FULL chunks only,
  distance-faded, no shadows) whose energy `DayNight` sets from `night_factor` on a 0.35 s tick
  - not only when the value changes, or lamps that streamed in since the last change stay dark -
  and `Quality` zeroes `DayNight.lamp_scale` below MEDIUM. The level is
  `max(night_factor, weather_darken * 0.85)`, published as the `lamp_factor` shader global, so
  the lamps come on in a storm at noon too. Alongside it, and always on, is the
  additive night quad (`shaders/light_pool.gdshader`, which reads `lamp_factor`,
  `PropFactory.light_pool()` / `lamp_face()` / `vehicle_lights()`): a pool of light on the
  pavement under each lamp (in the lamp's batch, so shooting the lamp takes its light with it)
  and head, tail and beam lights on every `Vehicle` (`_add_night_lights`, needed because
  `Vehicle._box()` skips every primitive once a generated body model is in use). A car's five
  lights are one mesh with the colours in the vertex colour, so 150 cars cost 150 draws and not
  750, and they stop drawing past 160 m. The shader reads `lamp_factor` itself, so all of it
  costs nothing by day. The headlight beam quads carry UVs shifted by 2 (`_light_quad()`'s
  `uv_shift`), and `UV.y > 1.5` is how the shader knows to draw a fan that widens and fades
  along the road instead of a round pool; drawn as a pool, a beam laid flat on the street read
  as a long white smear.
- Character arms: the generated clips were authored for arms that hang straight, but each
  generated rig is bound in whatever pose its mesh came out in (A-pose, or a palms-up shrug
  with the forearms raised), and the clips drive the arm bones as if that were the rest pose -
  so everyone walked like a scarecrow or with their hands up by their ears.
  `Pedestrian.fix_arm_pose()` rebuilds the upper-arm, forearm and hand keys once, on the shared
  animation resource, from the rig's own rest pose: collarbones re-centred on level (the clips
  slump them 8-20 degrees), upper arms hang with `ARM_GAIT` spread and the forearms come back
  in so the hands sit by the thighs, swing opposite the same-side thigh (phase read from the
  clip's own legs), elbows bend forward, palms turn to the thighs (`FOREARM_TWIST` +
  `WRIST_TWIST`, 60 in total - more turns them forward). The arms follow the chest's turn but
  NOT its lean: the clips tip the torso forward and arms carried by that pitch trail behind.
  It needs no per-model numbers (`ARM_SPREAD` is there for a bulky jacket). Do not go back to
  rotating fixed amounts off the keys: that is what the old `ARM_DROP` did and every rig
  needed its own guess. Judge it with `tools/glshot/character_shot.gd`, front AND side.
- Effects: `WeaponFX` builds everything in code (tracers, muzzle flash, impacts, explosions).
  An explosion is layered: an `OmniLight3D` flash, a white-hot core, alpha-blended fireball
  puffs, slow smoke, additive sparks, a ground shockwave ring, lit debris, a scorch `Decal`
  (Forward+ only, skipped on web) and a camera shake via `CameraRig.shake()`. Three traps cost a
  session each, so do not undo them: billboarded particle materials need
  `billboard_keep_scale = true` or every puff renders exactly one metre whatever `scale_amount`
  says; a `Curve` clamps its values to `max_value` (default 1.0), so raise it before using a
  growth factor above 1; and a particle system's automatic bounds start empty, so set
  `custom_aabb` big enough for the particles' travel or the burst can vanish. A fourth: the heat
  shimmer reads the screen texture, which Godot captures BEFORE transparent things are drawn, so
  drawn in its sorted place it painted the fire-less street over the fireball and smoke - every
  explosion was sparks and a ring around nothing. Its material has `render_priority` MIN so it
  draws first and the fire lands on top; anything else that reads the screen needs the same.
  Fire and smoke share `WeaponFX.puff_texture()`, a 128 px billow made once from FBM noise
  with its edge pushed in and out by the noise (a smooth radial disc read as a glowing ball),
  and the fireball's colour ramp is HDR only for its first instant (white-hot 5.0), then drops
  fast to a deep orange (2.4, 0.95, 0.2): AgX takes anything bright toward white, and a ramp
  held at 3.0 for its first third tonemapped the whole fireball to pale beige. A per-puff tint
  (`color_initial_ramp`) gives it hotter and cooler lumps. Smoke and dust use a second puff
  material with `render_priority` -1 so they draw before the fire whatever their depth -
  sorted puff by puff, grey smoke rising through the fireball veiled it - and the smoke only
  thickens once the fire is past its peak. Puffs are soft particles (proximity fade, desktop
  only), or the road cuts the fireball along a ruler-straight line.
  Screenshot effects with `tools/glshot/fx_shot.gd` (and store stills with
  `tools/glshot/still_shot.gd`): Godot caps a frame at eight physics ticks (0.133 s) however
  long a software frame really takes, so they count the effect's own elapsed time, never the
  wall clock - the wall-clock version stopped every shot in the first milliseconds.
- Weapons: subclass `Weapon` (`scripts/weapons/weapon.gd`), build the model in `_build_model()` with
  the `_box` / `_cylinder` helpers, call `_make_muzzle()`, implement `_fire(aim)`. Register it in
  `WeaponManager._ready()`. Effects go through `WeaponFX` static functions. `Player.get_aim()` is
  the crosshair ray (origin, direction, point, normal, collider). Explosions: `Explosion.blast()`.
- City: `CityPlan` (lazy, endless data: `road_pos()`, `road_width()`, `block()`, `intersection()`,
  `block_index_at()`, `district_at()`; `DISTRICTS` holds the parameter ranges for DOWNTOWN,
  MIDTOWN, SUBURBS, INDUSTRIAL and CAMPUS), `CityStreamer`
  (scene root of `scenes/levels/city.tscn`: streams chunks, ground follow, origin re-centering) and
  `CityChunk` (builds one block at FULL or LOD level). A chunk's build is a **list of steps**
  (`begin_build()` then `build_step()` until it returns true; `build()` runs them all at once for
  the loading screen, teleports and the smoke test). While playing, `CityStreamer` builds chunks
  hidden, `build_budget_ms` of steps a frame, and swaps each in only when it is complete - one
  whole chunk in one frame was ~100 ms on a slow machine and the physics then ran up to eight
  catch-up steps behind it, which is what made flying stutter. Two rules: steps run in the
  one-shot order and share the block's rng, so **the order is load-bearing** (the far skyline
  replays the same rolls); and a big job with its own rng (grass) goes through
  `_run_or_defer()`, which re-queues it before the finish step as a step that returns false
  until it is done. Small repeated props go through
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
  Mountains (owner, 2026-09-21: "LA is covered by mountains, Palos Verdes, the valley"): the basin
  is ringed. `raw_height_at()` is mountains only - a front range north of the city that fades out
  on its inland side, a higher back range behind the valley, an east range, and the peninsula
  headland south-west - composed with `max()` so ranges meet in ridges rather than adding into a
  dome. The knobs are the `*_start_z` / `*_full_z` / `*_height` exports at the top of `MacroMap`.
  The front range's fade-out window **is** the valley's fade-in window (`valley_from_z` ..
  `valley_to_z`) on purpose: the range has to reach zero before the valley starts, or `zone_at()`
  calls the valley floor HILLS and no city is ever built on it. So the valley floor is past
  `valley_to_z`; the window itself is the range's own flank, and sampling in it reads the
  mountain. A **pass** (`pass_center_x`, `pass_width`, `pass_floor`) notches the front range down
  to a canyon floor so roads, the freeway and the player can get into the valley at all - without
  it the valley is a 560 m wall away and anything heading for it ends up buried.
  The inland valley is a **city floor at altitude**, not a mountain: `plateau_at()` returns its
  elevation and `_relief_at()` starts from it, so `_gy()` lifts the whole city onto the plateau
  while `zone_at()` still says CITY. Keep those two separate: `raw_height_at()` drives `zone_at()`
  and the hill-road carving, `plateau_at()` drives where the blocks sit.
- Freeways (owner, 2026-09-21: "every street is just straight, there's no highways"): `Freeway`
  (`scripts/world/freeway.gd`) plans three long **curved** routes across the basin - Coast, Cross
  and Valley - as seeded polylines with a smoothed, grade-limited deck height, exactly the shape
  of data `HillRoads` uses (`segments_in()`, `ramps_in()`, `blocks()`, a cell index). The deck
  rides `DECK_RISE` above the ground on pillars, with barriers, lane paint, overhead sign gantries
  and off-ramps down to the surface streets. `CityChunk._build_freeway()` builds it in three
  meshes per chunk (asphalt top, vertex-coloured structure, unshaded paint) plus a `FreewayBody`
  with one tilted box per segment, and deliberately bypasses `_batch`, because the batch adds the
  ground relief to every instance and the deck is nine metres above it. A segment is built by the
  chunk its **midpoint** falls in, so the deck is built exactly once. `_under_freeway()` keeps
  buildings, trees and lamps out of the corridor - it is checked *after* the pad roll so skipping
  a lot does not shift the chunk rng for the lots after it. Trap: `PILLAR_SPACING` and
  `GANTRY_SPACING` are rounded to whole `STEP` segments, so they must be multiples of `STEP`; at
  32 with a 24 m step the bents landed on every segment and the deck read as a retaining wall.
  A drawn route is trimmed by `_drivable()` to its longest run over ground below `MAX_GROUND`
  and not at sea, then `_clear_ground()` lifts the profile out of any hill the grade limiter
  could not follow: it propagates the required clearance forwards and backwards relaxing by
  `MAX_GRADE` each step, then takes the higher of that and the smoothed profile. The maximum of
  two grade-feasible profiles is still grade-feasible, so the deck provably clears the ground
  everywhere and stays drivable. Smoothing and grade-limiting alone do not - they never look at
  the ground, so a rise they cannot follow leaves the deck inside the hillside.
  **Winding trap:** `CityChunk._ribbon()`'s plain vertex order makes a *horizontal* quad face
  DOWN. The deck top is built with its own order (`l0, r1, r0`) and faces up; anything flat laid
  on it - `_bar_flat()`'s lane paint, the cap on `_bar()`'s barriers - has to pass `flip = true`
  to match, or it is back-facing and culled and you get a deck with no markings at all. That
  looks exactly like a missing mesh or a z-fight, and is neither.
  Traffic: `TrafficManager` drives the decks from `Freeway.point_at()` / `length_of()` /
  `nearest_on()`, which are distance-parameterised (the route's points are a fixed step along
  the *drawn* curve, not along the ground). Cars carry a signed direction and are recycled at
  the route ends rather than wrapping, are grouped by route + direction + lane so each follows
  only the car actually in front of it, and are kept within `freeway_range` of the player so a
  three-kilometre deck costs what a short one does. Caps: `CityStreamer.freeway_cars` /
  `web_freeway_cars`, scaled by `Quality` like the rest of the traffic.
  The surface street grid is still axis-aligned (`CityPlan.road_pos()` is scalar per axis and
  blocks, lots, traffic lanes and the minimap all assume axis-aligned rects); the freeways and the
  hill roads are the curved roads.
- The horizon: everything outside the streamed chunks is the ground follower, a single plane
  14 km across (`CityStreamer.ground_size`) wearing `shaders/macro_ground.gdshader`. It is
  shaded from a 256 px image of the whole basin baked once at load by `MacroMap.bake()` (RGB is
  the ground colour per zone and district, alpha is height / 400 m), with relief shading from
  the baked height, a little noise to break up the bilinear smear, the grass texture blended
  back in within ~300 m of the camera, and haze that hands the far land over to the sky.
  `DayNight` keeps `haze_color` and `sun_dir` in step via `CityStreamer.set_ground_haze()`. The plane's
  vertex shader also drops it 24 m wherever the baked map says water (alpha exactly zero): the
  water chunks put their surface 15 cm above it and their troughs a metre or more below it, so
  it kept drawing through the waves in smooth grey patches, and at a kilometre the 15 cm is
  below depth precision and they z-fight as well. Over land it only sinks a few metres with
  distance, so the coastline keeps its shape.
  Since the mountains went in the plane also **stands up**: the vertex shader lifts it by the
  baked height (`macro_height`, `MacroMap.BAKE_HEIGHT_SCALE`), faded in with distance between
  `lift_start` and `lift_end` so the near ground stays flat and meets the streamed chunks, with
  two octaves of ridged noise breaking the 256 px bake into crags. A flat plane cannot give a
  silhouette, and the silhouette is the whole point of a ring of mountains. `GROUND_SUBDIVISIONS`
  is 200 so there are vertices to displace, and `CityStreamer` snaps the plane's position to that
  vertex grid **in world space** - without the snap the peaks swim as the follower slides.
  That grid is `CityStreamer.ground_step()`, `ground_size / (GROUND_SUBDIVISIONS + 1)`: a
  PlaneMesh with N subdivisions has N + 1 quads, and snapping by `/ N` slid every vertex 35 cm
  per step. The plane's height code (bake sample, crags, sink) lives in
  `shaders/macro_relief.gdshaderinc` so anything that must stand on the far ground computes
  the same surface: `shaders/far_canopy.gdshader` (Skyline's hill planting) seats each clump on
  it, interpolating across the plane's own 70 m triangles; the far hill houses ride in the same
  MultiMesh, and the far ridge sign uses its `rigid` mode (one shift for the whole name, from
  `Landmarks.sign_line()`, so it stays level). Placed at `MacroMap.height_at()`
  instead, the clumps hung in the sky above every ridge - the bake averages a ridge down and the
  crags move it tens of metres, so the real height is not the height that is drawn.
  `built_amount()` stays in `macro_ground.gdshader`: the smoke test reads its thresholds from it.
  Before this the plane was 4 km of flat green and its own edge was the horizon.
  **The plane and its collision are separate nodes** (`Ground`, drawn, slides with the player;
  `GroundBody`, a 14 km box, moved only when the player is `GROUND_BODY_REACH` of it from its
  centre). Moving a static body makes Godot Physics wake every body touching it - on any
  transform set, even to the same value - and that box touches every parked car, trash can and
  prop in the city. When it was the sliding plane, re-placed eight times a second, nothing in
  the city could stay asleep. Never move a big static body per frame.
- Trees and planting: `PropFactory.CITY_TREES` (five broadleaf street trees) and `HILL_TREES`
  (fir, pine, quiver, searsia) - the hills used to wear the same street trees as the basin, which
  reads as one texture stretched over everything. A block's dominant species comes from the
  district's `tree_weights`, which is walked as an array of any length; it used to be indexed
  `[0]`, `[1]`, `[2]` by hand, so a fourth tree would have been placed only by the fallback roll,
  silently. `BUSHES`, `PLANTS`, `FLOWERS` and `GRASS_CLUMPS` are the knee-height families, and
  `CityChunk._scatter_ground_cover()` plants parks and pocket gardens from them: one flowering
  species dominates a patch, because a mixed sprinkle of seven colours reads as confetti rather
  than as planting. FULL chunks only, no shadows, 80-95 m draw distance.
  **The jacaranda blooms in the shader, not in the texture.** Poly Haven's scan is photographed
  out of bloom, so the leaves are plain green; `shaders/foliage_tex.gdshader` takes each leaf to
  its own luminance and recolours it (`blossom`, `blossom_mix`, `blossom_patch`, set from
  `PropFactory.JACARANDA_BLOSSOM`). Multiplying green by violet only gives mud, and scaling by
  leaf luminance *alone* drags shaded leaves to navy - the constant term in that mix is what keeps
  a flower in shadow reading as a flower. `blossom_mix` 0 leaves every other tree untouched.
  `CityChunk._jacaranda_street` biases whole blocks to it, the same idea as the palm streets.
- Lawns: `PropFactory.lawn()` + `shaders/lawn.gdshader`, not a plain tiled texture - a 5 m tile
  mips down to one flat green rectangle from thirty metres up, and the grass-blade multimesh only
  reaches a few dozen metres. Dry/watered patches, mower stripes angled per lawn, worn dirt, and
  the same `ground_detail`-gated second rotated sample the road shader uses. Keep it subtle: the
  first pass used `sign()` for the stripes and a 1.6x albedo boost and the lawns came out
  candy-striped and blown out, which is louder than the flat green it replaced.
- Palms (owner, 2026-09-20: "it's Cali, put palm trees"): `PropFactory.palm(variant)` builds a
  whole tree as one vertex-coloured mesh (tall slender curved trunk with ridged bark, a crown of
  feathered fronds whose leaflets are separate pointed blades so daylight shows through, a skirt
  of dead fronds, coconuts), so a palm-lined boulevard is one MultiMesh draw. The material
  uses `shaders/foliage.gdshader`: backface culling off (leaflets are single-sided) and a
  vertex-shader wind sway whose bend grows with the square of height above the instance origin,
  phased by world position so a row does not sway in step. The fronds are **folded**: leaflets sit
  at an angle running from steep at the base of the frond to nearly flat at the tip, jittered per
  leaflet, and swept *forward* toward the tip the way a feather's barbs lie. Flat leaflets all in
  one plane overlap into a solid sheet and the crown reads as a paper fan; swept backward they
  read as a fishbone laid the wrong way round. Both of those were real attempts, in that order.
  Nothing else in the city moved except
  the grass, and a street of palms standing dead still reads as a model rather than a place. The
  downloaded trees and bushes use `shaders/foliage_tex.gdshader` on their leaf surfaces only
  (`PropFactory.foliage_textured()`, applied in `model_tree()`): same sway, plus the leaf
  textures, UV scale and alpha scissor carried across. Trunks stay opaque and still, which keeps
  them out of the transparent pass. Blocks roll palm-lined streets
  from the district's `"palms"` odds in `CityPlan.DISTRICTS` (`CityChunk._palm_street`), so palms
  run in runs rather than being sprinkled. Street palms pass `collide = false` to `_add_palm()`:
  street trees have never had collision, and solid trunks along a whole boulevard wall the road
  in and trap cars against the kerb. Landmarks plant palms through `PropFactory.palm()` too
  (the boardwalk batches them as `palm_<variant>`); their old hand-built stick-and-frond palms
  are kept only for the far version, where they read as a silhouette and nothing more. Up close
  they looked like spiders.
- Landmarks: `Landmarks.all()` lists them (id, world anchor, radius); `Landmarks.build()` makes
  one, detailed (with a StaticBody3D for shapes) or far (no collision). Add a new one by adding an
  entry and a `_build_<id>()` function. Everything original: no real names, logos or copies.
- Autoload `WorldState`: `world_offset` (local + offset = true world position, use `to_world()` /
  `to_local()`) and the destroyed-prop registry (`mark_destroyed`, `is_destroyed`).
- Anything that must survive origin re-centering has to be a 3D child of the scene root (the
  streamer shifts every Node3D child). Store true world positions only via `WorldState.to_world()`.
- Building windows use **interior mapping**: `shaders/building.gdshader` traces the view ray
  into a virtual room behind each pane and shades whichever inner surface it reaches, so windows
  have true parallax (lean left, see the room's right wall) instead of glass painted on a wall.
  Each room gets its own paint, depth falloff and a blind pulled to its own height. This is the
  single technique that stops a box reading as a box; do not replace it with a gradient.
  `room_depth` and `interior_enabled` are the knobs. At night a lit office is the same room
  lit from inside (`room_interior()` also returns where the ray landed and how much light
  falls there): a grid of ceiling panels, walls brighter toward the ceiling, a dim floor and
  a desk or partition silhouette in half the rooms, all emitted - not a flat yellow pane, which
  from the air turned every tower into a lit spreadsheet.
  Roofs pick a covering per building (`Building.roof_style` -> the shader's `roof_style`): white
  single-ply membrane with welded seams and ponding, gravel ballast, or patched bitumen. Roof
  plant scales with the roof's area rather than a flat count, and includes air-conditioning
  units, duct runs on legs, tilted solar arrays, skylights and cooling towers. Roofs are most of
  what the player sees while flying, so they are worth the geometry.
- Buildings: `Building` (`scripts/world/building.gd`, scene `scenes/props/building.tscn`) is a
  StaticBody3D. Set `seed`, `lot_size`, `min_height`, `max_height` before adding it to the tree; it
  generates in `_ready()`. Every box part uses `shaders/building.gdshader` with its own
  ShaderMaterial (see the decisions log for why). Rooftop props are primitives built in code.
- Characters: every rig (pedestrians, ragdolls, the player) renders through
  `shaders/character.gdshader` via `Pedestrian.prepare_rig(inst, look)`. The source models ship
  one flat 1K colour texture and a glTF material with full white emission and double specular,
  which renders a shiny self-lit mannequin; the shader replaces that with sensible roughness,
  a little subsurface on skin, and a per-character garment colour on half the looks (the other
  half keep the model's own clothes; with nine real models a photographed jacket beats a
  repainted one) so two copies of a model do not dress alike. Clothing is told from skin by
  hue distance from a skin hue **and** saturation: hue alone lets grey fabric pass as skin
  (grey's hue is arbitrary), saturation alone rejects strongly lit or shadowed skin and turns
  faces pink. Materials are cached per look (`Pedestrian.CHARACTER_LOOKS`), so hundreds of
  pedestrians share a handful. Pedestrians also get a height and width scale and a random seek
  into the walk cycle: a crowd stepping in unison is the loudest tell that they are one model.
  **Shader files use `//` comments, not `##`** - a `##` line is a syntax error and Godot falls
  back to a blank white material, which looks like a missing texture rather than a broken shader.
- Player body: `Avatar` (`scripts/player/avatar.gd`, built by `Player._build_avatar()` from
  `avatar_model`, one of `Pedestrian.MODELS`): idle / walk / run clips picked by speed, frozen or
  slowed stride in the air, forward lean while boosting. The orange capsule in `player.tscn` is
  only the fallback when the model file is missing. `Pedestrian.prepare_rig()` is the shared fix
  for every instantiated rig (AABB, materials). Knocked pedestrians become `Ragdoll`s that keep
  the same rigged model as one tumbling body (`build_from_rig`); far pedestrians move and animate
  every 3rd / 6th physics frame (`Pedestrian.lod_mid` / `lod_far`).
- Performance: `Quality` node in the city scene (`scripts/util/quality.gd`) starts desktop at
  **HIGH** (owner, 2026-09-21: "I need it PS5 level graphics" - global illumination is the single
  biggest difference between this and a modern-looking game) and steps down to MEDIUM, LOW and
  LOWEST (dropping SDFGI and volumetric fog, then SSR / SSAO / glow, lower render scale, 60 %
  then 35 % of the crowd and traffic caps, shorter shadows) when the average FPS drops under
  `min_fps`. Force a level with `-- --quality=0|1|2|3`. It also caps the frame rate at 60.
  Every level also has a **pixel budget** (`Quality.pixel_budget`, 2.6 MP at HIGH): the game
  opens maximised, and on a Retina Mac "native" was 3456 x 2234 - 7.7 million pixels through
  SDFGI, SSR, SSIL and volumetric fog - so the 3D scene now renders at most the budget and FSR
  2.2 scales it to the window. The HUD's quality line shows the 3D resolution in use.
  Pedestrians cast shadows only inside `Pedestrian.shadow_range` (45 m) and drop to coarser
  mesh LODs with distance (`LOD_BIAS`): on a downtown street the crowd was 6.4 of 15.7 million
  triangles a frame, most of it shadow passes of 16k-triangle rigs; now 2.4. Cars do the same
  (`Vehicle.body_shadow_distance`, `BODY_LOD_BIAS`). Street props have a per-model triangle
  budget, `PropFactory.TRI_BUDGET`: the Poly Haven scans are film assets (a lamp was 30k
  triangles, a barrier 61k) and a MultiMesh batch draws every instance at the LOD of its nearest
  point, so over budget `model_mesh()` makes a generated LOD the base mesh. Add new hard-surface
  props to it; not foliage, whose leaf cards a simplifier collapses. Occlusion culling is on
  (`rendering/occlusion_culling/use_occlusion_culling`): one `OccluderInstance3D` per chunk made
  of its building boxes (`CityChunk._build_occluder()`), inset by `OCCLUDER_INSET` so it never
  sticks out past a wall - an occluder bigger than what it stands for culls things in plain
  sight. Diff a shot against `OCCLUSION=0` on `tools/glshot/city_shot.gd` after changing it.
  CPU: parked cars past `PhysicsBudget.vehicle_script_radius` stop their own per-step script
  (the physics body is untouched), and see the physics-layers note on masks. The HUD shows the level and a frame-time line (cpu / physics / gpu ms, draws,
  objects, tris): ask the owner for a screenshot of it before guessing at lag. Building window
  frames are flat quads drawn out to `Building.FRAME_DRAW_DISTANCE`.
- Road surfaces use `shaders/road.gdshader` (via `PropFactory.road()`, picked in
  `CityChunk._road_look`): tiled asphalt plus world-space mottling, resurfacing patches on a
  jittered grid with darker seams, ridged-noise cracks and sparse oil staining, so the road never
  repeats visibly and never reads as a flat grey plane. Wetness comes from the `road_wetness`
  global that `PropFactory.set_wetness()` sets, not from walking materials one at a time.
  Pavements use the same shader with `joints` (expansion-joint spacing in metres) and a lower
  `wear`, so they read as poured slabs rather than a grey plane. It also kills the visible tile
  grid, which is the first thing the eye finds on a plaza or a long pavement: it samples the
  texture a second time, rotated and at a different scale, and cross-fades on slow noise. That
  second fetch is gated on the `ground_detail` global, which `Quality` clears on web and below
  MEDIUM. Car parks, port yards and plazas go through `PropFactory.road()` for the same reason. The hill terrain shader does the same thing with the same global: its
  texture has a directional grain, so at a 5 m tile a long slope turned into corduroy. Keep all of it subtle: the first
  pass used strong patch blends and dark joints and the ground read as a printed pattern rather
  than a surface.
  Far buildings (`shaders/building_lod.gdshader`) get a cheap version of the same depth: the
  window grid is sampled with a view-direction offset, so the panes parallax as if recessed,
  plus per-room brightness, a slab-edge band each floor, reveal shading and a vertical gradient.
- **Two measurement traps, each of which has already cost a session.** Both fail by reporting
  success, which is the worst way to fail.
  1. **Godot serves a CACHED import of a `.glb`.** Rebuild a model, render it, and you are
     looking at the *old* file. Run `godot --headless --path . --import` between writing the
     `.glb` and rendering it, every time. A shot script that prints the model's AABB catches it:
     if that does not match what the generator just printed, the render is stale.
  2. **`--headless` is the dummy rendering server**, where every `Performance` monitor reads
     exactly zero - `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, draw calls, objects, all of them. A
     geometry change of any size measures as no change at all. `MultiMesh.get_instance_transform()`
     is the same trap: it returns identity under `--headless`, so a check that reads instance
     transforms back out measures nothing and reports a clean bill of health.
  `tools/geo_count.gd` counts triangles, draw calls and objects for one frame and has the working
  invocation in its header: it must run under `--rendering-driver opengl3` with Xvfb, never
  `--headless`. Measure a geometry change before and after with it rather than arguing about it.
- Native screenshots without a browser: `tools/glshot/building_shot.gd` (one building) and
  `tools/glshot/city_shot.gd` (the city at a `--spawn`) render with the real OpenGL renderer under
  Xvfb + llvmpipe in ~20 s; usage lines in the files. Use these before the web harness.
  **Those are the Compatibility renderer**, though - no SDFGI, no SSR, no TAA, no volumetric fog,
  flat lighting - so they are NOT what the owner's Mac draws, and judging a lighting or material
  change on one is judging the wrong renderer. `tools/glshot/forward_shot.sh` runs the real
  **Forward+** pipeline headless with no GPU, via lavapipe (Mesa's software Vulkan driver,
  `apt-get install mesa-vulkan-drivers`, which puts `lvp_icd.json` in `/usr/share/vulkan/icd.d/`);
  Godot then accepts `--rendering-driver vulkan` and everything in the Environment actually
  applies. It costs about six minutes for one 960x540 shot, so use it to check a finished change
  and keep `city_shot.gd` for the fast loop.
  **One thing forward_shot.sh lies about: particles.** It renders at about one frame a second
  and Godot clamps frame time, so a raindrop jumps metres between frames and TAA - which is on
  at every quality level - cannot track it, so rain and smoke come out as soft ghosted blobs
  that are far worse than anything the owner's Mac draws at 60 fps. If a particle effect looks
  smeared in a Forward+ still, render the same frame through `city_shot.gd` on opengl3 first:
  that path has no temporal pass, so anything still wrong there is real geometry and anything
  that clears up was the harness. That is how the rain curtain's 2.2 m streaks were told apart
  from TAA ghosting.
- Physics masks as constants on `Player`: `AIM_MASK` (world + props) and `BLAST_MASK` (player + props).
- Forward is -Z. Yaw for a facing direction `d` is `atan2(-d.x, -d.z)`.
- Commit messages: short imperative subject, body explains why and how to test. One task per
  commit (or a few), pushed straight to `main`.
