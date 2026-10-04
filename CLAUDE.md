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
  **Meshy is retired (owner, 2026-09-19), people included since 2026-09-27**: the crowd is
  built by `tools/crowd/` from CC0 MakeHuman assets with the hero's MPFB pipeline (see the
  Characters note), because the Meshy people (pedestrian_d..l, 2026-09-22) had their look baked
  into one photo texture and read as plastic mannequins whatever the shader did. Their files stay
  (the hero's and the crowd's clips are retargeted from `pedestrian_d_anim.glb`) but are not
  loaded. Cars, jets, props and scenery stay Poly Haven / code. The existing
  sports car, the old pedestrians and the jets were made with the owner's Meshy account (the sedan,
  crossover, pickup and van are now Blender-built, see the car paint note): `python3 tools/meshy.py gen <name> "<prompt>"
  [--rig h --anims ids]` (key from `MESHY_API_KEY` or `MESHY_KEY_FILE`, never in the repo), then
  `python3 tools/shrink_glb.py assets/models/<name>.glb` (a hard-surface model like a car also
  gets `python3 tools/smooth_normals.py assets/models/<name>.glb`, see the car paint note), commit the `.glb`, its `.json`, the
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
  **Replica areas are the one exception, by owner decision (2026-09-24: "we are basically picking
  certain 1:1 replica areas and then filling them in between with whatever").** A replica area
  is a real place rebuilt at TRUE scale from real references (the owner's Street View shots, the
  map): street layout, lane / kerb / parking / pavement widths, lamp rhythm, building sizes and
  setbacks, bluff height, the view from the road. It is authored as a DATA TABLE in
  `scripts/world/replica_areas.gd` (legs, cross sections, height profile, where the stairs, car
  park and condominium stand) - never as hand-placed nodes - and everything between areas stays
  seeded, as does the detail inside one that no reference fixes (which house looks how, the
  backfill). Distances between areas may be compressed; an area itself is 1:1, and the map
  around it stays geographically sound (the Esplanade is south of the piers and the airport).
  Business names and logos stay original; public street names ("Esplanade") may appear.
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
tools/                 meshy.py, shrink_glb.py, smooth_normals.py, make_road_cars.py, webshot/ (screenshot harness)
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
  `debris` (short-lived props that get freed after a timeout), `wanted` (the one `Police` node),
  `police` (officers on foot - NOT in `pedestrian`, so alarms, the crowd cap and trimming never
  touch them; `LockOn` looks in it), `police_car` (cruisers, also in `vehicle`).
- Autoloads: `PhysicsBudget` (`scripts/util/physics_budget.gd`), `WorldState`
  (`scripts/util/world_state.gd`), `Sfx` (`scripts/util/sfx.gd`:
  `Sfx.play(name, position)`, `Sfx.loop_player(name)`).
  Sound is **real CC0 recordings** (`assets/audio/`, 131 clips - the siren is public domain - sources in `docs/ASSETS.md`) with
  the old synthesis kept as the fallback: `_build_synth()` fills every name first and
  `_load_samples()` replaces only the names whose files load, so a missing or unimported file
  degrades to a tone rather than to silence (the ambience names are the exception: their
  fallbacks, `ambience_synth()`, are built only for the names whose files did NOT load, because
  they are long and startup should not pay for them twice). A name holds several takes and
  `play()` picks one at random, which is what stops the rifle and the footsteps sounding like one
  file on repeat. Loop flags are set on the stream **in code** (`LOOPING`, `AMBIENCE_LOOPING`),
  never in the `.import`: a regenerated `.import` can silently drop the flag, and a non-looping
  ambience is very hard to diagnose. Only the clips named in `Sfx.SAMPLES` and
  `Sfx.AMBIENCE_SAMPLES` ship - do not leave working downloads in `assets/audio/`, this builds
  into a macOS app and a web page. Every name in them needs its loudness in
  `SAMPLE_LOUDNESS_DB` / `AMBIENCE_LOUDNESS_DB` (the smoke test checks the counts match); beds are
  recorded at their long-term RMS (all cut to -22 dB), one-shots at their loudest 50 ms window.
  **Buses** (`Sfx._install_buses()`, in code, no `.tres`): Master (limiter) <- `Game` (a low-pass,
  the slow-motion and blast muffle) <- `World` (street-canyon reverb) and `Ambience` (enclosure
  low-pass, then a compressor side-chained on World so gunfire pushes the city down).
  `Sfx.bus_for(name)` routes: the ambience names plus rain, wind, ambience_city and thunder go to
  Ambience, everything else (guns, blasts, engines, voices) to World. `Sfx.take(name)` hands a
  caller that owns its player a take and its trim. Web builds (sample playback) skip bus effects
  and play the plain mix. Bullet impacts sound by surface (`WeaponFX._impact_sound()`: Sfx
  `hit_concrete` / `hit_metal` / `hit_glass` / `hit_wood` / `hit_dirt` / `hit_flesh`, Kenney's
  CC0 impacts, at most `impact_sound_budget` a tenth of a second), and spent cases tink
  (`casing`, a light metal impact pitched up).
- Ambience (owner, 2026-09-24: "the city should SOUND like a real city, AAA-style"): `Ambience`
  (`scripts/util/ambience.gd`), a Node in `city.tscn`. Beds (stereo, non-positional: `city` by day,
  `city_far` - real downtown LA night traffic - by night and from the hills and the air, near
  `traffic`, crowd walla, birds, crickets, wind, gale, rain / downpour / rain on a roof / on the
  car roof), emitters (freeway, surf, airfield, port: AudioStreamPlayer3D with its falloff OFF,
  parked `emitter_distance` from the listener toward the source so it pans while the level is
  ours) and one-shots (far horns, far sirens, dogs, bus air brakes, gulls, coyotes, ship horns,
  crane clanks: Poisson events per minute, placed at a real distance so the distance filter dulls
  them). The nearest `TRAFFIC_VOICES` moving traffic cars carry a tyre-roll voice with a cheap
  Doppler, and a car predicted to pass within `pass_distance` gets a recorded pass-by started so
  its loudest instant (cut to sit at `pass_peak_seconds`, 1.2 s, in every take) lands as it goes
  by; wet roads use `car_pass_wet`. The survey (`survey_interval`, REAL clock - the wheel scales
  the process delta) never scans the city: `scene_at()` is MacroMap maths at a centre point and two
  rings (`ring_radii`), the freeway its cell index, and `_probe()` adds nine world-layer rays
  (street canyon, cover overhead), one sphere query on the npc layer (crowd, panic) and
  TrafficManager's own car lists. `levels_for()` / `rates_for()` are pure (scene, hour, night
  factor, weather) -> gains / events per minute, which is what the smoke test checks
  (`tests/ambience_checks.gd`, mixer state only under the Dummy driver). Knobs: `ambience_db`,
  `layer_db` (per layer), `pass_db` / `car_roll_db`, `fade_seconds`, the reaches, `district_density` (one per
  CityPlan.District, guarded), the enclosure cutoffs, `reverb_wet`, the duck numbers. The weather
  node's own rain loop only plays where there is no Ambience (the test room). Ducks: a blast
  within `blast_duck_radius` (polled from `Explosion.blast_count`) dips the ambience and, inside
  `concussion_radius`, muffles the Game bus for `blast_recover_seconds`; the weapon wheel or any
  slow motion (`AudioServer.playback_speed_scale` < 0.97) muffles Game and dips the ambience.
  Crowd screams stay where they were (`Pedestrian.alarm()`); the walla drops under panic.
- Day/night: `DayNight` node in the city scene drives the sun, the sky (`shaders/sky.gdshader`,
  a ShaderMaterial on the Environment's Sky: gradient, sun disc, FBM clouds, stars; colors set per
  hour via `set_shader_parameter`) and the `night_factor` shader global (`[shader_globals]` in
  project.godot). Shaders that should react to night read it with
  `global uniform float night_factor;`. **The sun rides the real Los Angeles path**
  (`_arc_basis()`: the circle tilted by `latitude_degrees` 34 and `sun_declination_degrees` 0):
  up due east at 6:00, due south 56 degrees up at noon, down due west at 18:00;
  `sun_rotation_z_degrees` turns the whole path. It used to swing from SSE through ENE at noon
  (85 degrees up) to due NORTH mid-afternoon, which backlit every mountain face the city looks
  at. The golden hour, dusk and night still run off the clock (`elevation` is `sin(t * PI)`). Clouds are lit by stepping the same noise field toward
  the sun and darkening where there is more of it in the way, which is what gives them bright
  shoulders and grey undersides; above them is a sheared cirrus deck. Both cost three extra
  noise taps, so `Quality` clears `cloud_detail` on the web and below MEDIUM.
  **Golden hour is the smog** (Los Angeles evening): `DayNight.golden` (0..1 off the sun's
  elevation only - `golden_elevation` ramps it in between about 27 and 10 degrees up,
  `golden_set_elevation` out a few minutes after sunset - so midday and night are untouched)
  drives a lid of lit haze in the sky shader (`smog`, `smog_color` brown-grey away from the sun,
  `smog_glow` orange-pink toward it and low down, `smog_top` its height as a sine; it also
  diffuses and reddens the sun disc sitting in it), the same colour on the far land under
  `smog_lid` metres (`macro_ground.gdshader`, via `CityStreamer.set_ground_smog()`, so mountain
  feet sink into it and crests stand clear), the depth-fog colour (`golden_fog_smog`) and its
  density (`fog_gain`, which Weather multiplies in like `haze_gain`). `sky_tint` and the ground
  haze follow what the sky really draws at the horizon. Sunrise gets `smog_morning` of it, and
  weather (`weather_darken`) takes it all away. Every piece works on Compatibility. The sunset
  colours wait for the sunset: while the sun is clearly up (`sun_high`, 1 from ten degrees) the
  zenith and horizon keep most of their day colour (`golden_blue_top`, `golden_pale_horizon`)
  and the violet earth's-shadow band is off (`twilight_band_gain`) - at 17:36 the sky used to be
  a full sunset already, and the ambient, which is the sky, turned every shadow lavender.
- Weather: `Weather` node in the city scene (`scripts/world/weather.gd`): states clear, overcast,
  rain, storm; drives DayNight (`cloud_extra`, `weather_darken`), fog, rain particles, wet roads
  (`PropFactory.set_wetness`), the `wind_factor`, `wave_scale` and `tsunami_scale` shader globals,
  lightning (sky `flash` uniform, sun meta `weather_flash`) and thunder. The ocean is
  `shaders/ocean.gdshader` on a subdivided plane per water chunk: Gerstner swells in the vertex
  shader, foam on the crests, and the sky mixed in by fresnel with a glare path to the sun,
  taken from the `sky_tint` and `sun_direction` shader globals that `DayNight` publishes (water
  is mostly the sky seen in it, and leaving that to reflections gives nothing on the web). Debug `?weather=storm`.
  **The mirror is EMITTED, the body lit** (2026-10-04): in ALBEDO the sky reflection was
  multiplied by the sun, so the golden-hour sea was a brown-black sheet under an orange sky.
  **The surf** (2026-10-04, see the Surf note) breaks along every waterline, and Weather also
  publishes the `surf_shape` / `surf_extra` globals and hands the ocean the piers' lamp rows
  (`Weather.pier_light_lines()`) for the night reflections.
  Rain at night is judged by the wet street, so: `Weather` starts as wet as the weather it
  starts in (soaking from dry spent the first 16 s on dry tarmac under a downpour); a soaked
  road is roughness 0.07 with mirror puddles at 0.02 (`road.gdshader`, spreading as it soaks,
  and drying unevenly afterwards - see Road surfaces),
  because at 0.18 SSR only gave a smear and the lit windows standing in the street are the
  whole look; drops are lit (with a faint glow of their own) and fade out within 5 m of the
  lens, splashes are lit like the road, and the lens rain is a few dozen drops at the frame
  edges - at 1,800 evenly spread it read as television static over the picture. An overcast
  night is the city's sodium light on the cloud base, not a grey sky: `DayNight` blends the
  storm colours, the rain haze (`night_storm_fog`) and the sky shader's `night_glow` /
  `night_cloud_light` to warm, dark values by `moonlight`, and turns the moon's
  `light_volumetric_fog_energy` down in bad weather - rain thickens the volumetric fog seventy
  times, and lit by the moonlight fill it hung over the street as a pale grey veil. At 88 %
  cloud the sky IS the clouds, so the night cloud colour is what decides it.
- Surf and beach (2026-10-04, owner: "the Pacific and the beach, AAA"). One wave model,
  `shaders/surf.gdshaderinc`, included by the ocean, the sand and the spray, mirrored in GDScript
  by `Surf` (`scripts/world/surf.gd`): crests parallel to the shore at `phi = TAU * ((s + wob) / L
  + t / T)` (`s` metres offshore, `wob` bends them along the shore), each wave with its own height
  (sets, sections along the shore) and so its own break point; it stands up, throws a lip at the
  break, runs in as a bore that shrinks to nothing at the waterline, and the bore that arrives
  starts the swash up the sand. Everything runs off shader TIME and two globals Weather sets from
  the wave scale (`Surf.params()`: `surf_shape` = face height, crest spacing, period, break
  distance; `surf_extra` = run-up, lip throw, zone width, swash length in periods; a clear day
  0.9 m breaking 38 m out, a storm 2.9 m breaking 103 m out; `Weather.surf_gain` scales the
  height). **Ocean**: in the zone the vertex shader takes the way to the land from the gradient of
  `shore_distance()` and adds the surf's height and lip (and its derivatives, so normals and the
  fold see it), handing the swell down to 30 %; the fragment works the whitewater out from the
  same wave (the bore's churned face and trail, the lip, feathering, a warped net of old lace),
  the turquoise light through every standing face (`surf_face_color`, glowing when backlit,
  `surf_golden` times more at golden hour), kelp beds (`kelp_*`, dark olive, chop calmed, fronds
  close to), sandy shallows in the last metres, and at night the piers' lamps and the city
  (`pier_lines` / `pier_info`, `city_front`) mirrored by intersecting the reflected ray with the
  lamps' vertical plane - lamp_factor gated, emitted, faded with the hand-over. **The surf never
  lifts the water landward of the waterline** (`shore_distance()` is 0 there and the envelope
  is 0 at s <= 0; `tests/surf_checks.gd` checks both). **Sand**: `shaders/beach_sand.gdshader`
  (`PropFactory.beach_sand_material()`), the old pbr sand plus the swash: the sheet (darker,
  glossy, mirroring the sky by fresnel, its relief drowned), a lace of bubbles on its edge, fizz
  on the uprush, threads of foam on the drain, and sand that stays dark and glossy for a few
  seconds after the water leaves (`surf_swash()`'s `wet`); rain darkens it through
  `road_wetness`. The mesh carries UV2 = (metres landward of the waterline, beach width), rows
  of constant z running inland along +x. `_build_beach` now also lays the sand over the street
  strip on the block's +Z side, dipping under the road: every street end along the coast was a
  hole in the beach showing the sea plane. **Spray**: `CityChunk._build_surf_spray()`, one
  MultiMesh of quads per FULL shoreline chunk (two per `SPRAY_STEP`: tall spray off the lip and
  low drifting mist), carried by `shaders/surf_spray.gdshader` out to the break point and puffed
  when a wave breaks there; transparent between waves, one draw a chunk, no particles. Stills:
  the bookmarks in docs/HANDOFF.md 9ax; checks: `tests/surf_checks.gd`. **Traps, each found by
  a striped waterline:** a varying the fragment wraps (`fract(surf_phi)`) must be set on EVERY
  vertex, never 0 outside the zone; never project world positions (hundreds of metres) onto an
  interpolated direction (the foam is laid out on true-world z); near the shore the sea is held
  over the ground follower (y 0, which is drawn as land up to a bake texel out to sea); and the
  sand under the water falls to `SAND_STEEP_Y` / `SAND_LOW` so no trough meets it.
- Look (owner, 2026-09-20: "as realistic as possible, like an industry giant made it"). The
  realism settings are deliberate, not defaults: **AgX** filmic tonemapping (not ACES, which
  clips highlights hard), **sky-source ambient** so shadows take the sky's colour instead of a
  flat grey fill (`DayNight` sets it every frame; never put it back to `AMBIENT_SOURCE_COLOR`),
  **SSIL** indirect bounce, **aerial-perspective fog** (`fog_aerial_perspective`, which tints
  distance haze with the sky per direction) plus **height fog** so haze pools in the streets and
  towers rise out of it, and **auto exposure** on the player camera. Antialiasing is temporal at
  every level: TAA at native resolution, FSR 2.2 when `Quality` upscales. MSAA stays off (it
  costs a lot and does nothing for shader aliasing). Car paint is a metallic basecoat under a
  clearcoat lobe with flake (`shaders/car_paint.gdshader`). The single-texture bodies mark
  glass by a dark texel, but the van's texture does not (its darkest 5 %
  is 0.49), so it finds glass by shape - above `Vehicle.GEO_GLASS_BELTLINE`, tilted between
  roof and door skin - or every white car was one pale ice-sculpture shape. That was only half of
  it: the other half was the sky. The radiance map is what every lacquer, window and puddle
  mirrors, and the drawn sky fades to haze over 27 degrees below the horizon, so every car door
  (which faces a little downward) mirrored pale-blue sky - a dark red pickup read as ice-blue,
  and with the clearcoat off the same car was dark red. `sky.gdshader` now puts the street
  (`reflect_ground`, a warm grey following the horizon's brightness) under the horizon in the
  cubemap pass only (`AT_CUBEMAP_PASS`); the sky you see is unchanged. The Meshy bodies
  (van, sports; the sedan and pickup were too) were also flat-shaded: ~8k-triangle remeshes exported with the
  normals split at 30 degrees and along every UV seam, so a curved wing was a set of facets and
  the lacquer mirrored each one. `tools/smooth_normals.py` (run once on the `.glb`, then
  `--import`) re-smooths them by angle: triangles joined through bends under 45 degrees share
  one angle-weighted normal, sharper bends stay hard, UV seams no longer crease, no triangle
  is added (`--report` prints the crease table). The exotics are Blender-built with their
  creases on purpose; leave them. Smooth normals drift slowly through the glass slope band, so
  the geometric glass test blends over one pixel (`fwidth`), not a fixed 0.04, and
  `Vehicle.GEO_GLASS_SPAN` kept the Meshy van's glass to its cab (both tables are empty now,
  kept for any single-texture body that comes back). **The everyday bodies - sedan, compact
  crossover (`BodyType.CROSSOVER`, the commonest car in `BODY_ODDS`), full-size pickup,
  high-roof panel van - are Blender-built** by `tools/make_road_cars.py`
  (`tools/road_cars_setup.sh` fetches Blender 4.2 into the ignored `build/car_src/`; run it
  `blender -b --factory-startup -P tools/make_road_cars.py -- sedan crossover pickup van
  [--render]`, then `--import`). The shape is
  PROFILE CURVES (side view: roofline, rail/pillar line, belt, shoulder, sill, floor; plan view:
  width; insets for the shoulder shelf, tumblehome and sill tuck) lofted through eight-anchor
  sections into a quad cage, capped by a rolled rim and a domed Coons patch, subdivided at
  level 2 with a creased shoulder. The rail anchor IS the glasshouse line (roof side, A- and
  C-pillar), so windows are regions between rings. A flat-roofed body (the van) adds a ninth
  anchor, the roof edge (`roof_z` / `roof_w`, at `ROOF_J`), and pins the side's and the roof's
  tangents (`tangent_over`, weighted by `over_w`) - with the default bisector tangents a tall
  flat side bowed in 12 cm and the roof sagged. **Every profile must have keys to both ends of
  the car**: `Mono` extrapolates linearly past its last key, and a two-key weight curve
  extrapolated to 11.7. A sharp corner in the side profile (the pickup's roof edge over its
  near-vertical back, the header, the cowl) needs `extra_stations` either side of it and a
  `station_creases` loop at it, or subdivision rolls it off over the station spacing; extra
  stations clear the evenly spaced ones near them but never each other (they used to, which is
  why the first pickup's cab back was a long roll). Parts placed in an end view whose rays miss
  or spread over half a metre in depth are dropped and logged (a ray past a rounded corner runs
  on down the flank and made a streak along the van); bumpers are `wrap_band()`, one grid of
  horizontal rays across the face, radiating round each corner and along each flank. Arches, windows, lamp pockets, grilles and
  4 mm panel gaps are booleans after subdivision (guarded: a result that loses most of the mesh
  is rolled back and logged; gaps are cut one strip at a time with the hole-tolerant solver -
  a union of strips, or V-profiles meeting edge on edge, left the body open and every later
  cut deleted the car). Glass, lamps, mirrors, handles, trims are separate parts placed by
  raycast. Seven slots (`paint`, `glass`, `trim`, `chrome`, `tyre`, `light_front`,
  `light_rear`); only `paint*` takes the paint shader, `glass` takes the cabin glass (see Car
  glass and drivers), and on Compatibility `chrome` is swapped
  for a satin grey (`Vehicle._part_material()`, a metal has nothing to mirror there). Each .glb
  also holds a `<name>_far` twin (~8k triangles, `paint_far` + one vertex-coloured `parts`
  surface, `Vehicle.PARTS_SHADER`) drawn past `Vehicle.body_far_distance` (30 m) - seven
  surfaces are seven draws plus seven depth pre-pass draws a car - and only the twin has a baked
  wheel (WHEEL_POSE `"baked"`: no runtime tuck). `road` in `_dims()` is where the physics wheels
  touch the road in body space and `ride` where the model's bottom goes (road plus the far
  tyres' 2 cm gap; with ride = road the whole car sat 2 cm low); traffic places its kinematic
  cars `Vehicle.road_lift()` (= -road) over the road (a flat 0.55 m once made every traffic car
  float 15-27 cm). A long body's physics wheels can sit under its own asymmetric axles
  (`wheel_front` / `wheel_rear`; the van and the pickup). `tools/glshot/car_shot.gd` prints the
  contact (CONTACT) for a parked car (`--police --heavy` is the tactical van)
  and shoots front3/rear3/side/close/far views of any types in one launch (`--each=0,8,1`).
  The basecoat metallic is
  kept low (`Vehicle.FINISHES`): the mirror is the lacquer's job. `Vehicle.PAINTS` is weighted the way
  a real car park looks (mostly white/black/grey/silver). Grass is tapered curved blades whose
  normals are bent toward up so a lawn lights as a carpet, not as a pile of lit slivers.
- Vignette and lens: `CityStreamer._build_vignette()` puts `shaders/vignette.gdshader` on a
  full-rect `ColorRect` in its own CanvasLayer at layer -1, so it sits under the HUD, survives F1
  and shows up in screenshots. It reads the 3D picture (`hint_screen_texture`) and writes it
  back with the corner falloff (`CityStreamer.vignette_strength`), lateral colour fringing that
  grows with the square of the radius (`lens_fringe`), and a luminance film grain re-rolled at
  24 fps (`film_grain`). Every lens and film stock does these; keep each subtle enough that you
  cannot point at it (0 turns any of them off).
- Motion blur and depth of field (VISUAL_ROADMAP #12, 2026-09-27): both belong to `CameraPost`
  (`scripts/player/camera_post.gd`), the `Post` node under the player's CameraRig (so the test
  room has it too); every knob is an export there. **Motion blur** is `MotionBlurEffect`
  (`scripts/util/motion_blur_effect.gd` + `shaders/motion_blur.glsl`, an RDShaderFile whose six
  `#[versions]` are the kernels: prepare, tile max x / y, neighbour max, gather, resolve -
  McGuire 2012 with Guertin 2014's alternate taps; gather writes a result image and resolve
  copies it back only where a tile blurred, so a still frame copies nothing), a CompositorEffect on the player camera's `compositor`,
  built only where `CameraPost.supported()` (Forward+ with a RenderingDevice) - never on
  Compatibility, the web, the opengl3 stills or headless. It runs at POST_TRANSPARENT: HDR, the
  internal resolution, BEFORE TAA / FSR 2.2 (the last callback Godot has; TAA cleans its noise
  and the tonemapper sees a streaked highlight). Frame-rate independent: the velocity is one
  frame's displacement, times `shutter / reference_fps / frame_seconds`, where frame_seconds is
  the UNSCALED process delta (the wheel's slow motion blurs less, like a high-speed camera);
  lengths are in 1080-line pixels scaled to the internal resolution; `velocity_threshold_px` is
  a soft knee (walking stays sharp), `max_blur_px` the cap. Traps: with FSR 2.2 - which the
  pixel budget turns on at HIGH on a Retina Mac - the engine writes velocity only for MOVING
  objects and clears the rest to (-1, -1), and the sky writes none in either mode; both are
  rebuilt in the shader from depth and the camera's reprojection. `RenderSceneDataRD
  .get_cam_projection()` is already corrected (y flipped, reverse-Z in 0..1, the TAA jitter in
  its z column, which is zeroed), and its z row gives linear depth (`b / (depth + a)`). A camera
  that jumps over `max_camera_jump` or an origin re-centre (`effect.cut`) skips that frame, or
  the whole picture smears once. Quality: on at HIGH and MEDIUM. `-- --motionblur=0|1|<scale>`;
  `still_shot.gd` / `city_shot.gd` turn it off (`Engine.set_meta("postfx_motion_blur", 0)`)
  unless `MOTION_BLUR=1`; the HUD's FULL line says `+mblur` while it runs. Prove a change with
  `tools/glshot/motion_blur_shot.gd` (a small street through lavapipe Forward+; `DEBUG=1` paints
  the vectors, `AA=fsr` the FSR path). **Depth of field** is Godot's far blur on the camera's
  CameraAttributesPractical (only the dof_* fields; the auto exposure shares the resource), three
  states eased on the REAL clock: ambient (the old CameraRig focus that opens with altitude,
  HIGH only), aim (`LockOn.aiming`: blur from `focus + max(aim_dof_margin_min, focus *
  aim_dof_margin)`, focus = the locked target or the crosshair hit, HIGH and MEDIUM) and the
  weapon wheel (from `wheel_dof_distance`, amount `wheel_dof_amount`). Compatibility has no DOF.
- HUD: `scenes/ui/debug_hud.tscn` holds the stats, crosshair, the round minimap and the wanted
  stars and health bar (`WantedHud`, see the Police note), and `DebugHud` adds the weapon panel
  (`WeaponHud`, `scripts/ui/weapon_hud.gd`, top right: a pill of the wheel's smoked glass -
  `glass_hud.gdshader` mode 1 with no fill - with the gun's silhouette from the wheel's static
  icons, its name, an infinity sign and a chip per slot; it pops on a change; the stars hang
  under it via `panel_rect()`). The old text list (`$Weapon`) is hidden and only a fallback.
  Combat feedback: the crosshair (`Crosshair`, `scripts/ui/crosshair.gd`) flashes a hit marker
  when a round lands (`Crosshair.mark_hit(person)`, called by the rifle's `_mark()` and the
  shotgun: red for a person or a body, white for a car or an aircraft), and `DamageHud`
  (`scripts/ui/damage_hud.gd` + `shaders/damage_hud.gdshader`, the HUD's first child, built by
  DebugHud) blooms the screen edges dark red on each hit, draws a red arc on a ring round the
  crosshair toward whoever fired (from `PlayerHealth.hit_taken(amount, from)`), and pulses the
  edges like a heartbeat under `low_health`. `post_room_shot.gd MODE=hurt` shows both.
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
- Weapon wheel (owner, 2026-09-24: "GTA style ... slows everything ... apple glass style"):
  `WeaponWheel` (`scripts/ui/weapon_wheel.gd`) is its own CanvasLayer (3) in the HUD scene, so it
  draws over the HUD and still works in HIDDEN (a nested layer ignores its parent's visibility).
  Hold `weapon_wheel` (Tab at once; pad LB after `pad_hold_seconds`, a shorter tap = previous
  weapon): time eases to `slow_time_scale` and audio to `slow_audio_scale` on the REAL clock
  (the process delta is itself scaled), the mouse moves a virtual cursor (consumed in `_input`,
  so the camera never sees it) or the right stick points, and the release equips the segment
  (the centre keeps the current gun). It sets the rig's `look_blocked` and
  `WeaponManager.wheel_open`; every other close (pause, car, leaving the tree) restores time at
  once. The glass (`shaders/glass_ui.gdshader`) is one rect of signed distance fields: blurred
  screen (28-tap spiral on the screen mips, which Compatibility builds too) darkened into smoked
  glass so white glyphs read on anything, a lens and clearer frost at the rim, a magnifying
  centre disc, a specular hairline. Icons: `_build_icons()`, one per weapon class name. Shoot it
  with `WHEEL=<index>` on `tools/glshot/still_shot.gd` (no `--nohud`).
- Pause menu (`scenes/ui/pause_menu.tscn`, built in code by `scripts/ui/pause_menu.gd`) owns
  Esc: pause, mouse release, the frozen frame blurred and darkened behind it
  (`shaders/pause_backdrop.gdshader`, screen mips), a column of frosted chips in 1080-line units
  scaled to the window - Resume; TIME OF DAY presets (sets `DayNight.hour` and redraws at once,
  the tree being paused); WEATHER (`Weather.force_state()`: instant, a wetter state soaks the
  streets at once; Auto lets it roll); GRAPHICS (`Quality.force_level()`; Auto adapts again);
  the seed and Rebuild (`WorldState.pending_seed` + `reload_current_scene()`); Quit - and a
  CONTROLS card on the right. `post_room_shot.gd MODE=pause` shows it in seconds.
- Input actions live in `project.godot` under `[input]`. Current actions: `move_forward/back/left/right`,
  `jump`, `boost` (Shift / gamepad B), `look_left/right/up/down` (right stick), `fire`, `alt_fire`,
  `next_weapon`, `prev_weapon` (mouse wheel only), `weapon_1..3`, `weapon_wheel` (Tab / gamepad
  LB: a quick LB tap is still "previous weapon", see the weapon wheel note), `interact` (E / gamepad Y),
  `respawn`, `toggle_mouse`, `toggle_hud`. Add new actions there. There is no sprint; boost replaced it. In a
  jet: boost = throttle up, alt_fire = throttle down, move axes = pitch and roll.
- NPCs: `Pedestrian` (wanders a block's sidewalk ring, going round it by its corners -
  `_ring_route()` - and now and then across a crosswalk to the next block, see Street life;
  `knock(impulse)` turns it into a `Ragdoll` debris) and `TrafficManager` (kinematic `Vehicle`s
  with `traffic` state driving the lanes).
  Never freeze a VehicleBody3D and never give a kinematic one VehicleWheel3D nodes: NaN.
  Panic (owner, 2026-09-23: "when you shoot there should be NPCs screaming"):
  `Pedestrian.alarm(tree, at, radius, screams)` scares everyone in range - they run
  (`run_speed`, the avatar's run clip) along their pavement ring away from the threat for
  `panic_seconds`, and the nearest few of the newly scared scream (Sfx `scream`, 12 real takes,
  spaced across the crowd by `scream_gap_ms`). `Weapon.tick()` raises it at `alarm_radius` from
  the shooter (70 m for the shotgun), `Explosion.blast()` at six blast radii. One pass over the
  crowd group per alarm, rate-limited per spot, so an automatic rifle costs nothing extra.
  Dismemberment (owner, same day: "body parts limbs flying off ... from the rocket launcher"):
  `Explosion.blast()` passes `gibs` (up to 3 inside `gib_reach` of the radius) to
  `Pedestrian.knock()`, and `Ragdoll.dismember()` collapses each lost limb with a `LimbHider`
  (a SkeletonModifier3D - the clips key scale, so a plain bone scale is overwritten), adds a
  stump, and throws the limb as a static mesh cut from the character (`_limb_mesh()`, cached per
  model and limb). Three traps, each found the hard way: a skinned vertex must be taken through
  its bones' bind poses (`skin.get_bind_pose()`) - read raw, these rigs put the limb a hundredth
  of its size at the feet; a limb must not collide with the body it spawns inside, or with the
  ground it overlaps (the depenetration fired legs up at 45 m/s); and cutting needs mesh data,
  which the headless dummy renderer does not keep, so the smoke test cannot see limbs - judge
  them with `still_shot.gd` (`FX_AT_PED=1 FX_PED_PLACE=1`). Blood from gunshots and gibs is in
  the Effects note (`WeaponFX.bullet_wound()` / `blood()`).
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
- Police (owner, 2026-09-24: "a police and star system", GTA-style but original - no "WASTED",
  no "BUSTED", no copied UI). `Police` (`scripts/npc/police.gd`) is a node in the city scene, in
  group `wanted`: `stars` is a plain int 0-5 that other systems read (the police helicopter is
  another branch's and reads it there), `stars_changed` fires on a change, `report_sighting()`
  tells it a non-police unit saw the player, and `report_crime(kind, world_pos, severity)` takes a
  TRUE world position. Crimes come from hooks where they already happen, never from the
  weapons: `Pedestrian.alarm()` (every gun and blast calls it; it now counts who heard it and
  reports gunfire, or an explosion when forced; its `crime` argument "" reports nothing - police
  fire uses that), `Pedestrian.knock()` (`Police.person_down`: an officer is `cop_down`, which
  always counts) and `Vehicle.drop_out_of_traffic()` (`Police.car_hit`). A crime counts only
  with a witness (pedestrians within `witness_radius`, police within `cop_hear_radius` or in
  sight) and adds heat; `star_heat` turns heat into stars, which never fall with it.
  `Police.innocent` is set around every knock the police cause themselves (their rounds, a
  cruiser's bumper) so it is not the player's crime. Units look for the player every
  `sight_interval` (a world-layer ray each, `max_sight_rays` a look); unseen for `lose_seconds`
  the stars flash (`flashing`) and drop one per `flash_seconds`, and the units go to `last_seen`,
  the centre of a search area that grows while the trail is cold. Response caps
  `cruisers_per_star` / `officers_per_star`, roadblocks from `roadblock_stars`, tactical vans
  from `heavy_stars`; units past `recall_distance` that nobody has seen are recalled; cruisers
  are pooled. `PoliceCar` (`scripts/npc/police_car.gd`, extends Vehicle): DISPATCH drives the
  lanes kinematically (its `traffic` dict carries `"police": true`, so it has no VehicleWheel3D),
  taking each junction's turn from a street route (`StreetRoute`, see Street life) and running
  every red with the siren going; for a player on foot it stays on the lanes to the kerb nearest
  him (`StreetRoute.kerb_stop()`) and pulls up there (`_pull_up()`: `go_physical()` then
  `stop_here()`) - handed to physics on the last straight instead, it got knocked off the road
  by the wrecks of a busy fight and stuck short. PURSUE is real physics within `engage_range` of a player in a car the police
  can see (the same handover traffic uses, `go_physical()`), and after a hit or a reboard: it
  steers along the route's lane polyline (`_path_target()`, slowing for turns), straight at the
  car only inside `ram_range` with a clear line - it used to steer straight at the target from
  70 m, so a player on a roof got a cruiser nosing into the wall. Then STOPPED -> PARKED and the
  crew gets out (`Police.deploy_crew`). Pooling strips the wheels BEFORE it re-freezes the body (a frozen
  VehicleBody3D with wheels is NaN). Livery is `car_paint.gdshader` `stripe_mode` 5 (white doors
  and roof over black), the light bar one vertex-coloured mesh on `shaders/police_lights.gdshader`
  plus an OmniLight3D at night (desktop), the siren the Sfx `siren` loop (a real recorded wail). `PoliceOfficer`
  (`scripts/npc/police_officer.gd`, extends Pedestrian, so it is shot, knocked, gibbed and
  ragdolled like anyone; takes `hits_to_down` rounds): an `Avatar` body (so `Avatar.hold_gun`'s
  IK holds its `PoliceGun`), a navy recolour through the character shader
  (`uniform_material()`, only on the rigs in `OFFICER_MODELS` - people in trousers with short
  hair; the crowd's region colours recolour any garment exactly) and a peaked cap (the hair
  cards are hidden under it); COVER at the ends of its cruiser, ENGAGE, SEARCH the area, REBOARD when
  recalled; it fires only with an open line from the muzzle (`_line_of_fire()`: the first
  version emptied its gun into the cruiser it hid behind) and steps out sideways when blocked;
  its rounds go through `WeaponFX.tracer/flash/impact`. A knock-down is pinned on the player a
  tick late (`Police.knocked_down`), because `Weapon.tick()` knocks the target over before it
  raises the alarm that says it fired. Player
  health is `PlayerHealth` (`scripts/player/player_health.gd`, `Player.health`,
  `Player.take_damage()`): 250 hp, regen after `regen_delay`, `self_blast_damage` off (rocket
  jumps stay free), and at zero a real-clock slow-motion collapse, the "OUT COLD" card
  (`shaders/downed.gdshader`) and a respawn at the nearest street corner `respawn_clearance` away,
  stars cleared. HUD: `WantedHud` (`scripts/ui/wanted_hud.gd`, `shaders/glass_hud.gdshader`,
  the weapon wheel's glass) draws the stars under the weapon list and the health bar over the
  minimap; the minimap draws the units as flashing red/blue blips and the search area. The
  smoke test runs with `Police.enabled` false except in `_test_police`. Stills: `STARS=n
  POLICE=standoff|pursuit` on `tools/glshot/still_shot.gd`.
- Street life (owner, 2026-09-24: "GTA-level street life"). **Signals are worked out, never
  ticked.** `TrafficSignals` (`scripts/world/traffic_signals.gd`, static) is one shared clock
  (`clock`, advanced once a physics tick by `TrafficManager` and pushed as the `signal_clock`
  shader global) plus a seeded offset per intersection (`offset01()`), so any head's state
  anywhere is a few multiplies: `light(plan, ix, iz, axis)` for cars on roads of `axis`,
  `walk(plan, ix, iz, crossing_axis)` for people crossing a road (they walk with the traffic
  beside them - the other axis' green: WALK, then the flashing hand and countdown), `force()` for
  tests and stills. The cycle's four numbers (`GREEN`, `AMBER`, `ALL_RED`, `WALK_TIME`) reach
  the lens shader only through `PropFactory.signal_lens_material()`; the smoke test checks the
  copy. The hardware is `tools/make_signals.py` (Blender, headless, like the facade kit;
  dimensions in its header, mirrored by `PropFactory.SIGNAL_*` and checked against the loaded
  bounds) -> `assets/models/traffic_signal.glb`: tapered pole on a bolted base, a mast arm scaled
  along its length per approach, three-lamp heads with tunnel visors and a yellow-bordered
  backplate, a side-mount bracket, pedestrian heads (original raised hand / walking figure beside
  a seven-segment countdown), push buttons, a controller cabinet. `CityChunk._add_signal_corner()`
  lays a junction out US-style - each corner's pole carries the arm for the approach it is the
  far right of, a head over every lane plus one low on the pole, and the two pedestrian heads
  facing back across the crosswalks that end there - as ONE prop per pole (it breaks as one)
  whose head instances carry `Color(offset01, axis, 0, 0)` as MultiMesh custom data (the fifth
  entry of an `_add_prop()` instance). `shaders/traffic_signal.gdshader` reads that and UV2.x
  (the lamp id the model bakes) and lights LED-dotted HDR lamps. Nothing per signal runs on the
  CPU. The old primitive `_add_signal()` is only the fallback for a missing model.
  **Street traffic queues.** `TrafficManager._drive_streets()` groups the street cars by lane
  (`lane_key()`: road, axis, direction, lane), sorts each group along the road and drives each
  car with the Intelligent Driver Model behind the one in front; everything else it must stop for
  is another stationary car in front of it - the stop line (nose `stop_line_back` short of the
  crossing road) at a red or an amber it can stop for (`_must_stop()`, `amber_margin`), a stop
  sign until it has stood `stop_sign_wait` at it, a crosswalk with somebody on it
  (`Pedestrian.crosswalk_busy()`), the player's car in the lane (solid) or the player on foot
  (braked for, up to `player_brake`, not guaranteed). A hard clamp (`room`) means a nose never
  passes what is in front of it, and a car closed up on something still stands still (the IDM
  alone creeps forever). Turns are rolled once per junction (`t.turn`), slowed for
  (`turn_speed`), and skipped if the target lane is occupied at the corner; cars pull to the kerb
  and stop for a siren behind them (`siren_yield_distance`). **A forced turn is never dropped:**
  where the road ahead is closed (`t.forced`) and the lane the car must turn into is taken, it
  waits at the centre of the crossing; dropping it drove the car straight into the closed road,
  which was MacArthur Park's traffic leak (it only showed at a busy corner). Police cruisers are not in the
  groups and run reds. `place_car()` puts a street car exactly somewhere (tests, stills), and
  **`staged`** stops the upkeep shedding or spawning street cars while that is going on - with
  spawns still queued a lowered cap overshoots, and the shedding that follows takes the placed
  cars with it (it did, in the first version of the checks).
  **Pedestrians cross.** At a spot on their ring, `cross_chance` of walkers call
  `plan_crossing()`: the corner nearest them, if its junction has crosswalks (signals or stop
  signs) and the block over the road is city ground; they walk round the ring to the kerb (TO_KERB),
  wait (WAIT: the walking figure at a signal, `stop_sign_patience` at a stop sign), cross placed
  rather than slid (CROSSING, down onto the asphalt and up again; `cross_pace`) and belong to the
  next block's ring after. `Pedestrian._crosswalks` counts who is on each crosswalk,
  `Vector4i(ix, iz, crossed axis, side)`, taken on in `_start_crossing()` and off in
  `_leave_crosswalk()` (also from `_exit_tree()`, so a knocked or freed walker never leaves a
  crosswalk "busy"). Panic cancels a wait; somebody already in the road runs the rest of the way.
  A walker stays a child of the chunk it spawned in wherever it walks, and its movement now
  reads the chunk-local `position` (true world, the ring's space) - it read `global_position`,
  which is the same thing only until the first origin shift.
  **Police route by street.** `StreetRoute` (`scripts/npc/street_route.gd`, static): A* over
  the intersection grid (`path()`, bounded to a box round the ends, U-turns charged
  `U_TURN_COST`, stretches off city ground refused), `kerb_stop()` (the lane on the goal's side
  of the nearest road, level with it, clear of the crossings, just inside the parked cars; a goal
  on the carriageway itself is stopped short of), `locate()` and `polyline()` for the physics
  follower. Stills: `STREET=queue|crossing` on `tools/glshot/still_shot.gd` (a queue at the red
  of the junction ahead of the camera, walkers on the crosswalk in front of it; `--hour=21` for
  the heads at night). Checks: `tests/street_life_checks.gd`, loaded by the smoke test like the
  air traffic's.
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
- Car damage (roadmap #10): `CarDamage` (`scripts/vehicles/car_damage.gd`), a node the car makes
  on its FIRST hit - an undamaged car has none, keeps the shared `car_paint.gdshader`, its body's
  shared cabin glass and the model's own lamp materials, and costs what it did (the only per-car addition is
  `Vehicle._crash_watch()`, one velocity subtraction a tick in the car's existing script).
  **One entry point: `Vehicle.take_hit(shape, damage, dir, at, kind)`** with `HIT_BULLET` /
  `HIT_PELLET` (the weapon's own damage: rifle `fire_ray`, shotgun `fire_pellet`, police
  rounds under `Police.innocent`), `HIT_BLAST` (`damage` is the falloff at the car, `at` the
  centre: `Explosion.blast()`, once per car, not once per collision shape), `HIT_CRASH`
  (`damage` = m/s over `crash_min_dv` / `landing_min_dv`: the crash watch, a velocity change in
  one step; call `hold_crash_watch()` before changing a car's velocity on purpose - jumps,
  respawns, blasts do) and `HIT_PROP`. A traffic car goes physical first. Rounds are traced
  onto the real body mesh (`TriangleMesh`, cached per mesh; face -> slot), so a hole lands on
  the skin, a round in the glass slot crazes or shatters that pane and one in a lamp breaks
  it. The paint is copied onto `car_paint_damage.gdshader` (the same `car_paint.gdshaderinc`
  with `CAR_DAMAGE` defined: holes with a bright torn rim and chipped halo, crumpled dents
  displaced in the vertex shader, blast scorch, the burn front from the engine bay in bands of
  blistered paint, soot and rust / ash bare steel) on the car's body meshes AND its shadow
  twins; the glass slot onto `car_glass_damage.gdshader` (panes = the glass surface's connected
  pieces, `CarCabin`'s, measured once per body type: tempered side and rear glass crazes then
  falls out as cubes, the windscreen only collects webs, lamp lenses go with their lamp; an
  empty frame shows the traced cabin of `car_cabin.gdshaderinc` at `cabin_light`, what is still
  whole shows it through its tint like the intact glass; the occupants move onto it - it takes
  the same occupant uniforms - and leave when it catches fire); the
  lamp slots onto `car_lamp_damage.gdshader`; the night glow is
  `PropFactory.vehicle_lights(..., broken)`, one shared mesh per combination. Health
  (`max_health` 1000): smoke past `smoke_at`, fire past `fire_at`, `burn_seconds` later (a
  `quick_fuse` after a rocket-sized hit) `explode()`: the driver is thrown out, the car's own
  `Explosion.blast(..., exclude)` is the player's crime unless the police lit it
  (`blame_police`), the wreck is tossed, burnt out, sat on charred rims, burns, smokes, and is
  PhysicsBudget debris for `wreck_lifetime` (`register_debris(body, lifetime)`). Caps (static):
  `max_burning`, `max_smoking`, `max_wrecks`, `max_glass_bursts`. A wreck cannot be driven
  (`is_wreck()`), a pooled cruiser is `repair()`ed, a burnt cruiser leaves the police
  (`Police.car_wrecked`), the flyable jets opt out (`can_take_damage()`). The fire is the
  explosion's `fire_puff.gdshader` on `CarDamage.fire_material()` (short soft fade, lower heat):
  a billowing body out of the bay, tongues off the bonnet's edges and up the windscreen, flames out
  of the cabin's empty frames after `spread_share` of the burn, embers, black smoke opaque where
  it leaves the flames, a flickering light (desktop); the plain puff on the web. **Flame colours
  hold green at ~half of red while bright**: through AgX a red-heavy colour brighter than ~1
  turns salmon pink (measured with an unshaded colour chart), and fire_puff gives a puff's core
  and edge the same ratio. Stills:
  `DAMAGE=holes,glass,dents,smoke,burning,blaze,wreck` on `tools/glshot/car_shot.gd` (views `door`,
  `glass`, `screen`, `cabin`); checks: `tests/car_damage_checks.gd`. Traps: a `--script` tool
  that names `CarDamage` as a type compiles it before the Sfx autoload exists (load it by path);
  setting a `CPUParticles3D`'s `amount` restarts it (every particle gone), so a fire resized
  every frame drew nothing - change amounts in steps, only when they change; a crash watch
  without its contact ray takes every scripted velocity reset for a crash;
  `Explosion.blast()` still pushes a car once per collision shape (2-3x a rocket's 30 m/s).
- Car glass and drivers (2026-09-28: "every car on the street reads as a sealed toy, and traffic
  drives itself"): `CarCabin` (`scripts/vehicles/car_cabin.gd`). Every body with a glass slot
  (the road_* bodies, the exotics; the Meshy sports car has its glass in the paint and stays
  opaque) wears `shaders/car_glass.gdshader` on it, ONE shared material per body type while
  nobody is inside (`CarCabin.glass_material()`, set by `Vehicle._add_cabin_glass()` after the
  wheel tuck): still
  opaque (no transparent pass, nothing to sort), the model's own glass colour / roughness / metal
  so the renderer's reflection is what it was, and the cabin behind the pane EMITTED over it -
  `shaders/car_cabin.gdshaderinc`, the trace the damage glass had, moved into an include both
  shaders use (`#define CABIN_FIRE` for the damage's `burnt` / `cabin_fire`), traced in the
  body's mesh space so it has true parallax: dash (instrument cluster and centre screen glowing
  after dark while somebody is at the wheel, `dash_glow`), steering wheel on the driver's side
  (left-hand drive, `driver_side`, column raked up), console and gear lever, two front seats and
  the rear bench with headrests, headliner, door cards, the far windows letting the day in (and
  the street at night, `street_light` x `lamp_factor`). Through whole glass it is dimmed by
  Fresnel (the renderer draws the reflected share), `glass_tint`, `through_light` (0.45: on
  Forward+ it read as bright as the paint at cabin_light; `through_light_compat` 0.9 on the
  Compatibility renderer, which lights the paint far brighter) and the pane's own tint in
  `pane_n.w`: windscreen 0.8, front side glass 0.6, rear side 0.48 (privacy 0.17 on the
  crossover, pickup and van: `side_t`, picked per fragment by which side of the front seat backs
  it is, since the pickup's two door windows are one piece of glass), rear screen 0.42 (privacy
  0.17), a two-seater's engine cover 0.1, mirrors and badges (`TINY_PANE`) and lamps nothing.
  Past `cabin_detail` (12 m) the lever, screen, wheel hub / spokes / column and thighs leave the
  trace; past `body_far_distance` (30 m) the far twin (no glass slot) draws anyway; exotics fade
  to plain glass by `cabin_far`. **Who sits there** is four uniforms (`occupant_top` / `_skin` /
  `_hair` / `_mate`; seats in `occupant_top.a`, bit 0 the driver, bit 1 the front passenger) set
  by `CarCabin.seat()` from `Vehicle._update_occupant()` / `_apply_occupant()`: an empty car on
  the shared material, an occupied one on its own copy (`_glass_own`, made once and kept), a
  damaged one on CarDamage's glass (`_update_occupant(true)` when that swaps in or out); shadow
  twins keep what they have. **Never `instance uniform`s here**: each instance using them takes a
  16-item block of the global shader buffer, which the Compatibility renderer caps at 4096 items
  (WebGL2 can give a quarter of that) - with every car and its shadow twin on them a downtown
  still logged 267 allocation errors. Traced people (`person()`: head with hair / a cap / long
  hair by style and a darker eye band, neck, shoulders, chest, thighs, arms whose elbows bend to
  hands at ten to two on the rim, or in the lap for a passenger), laid out from the side glass
  down (crown just under `side_top`, shoulders a hand over the door line) because the bodies'
  cabins are 10 cm lower than a real one's, lit like the seats at `people_light`. Rules
  (`Vehicle._cabin_seats()`): a car given `traffic` gets a driver (`_npc_driver`, a look from
  `_occupant_seed`, re-rolled each time it comes out of the pool; `PASSENGER_SHARE` 22 % carry a
  passenger), who stays when a hit knocks it out of traffic and gets out when it catches fire
  (`_abandoned()`); the player at the wheel is the player (`driver` setter; the hero himself is
  hidden in a car, `CarCabin.player_look()`), and the car he leaves is empty; a parked car is
  empty; `PoliceCar` seats its crew from `crew_aboard` (a setter), driver and passenger in
  uniform and cap. `CarCabin.measure()` (was CarDamage's `_measure_panes` / `_set_cabin`) keeps
  the panes, the cabin box, `belt_y`, `side_top`, the seat rows (front row `COWL_TO_SEAT` 0.95 m
  behind the windscreen's foot - the old middle-of-the-side-glass rule sat the saloon's driver
  behind the B-pillar and the van's seat under its dash; no back seats on a two-seater or a cab
  shorter than `REAR_SEATS_SPAN`; the dash face at least `DASH_TO_SEAT` ahead of the front row),
  per body type, with the stand-in panes where the headless
  dummy keeps no mesh data. Stills: `OCCUPANT=npc[:seed]|pair[:seed]|player|none` on
  `tools/glshot/car_shot.gd`, views `driver`, `inside`, `street`, `chase`, `CABIN_DEBUG=1`
  paints the body parts, `CAR_GLASS=0` (also on `still_shot.gd`) is the A/B, `TIME=n` a view's
  frame time.
  Checks: `tests/car_cabin_checks.gd`.
- Aircraft: `Aircraft` (`scripts/vehicles/aircraft.gd`) extends `Vehicle`; kinds PRIVATE and
  AIRLINER, flight numbers are exports at the top, models in `MODELS`. Jets spawn at
  `MacroMap.apron_spots` (position, kind, optional yaw) from the airport chunk. Every airliner -
  the flyable one, the air traffic's, the parked gate jets - wears an invented livery painted
  from the model's own shape (`shaders/airliner_livery.gdshader`, see the Airport note): the
  Meshy texture read as camouflage. Terrain bodies carry `CityChunk.TERRAIN_LAYER`
  (bit 5) and the player's under-terrain ray uses only that layer.
- Air traffic (owner, 2026-09-24: "helicopters, police choppers, news choppers, private jets
  flying thru the sky, commercial jets taking off and landing at LAX"): `AirTraffic`
  (`scripts/world/air_traffic.gd`, a Node3D in `city.tscn`) flies scripted `AmbientCraft`s -
  `AmbientJet` (airliners and private jets on `AirRoute`s) and `Helicopter` (police, news) -
  none of them simulated. An `AirRoute` (`scripts/world/air_route.gd`) is a world-space track
  of straight legs and circular turns with a height per point, sampled by distance flown, and
  lifted clear of the city by `AirRoute.clear()` against `AirTraffic.obstacle_top()` (terrain,
  the plan's own lots and massing heights plus roof plant, freeway decks that really pass
  overhead, the far landmarks' bounds, trees, port cranes; 50 m cells, cached). The east range
  stands two kilometres from the airport fence, so arrivals come up the basin from the south
  (`downwind_x`), turn onto a 3 degree final over the city and land WESTBOUND on the south
  runway, 27L (`MacroMap.arrival_runway`); departures line up on the north runway, 27R
  (`MacroMap.departure_runway`; the hangars stand across its east end) and climb out west over
  the sea.
  `MacroMap.runway_clear_zone()` keeps lots out from under the last 700 m of the final
  (`CityPlan.lots()`): midtown lots put 20 m buildings where the glide path is 15 m up. News:
  `Explosion.blast_count` / `last_blast_world` are polled; a blast within
  `news_interest_radius` of the player sends the news helicopter to circle it. Police: the
  group "wanted", `.get("stars")` (the most any node in it says; absent is 0); at
  `police_stars` one, a star more two, circle the player with a `SpotLight3D` searchlight -
  volumetric only where volumetric fog is on (Forward+ HIGH), a drawn shaft elsewhere
  (`shaders/searchlight_beam.gdshader`), always an additive pool where it lands - and LEAVE when
  the stars clear. While the light holds him with a clear line (`Helicopter.has_eyes_on()`)
  AirTraffic calls `report_sighting()` on the wanted node (`Police`), so the stars do not drop
  under a helicopter that can see him. Every aircraft is an AnimatableBody3D on the props layer (mask 0) with box
  shapes and `take_hit()`, so bullets, pellets, rockets and blasts hit it with no weapon code
  knowing aircraft exist; the layer is dropped past `hit_range`. Shot down: smoke, a spin
  (helicopters) or a dive (jets), `Explosion.blast()` where it hits, a charred burning wreck for
  `wreck_seconds`, a replacement later. Lights are one additive billboard mesh per aircraft
  (`shaders/aircraft_lights.gdshader`: nav, strobes, beacon, landing lights), never drawn
  smaller than a few pixels and pulled inside the camera's far plane (12 km), so a night approach
  reads across the basin. **A light is aimed only if its UV2.y code has 100 added** (the landing
  lights): Godot cannot store a zero normal (it comes back (0, 0, -1)), so the old "zero normal
  = all round" made every nav light, strobe and tower obstruction light face NORTH and show at
  6 % from anywhere else. Above `disc_rpm` the rotor blades are swapped for
  `shaders/rotor_disc.gdshader` (real blades strobe). Sound: Sfx `jet_loop` / `rotor_loop`,
  real CC0 recordings, with a long falloff and a cheap Doppler. **Trap:** give an aircraft its
  transform BEFORE `add_child()` (`AirTraffic._place_before_entry()`). Godot derives a kinematic
  body's velocity from how far it moved in a step; one that entered at the origin and was put
  two kilometres away moved at ~170 km/s for a step, and a player standing at the origin took
  that as platform velocity and left the map. The checks (`tests/air_traffic_checks.gd`, loaded
  by the smoke test) step aircraft with `advance(dt)` in a loop - minutes of flight in a frame.
  Stills: `AIR=final|takeoff|news|police` on `tools/glshot/still_shot.gd` (the staged jet is
  faded in at once, `AirTraffic._shown()`). The helicopter model is `tools/make_helicopter.py`
  (Blender, headless; ASSETS.md).
- Airport (2026-10-04, "a major international airport, ground and air"; original - invented
  airlines, no real names or logos, a big field's FORMS). Three files. **`Airport`**
  (`scripts/world/airport.gd`, static) is the LAYOUT, all derived from MacroMap's numbers:
  `runway_zs` is the parallel pair (870 = 27R / 09L, 960 = 27L / 09R, 45 m wide; the old third
  runway at z 780 is `taxiway_z`, the parallel taxiway), `CONNECTOR_XS` the cross taxiways, the
  grass between (`grass_rects()`), the concourse ARC (`ARC_CENTRE`, `CONCOURSE_RADIUS`, a = 0
  due south of the centre; `arc_point()` / `arc_normal()` / `arc_tangent()`), `gates()` (9
  stands: nose, centre, yaw, the jet bridge's rotunda, the forward-left door, livery, which
  trucks attend it; stand 17 is empty), `mast_spots()`, `runways()` (ends, designators),
  `papi_spots()`, `windsock_spots()`, and the landside rects (`HEAD_HOUSE`, `TOWER_AT`,
  `SKYHOOK_AT`, `GARAGE_RECT`, `RENTAL_RECT`). `Airport.build_chunk()` (from
  `CityChunk._build_airport()`) lays the ground as a **partition** (`ground_pieces()`: apron
  concrete, asphalt taxiways and runways, grass, side by side - never one slab over another,
  which z-fights from a few hundred metres up and drew every runway as grey streaks; one
  collision box under it), which the far city's capture records; then FULL and LOD get the
  floodlight masts with their night pools, the perimeter fence (`AirportKit.fence_panel()` on
  the chain-link shader) and the navaids (blast fences, localizer, glide slope, windsocks,
  PAPI), and FULL the paint (runway thresholds, designators as flat TextMesh, touchdown zone,
  aiming points, centre and edge lines, rubber; taxiway centre and edge lines, lead-off curves,
  hold-short bars; stand lead-in lines, stop bars, numbers, red equipment-restraint envelopes,
  the service road; the texts - designators, stand numbers - ONE mesh per colour a chunk,
  `Airport.merged_text()`), the light fixtures and every attended gate's ground service equipment
  (pushback, belt loader, baggage tug and carts, catering truck on its scissor lift, fuel
  truck, GPU, cones) as ONE instance of `AirportKit.gate_set(variant)` (one mesh per service
  variant, built in the stand's frame through `AirportKit._xf`; never `append_from()`, a
  read-back), the staging rows at the concourse ends (`staging_set()`), and 2-3 `ApronCrew` (`scripts/npc/apron_crew.gd`, a Pedestrian in hi-vis
  on a small ring by the jet, crowd-capped, never crosses). Every roll is a hash, never the
  block rng. **The field's lights** are ONE billboard mesh (`Airport.lights_mesh()`, ~640
  lights) on `aircraft_lights.gdshader`, worn by the `airfield_lights` landmark near and far
  alike (meta `air_ignore`: AirTraffic's clearance field skips it): runway edges (yellow over
  the last 200 m), centre lines (red toward the end), green thresholds and red ends (aimed),
  touchdown zone bars, the approach light system 450 m out east over the long-term parking with
  its crossbar, red side rows and sequenced flasher, the PAPI, blue taxiway edges, green centre
  lines, red stop bars, the masts' floods, red obstruction lights and the tower's rotating
  beacon. Kinds 4-7 in the shader: field light (nothing by day, `field_day`), rabbit, rotating
  beacon, PAPI (white or red by the eye's angle). **`AirportTerminal`**
  (`scripts/world/airport_terminal.gd`) builds the landmarks (each its own entry in
  `Landmarks.all()`, far copy kept, so the chunk round each builds it in detail): `terminal`
  (the head house: a glazed hall under a wing roof that sweeps out over the drop-off on
  branching tree columns, its slatted soffit lit at night; plus `Landmarks._build_dropoff()`'s
  road and lit DEPARTURES boards), `concourse_w` / `concourse_e` (the arc's halves: service
  level, glazed departures level on `curtain_glass` with its lit interior, clerestory, jet
  bridges docked at each gate, and ONE MultiMesh of the airliner model at the gates on
  `airliner_livery.gdshader`, the livery in INSTANCE_CUSTOM.r * 8), `control_tower` (ribbed
  shaft, lit glass cab, beacon at `TOWER_TOP`), `skyhook` (two crossing parabolic arches over a
  lit disc restaurant, floodlit), `airport_garage` (`ArenaGrounds.garage()`), `rental_lot`
  (`ArenaGrounds.surface_lot()` and a pavilion). **`AirportKit`**
  (`scripts/world/airport_kit.gd`) is the hardware, code-built at real size on
  `shaders/airport_kit.gdshader` (part kind in the vertex alpha: paint, lamp, glass, rubber,
  metal; a vehicle's livery in INSTANCE_CUSTOM). Liveries: six invented airlines in
  `airliner_livery.gdshader`, painted by region of the model in its own units (fuselage, belly,
  cheatline, windows, doors, cockpit, fin and its mark, nacelles, wings, gear). Checks:
  `tests/airport_checks.gd`. Stills: the four in docs/HANDOFF.md 9bb.
- Shop signs: storefront sign bands carry real names. `Building` picks how many window bays
  make one shop per face (`_shop_spans()`, hashed from the seed, never from `_rng`) and passes
  it to the shader as `shop_span`, so the bands the shader draws and the `TextMesh` names the
  script places line up. One `MeshInstance3D` per name, shadows off, stops drawing past
  `Building.SIGN_DRAW_DISTANCE`, and skipped entirely on web. Names are in
  `Building.SHOP_NAMES` and are original, never a real brand. Note the shader measures its `u`
  the opposite way round the box from the script's `a` on every face, so a run's centre has to
  be mirrored.
  **Street level at night** (the storefront row is a patchwork, not one lit band): each shop's
  night is rolled from INTEGERS - `shop_hash()` in `building.gdshader`, `Building.shop_hash()` /
  `shop_byte()` / `shop_key()` bit for bit (a float hash cannot be reproduced off the GPU), salts
  listed on `Building.shop_hash` - so the script knows what the shader draws. About 62 % of shops
  are open: their traced room is lit in its own `shop_tone()` (warm, neutral, cool, now and then
  pink or teal) at its own brightness, and a third hang a neon piece (`neon_shape()`, four
  shapes, `neon_color()`) in the bay after the door. Closed ones are dark with a night light, and
  over half pull a roll-down shutter (only while `lamp_factor` > 0.5, so never by day; a third
  of those a see-through scissor gate instead), and the door bay itself is now an integer roll
  too (salt 15), so the kit's door stands in it (see Storefronts and curtain walls). Sign
  bands: a closed shop leaves its lightbox off as often as not, and over half the boards are
  dark with lit channel letters (`Building.shop_letters()` -> `PropFactory.shop_sign_material()`,
  cream by day as before); the board draws a lit stand-in strip of their colour where there are
  no letters (`sign_letters` false: the web, landmark towers) and past the letters' cull. Open shops
  throw their light on the pavement: `Building.shop_pools` -> `CityChunk._add_shop_spill()`, ONE
  additive batch per chunk (`PropFactory.shop_spill()`, `light_pool.gdshader`), knobs
  `shop_spill_*` on Building. All of it runs off `lamp_factor`. The palettes are written in
  both places; the smoke test reads the shader's copies back.
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
  750, and they stop drawing past 160 m. Far (LOD) chunks build no lamps, so their streets glow
  instead (`shaders/street_glow.gdshaderinc`, used by `far_ground.gdshader` and, past
  `street_glow_near`, by `road.gdshader`, whose road materials carry `lamp_axis`): pools of
  sodium light at both kerbs, staggered, every `street_glow_spacing` metres, over a faint run
  down the carriageway, ramped in as `lamp_factor` cubed (a lamp is invisible from the air until
  it is properly dark), so a night flight shows the double rows of orange dots a real city is
  from the air instead of lit towers in a void. A pool the width of the road read as orange
  tiles. The far chunks' merged ground marks its carriageways in the vertex colour's alpha (which
  way each runs, from the slab's shape), and every city ground grid carries a 0..1 UV across its
  rect so the shader knows where the kerbs are. Far ground colour is the tint at 0.6 for
  anything textured up close (only asphalt is taken at its tint): at the bare tint the far
  pavements were twice as bright as the near ones. **Trap:** `SurfaceTool.append_from()` ignores `set_color()`
  - the colour has to be in the appended mesh (`_grid_mesh(..., colored, color)`). Until that
  was found the far city's ground had no colour at all and was black by day as well as night. The shader reads `lamp_factor` itself, so all of it
  costs nothing by day. The headlight beam quads carry UVs shifted by 2 (`_light_quad()`'s
  `uv_shift`), and `UV.y > 1.5` is how the shader knows to draw a fan that widens and fades
  along the road instead of a round pool; drawn as a pool, a beam laid flat on the street read
  as a long white smear.
- Car lights (GAME_PLAN G4 / G6, 2026-10-04): the lamp mesh is `PropFactory.vehicle_lights()`
  on `shaders/car_lights.gdshader` (it replaced light_pool for cars): head and tail glows, the
  beam fan, amber indicators at all four corners, reversing lamps and a red wash on the road
  behind. Which part a quad is rides in its u (shifted by 2 x the part, `PropFactory.LIGHT_*`;
  the beam keeps its v + 2). What the car is DOING is the MATERIAL:
  `PropFactory.vehicle_light_material(brake, signal, phase, reverse)`, one shared copy per
  combination (blink phase in four buckets so a queue does not flash in step), so a car is still
  one draw and a street a handful of materials - never instance uniforms (the Compatibility
  global buffer, see Car glass). `Vehicle._tick_lights()` (from `_update_wheels`, which every
  driving path calls) works the state out: the player's brake pedal / handbrake (`brake` > 5)
  and reverse; a traffic car's brake from its speed falling (> 0.8 m/s2) or standing, held
  0.35 s; its indicator from the turn TrafficManager rolled (`t.turn`, and `t.to_c`, the
  distance to that junction, within `Vehicle.TURN_SIGNAL_DISTANCE`), a U-turn signalling left;
  hazards on a car knocked out of traffic with its driver in. Past PhysicsBudget's
  `vehicle_script_radius` a car's own step is off, so `TrafficManager._place()` ticks the lamps
  of the cars it places whose script is off (they froze, blinking or braking for good).
  **A parked car's lamps are off**
  (`lights_running()`: somebody in the cabin, not a wreck); they used to burn like a moving
  car's. Brake, indicator and reversing lamps show by day (`day_glow`), head / tail / beam
  follow `lamp_factor` as before. **Real lights**: `CarLights` (`scripts/vehicles/car_lights.gd`,
  one node under the tree root, made by the first Vehicle; Forward+ only, never the web or
  Compatibility unless `CarLights.force`) keeps a pool of SpotLight3Ds on the nearest running
  traffic cars within `reach` (60 m; `budget` 6 / 3 / 0 / 0 by Quality level), faded by distance
  and on every hand-over, plus the player's car (longer, brighter, shadowed at HIGH) and a small
  red OmniLight3D behind it for the brake / reverse. Positions are set from the cars' global
  transforms each frame, so origin shifts do not touch it; it reads `DayNight.lamp_now` (never
  the global back from the server). **Trap: a spot's `light_projector` is mapped through its
  shadow matrix, which an unshadowed spot never gets - a cookie on an unshadowed spot draws
  NOTHING** (measured on lavapipe Forward+). So only the shadowed player light carries the
  low-beam cookie (`CarLights.low_beam_cookie()`: flat cut-off with the kick up on the right);
  traffic lights are soft plain cones (`spot_softness`), dipped more. Compatibility ignores
  projectors too. Look with `tools/glshot/car_light_shot.gd` (a small street, lavapipe in a
  minute: `VIEW=chase|side|top|rear`, `NOLIGHTS=1` the before, `BRAKE=1`, `REVERSE=1`,
  `PSHADOW=0`, `NOCOOKIE=1`, `AHEAD=1` a car driving away, `OLDMAT=1` the old light_pool
  material on the lamps); in the city `CAR_LIGHTS=1` on `still_shot.gd` forces them onto an
  opengl3 still, and every GEO line there is followed by a `LIGHTS` line (car spots and street
  lamps, on and in view). Checks: `tests/car_lights_checks.gd`.
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
- The boost (`BoostTrail`, `scripts/player/boost_trail.gd`, a child of the player that
  `Player` drives with `drive()` every tick; it replaced a stream of solid cyan spheres): a
  world-space vapour trail on WeaponFX's smoke material that widens and thins behind, a WAKE of
  mist streaming off the body in the player's own space (at 45 m/s the contrail is behind a chase
  camera within a tenth of a second, so the wake is what the camera sees), camera-facing streaks
  of air stretched along their velocity (`shaders/boost_streak.gdshader`, `particle_flag_align_y`,
  warmed on the loading screen), dust ripped off the ground within `dust_reach`, and a vapour
  ring on take-off and again at `boom_share` of top speed; all dimmed by `night_factor`. The
  puff texture's shade averages ~0.65, so the vapour colours sit OVER 1 to read white. Judge it
  with `post_room_shot.gd MODE=boost` (seconds) or `still_shot.gd BOOST=fly` (the city).
- Landings (`LandingFX`, `scripts/player/landing_fx.gd`, static; the player calls `land()` with
  the fall speed it had before `move_and_slide()`): a normal 12 m jump already lands at ~47 m/s
  (fall gravity is 1.6x), so the scale runs from there to `full_speed` (85): dust from
  `dust_speed` (22), a ring of it racing out along the ground and a camera kick that grow, and
  from `slam_speed` (72, a drop of ~30 m) grit, a crater of cracks (a Decal: Forward+ only) and a
  shockwave that knocks the people, props and loose cars within `slam_radius` (a police crime
  like any knock). `post_room_shot.gd MODE=land` (`DROP`, `LAND_AFTER`) shows it.
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
  The fireball's puffs have their own shader (`shaders/fire_puff.gdshader`, via
  `WeaponFX._fire_material()`, desktop only): the billow's density is its temperature, so dense
  lumps burn yellow-white (HDR, blooms) and thin edges cool to red and soot, and the soft-particle
  fade runs over 2.6 m - at 1.2 the road still cut the fireball along a straight line. With every
  part of a puff the same colour, forty of them were one flat orange cloud that read as dust.
  Blast debris is small dark wedges (`_chip_layer` uses a PrismMesh): 18 cm brown cubes read as
  cardboard boxes in a still.
  Blood (owner, 2026-09-24: "I want more blood when people get shot"). Every gun hands its ray
  hit to `WeaponFX.bullet_wound(node, hit, dir, strength, knock)`, which duck-types the victim:
  a pedestrian goes to `Pedestrian.shot()` (down, then the round goes into the `Ragdoll` it
  became, so later pellets of a volley bleed into the body), a body to `Ragdoll.shot()`, a
  torn-off limb to `blood_gush()`. `blood(node, at, dir, strength, victim)` is one wound:
  backspatter out of the entry; the exit spray from `blood_exit_depth` further along the bullet
  (lit, glossy, OPAQUE droplet meshes aligned to their velocity - an unshaded red dot glows at
  night - with no damping, so they fly the same arcs as the trace, and backlit red); a mist that is
  unshaded and darkens itself by `night_factor` (`shaders/blood_mist.gdshader` - lit, the
  camera-facing cards caught no sun and read as grey-brown dust); one ray
  `blood_wall_reach` on for a spatter plus runs that creep down the wall; and `blood_landings`
  drops traced along those arcs to where they land, each laying a splat at the moment it lands
  (the first always straight under the wound). `strength` 1 is a rifle round (`AssaultRifle
  .blood_strength`), limbs are `blood_gib_strength`; the shotgun sums a person's pellets into
  one call (`Shotgun.blood_per_pellet` 0.45 each, capped at `blood_strength_max` 4, so a close
  blast is four rifle rounds' worth). Called per pellet it also works: sprays stack, caps hold.
  A Ragdoll keeps `bleed` (its wounds summed): a pool spreads from under the Hips once it rests
  (`blood_pool`, over `blood_pool_grow`, widened by `feed_pool` when it is shot again), drag
  smears while it slides, a world-space drip from the exit wound, the stumps and each torn limb
  end (`blood_drip`), and limbs mark where they land and skid. The clothes stain round each
  wound through `wound_0..3` / `wound_count` in `character.gdshader`, on a per-ragdoll DUPLICATE
  of the look material (looks are shared by the crowd; set on the shared one and every copy of
  that look bleeds), each wound riding its nearest bone and soaking out over `STAIN_SOAK`.
  Marks are Decals on Forward+ with albedo, normal and ORM generated in code
  (`blood_textures()`: dark coffee-ring rims, a meniscus in the normal that carries the wet
  look, and SATIN roughness, 0.72 thin to 0.5 thick - a splat on the road is always seen at a
  grazing angle, where Fresnel turns anything glossy into a mirror of the sky whatever its F0,
  and at 0.05, 0.2 and 0.3 splats measured brighter than the road and read pale pink; the
  albedo carries its own coverage-keeping mips, `_coverage_mips()`, or a small mark goes
  translucent a few mip levels down) and flat alpha PlaneMesh quads with the same maps on the Compatibility renderer -
  the web build AND the opengl3 screenshot path, so a `still_shot.gd` still shows the quads,
  never the decals. Caps: `blood_splat_max`, `blood_wall_max`, `blood_pool_max`,
  `blood_system_max` (particle systems), `blood_budget` (detailed wounds per 0.7 s); lifetimes
  `blood_*_life`; textures, materials and the decal atlas are warmed on the loading screen
  (`warm_materials()`, `warm_decals()`). Two traps: `get_meta(key, null)` is an error when the
  key is missing (a null default means no default), and a CPUParticles3D under a bone attachment
  inherits the rig's 0.01 scale and shrinks a hundredfold, so drips ride the ragdoll's body.
  Stage it with `still_shot.gd` `FX_SHOOT=N` (`SHOT_YAW`, `FX_PED_WALL`, `FX_SCALE`).
  Screenshot effects with `tools/glshot/fx_shot.gd` (and store stills with
  `tools/glshot/still_shot.gd`): Godot caps a frame at eight physics ticks (0.133 s) however
  long a software frame really takes, so they count the effect's own elapsed time, never the
  wall clock - the wall-clock version stopped every shot in the first milliseconds.
- Weapons: subclass `Weapon` (`scripts/weapons/weapon.gd`), build the model in `_build_model()`,
  call `_make_muzzle()`, implement `_fire(aim)`. Register it in `WeaponManager._ready()`. Effects go
  through `WeaponFX` static functions. `Player.get_aim()` is the crosshair ray (origin, direction,
  point, normal, collider, target). Explosions: `Explosion.blast()`. The arsenal is the AK-47, the
  rocket launcher and a pump **shotgun** (`Shotgun`, slot 3; owner, 2026-09-24: "lose the gravity
  gun, give us a shotgun"): nine pellets in a 4.5-degree cone down the rifle's hit path
  (`fire_pellet()`), people (and bodies already down) thrown and bled by all the pellets that
  hit them at once - one `WeaponFX.bullet_wound()` each at `blood_per_pellet` a pellet, so a
  close blast is a far heavier wound than a rifle round - a heavy flash and camera shake, then the pump strokes back and home
  (`pump_amount()`), a spent shell is thrown out of the port as debris and the left hand rides
  the forend (the script moves `grip_left`). The rifle throws a brass case out of
  `AssaultRifle.EJECT_PORT` every round (`BrassCasings`, `scripts/weapons/brass_casings.gd`: ONE
  MultiMesh for every case in the scene, simulated in GDScript - a gravity arc, one ground ray
  per case, bounces with a synthesised Sfx `casing` tink, rest, shrink away - never ten rigid
  bodies a second; its buffer is written whole on the CPU each frame). `post_room_shot.gd
  MODE=fire` (`AIM=1` over the shoulder) shows it in seconds. Sfx `shotgun` (three real CC0 pump guns) and `pump`.
  **The guns are real models** (owner, 2026-09-24: "What are these horrible assets ... I need it to
  look like RDR2"), built, UV-unwrapped and texture-baked by `tools/make_weapons.py` in Blender:
  `blender -b -t 2 --factory-startup -P tools/make_weapons.py -- [ak47] [rocket_launcher]
  [shotgun] [--nobake]` writes `assets/models/weapon_<name>.glb` (a few minutes a gun; `--nobake`
  is the fast shape loop), then `godot --headless --path . --import` and
  `python3 tools/fix_texture_imports.py` on the new `weapon_*.import` files, and commit the
  `.glb`, the extracted `weapon_*_*.jpg` and every `.import`. Everything is authored in mm from
  real dimensions, every part has a bevel plus weighted normals (the catch-light on the edges is
  most of what reads as real), and each material is a procedural finish baked to 1K
  colour / metal-rough / normal maps through a baked edge and AO mask: parkerised and blued
  steel worn bright on the edges, oiled wood (Poly Haven's CC0 `dark_wood`, fetched into
  `build/weapon_src/` and projected so the grain runs down the gun), chipped olive paint. Node
  names are the contract with the scripts: `Muzzle` in every gun, `Warhead` on the launcher
  (hidden until it has reloaded), `Pump` / `PumpBack` / `Shell` / `EjectPort` on the shotgun.
  Each script keeps its old box model as the fallback when the file is missing. Trap: when
  several objects bake into one image, Blender applies each object's margin over the others'
  islands, so `ISLAND_MARGIN` must stay wider than two `BAKE_MARGIN`s or colours bleed (the
  shotgun's rib came out striped red from the shell). Judge a gun alone with
  `tools/glshot/weapon_shot.gd` (the city's own AgX / sun / fill numbers) and in the hands with
  `hero_shot.gd` (`DEBUG=1` shows the wrist targets); the hold numbers (`grip_*`, `hold_*`)
  are set per gun in its `_init()`.
  GTA-style aim (owner, 2026-09-24): `LockOn` (`scripts/player/lock_on.gd`, a child of the
  player). Holding `alt_fire` (right mouse / left trigger) with a gun whose `lock_on` is true
  (all three) pulls the camera in over the shoulder
  (`CameraRig.set_aiming()`, `aim_shoulder` - without the offset the hero's own head sat on the
  crosshair) and locks the person, else the traffic car, nearest the crosshair in
  `acquire_cone_deg` with line of sight. The camera tracks it (`CameraRig.track()`; mouse and
  stick become a fading nudge, `lock_active`), a flick switches target, `get_aim()` goes at the
  target (led for the rocket), and a downed target is replaced after `reacquire_delay`. The
  crosshair turns red with brackets on the target. The crosshair ray now starts at
  `CameraRig.aim_origin()` (the shoulder while aiming), which the camera's centre ray passes
  through. `look_blocked` on the rig stops the view turning (the weapon wheel sets it).
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
  one-shot order and share the block's rng, so **the order is load-bearing** (the far city runs
  the very same LOD steps in capture mode, `CityChunk.capturing`, and must get the same rolls);
  and a big job with its own rng (grass) goes through
  `_run_or_defer()`, which re-queues it before the finish step as a step that returns false
  until it is done. Small repeated props go through
  `MultiMeshBatch` with meshes from `PropFactory`. Breakable props are registered with
  `CityChunk._add_prop()` (instances + shapes + health); their shapes live on the chunk's
  `StreetProps` body, which routes `take_hit()` to the chunk. Physics props (trash cans) are
  `TrashCan` RigidBody3D nodes in the `physics_prop` group. Street furniture and markings live in
  `StreetDetail` (`scripts/world/street_detail.gd`, static, seeded per block and intersection);
  street names come from `CityPlan.road_name()`. The pavement clutter is `StreetClutter`
  (`scripts/world/street_clutter.gd`, called last from `StreetDetail.build_block()`): coin-op
  news boxes and free-magazine racks in rows near a corner, chalkboard A-frames on shop blocks,
  litter and dead leaves in the gutters - meshes built in code at real size on one shader
  (`shaders/street_clutter.gdshader`: paint from INSTANCE_CUSTOM, printed front pages, covers and
  chalk from the vertex alpha), one draw per kind a chunk. StreetDetail still makes the news
  boxes' old rng rolls and hands them over; everything else is hash-seeded.
  **Street wear** (`StreetWear`, `scripts/world/street_wear.gd`, a build step of every FULL
  chunk after everything it lies on): spray tags, throw-ups and roller letters with buff-out
  patches over some, wheat-paste runs and flyers, stickers on lamp / signal / utility poles and
  signal cabinets, freeway columns, grime along the foot of every street wall and gum and stains
  in patches on the pavement - ONE shadowless transparent batch (`wear`) a chunk on
  `shaders/street_wear.gdshader`, faded out by `DRAW_DISTANCE` (120 m). The art is original,
  drawn by `tools/make_street_wear.py` into two atlases (`assets/textures/street_wear/`: abstract
  letter scribbles, invented gigs and lost-pet bills, invented stickers); grime and gum are
  procedural. Walls are read off the chunk's Building parts and the window / door / sign-band
  layout is worked out as `building.gdshader` draws it (`_paintable()`), so posters never land
  on glass; tags may run over `TAG_SLACK` of glass and frame. **Measure heights from the
  pavement, never the building base** (`floor_of` in `_wall_run()`): on a slope a building's base
  is up to a metre under the pavement, and the first version buried every low tag and all the
  grime. Every roll is a hash of seed + block / face / prop, never the chunk rng. Nothing within
  `WORSHIP_MARGIN` of a place of worship (`WORSHIP_IDS`). Web: no grime or pavement patches, no
  screen read, half the cap (`full_detail`). Densities per district are the consts at the top.
  `STREET_WEAR=0` in the environment turns it off (the A/B); `SHOTS=` on `still_shot.gd` takes
  several EYE views and hours from one load. Checks: `tests/street_wear_checks.gd`.
  **Ground nobody builds on is never left as bare paving** (from the air it read as empty tan
  squares): a freeway corridor lot (`_under_freeway` / `_lot_under_freeway`) is the right of way,
  filled out to its cell by YardFill (below; `_build_corridor_lot` hands it over and keeps the old
  ivy-and-shrubs only for `YardFill.enabled` false), a PLAZA block raised beds, tree rows
  and benches round its fountain (`_furnish_plaza`), and the strip under the airport's final
  approach (`MacroMap.runway_clear_zone()`, where `CityPlan.lots()` drops every lot) is long-term
  parking (`_build_approach_parking`: stall rows, ArenaGrounds' cheap static cars, half as many
  on LOD chunks). All three use a private rng after the block rng's own rolls, so nothing else in
  the chunk moves; never add rolls on the block rng for new filler.
  **Nor is a downtown or midtown lot** (`LotFill`, `scripts/world/lot_fill.gd`, 2026-09-27):
  towers stood alone on their lots and 44 % of the financial core's buildable ground (31 % of
  the rest of downtown, 54 % of midtown) was the block's bare paving (`tools/lot_coverage.gd`
  measures it; `FILL=0` is the before). Now a slender tower on a big lot stands on a **podium**
  (`Building._add_podium()`, see the Buildings note); what a building leaves of its lot, out to
  the lot's grid cell (`lot.cell`, the lot plus half the gap), is a **forecourt** in the block's
  own paving look (`LotFill.PAVINGS`, one a block) - raised planters (the plinths' concrete, so
  they merge into that mesh) with one shrub species a chunk and the block's street tree
  (`MAX_TREES` a chunk), benches, a short run of bollards (`BOLLARD_ODDS`, `BOLLARD_RUN`), and
  in a plaza-sized piece (`PLAZA_DEPTH`) a reflecting pool or a bronze on a cross of walks with a
  lawn in each quarter (`LAWN_ODDS`, its own ground kind, laid far too); a retail podium's roof
  is the tower's garden (lawns, planters, a turquoise pool); some lots are **surface car parks**
  (`CityPlan.lots()` `"parking"`: DISTRICTS `surface_lots` / `core_surface_lots`, a hash, only
  under `SURFACE_LOT_MAX_HEIGHT`; stall rows, ArenaGrounds' static cars (`car_mesh()`, ~400
  triangles, two kinds, a two-box shadow twin to `CAR_SHADOW_DISTANCE`), a pay booth, light
  poles in the street lamps' batch without their OmniLight, a wall / hedge / chain-link
  (`shaders/chain_link.gdshader`) on the street sides); a
  parking podium gets its drive-in (asphalt out to the kerb) and cars and light poles on its roof
  deck; and the cells a landmark's square dropped (`CityPlan.dropped_cells()`) are forecourt
  round the landmark (a downtown tower's own footprint kept 4 m clear) or a car park. Every
  roll is a private rng of seed + lot, never the block rng or `Building._rng`. A FULL chunk's
  pavings, asphalt, lawns, planted tops, pools and polished stone are ONE mesh on ONE material
  (`LotFill.commit()`, `shaders/lot_ground.gdshader`, the kind in the vertex colour; no shadow,
  one quad a rect where the relief is planar, appended unindexed); LOD chunks and the far city lay only the car parks' asphalt and the lawns
  (the forecourt paving reads as pavement from there) and the podium boxes come with the parts.
  AirTraffic skips car-park lots. Look at it with `tools/glshot/still_shot.gd` (`SPLIT=1` has a
  LotFill line) and measure it with `tools/lot_coverage.gd`.
  **Nor are the yards outside them** (`YardFill`, `scripts/world/yard_fill.gd`, 2026-10-04; beach
  town 56 % bare -> 4 %, campus 74 % -> 1 %, the right of way's cells 23 % -> 0, docs/HANDOFF.md 9az). A BEACHTOWN lot's cell less its
  house is a yard planned in the lot's street frame (u along the street, v back from it): a
  driveway to the kerb (`DRIVE_*`, a static car in some), a front walk, a front garden (lawn,
  decomposed granite with gazania, brick or saltillo; a mulch bed of shrubs along the house), a
  low stucco wall / white pickets / clipped hedge on the street line, timber or stucco fences down
  the lot lines from the house front back (built by the lot on the -x / -z side of a shared line,
  so once), a back yard (lawn, deck, tile, concrete; a pool now and then), an L's inner corner a
  tiled courtyard with a fountain; a **walk street** (`WALK_*`) cuts some blocks along x between
  two rows of houses that front it; the cells a landmark's square dropped are beach car parks
  (LotFill's) or pocket parks (`beach_dropped()`, trimmed off the sand and the boardwalk's shops).
  A CAMPUS block's free ground (the campus hall's square drops most lots; `Landmarks.campus_footprint()`)
  is quads (diagonal walks as ribbons, a cross walk, trees along them, lamps, benches), one car
  park a block (`CAMPUS_PARK_MAX`), service yards (block-wall bays, dumpsters, a transformer), and
  every building gets an entry walk to the pavement with an apron and shrubs by the door. The
  freeway's **right of way** in every district is its corridor lots' cells: ivy, fading to bare
  dirt in the deck's shade (per vertex, `BARE_FADE`), oleander hedge rows and a tree row parallel
  to the deck, a split-face sound wall (`SOUND_WALL`, creeping fig up its foot) where it meets a
  house lot in `SOUND_DISTRICTS`, chain-link elsewhere and on the street, and in some blocks a
  maintenance yard (gravel, k-rail, a container, a crew truck). **Plans are pure** (`beach_block()`,
  `campus_block()`, `corridor_block()`: the plan, the block, each lot's ground footprint), which
  is how `GroundCoverage` (`scripts/world/ground_coverage.gd`, behind `tools/lot_coverage.gd`:
  `FILL=0|lot|1`) and the smoke test ask the chunk's own question; the chunk records its lots'
  footprints (`record_lot()`) and runs `block_step()` after the lots, laying the ground at once
  (the lawn's grass keeps off it through `_lot_rects`) and the walls, planting and props as
  time-sliced steps before the finish (`_defer()`, so the block's own props keep their ids).
  Every roll is a hash of seed + lot / block, never the chunk rng. A FULL chunk's yard ground is
  ONE mesh (`YardGround`, `shaders/lot_yard.gdshader`, kind in COLOR.r, a variant in COLOR.g, no
  shadow) and everything upright ONE casting mesh (`YardWalls`, `shaders/lot_walls.gdshader`,
  kind in COLOR.a, paint in COLOR.rgb as written, UV in face metres, UV2.x the height); pickets
  and chain-link are cut out by the shader. Both shaders include `color_space.gdshaderinc` and do
  their arithmetic in display numbers (`disp()` takes Forward+'s decoded textures and tints back,
  `to_lit()` hands the result over), so the Mac draws the albedo the opengl3 stills show. Two shaders, not more kinds in
  `lot_ground`: one shader sampling both texture sets passes what the Compatibility renderer
  leaves a material. Planting goes in batches a chunk already has, under per-chunk budgets
  (`MAX_SHRUBS` / `SHRUB_TRIS` - one shrub species a chunk, LotFill's pick where it runs too and
  else one of the cheap two, `CHEAP_BUSHES` -, `MAX_TREES` of the block's street tree,
  `MAX_PALMS` of one variant, `FLOWER_TRIS` of one flower). LOD chunks and the far city get the
  lawns and the ivy as slabs, nothing else. A PLAZA rolled across the street from a landmark's
  site is buildings (`CityPlan.block()` `"was_plaza"`: the empty square south of MacArthur Park).
  `YARD_FILL=0` on `still_shot.gd` and `tools/glshot/block_shot.tscn` (a few FULL blocks alone,
  a minute or two a shot) is the A/B; it does not undo the beach town's lower heights
  (DISTRICTS) or the plaza. Checks: `tests/lot_fill_checks.gd`.
  Shopping plazas, big-box stores, fast-food and gas-station pads are `Commercial`
  (`scripts/world/commercial.gd`); block kinds `MALL` and `BIGBOX` and the `pads` odds live in
  `CityPlan.DISTRICTS`. Shop names are original, never brands.
- Port (roadmap #35, 2026-09-27): the container terminal (`MacroMap.port_rect`) is
  `CityChunk._build_port()` laying out `PortKit` (`scripts/world/port_kit.gd`), all built in code.
  **The old port's rolls stay** on the block rng in the old order (rows, columns, the 30 % truck
  lanes, the 35 % empty slots, stack heights, one colour roll a box, which now picks the box's
  shipping line); everything new - the second pile abreast (`PORT_ROW_OFFSET`, leaving 3.9 m
  aisles), 20 ft pairs, high-cubes, door facing, liveries, wear, gantries, crane poses - comes from
  a private `hash([seed, ix, iz, "port_kit"])` stream, and the far city replays it in capture
  mode. **A container is ONE mesh** (`PropFactory.container()`) with a hand-built ladder (568 /
  142 / 12 triangles: castings, rails, posts, recessed panels, doors with bars, keepers, handles
  and hinges; then frame and panels; then a box) and a box shadow twin pulled in behind its
  panels (a proxy face in front of a lit face shadows it). **20 ft and high-cube boxes are the
  same mesh scaled** (`PortKit.container_xform()`): `shaders/container.gdshader` moves every
  vertex within 1.3 m of an end back to its distance from that end, so castings and doors keep
  their size while the MultiMesh bounds, the far city's box and the collision see the true size;
  never scale an instance in z. The shader draws the ISO corrugation (a normal tilt with a short
  parallax march - the mesh has no tangents), the liveries (instance COLOR is the paint from
  `PortKit.LIVERY_PAINT`, INSTANCE_CUSTOM is livery / 16, wear, seed, 1; ink, names, marks and
  owner codes are in `shaders/port_lettering.gdshaderinc` under the same index, a stroke font
  shared with the ship's hull; every line is invented), ID codes, rust streaks, repaint patches,
  dirt and dents. **Cranes**: two ship-to-shore cranes a quay chunk (`PortKit.sts_mesh()`, one
  merged mesh per pose, 3.8k / 1.7k / 0.7k triangles, `shaders/port_steel.gdshader`: vertex
  colour plus a finish in UV2.x), boom down with the trolley over the moored ship within 95 m of
  it, raised elsewhere; built at FULL and LOD, and as boxes in the far city (`sts_far_boxes()`
  into `captured.boxes`). Yard gantries (`PropFactory.rtg()`) straddle three rows with their legs
  in the aisles; `PORT_APRON` of the quay chunks stays clear for the rails, coping, bollards,
  fenders and lanes. After dark the masts and cranes throw additive light pools on the yard
  (`port_pool`, `light_pool()` with a soft falloff) at FULL and LOD. The port block is three
  build steps, and every piece is lifted by the slab's single relief lift (`_port_lift`) - the
  paint alone sampled the relief ~2,000 times; `PortKit.warm()` builds the kit's meshes on the
  loading screen (a crane pose is ~20 ms of GDScript). The ship (`cargo_ship`, now 7 m off the quay, not on it) is
  `PortKit.ship_mesh()`. Look at a change in seconds with `tools/glshot/port_shot.gd` (the kit
  alone; `SHIP=1`, `RAISED=1`, `LOD=n`, `WEAR`).
- Map: `MacroMap` (`scripts/world/macro_map.gd`) decides zone (city, beach, ocean, hills, airport,
  port), land height and district for any world XZ. The city itself rolls: `relief_at()` is the
  gentle height field under the blocks (zero on beaches, flat zones, mountain hills and around
  landmarks) and `height_at()` includes it. In a chunk, sample it only through `_gy()`: the
  multimesh batch adds it to every instance, `_add_slab()` builds relief-following grids for thin
  city ground, `_add_prop()` lifts shapes; nodes you add yourself (bodies, buildings) need
  `+ _gy(x, z)` explicitly. Never add it twice. The hill steps are the other way round: they
  place at `height_at()`, which already includes the relief (the valley plateau and the rolling
  ground up the lower slopes), so they run with the batch's lift off (`_on_map_ground()`);
  with it on, 700 of 1,597 hill chunks floated their rocks and planting up to 144 m in the air
  (`tools/float_probe/hill_float_probe.tscn` measures every hill chunk in a `REGION`). `CityPlan.macro` holds it; `zone_at()` / `height_at()` on
  the plan go through it. `height_at()` is the terrain with hill roads and mansion pads carved in
  (`raw_height_at()` is the noise alone); `MacroMap.hill_roads` (`HillRoads`, seeded polylines
  with grade-limited height profiles, `carve()`, `segments_in()`, `mansions_in()`) is what hill
  chunks build asphalt strips and estates from. `carve()` grades the ground off a road or pad on
  **banks** (`CUT_BANK` 1:1, `FILL_BANK` 1:1.5, out to `BANK_REACH`): with only the old 14 m
  shoulder every deep cut was a sheer wall. A road the mountains are too steep for is not built:
  canyon roads and estate lanes are kept only as far as `_earthwork_ok()` passes (bed within
  `MAX_EARTHWORK` of the ground, banks met by `DAYLIGHT_AT`) and re-profiled over what is kept,
  a branch starts at its parent's bed height, a pad must pass `_pad_ok()`, and the boulevard is
  slid downhill off the range where it cannot be graded in. The front range is steeper than 45
  degrees almost everywhere, so of its canyon roads only the one up the pass survives (with its
  estates) and the rest are stubs; a branch ramps at up to `JUNCTION_GRADE` for its first
  `JUNCTION_RUN` metres to meet its parent. The walks, branch points and mansion rolls are
  still made, so the rng stream (and the headland's estates after it) does not move.
  **The front range's drives and estates are switchbacks** (roadmap #20, 2026-10-04): after
  everything above (own rngs, so nothing above moves), `_add_switchbacks()` grows a network of
  contour-following drives off the kept roads and off each other (`_walk_switchback()`: legs
  across the slope climbing `SB_GRADE` 8.5 %, hairpins of `HAIRPIN_RADIUS` 13 m turned uphill
  only on a slope, a slow wander on flat ground, the bed benched `SB_BENCH` into the hillside,
  every step asked `_sb_daylight()` before it is taken, the whole drive trimmed by
  `_earthwork_ok()` like any road), plus `Valley Vista Dr` along the inland foot
  (`_add_north_foot_drive()`, kept in the runs its banks pass). Beds, including pads, keep
  `BANK_SEPARATION` (1.5 m per metre of height between them) apart rim to rim, or carve() is left
  two banks that cannot both hold - a step. Estates line them (`_place_estates()` /
  `_try_estate()`): a pad of `ESTATE_RADII` (17 m, or a 13 m compact one) beside the road or up a
  4-26 m driveway at up to `DRIVE_GRADE`; a long driveway is a road of its own (`"drive": true`,
  carved, not drawn as asphalt), and a mansion records `drive_from` / `drive_h` / `radius`
  (`carve()` and `_pad_ok()` read the radius). The ground is read off a 12 m lattice while they
  are laid out (`GCACHE_STEP`, `_ground_cached2()`): a walk asks for the same hectares hundreds of
  times. Drives and estates stay where the mountains stand `SB_MIN_RAW` over the plain, so their
  chunk is a hill chunk (a chunk's zone is its block centre's). The south face toward the city
  stays bare: it is steeper than 45 degrees almost everywhere, where neither bank ever meets the
  ground. `tools/hill_road_probe/hill_road_probe.tscn` counts roads, hairpins and estates, the
  carved cells steeper than 60 degrees (`STEEP`) and the pieces that fall outside hill chunks, and
  draws a slope map with the roads (`OUT=`; `SB_DEBUG=1` adds every walk tried); seconds, headless.
  Estates are built by `CityChunk._build_mansions()`: pad, walls, gate piers, gate, pool and
  coping are oriented boxes merged into the chunk's boxes (`_merge_box_xf()`), the driveways one
  strip a chunk, and each side's wall is what the ground beyond it makes it (garden wall, a
  retaining wall holding the cut, or one dropping down the fill). Hill road strips are mitred at
  their joints (`HillRoads._mitre()`, `na` / `nb` in `segments_in()`) and each edge vertex sits on
  the carved ground, so hairpins have no wedge gaps and forks no steps. Chunks
  build water, sand or terrain for non-city
  zones; the water surface is at y 0.15 (above the ground follower plane). To start
  somewhere else for testing: web `?spawn=x,z,yaw,pitch[,y]`, desktop `-- --spawn=x,z,yaw,pitch[,y]`.
  Mountains (owner, 2026-09-21: "LA is covered by mountains, Palos Verdes, the valley"): the basin
  is ringed. `raw_height_at()` is mountains only - a front range north of the city that fades out
  on its inland side, a higher back range behind the valley, an east range, and the peninsula
  headland south-west - composed with `max()` so ranges meet in ridges rather than adding into a
  dome. The knobs are the `*_start_z` / `*_full_z` / `*_height` exports at the top of `MacroMap`.
  **The ranges are eroded** (owner, 2026-09-25: "the hills look like garbage, not real
  mountains"): each is a SMOOTH base (`_range_heights_at()`, `_range_noise`: the map noise's first two
  octaves only, so the summits stay where the sign, the observatory and the hill roads were laid
  out round them - a fresh noise put the sign behind a crest) with erosion noise cut into it (`_erode()` / `_erosion_filter()`, after
  Fewes): stripes that run DOWN each slope over a jittered grid of cells, the slope taken from
  the base (over `EROSION_SLOPE_STEP` either side, so they follow the landforms, not every bump)
  plus the walls of the coarser orders, so every order branches off the one above - canyons
  `erosion_spacing` apart and their tributaries, `erosion_depth` / `back_erosion_depth` of the
  range deep, and NONE where the ground has no downhill (the base's summits and saddles, or a spot
  where a coarser order's wall cancels the slope): the stripes' direction spins round such a
  point, and with the old 45 % floor every summit was a star of pinched wedges (`smoothstep(0.02,
  0.32, |slope|)` on the amplitude, `smoothstep(0.02, 0.2, |d|)` per order, the same in
  `erosion.gdshaderinc`). The old bases used the map's own noise plus a
  second octave at 2.7 times the frequency and read as fields of cones; the first erosion pass
  stretched a ridged noise along the slope and read as combed streaks. `last_drain` (-1 spur
  crest .. +1 gully floor) is what the erosion leaves for the ground: the hill tiles' vertex
  colour, `bake_height`'s G channel for the far ground, HillPlanting. Only `erosion_octaves` (3:
  440, 220 and 110 m) orders are in the height; `shaders/erosion.gdshaderinc` draws two finer
  ones (55 and 27 m) as shading on the near terrain and the far ground. A height in the hills costs 20-40 us on the build box,
  so a hill tile samples its heights a few rows a build step (`CityChunk._sample_terrain()`),
  the planting reads the drainage off the tile and Skyline off its lattice, never
  `drainage_at()` again. Look at a change in seconds, before any render, with
  `tools/terrain_preview/terrain_preview.tscn` (a top-down hillshade with the drainage tinted;
  `BENCH=1` times the setup, the bake and a hill tile; `PROBE=x,z;...` prints heights and
  zones; it prints the hill roads and estates planned).
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
  and off-ramps down to the surface streets. `CityChunk._build_freeway()` builds it with
  `FreewayKit` (see the Freeway kit note) in four meshes per chunk (asphalt top, structure, paint
  and sign faces, night light pools) plus a `FreewayBody`
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
  **Winding trap:** the old `CityChunk._ribbon()`'s plain vertex order made a *horizontal* quad
  face DOWN, so the lane paint was once back-facing and culled - a deck with no markings at all,
  which looks exactly like a missing mesh or a z-fight. `FreewayKit.tri()` / `quad()` now take
  the direction each face must face and fix the winding and the normal themselves (LandmarkGeo's
  rule); never add freeway geometry any other way. The deck top keeps its own order
  (`l0, r1, r0`).
  **The freeway kit** (VISUAL_ROADMAP #43, 2026-10-04, `scripts/world/freeway_kit.gd`): per deck
  segment, a box girder (fascia, cantilever soffit, inclined web, bottom slab), New Jersey
  barriers at both edges and down the median, and on whole-STEP spacings: bents (`PILLAR_SPACING`:
  two 1.6 m columns square to the route with flared heads, the bent cap, five bearing pads, a
  downpipe, two under-deck lights with a pool on the street below), median light standards
  (`LIGHT_EVERY` segments: a tapered pole, twin arms, cobra heads with a glowing drop lens, a pool
  on each carriageway - sodium amber or LED white per route), sign gantries (`GANTRY_SPACING`:
  laced box truss on two laced posts, a catwalk and sign lights, and per carriageway a guide sign
  - shield, direction, destinations, a down arrow per lane - and an exit sign where an off-ramp
  is within 1.5 km on that side: street, distance or EXIT ONLY, the exit tab), expansion joints
  (`JOINT_EVERY_BENTS`), scupper grates every `SCUPPER_SPACING`, the carpool diamond
  (`DIAMOND_EVERY`), and at FULL only call boxes, CCTV poles, postmile paddles and tyre debris
  on the shoulders. **Lanes are `Freeway.lane_layout(width)`**: four each way (`LANES`), lane 0
  by the median the carpool lane behind a double yellow, yellow left edge line with yellow
  markers, Botts' dots (4 dots and a marker every `BOTTS_CYCLE`) on the next line, a dashed
  stripe with a marker in each gap on the last, white right edge line; `TrafficManager` drives
  `Freeway.lane_fraction()` - keep the two together. What a vertex is rides in its colour's
  alpha (`kind / KIND_SCALE`, `S_*` on `shaders/freeway_structure.gdshader`, `P_*` on
  `shaders/freeway_paint.gdshader`), its colour sRGB in the rgb (both shaders decode it and work
  in linear, `color_space.gdshaderinc`). Structure UV is (metres along the route, metres up the
  feature), which is what puts the barrier joints, the tyre scuffs, the drip streaks, the rust
  under each scupper (the same `SCUPPER_SPACING` phase as the grates) and the column streaks
  where they belong. **Retroreflection** (markers, paint beads, sign sheeting) is lit by
  `lamp_factor` in a cone ahead of the CAMERA (`glint_reach`, `glint_cone`): the headlights are
  taken to be at the camera, so a free camera at night glints too; markers the cone reaches
  never draw under about a pixel. Sign faces are also washed by their sign lights at night
  (`sign_light`). Signs: route numbers are this game's own (`ROUTE_NUMBERS`, never the real
  route's), destinations invented (`DESTINATIONS`, "Downtown" when the carriageway heads for it),
  street names the plan's (`sign_case()`); lettering is TextMesh geometry merged into the paint
  mesh (`text_geo()`, cached per string, coarse curves - it is most of a gantry's triangles), FULL
  only; an LOD chunk keeps the deck, barriers, bents, blank boards, lights and pools and plain
  dashed lines (`tests/freeway_kit_checks.gd` holds both to a triangle budget per segment). Off-
  ramps use `FreewayKit.ramp_piece()` (slab, barriers, edge lines). Hashes only (seed, route,
  segment), no rng. StreetWear's column tags read the same column frame (`_pillars()`). Stills:
  the 110 by downtown, `EYE=1989,12.0,160,-6,-3` (north), the gantry at (1986.7, 55.6)
  `1990,12.5,82,-6,10@13@40` (guide signs) and `1980.5,12.1,27,174,10@13@45` (exit sign), under
  it on 5th St `2045,1.7,2,60,10` - `--hour=22` for the lights (HANDOFF 9ba).
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
  is 320 (44 m a vertex; at 200 the ridges three kilometres out were straight facets and the
  peaks cones) so there are vertices to displace, and `CityStreamer` snaps the plane's position to that
  vertex grid **in world space** - without the snap the peaks swim as the follower slides.
  That grid is `CityStreamer.ground_step()`, `ground_size / (GROUND_SUBDIVISIONS + 1)`: a
  PlaneMesh with N subdivisions has N + 1 quads, and snapping by `/ N` slid every vertex 35 cm
  per step. The plane's height code (bake sample, crags, sink) lives in
  `shaders/macro_relief.gdshaderinc` so anything that must stand on the far ground computes
  the same surface: `shaders/far_canopy.gdshader` (Skyline's hill planting) seats each clump on
  it, interpolating across the plane's own 44 m triangles; the far hill houses ride in the same
  MultiMesh, and the far ridge sign uses its `rigid` mode (one shift for the whole name, from
  `Landmarks.sign_line()`, so it stays level). Placed at `MacroMap.height_at()`
  instead, the clumps hung in the sky above every ridge - the bake averages a ridge down and the
  crags move it tens of metres, so the real height is not the height that is drawn.
  The bake's height is read as a **cubic B-spline** (`macro_sample()`, 16 texel fetches with
  its analytic derivative), never smoothstep-weighted bilinear: those weights have a ZERO
  derivative at every texel centre, so the normal went flat once every 31 m and every range was
  drawn as a staircase of terraces - from the basin, zig-zag contour lines across the
  mountains. The colour stays hardware bilinear, and its alpha is only the water test.
  `built_amount()` stays in `macro_ground.gdshader`: the smoke test reads its thresholds from it.
  Before this the plane was 4 km of flat green and its own edge was the horizon.
  **Where it meets the streamed hill tiles** the plane is lit by the renderer (ALBEDO) out to
  `paint_start` (900 m) and painted by hand (EMISSION, its own sun, sky and ridge-shadow march)
  past `paint_end`; in the lit band it has to BE a tile. So there it takes the tiles' SPECULAR
  0.5 and roughness 0.93 - at 0.15 Godot reads the F0 as occluded and drops the grazing sky
  reflection, and with the same albedo and normal the plane lit at two thirds of the tiles (found
  by emitting albedo, normals, coverage and a flat grey on both in a debug render) - draws the
  tiles' own stands, and takes the ridge shadows it marches off its direct share (`shade`), since
  the renderer's shadow maps stop at 500 m. **The plane paints the tiles' own field**: it
  includes `shaders/hill_splat.gdshaderinc` - the stand rule, `hill_rocky()` / `hill_bare()`
  and the colours (`straw_color`, `chaparral_color`, `dirt_color`, `rock_color`, `snow_color`,
  `drain_shade`, `macro_variation` all live there) - with every octave a far pixel cannot
  resolve at its mean and the stand edge widened by what it spread, and the tiles' far average
  of straw and brush (`FAR_CHAP_TONE`, `FAR_BARE_SHARE`); off the bake's smooth slope in the lit
  band, the full crag normal in the painted one (which is what mottles a range kilometres out).
  There are no copies left to keep equal (`tests/hill_air_checks.gd` fails on one). The bush
  speckle, gully streaks and craggy-face rock (`far_rock_slope_*`) are painted-band only.
  `paint_gain` scales the painted band's albedo to the lit band's brightness (`paint_debug`
  forces the whole plane one way; `hill_ground_shot.gd PAINT_AB=1` measures it).
  **The plane and its collision are separate nodes** (`Ground`, drawn, slides with the player;
  `GroundBody`, a 14 km box, moved only when the player is `GROUND_BODY_REACH` of it from its
  centre). Moving a static body makes Godot Physics wake every body touching it - on any
  transform set, even to the same value - and that box touches every parked car, trash can and
  prop in the city. When it was the sliding plane, re-placed eight times a second, nothing in
  the city could stay asleep. Never move a big static body per frame.
- The distance (owner, 2026-09-24: "certain areas of the map aren't loading properly at a
  distance ... do whatever GTA does"): four tiers ALWAYS cover the visible world, the way GTA V
  and RDR2 do it - FULL chunks (two blocks round the led focus, one round the player), LOD
  chunks (seven blocks), the **far city** (`Skyline`, `scripts/world/skyline.gd`, the super-LOD:
  every block within `CityStreamer.far_city_radius`, 7 km, which is the whole basin) and the
  horizon plane with the mountains. The handoff is **per block, never by distance**:
  `CityStreamer._install_chunk()` calls `Skyline.cover(block, level)`, which dissolves the far
  city out there (each block's instances carry their visibility in the colour alpha, dithered by
  `building_lod.gdshader` / `far_canopy.gdshader` and collapsed at 0), and a chunk leaving the
  window is **retired** (`_retire_chunk()`: `Skyline.uncover()`, `CityChunk.retire()` drops its
  cars, people and collision at once, the node stays drawn for `lod_fade_time` while the far
  city dissolves back in over it, then goes). So no ring is drawn by nobody and no block by two.
  The far city IS the LOD chunk's city: `CityChunk.capturing` runs the LOD block build (same
  steps, same rng) and records slabs and boxes into `captured` instead of building them, and
  Skyline takes the `lod_box` batch as it is - anything added to the block build shows in the
  far city with no far-city code - less the roof plant under a pixel out there (the coded far
  buildings, `FarBuilding`, in the far-buildings note below). Around it: one plate per block over `CityPlan.owned_rect()`
  (`INSTANCE_CUSTOM.a` 2, roads painted by the shader from the widths in .r/.g, linear colours
  from `CityChunk.far_tint()`, the numbers the LOD chunks' ground uses; outside the city, where
  a chunk draws its ground as a box in a `road()` material, `PropFactory.far_albedo()` - the
  set's measured `TEXTURE_MEAN` times the tint - and the airport's runways cut its plates into
  strips rather than lying on them, because two plates 10 cm apart z-fight at a kilometre on
  the web's depth buffer), freeway decks and
  pillars from `Freeway.segments_in()` (deck mode, .a 3), the port's containers, and canopies
  (`PropFactory.canopy_blob()`) for street and park trees and hill scrub, which stay under a LOD
  chunk (it plants none) standing on the real ground (`INSTANCE_CUSTOM.r` 1) and go under a
  FULL one; the HillRoads estates in their own MultiMesh. Built a capture STEP at a time (one
  LOD build step of one block, so no block costs a frame more than a chunk step does) in
  `stream_priority_at()` order inside `far_city_budget_ms`, `far_city_immediate_radius` at once
  on `update_streaming(true)`, the whole radius on the loading screen (`finish_far_city()`,
  which `--nohud` / `--noload` runs too, so screenshots show what the player sees). The plane's
  rim and the far city's last kilometre fade to the sky's horizon colour together
  (`CityStreamer.GROUND_EDGE_FADE`, `edge_start` / `edge_end` in the three shaders).
  Chunks build in `stream_priority()` order: distance to the player or the led focus, weighted
  against the camera's heading by `view_priority`. The camera draws to 12 km (`player.tscn`
  `far`; it was 2 km, which clipped two thirds of the basin), `aircraft_lights.gdshader`
  `max_depth` stays just inside it, and the horizon plane no longer lifts itself over the far
  city (`urban_lift` 0: it buried every suburb past 2.6 km). Rules: never give a far-city node a
  visibility range; never free a chunk except through `_retire_chunk()`; anything a far block
  draws must hide under its chunk. Checks: `tests/distance_checks.gd`. Look with
  `tools/glshot/lod_pano.gd` (a 360 panorama; `TIERS=1` paints each tier a flat colour), measure
  with `tools/flight_bench.gd` (frame times on a scripted 90 m/s flight; `CENSUS=1` counts the
  blocks ahead nobody draws).
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
  **The hills are planted where the ground is painted.** `HillPlanting`
  (`scripts/world/hill_planting.gd`, static) is `terrain.gdshader`'s splat worked out on the
  CPU - the same hash, noise octaves, offsets and thresholds (`HillPlanting.MIRRORED`, which the
  smoke test checks against the shader source; change one, change both) - so `ground(w, grad)`
  says whether a point is a chaparral stand, bare dirt or rock and which way it faces, and
  `hollow()` finds gullies and slope feet. FULL hill chunks run `_plant_hills` (after
  `_scatter_hills`; a jittered `hill_brush_spacing` grid, a private rng per grid row, a few rows a
  build step, heights off the chunk's own terrain grid): budgeted searsia
  (`PropFactory.model_chaparral()`, `CHAPARRAL_BUDGET`) wide and low on every stand point,
  a budgeted city broadleaf (`tree_a`) as the oaks in the hollows (`model_hill_oak()`), a rare
  lone shrub on open grass, nothing on rock, cuts or trails. Their tints are OVER 1 (1.4-2.2):
  both leaf atlases are mostly black background, which the mip chain averages into the leaves,
  so tinted below 1 a stand drew black from twenty metres. The far tier
  (`Skyline._add_hills`) asks the same field on a 30 m height lattice and plants ONLY the oaks
  and sycamores in the hollows. It also drew a low chaparral mound on every stand until
  2026-10-04: from the air each was a 6 x 3 pixel blob, lit by the renderer against a far ground
  that paints its own light, and the ranges were covered in dark dashes. The brush out there is
  the ground's (the LOD tiles' and the horizon plane's stands, the same field).
  **The near hill ground grows out of the paint (hill shells).** The splat's maths lives in
  `shaders/hill_splat.gdshaderinc` (uniforms, noise, `hill_stand_threshold()`, `hill_brush()`,
  `hill_bare()`, `hill_rocky()`, `hill_crowns()`), included by `terrain.gdshader` AND by
  `shaders/hill_shells.gdshader`; the smoke test reads the include for `HillPlanting.MIRRORED` /
  `MIRRORED_CONSTS`. Every FULL hill chunk draws its terrain mesh again as `HillShells.LAYERS`
  (16) thin lifted layers (`HillShells`, `scripts/world/hill_shells.gd`): a MultiMesh of that
  one mesh with identity instances whose `INSTANCE_CUSTOM.r` is the layer's height, so it costs
  one draw, no memory and ~0.3 ms to build (`CityChunk._build_hill_shells`). The vertex shader
  lifts each layer (grass span 0.55 m, the brush understory 0.42 m where a stand is likely), the
  fragment shader keeps a fragment only where a blade (a 2 x 5 cm cell in the frame of a slow
  lean field, tapering, bent over with height and swayed by the wind, a thatch mat at the
  roots) or the brush understory (the painted shrub crowns grown into low mounds of 3 cm leaves;
  the lone sage dots into paler round bushes) reaches that high, and nothing on rock, cuts,
  trails, roads, pads or landmarks: `_mark_shell_ground` (a build step before the mesh)
  writes a signed keep-out distance into the terrain's COLOR.b (0.5 at the edge; the terrain
  shader ignores it). Layers are stored bit-reversed so any power-of-two prefix is spread evenly
  up the canopy, and `visible_instance_count` is the LOD (`HillShells.LAYER_REACH`: 16 within
  40 m of the tile, 8 to 65, 4 to 90, none past; the shader thins them from `fade_start` 35 m to
  `fade_end` 75 m). Blades and leaves under a pixel only alias (moire, sequins), so past that a
  layer is kept by its average cover, dithered per pixel, coloured by the layer's height (TAA
  resolves it; compat stills show it as grain). The understory stays low on purpose: a metre of
  shells seen from the side is a stack of slices and read as velvet pillows; the 3D shrubs are
  the canopy. No shadow, no GI. Off on the web and below MEDIUM (`CityChunk.shells_enabled`,
  set by `Quality`, which also hides the built ones - group `hill_shells`). **Trap:** a MultiMesh
  without `use_colors` hands the Compatibility renderer's shader a COLOR that is not the vertex
  colour; the shells set white instance colours or their keep-out reads as "never grow". And
  the painted straw is `straw_color` times the terrain's grass texture and mottle (`gl`), not
  `straw_color`: the shells sample the same two textures (copies of their tile sizes and mean
  lumas sit in hill_shells.gdshader; keep them equal), or they draw a third as bright. The
  painted stands carry **shrub crowns** (`hill_crowns()`: a dome per jittered 2.6 m cell,
  0.64-1.24 cells across, 0.55-1 tall, never reaching past the four cells searched): the stand
  edge runs round them (`crown_edge`) and inside a stand they are lit as domes with shade
  between them (`crown_relief`), faded out from a pixel footprint of 0.06 to 0.2 m (gone by ~120 m
  at 720 rows: resolved across a canyon they read as bubble wrap), off with `ground_detail`; `HillPlanting.crown()` is the same
  field (`CROWN_MEAN` is its measured mean, which the edge push is centred on). The lone sage
  dots are painted `sage_color` (grey-green, paler), not chaparral: they read as polka dots.
  `_scatter_hills` reads heights off the tile grid and runs `SCATTER_PER_STEP` tries a step
  (it asked `height_at()` ~1,000 times in one step: a 60 ms hitch per hill chunk). Judge any of it fast with `tools/glshot/hill_ground_shot.tscn` (the real hill chunks
  round an EYE, lit by the city's environment, a minute a shot; `SHELL_DEBUG`, `NOSHELLS`,
  `PROFILE` under Forward+) and time the steps with `tools/hill_step_bench/hill_step_bench.tscn`.
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
  they looked like spiders. `palm()` builds the tree at every level of `PALM_LEVELS` from one
  random stream (see the Performance note): anything added to it must draw its random numbers
  at every level, whether that level draws the part or not, or every frond after it moves.
- Replica areas (see the technical rule): `ReplicaAreas` (`scripts/world/replica_areas.gd`,
  `MacroMap.replica`, built in `MacroMap.setup()` before the hill roads, `fit_hill_profile()`
  after) holds each area as a table - today only `ESPLANADE`: Knob Hill down the Redondo
  Esplanade, the south curve and the Avenue I roundabout, Paseo de la Playa, then Palos Verdes
  Blvd / Dr N climbing the peninsula's north face. Legs (straight, arc, roundabout, a
  grade-seeking `climb`) are sampled every `STEP` 4 m into `pts` / `dirs` / `run` / `top` /
  `sec`; a section's lateral lines (`kerb_w`, `walk_e_edge`, `edge`, `toe`, `water`,
  `east_back`, ...) are offsets from the centre line, POSITIVE TO THE LEFT of travel (east,
  heading south). `at_s(s)`, `nearest(pos)` (cell-cached), `blocks_grid(pos)` (the corridor the
  seeded city must not build in), `block_role()` / `block_lots()` (CityPlan.lots() returns the
  replica's lots for its blocks, so LOD chunks, Skyline and AirTraffic see the same houses; they
  read `lot.height` / `lot.color`). The route drives the map: `terrace_at()` is folded into
  `MacroMap._relief_at()` (with a `calm` factor that keeps the seeded rolling relief off the
  town), so every chunk's `_gy()` already follows the bluff; its `waterline_table()` becomes
  `MacroMap.coast_x()` / `beach_width_at()` and the ocean shader's coast table (Weather
  `_push_ocean_shape`); the Palos Verdes headland is an ellipse (`peninsula_*`,
  `peninsula_crest` fitted to the Street View skyline to a quarter of a degree) and the far
  ground keeps its crags off it (`calm_*` in `macro_relief.gdshaderinc`); HillRoads carves the
  hill part (`draw: false`, the replica draws it) and lays the peninsula's rim road and estate
  lanes. `CityChunk.begin_build()`: a block with role 1 skips the seeded block and
  `ReplicaBuilder.attach()` (`scripts/world/replica_builder.gd`) adds its steps - the grid roads
  on the chunk's +X/+Z sides cut exactly round the corridor (`Geometry2D` polygons, kerbs along
  every cut edge except a mouth), the road with gutters, kerbs, medians, markings and parking T
  marks, the walkway / seat wall / verge / fence / bluff face and beach stairs, the roundabout
  and the beach car park, the backfill ground, the furniture (`ReplicaSigns`: cobra lamps,
  parking plates, roundabout diamond and chevrons, stops, name posts, speed plates, bus stops),
  each house (`ReplicaHouses`), the parked cars, the people (`ReplicaWalker`, a Pedestrian
  that strolls along a pavement instead of a block's ring), one commit. Ownership: a path segment by its
  midpoint, a lot by its centre (in the chunk's owned rect), a feature by its centre. Heights: the
  road and everything along it at the profile (`top`, = terrace + ROAD_TOP); batch instances
  through `rel()` (the batch adds `_gy`). Houses are real geometry - walls cut round every
  opening with reveals, framed glass on `shaders/house_glass.gdshader` (sky/street mirror
  emitted, parallax room, blinds, lit at night), panelled garages, hip/gable clay-tile roofs with
  eaves (`roof_clay`) or coped parapets, balconies, garden walls - one mesh per material per
  chunk; `ReplicaHouses.frame(lot)` is the footprint, shared with the kerb parking's driveway test.
  Traffic: `ReplicaTraffic` (`scripts/npc/replica_traffic.gd`, child of the streamer) drives the
  lanes by path distance, anticlockwise round the ring (decreasing angle in x/z), and the grid
  traffic turns round at the corridor (`TrafficManager._turn_back_from_replica()`). Traps: a
  `SurfaceTool`'s format is fixed by its FIRST vertex (the lamp column's taper had no UV and the
  arms after it did); the default smooth group averages normals across every shared position, so
  a box built in it shades round its corners (houses and `box()` use smooth group -1); a
  coastline is not a function of z where it runs east-west (the peninsula's north face), so test
  it only to `coast_range()`. Shots: `EYE=x,y,z,yaw,pitch` on `tools/glshot/still_shot.gd` puts a
  free camera at a true world point (a Street View lens is ~2.5 m up). Checks:
  `tests/replica_checks.gd`. Adding an area: another table like `ESPLANADE` in `AREAS`.
- Landmarks: `Landmarks.all()` lists them (id, world anchor, radius; built once and cached, so
  never modify what it returns); `Landmarks.build()` makes one, detailed (with a StaticBody3D for
  shapes) or far (no collision). Add a new one by adding an entry and a `_build_<id>()` function.
  Everything original: no real names, logos or copies - with ONE exception, by owner request
  (2026-09-24): **downtown's skyline follows the real DTLA massing** (which towers, where they
  stand relative to each other, relative heights at real metres, silhouettes, crowns, facade
  character). **Names and logos stay original**: no real building, company or brand name in any
  game text or on the minimap, and no lettering on any crown. Code ids are neutral (`dt_*`).
- Downtown skyline (owner, 2026-09-24: "a 1:1 match of DTLA skyline ... It needs more
  buildings"): `LandmarkDowntown` (`scripts/world/landmark_downtown.gd`) builds nineteen `dt_*`
  landmarks, listed in ONE contiguous block at the end of `Landmarks.all()` (other branches add
  theirs elsewhere; the civic centre and the arena district are not these). **Everything about
  a tower's placement is ONE table, `LandmarkDowntown.TOWERS`**: its real point(s) (keys of
  `DowntownReal.POINTS`, geocoded addresses; two for a pair, built round their midpoint), radius,
  height (real metres: the 335 m sail with a spire, the 310 m round tower with the lit glass
  crown, the 262 m white slab, ...), plan (real footprints, the pairs at their real spacing;
  checked against the built geometry) and crown. `LandmarkDowntown.anchor(id)` is the real point
  through `DowntownReal.game_xz()`, clamped into its block less the pavement (13.8 m at worst;
  the checks hold it under 30). `Landmarks.all()` appends `LandmarkDowntown.entries()`. Downtown
  is **1:1**, plan and heights (see the DowntownReal bullet). Each tower is built by
  `TowerMesh` (`scripts/world/tower_mesh.gd`): outlines (rect, chamfered, notched, circle,
  ellipse, rounded, bowed, `union()`) extruded into tiers with setbacks (`prism`, `sloped`), and
  `loft` / `wedge` / `vault` / `spike` / `mast` / `fins` / `balcony` for crowns and details, all
  into ONE ArrayMesh per tower: a facade surface per material on `shaders/building.gdshader` in
  its **`uv_facade` mode** (UV.x = metres round the outline, each face a whole number of bays so
  no window straddles a corner; UV.y = face index, 100+ = blank wall - so round and curved towers
  get the same traced recesses, rooms, lit offices and emitted glass mirror as the boxes), a
  vertex-coloured metal surface, and a lit-crown surface on `shaders/tower_crown.gdshader`
  (glass by day, `night_factor` glow in the vertex colour at night). Aviation lights are one
  billboard mesh on `shaders/aircraft_lights.gdshader`; each tower carries its own
  `OccluderInstance3D` (boxes inset like `CityChunk.OCCLUDER_INSET`) and, detailed, convex-hull
  collision per tier plus a small detail mesh. Meshes are cached per id, so the far copy
  `CityStreamer` keeps (the skyline from the freeway, hills and beach) and the detailed one a
  chunk builds are the same geometry. **Rules:** outlines have positive signed area in (x, z)
  (NW, NE, SE, SW), `TowerMesh.clean()` fixes any other; facade surfaces never carry vertex
  colour (SurfaceTool fixes a surface's format at its first vertex); every tower must stay
  inside its block less the pavement (`LandmarkDowntown.footprint()`, checked by the smoke test
  on this seed and another). The blocks are fixed because **`CityPlan.pinned_roads()`**
  (`DowntownReal.pins()`) pins the real street grid for every seed; the seeded blocks either side
  of a run of real streets stretch or split to meet them (`CityPlan._next_road()` /
  `_prev_road()`). Between the towers, `MacroMap.downtown_core` (`DowntownReal.game_core()`, two
  rects: Bunker Hill and the Financial District from the 110 to Olive, South Park) +
  `core_margin` make the district DOWNTOWN and the skyline boost 1, and DISTRICTS DOWNTOWN's
  `core_height` / `core_curve` / `core_shapes` / `core_finishes` / `core_courtyard` turn the
  infill into a field of 30-190 m towers on bigger lots (`core_lot`), 52 lots over 130 m (never
  over the named ones; no SLAB, which caps itself at 40 m and would disagree with the far tier's
  box; more stone than glass). Outside the core the district is the historic core's 14-80 m of
  stone, brick and render. The minimap only labels a pin with `LABEL_ROOM` pixels of room.
  Stills: the south-west aerial `--spawn=1450,2150,-38,4,140`, on the avenue (Flower at Olympic,
  north) `--spawn=2359.4,880,0,12,2`, the civic centre `--spawn=2600,-450,-50,-4,60`, the arena
  `--spawn=2300,1150,138,-8,30`, with `HIDE=Visual` on `tools/glshot/city_shot.gd` (hides the
  player, who otherwise stands in the middle of it).
- DowntownReal (owner, 2026-09-24: "I want the whole downtown landscape to become a 1:1 replica
  ... geographically sound"): `scripts/world/downtown_real.gd`, the replica area that carries
  downtown - the Esplanade's idea (a REAL ORIGIN, a TURN, a GAME ANCHOR) for a street GRID. The
  real grid was fitted from OpenStreetMap (93 cached Nominatim answers in
  `tools/downtown_relay/geocode_cache.json`, `fit2.py`): bearing 37.86 degrees, RMS 2.0 m over 115
  centre-line points. The whole grid is turned onto the game's axes (grid north = game north),
  Pershing Square is `GAME_ANCHOR` (2800, 102.7) and 5th St is exactly z 0 (CityPlan's road 0).
  Tables: `AVENUES` / `STREETS` (name, position in grid metres, width, points, RMS, `run`),
  `POINTS` (geocoded towers, civic buildings, parks), `FREEWAY_110/101/10`, `EXTENT`, `CORE`,
  `PARKS` (Pershing Square, Grand Hope Park, Grand Park are their real kinds, every other block
  inside is buildings), `MACARTHUR`. Helpers: `game_xz(latlon)`, `point(key)`, `pins()` (what
  CityPlan pins: [x or z, width, name, run]; a pinned road runs the whole map), `pin_at()`,
  `named()`, `block_inner()`, `freeway()`, `in_extent()`. What it does to the rest: downtown is
  x 1650-3950, z -1750..2020 (the 110 to Vignes, Cesar Chavez to Venice); all its crossings are
  signals; the rolling relief is off inside it; `MacroMap` pushes the east range out to x 5000
  and steps the whole north back `embay_depth` 1250 m over `embay_x` (the real range ends at the
  Cahuenga Pass; only low hills stand above the civic centre); the port is where the real one
  is (owner, 2026-09-25: "it should be on the east side of palos verdes"): on San Pedro Bay at
  the foot of the 110, just east of the headland's land end, x 2750-3380, z 5935-6495, its south
  third built out into the bay, the harbour (the berth, `harbor_rect`) off its south quay and the
  cargo ship at (3065, 6541). The bay (`bay_z` 6300, `bay_east_x` 4700) wraps the headland's
  south and east and is open sea; east of the port its north shore is Long Beach's sand
  (`bay_beach_depth`). There is no inland water anywhere: the old harbour at z 3300 is city now (all of it checked by `_port_on_the_bay()` in `tests/downtown_checks.gd`).
  The ocean shader gets `bay_east_x` from `Weather._push_ocean_shape()`. Industrial is east of the
  110 below z 2300 (`industrial_corner` (2150, 2300)) all the way down to the port, and the Arts
  District east of Vignes; the
  freeways (`Freeway`, `_spline()` of control points) are the 110 and the 101 on their geocoded
  lines (the 110 then runs nearly due south to the port's north-west corner), the 10 new, the
  105 rerouted south of the airport's clear zone, down the west side of the 110 corridor and
  east at z ~2900; the 405 stops 60 m short of the airport fence (`Freeway.AIRPORT_KEEP`; it
  used to cross the terminal and the runways). No building part of any lot, plaza or big-box
  store stands within 3 m of a deck or an off-ramp (`Freeway.blocks_rect()`, checked downtown by
  `tests/downtown_checks.gd` against every captured box, the towers, the civic sites, the
  masjid, the airport and the port); the airport's final turns in over Westlake
  (`AirTraffic.downwind_x` 1250, `MacroMap.approach_clear_length` 1150). CityStreamer stops the
  LOD ring at `lod_reach_metres()` (840 m; downtown's 440 m blocks would run it 3 km) and retires
  LOD chunks left 150 m past it, and builds a block of the FULL ring in full detail only inside
  `full_reach_metres()` (240 m, where two ordinary blocks end; two of downtown's 125 x 200 m
  blocks each way was 2.6 times the full-detail area). NOT 1:1: east of Main the real streets are another grid (only Alameda and
  Vignes are pinned there); one road is one line (Wilshire also splits the historic core, 12th St
  is left out, Georgia runs the whole map); the streets west of the 110 bend 8 degrees and are
  straightened (MacArthur Park 280 m grid-north of the real one, and 6th to 7th is 204 m there
  where the real park is 310 m); distances BETWEEN areas are compressed (the port is about 6 km south of
  Pershing Square, not 30). Checks: `tests/downtown_checks.gd` (the grid on two seeds, the real
  order and spacing, towers and civic sites at their points, real distances, the frame, the
  masjid's place). Probe: `tools/downtown_relay/probe.gd.txt`.
- Downtown civic set (owner, 2026-09-24: "downtown must match real downtown LA, we need staple
  center"): the same exception as the skyline - the real buildings' FORMS in their real places
  relative to the core, every NAME invented (no real arena, sponsor, team, hotel, museum,
  hall or station name anywhere, the LED slides' brands included). South-west of the core, `LandmarkArenaDistrict` (`scripts/world/landmark_arena_district.gd`):
  `arena` (RANDO ARENA: oval bowl on a stepped podium, glass ring leaning out, banded metal drum,
  domed roof you can land on, corner marquee with LED screens), `live_plaza` (STARLIGHT PLAZA with
  the STARLIGHT THEATER, screens, neon, crowd), `live_hotel` (HOTEL ALTAIR, 200 m slab with a lit
  crown), `convention_center` (white hall, two tilted green-glass pavilions). The blocks round
  them are filled, not paved (owner, 2026-09-25): `ArenaGrounds` (`scripts/world/arena_grounds.gd`)
  has the pieces - a multi-storey car park (`garage()`: decks, spandrels, cores, roof stalls,
  static parked cars from `car_mesh()`, a ~260-triangle code car: the traffic bodies' LODs stop
  at 4,000+ triangles and 250 of them cost 3 M), surface lots, raised planting beds (`bed()`),
  tree groves with ring benches (`bosque()`, 12-14 m apart, trees gone at 280 m) and bronze
  figures on plinths (`sculpture()`) - and the builders lay them out: the arena at real size
  (`ARENA_RADII` 54 x 45, drum to 40 m) toward Figueroa, the car park west of it, the star plaza
  on its north front, palms in beds along Figueroa, a service drive and berm south; the plaza's
  theatre and cinema block at real depth with a grove in the south of the plaza; the hotel podium
  filling its footprint; beds along the convention centre's front. A site keeps its table
  footprint (the real building's point, held by the tolerance check), so the rest of each block
  is `ArenaGrounds.leftovers()` (block less every district site in it, built by the first site in
  `CivicSites.ORDER`) filled by `build_leftovers()` from `CivicSites.build()`: the arena block's
  north strip a grove, its south a surface lot, a car park west of the hotel, a second hall
  south of the convention centre. North-east,
  `LandmarkCivicCenter` (`landmark_civic_center.gd`): `ziggurat_hall` (CITY HALL - on its real
  block, turned to face its real street, floodlit), `civic_park` (CIVIC PARK: fountain
  terrace, lawn, pink furniture), `concert_hall` (SYMPHONY HALL, steel sails from
  `tools/make_concert_hall.py`), `lattice_museum` (THE LATTICE), `pueblo_station` (PUEBLO
  STATION). **One table places them all: `CivicSites.SITES`** (`scripts/world/civic_sites.gd`):
  the real point (a key of `DowntownReal.POINTS` plus its lat/long; `at` in grid metres for the
  hotel and the plaza, which share one block and whose geocoded point is a POI), footprint (own
  frame), yaw (quarter turns, set so each faces its real street after the grid's turn: city hall
  90, the concert hall 180), `tolerance` (how far the block may clamp it off its point, checked)
  and the real size and facing. `CivicSites.anchor(id)` / `real_xz(id)` go through DowntownReal;
  `site()` centres the footprint on the anchor as far as the block lets it. Builders work in a frame centred on their site; `CivicSites.build()` puts a turned
  pivot with its own static body in the world, and anything that needs world coordinates (crowd
  rects, the chunk's grass) goes through `CivicSites.to_world()` / `rect_to_world()`, with the
  chunk in `CivicSites.ctx`. They are **block sites**: `"site": "block"` in `Landmarks.all()` makes
  `Landmarks.claims()` true for the block the anchor falls in, so `CityPlan.lots()` returns
  nothing there and `CityPlan.block()` overrides its park/plaza/mall roll (AFTER the roll, so no
  seed moves); every builder lays itself out inside `Landmarks.site_rect()` (the block inside its
  pavement ring), so nothing ever stands on a road whatever the seed (the real grid is pinned on
  every seed). Radius only flattens relief and stays inside the block. Crowds:
  `Landmarks.crowds()` returns rects the chunk fills with ordinary pedestrians (as build steps).
  Geometry is `LandmarkGeo` (`scripts/world/landmark_geo.gd`): one mesh per building, a surface
  per material; UVs in METRES (u along a wall, v world height) which the landmark shaders read;
  every triangle is flipped to face the normal it is given, so winding cannot go wrong; curved
  things you stand on get one concave shape, boxes get box shapes. Shaders:
  `landmark_facade` (texture as detail, joints, bands, punched windows, FLOODLIGHT after dark),
  `curtain_glass` (UV mullions, emitted sky + fake skyline, traced interior lit at night),
  `brushed_steel`, `clay_roof`, `fountain_water` / `fountain_jet`, `led_screen` (slides from
  `LedScreen.atlas()`, a 5 x 7 dot-matrix atlas of INVENTED brands in `LedScreen.SLIDES`), all
  sharing `landmark_common.gdshaderinc`. Far versions are the same builders at low detail (a few
  draws each). Checks: `tests/civic_checks.gd`. Frame them with `tools/glshot/landmark_shot.gd`
  (free camera: `CAM`, `LOOK`, `FOV`).
- Westlake (owner, 2026-09-24: "MacArthur Park and a bunch of homeless tents up on random
  streets in downtown and people slumped over"): the first **replica area** on the street grid.
  **The park is ON** (`LandmarkMacArthurPark.enabled`, since 2026-09-24 evening; it was held off
  while traffic leaked onto its closed roads - the forced-turn note under Street life, and
  `CityStreamer.recenter()` called outside the physics tick by the tests); the
  encampments are on. Its entry's table is `"area"` (the civic set's
  `"site": "block"` is a different thing).
  `LandmarkMacArthurPark` (`scripts/world/landmark_macarthur_park.gd`) keeps everything real in
  ONE table, `SITE` (lat/long, the real offset from Pershing Square, real size, Wilshire's real
  heading, the lake outline in the south half's 0..1 frame) plus its placement at 1:1
  (`DowntownReal.MACARTHUR`: Park View x 100, Alvarado x 487, 6th z 200.2, Wilshire z 312.7, 7th
  z 404 - all pinned real streets; anchor (293.5, 312.7)). Stills: the whole park from the south
  `--spawn=300,528,0,-35,120`. Its `Landmarks.all()` entry carries a `site`, which
  `CityPlan.sites()` snaps to whole blocks: `block()` gets `"site"`, `lots()` is empty, and
  `road_open(axis, index, along)` / `road_open_at()` / `junction_closed()` close every road
  inside the four boundary roads except Wilshire. Everything that puts things on roads asks it:
  `CityChunk._build_roads` / `_build_intersection`, `StreetDetail._has_poles`, `TrafficManager`
  (spawns, and turns forced at a closed arm - a dead end U-turns short of the crossing),
  `PoliceCar._drivable`, police dispatch and roadblocks, the respawn corner and the minimap (park
  colour, lake). A site chunk builds its own part of the park (`Landmarks.site_steps()` ->
  ground, water, walks, planting, furniture, features, crowd), so a 430 m park streams with the
  city; only the fountain and the boathouse are the anchored landmark with a far version. The
  lake is `shaders/lake.gdshader` (local = world space inside a chunk) on a basin with coping and
  wall collision; its floor (`FLOOR_Y`, -1.2) is BELOW CityStreamer's GroundBody (top 0), so the
  lake-shaped `LakeSplash` Area3D adds a collision exception between each player/props body in
  it and the GroundBody (`_sink`), removed on exit or when the chunk unloads. Keep `FLOOR_Y`
  above `under_city_ground()`'s 1.5 m or the player standing in the lake is lifted out.
  Encampments: `Encampment` (`scripts/world/encampment.gd`, static, a step after
  `_build_sidewalk_props`) on DOWNTOWN `BUILDINGS` blocks, far denser since the owner's
  "multiply by 20" (2026-09-27): some streets far more than others (`CAMP_STREET_SHARE`,
  `FACE_ODDS*`), a **skid-row band** east of the centre (`skid_row()`, in downtown radii from
  `MacroMap.downtown_center`, patchy per block, spilling into the midtown and industrial blocks
  beside it: whole faces wall to wall, a kerb row of carts and bags, higher caps), camps under
  the freeway decks near downtown (`_build_underpass()`), the faces across from MacArthur Park,
  and never within `WORSHIP_CLEAR` (160 m) of a landmark whose id names a place of worship. Runs
  are laid along the building line (walls from `StreetDetail._footprints()`) with doorway gaps,
  corner and prop clearance and a kerb-side `PATH_KEEP` the block's walkers keep to.
  **Every roll is a hash of seed, block and face, never the chunk rng.** Pieces are
  `PropFactory.encampment(piece)` from `assets/models/encampment_kit.glb`
  (`tools/encampment_kit.py`, Blender; now with a loaded cart and a roped bundle), batched as
  `camp_<piece>` with colour and a per-instance sun-bleach in the instance custom
  (`shaders/encampment*.gdshader`); each knockable piece is an `EncampmentItem` static body
  (props + npc layers, mask 0) that turns into a `PhysicsProp` debris copy when hit and stays
  gone (WorldState). Caps per chunk `MAX_ITEMS` / `SKID_MAX_ITEMS`, FULL chunks only,
  `DRAW_DISTANCE` 190 / 120 m. **The people come in two kinds.** Everyone sitting, lying or
  slumped is a `CampFigure` (`scripts/world/camp_figure.gd`): each (model, pose) is posed once
  on a real RoughSleeper and its welded middle body (`Pedestrian.far_mesh()`) skinned on the CPU
  into a plain mesh in the worn look (the loading screen bakes all 45), and a chunk's figures
  are merged into ONE `CampFigureMesh` (`SurfaceTool.append_from()`, a surface per material,
  plus a one-surface shadows-only twin from the far bodies, shadows to 60 m). Seeds are searched
  so each model has one look and no cap or pack (`CampFigure.seed_for()`), so a chunk using
  `FIGURE_MODELS` (3) models is three draws; up to `MAX_FIGURES` / `SKID_MAX_FIGURES` a chunk,
  half on the web. Flat camp pieces cast no shadow (`NO_SHADOW`), the rest to `SHADOW_DISTANCE`
  (`MultiMeshBatch.set_shadow_distance()`). A figure's body is on the npc
  layer; a round, a blast, a bumper, or an alarm (`Pedestrian.alarm()` -> `wake_near()`, the
  nearest `wake_on_alarm`) **wakes** it: the merged mesh is rebuilt without it and a live RoughSleeper with the same
  seed, pose and spot takes its place and the hit. Standing people (in twos and threes, by a
  bundle) and cart pushers (`Pose.PUSH`, walking the walkers' strip) stay live `RoughSleeper`s
  (`scripts/npc/rough_sleeper.gd`, extends Pedestrian, so shot, knocked, bled and ragdolled like
  anyone), capped by `MAX_SLEEPERS` / `SKID_MAX_SLEEPERS` and counted in the crowd cap through
  `take_crowd_room()` - walkers near downtown leave `CROWD_RESERVE` of the cap for them. Poses
  SIT, LIE, SLUMP, CHAIR are held by overriding bone poses over a paused idle clip, solved per rig
  from its own rest pose (aim a bone's child direction, like `fix_arm_pose()`); gunfire makes the
  sitting and lying get up and FLEE (then RETURN and settle) and the slumped
  COWER in place. Worn clothes are `RoughSleeper.worn_material()` - the character shader's
  `grime` uniform (dirt low on the body, never on skin). Depict it as the street, never as a joke.
- Masjid Omar ibn Al-Khattab (owner, 2026-09-24: "way more detailed and 1:1 accurate", six
  photos, "give it an interior", and "make it impossible for the character to shoot anything at
  it"): `LandmarkMasjidOmar` (`scripts/world/landmark_masjid_omar.gd`), a replica of the real
  building on Exposition Blvd with its OSM footprint (way 412475901: 49.2 m, a tall west block
  and a lower east wing, 15.7 m), the lattice bays, the green ribbed dome, the minaret, the
  entrance flight and a walkable interior (prayer hall with gallery, mihrab, minbar and
  chandelier; lobby; a second hall under the hollow dome). Geometry is built once in code into
  merged meshes (one surface per material, cached in static vars) plus ONE trimesh collision
  body with the doorways left open; custom looks are `shaders/masjid_carpet.gdshader`,
  `masjid_lattice.gdshader`, `masjid_marble.gdshader`. **Where it stands** (anchor (1917, 2722.8)):
  where the real one is relative to downtown at 1:1 - grid-south of Pershing Square on the real
  building's line (`REAL_LATLON` through `DowntownReal.game_xz()`, 40 m off in x), west of the
  110, south of where the 10 leaves it and north of the 105, the distance south compressed (the
  real point is past the port; checked in `tests/downtown_checks.gd`). The block west of Georgia
  St; its south road (the default seed's 24 m boulevard at z 2785.1) plays Exposition and the
  entrance flight lands on its pavement. It used to stand at (-235.7, 165.2), which the 1:1
  downtown put 3 km due west of Pershing Square, past MacArthur Park. Still:
  `--spawn=1880.7,2809.6,-31.8,-23.7,32` (tools/glshot/bookmarks.sh `masjid`).
  **It is a sanctuary** (`Sanctuary`, `scripts/weapons/sanctuary.gd`): a zone box (group
  `sanctuary_zone`, built by the far copy too, since that has no collision) and the collision
  body (group `sanctuary`). `Weapon.tick()` refuses the shot when the crosshair is on it, when
  the shot would cross its grounds, when a blast would land within the weapon's
  `explosion_radius` of them, or when the player stands inside - no recoil, no alarm, no
  cooldown spent. Rockets that reach it fizzle (`Rocket.fizzle()`), and bullet holes and scorch
  marks skip it whoever fired. Never route a new weapon around `Weapon.tick()`, and give any new
  place of worship the same zone.
- Autoload `WorldState`: `world_offset` (local + offset = true world position, use `to_world()` /
  `to_local()`) and the destroyed-prop registry (`mark_destroyed`, `is_destroyed`).
- Anything that must survive origin re-centering has to be a 3D child of the scene root (the
  streamer shifts every Node3D child). Store true world positions only via `WorldState.to_world()`.
  A node under one of those shifted children is placed relative to its parent, not as if the
  parent sat at the origin: TrafficManager's spawns set `WorldState.to_local(p) - position`
  (before that, every car spawned after the first re-centre landed the whole offset away).
- Building windows use **interior mapping**: `shaders/building.gdshader` traces the view ray
  into a virtual room behind each pane and shades whichever inner surface it reaches, so windows
  have true parallax (lean left, see the room's right wall) instead of glass painted on a wall.
  Each room gets its own paint, depth falloff and a blind pulled to its own height. This is the
  single technique that stops a box reading as a box; do not replace it with a gradient.
  `room_depth` and `interior_enabled` are the knobs. The opening itself is traced too
  (`window_recess`, faded out between `recess_fade_start` and `recess_fade_end`): the glass sits
  behind the wall face, a view ray that hits a jamb, sill or head first draws that surface with
  its own normal (so a sill catches the sun), and a ray toward `sun_direction` shades the glass
  and reveals under the head. `u` runs against the wall tangent on the -X and +Z faces
  (`u_sign`); the room parallax had that mirrored until the recess went in. Most of the glass's mirror is EMITTED
  (`reflect_emit`, `reflect_energy`, scaled by the `sky_tint` global), not mixed into the albedo:
  a reflection does not depend on the light falling on the pane, and carried in the albedo a glass
  tower on the shaded side of a street was lit like paint and came out black (16/255 against 111
  for the asphalt in the same shadow). What the glass mirrors is a fake city, not one flat
  colour: two rows of blocks keyed on the reflected ray's heading (rooflines, window rows faded
  out under a pixel, sky above them; `reflect_city`), and each pane's reflection knocked a little
  off true (`pane_bow`), because coplanar mirrors across a whole facade read as one sheet of
  plastic. At night a lit office is the same room
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
  generates in `_ready()`. **A building is a handful of draw calls, not one per piece**
  (2026-09-27; it was 57 % of the downtown frame's draws). Its box parts are ONE mesh (`Walls`)
  under ONE ShaderMaterial on `shaders/building.gdshader`: what differs part to part (size,
  window pitches, floor heights, storefront, base course, crown) rides in the vertices as float
  CUSTOM0-3 (`part_attributes`; the landmark towers leave it off and keep the uniforms), and
  each part's numbers are also kept on `Building.parts` (StreetWear reads them there). The facade
  detail is one MultiMesh per kind (`Frames`, `Details` - the bands and the parapet -, `Bays`) on
  `shaders/facade_detail.gdshader`, which keeps every part's OLD visibility range per instance:
  a node's range is measured to the centre of its bounds, so each instance carries its part
  index and the material holds the parts' centres in TRUE world space (`part_ref`), brought into
  the shifted scene by the `origin_shift` global that `WorldState.world_offset` pushes on every
  change - never per-instance positions, which the Compatibility renderer packs into half
  floats. The roof boxes and cylinders are one mesh (`RoofPlant`, `shaders/roof_plant.gdshader`,
  the material in the vertices), the rooftop air conditioners one MultiMesh per model (they
  share the LOD of the building's nearest unit, never a coarser one), and the plinth goes into
  the chunk's merged boxes (`plinth_in_chunk`). Both replacement shaders are the
  StandardMaterial3D they stand for, line for line, down to the unset textures it samples; a
  colour in a vertex is handed over as the renderer would hand the uniform (RD linearises
  `source_color`, Compatibility passes it verbatim: `Building._roof_albedo()`). Still one node
  each: the shop names and the kit batches (one per kind already). Prove a change here with
  `tools/building_merge_probe.gd` (rebuilds the old nodes from `Building.keep_records`, diffs
  them, and splits the difference by kind; `SHIFT=1` shows what an origin re-centre alone flips).
  **Podiums** (2026-09-27): where CityChunk sets `podium_lot` (LotFill's districts),
  `_add_podium()` - after `_layout_parts()`, before `_pick_style()`, from hashes of the seed only,
  so no `_rng` roll and no colour moves - gives a tower whose ground parts cover under
  `podium_max_cover` of a big lot a base part (`parts[0]`, `"podium"`: 1 retail and lobby storeys
  in the building's finish, 2 a parking deck) filling `podium_fill` of the lot, lifts every
  ground part onto it (tops unchanged) and slides the tower off centre. A parking deck is drawn
  by `building.gdshader` from CUSTOM3.z (`garage_*` uniforms: precast spandrels, columns on the
  bay lines, the deck behind traced - floor stalls and nose-in cars, the next deck's lit
  underside, the far side open to the day -, the drive-in bay `garage_entry` on `street_face`,
  and a roof that is itself a deck of stalls); it gets no facade details or kit, its storey is
  `GARAGE_STOREY` and its far box is its concrete (`part_lod_color()`). StreetWear only paints its
  spandrels. No podium roof gets roof plant: LotFill parks cars on a deck and lays a garden on a
  retail one.
- Facade kit (owner, 2026-09-24: "it must look like RDR2, not San Andreas"): real moulded geometry
  on the buildings near the camera, modelled by `tools/facade_kit.py` in Blender
  (`blender -b --python tools/facade_kit.py`, then `--import`) into `assets/models/facade_kit.glb`,
  one node per piece: three cornices, a parapet coping, three window surrounds, a window AC,
  a shop awning, a balcony, fire-escape landings (stair left, stair right, drop ladder), a timber
  water tank, two vents and a packaged rooftop unit. `PropFactory.facade_kit(piece)` loads one
  through `model_mesh()` (so `TRI_BUDGET` guards it, keyed `facade_kit.glb:kit_<piece>`) and
  swaps the glTF materials for `PropFactory.kit_material()` by name. `Building` places them
  (`_pick_kit`, `_kit_runs`, `_kit_awnings`, `_kit_roof_plant`, and inside
  `_add_facade_details`) into ONE `MultiMeshBatch` per building (`Batch_kit_<piece>`): per
  building rather than per chunk because frustum and occlusion culling and the distance fade
  (`kit_*_distance` exports, 110-320 m) all work per node, and a chunk-wide batch is never
  occluded. Two tricks in `shaders/facade_kit.gdshaderinc` let one mesh fit every building, and
  the Blender side has to keep their rules (header of the generator): roofline runs are 2 m,
  x -1..1, and the shader slides only their end rings by `INSTANCE_CUSTOM.r/.g` (tan of half
  the corner's turn) so any corner, square or chamfered, is a true mitre; everything else is
  three-sliced by `INSTANCE_CUSTOM.b/.a` round a 1 x 1 m opening, so a sill's lugs, a lintel's
  height, a jamb's width and an awning's cheeks keep their real size on every window and shop.
  So never scale a surround or awning instance - pass the slice instead - and never let a run
  vertex other than its ends reach |x| 1. `INSTANCE_CUSTOM.r` is also the ironwork paint on
  pieces with no mitre. Placement is all hashes of the seed (`_kit_hash`) or a private
  `RandomNumberGenerator` (`_kit_roof_plant`), never `_rng`, and the old rolls it replaces are
  still made: the smoke test builds the same block with the kit off and on and checks the roof
  units and shop names do not move. The surrounds use `Building.WINDOW_RECTS`, which the smoke
  test checks against the shader's own window rects. Near the camera the kit hides the old box
  bands; past its distance they carry the look, so the cornice's far band is sized to sit inside
  the moulding (`KIT_CORNICE_CORE`) and never doubles it. Balcony slabs and fire-escape landings
  are one trimesh per building (`KitSolids`). Baked AO lives in UV2.x as occlusion, and is off
  on `kit_iron`, whose thin bars bury their only vertices in the rails they meet. The kit is off
  on the web (`Building.kit_enabled`), where the boxes and painted frames stand in for it.
- Storefronts and curtain walls (owner, 2026-09-27: "next level ... AAA studio quality"): the
  kit's code-built half, `ShopfrontKit` (`scripts/world/shopfront_kit.gd`), meshes built in
  GDScript in the kit's frame and conventions, wearing `PropFactory.kit_material()` and added
  to the building's one kit batch (a key each: `kit_shop_bay`, `kit_shop_door`,
  `kit_shop_pier(_metal)`, `kit_shop_fascia`, `kit_shop_blade`, `kit_awning_dome/_flat/_roller`,
  `kit_cap_v`, `kit_cap_h`): a frame round every display window (jambs, head, sloped sill, the
  transom at door-head height, a centre mullion in some shops), a door in every door bay (a pair
  of glazed leaves with pull handles, or one leaf with a push bar beside a sidelight), cladding
  on every pier box (plinth, shaft, capital), a trim round every sign board, blade signs with
  the shop's name up both faces (a lightbox after dark as the shop's board is), awnings in four
  shapes (one per building by hash), and on a curtain wall mullion and transom caps. The kit
  shader grew **anchors** for them: UV2.y - 1 is a per-vertex code (bits 0-1 x, 2-3 y: 0 the
  slice, 1 moves with the low edge, 2 with the high edge, 3 stays at the centre; bits 4-7 keep a
  vertex only where INSTANCE_CUSTOM.g / .r is or is not set, so one mesh holds two layouts), so a
  door's meeting stiles stay in the middle, its handles at hand height and its transom at door
  height on any opening. The glTF pieces carry UV2.y = 1 (code 0) and are untouched;
  `ShopfrontKit.place()` is the shader's placement in GDScript (the smoke test checks a door
  with it). The caps cull per instance (`cull_distance` on `kit_mullion`, set from
  `Building.kit_mullion_distance`), so a tower's caps are two draws and still stop floor by
  floor. **The storefront pieces stand exactly where `building.gdshader` paints the same
  frames**: which bay is the door, whether it is a recessed entry, the centre mullion, the door
  layout and the frame finish all come from `Building.shop_byte()` with salts 14-18 shared
  with the shader (`ShopfrontKit.SALT_*`; the smoke test reads the shader's thresholds back),
  and the painted frames give way to the geometry within `shop_paint_near` (45 m) and carry the
  look alone from `shop_paint_far` (70 m) - the pieces draw to `kit_shopfront_distance` (100 m,
  the building's node), so past 70 m both draw and the 7 cm between them is under a pixel. A
  recessed entry (28 % of door bays) is the shader alone at every range: a 1.1 m traced lobby
  with a mosaic floor, stone returns, a soffit downlight and the painted door at the back. The
  shader also puts vinyl lettering, posters, opening hours and OPEN plates on the glass (on the
  traced pane, so they parallax with it), scissor gates on some closed shops at night, and
  measures the storefront from the part's base (it used to be a ratio of WORLD height, which
  squashed or erased every shopfront standing off y 0; StreetWear's `_paintable()` and the
  shop names follow). Curtain walls (`curtain_spandrel`) have the far shader's vision band and
  spandrel (0.08 / 0.93 of the floor, pale or dark by its roll through `lod_seed`) and thin
  lines in the frame paint where the caps stand; with the kit on they wear no flat `Frames`.
  The `Frames` everywhere else are `ShopfrontKit.window_frame()`: a real 45-60 mm section
  (`Building.FRAME_WIDTH`) with its inside faces, a sash bar in most punched windows, one paint
  a building (`Building.FRAME_PAINTS`). Knobs on Building: `kit_shopfront_distance`,
  `shop_paint_near` / `_far`, `kit_awning_building_chance`, `kit_blade_chance`,
  `kit_mullion_distance`; `ShopfrontKit.enabled` (off: none of these pieces, the A/B -
  `STOREFRONT_KIT=0` on `still_shot.gd`). The blade-sign names are flat text merged on the CPU
  (`ShopfrontKit.TextAcc`): never `SurfaceTool.append_from()` a mesh per building (a read-back
  from the renderer). Look with `tools/glshot/still_shot.gd` `EYE=` / `SHOTS=` (a third `@fov`
  field per shot); `building_shot.gd` for one building.
- Shop interiors (VISUAL_ROADMAP #14, 2026-10-04): behind every storefront's glass is ONE room
  the width of the whole shop (6-9.5 m deep, a tower lobby 13 m and double height), traced per
  pixel in `building.gdshader` by `shaders/shop_interior.gdshaderinc` (`shop_interior()`): the
  room's walls, floor and ceiling fixtures plus its fittings as boxes and ROWS of identical
  boxes (`shop_row()`: one slab test and an analytic step to the next item, so a row of tables
  is one call), so they have true parallax. Kinds (`ROOM_*`, mirrored by `Building.ShopRoom`):
  retail (wall shelving and gondolas of rolled product facings, a counter, chillers), clothing
  (racks of garments, cubbies, mannequins), cafe (tables, chairs, counter, back bar and menu
  board, pendants), restaurant (cloths, banquette, pictures, pendants), laundromat (washers and
  dryers with portholes and LEDs, an island, a folding table), barber (chairs, mirrors, counter,
  bench), bank (teller line, a desk, stanchions) and lobby (stone, columns, a lit reception
  desk, a lift bank with indicators, planters, a bench). **The room follows the shop's name**:
  `Building.shop_names()` (the sign roll, now shared) -> `SHOP_NAME_ROOMS` -> `shop_room_codes()`
  -> the `shop_rooms` uniform (4 bits a shop, the first `SHOP_ROOM_SLOTS` 7 a face); past those,
  and on the landmark towers, `shop_room_kind()`'s hash (salt 40). **Lobbies**: the middle shop
  of most faces of a building over 30 m (`tower_height` uniform = `Building.height`; a tower's
  ground part is often a low tier) - lit all night, no neon or glass decals, its street number
  on the sign (`shop_is_lobby()`, mirrored). Light: `room_tone()` per kind (warm cafes, cold
  laundromats; `Building.room_tone()` colours the pavement spill to match), the day term (the
  room lit by daylight from the front, falling off inward), the shop's own lights by day
  (`shop_day_light`) and after dark (the old lit-shop path, `lamp` per surface), and practical
  glows (`shop_glow`: pendants, chillers, tills, LEDs, lift indicators). Salts 40-45. Detail
  under a pixel fades to its average (`px` grown with depth). Zero triangles, zero draws: the
  frame cost is ALU on storefront glass pixels only. Judge with `building_shot.gd` (`NIGHT=1`,
  `BENCH=n`) and `still_shot.gd` `EYE=`/`SHOTS=` from the pavement; `tools/glshot/shop_probe.gd`
  (headless) lists the storefronts near a point with an EYE for each face.
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
  The player wears a tracksuit (owner, 2026-09-24: "a new jersey mafia tracksuit";
  `Player.avatar_tracksuit`, alpha 0 turns it off): `Pedestrian.tracksuit_material()` paints top
  and trousers one velour colour (`velour` is Godot's rim lobe, `cloth_shade_keep` flattens the
  source jacket's patches), and `Pedestrian.add_piping()` bakes CUSTOM0 (signed distance round
  each arm and leg from its outer line, limb weight, outward facing) and CUSTOM1 (head, hand and
  foot weights) from the rest pose, so the piping moves with the cloth and skin, head and shoes
  are found by bone rather than by colour or height. The height band was set for the crowd's
  average build and took in the hero's collar and shoulders; his jacket's tan yokes passed
  every colour test for skin. Like limb cutting, the bake needs mesh data, so it does nothing
  under the headless dummy renderer.
  **The crowd** (owner, 2026-09-27: real people, "AAA studio PS5 quality"): `Pedestrian.MODELS`
  is twelve rigs, `assets/models/crowd_a..l.glb`, built by **`tools/crowd/`** with the hero's
  toolchain (`tools/hero/setup.sh` fetches Blender 4.2, MPFB 2 and the CC0 MakeHuman pack):
  `tools/crowd/build.sh [names]` runs, per character of `tools/crowd/crowd_config.json`,
  `build_character.py` (Blender: the MPFB human from a phenotype, targets and skin - or a blend
  of skins for a complexion the pack lacks - in library clothes, shoes, hair, brows and lashes;
  bound with the hero's lowered arms and a relaxed hand baked in, the finger bones folded into
  the hands; hidden skin deleted; cut to per-part triangle budgets, ~11-12.9k body + up to 3.8k
  hair; every texture's islands cropped and skyline-packed into a 2K body atlas and a 1K hair
  atlas, garments optionally dyed, logos painted out; soles on y 0, cm under 0.01, +Z),
  `crowd_atlas.py` (python3: composes the atlases, skin relief from the skin photo, the scalp
  under the hair painted in the hair colour) and `crowd_export.py` (Blender: the hero's retarget,
  `tools/hero/retarget_lib.py`, and the .glb) - a minute or two each. Then `godot --headless
  --path . --import`, `python3 tools/fix_texture_imports.py assets/models` (put back any
  unrelated `.import` it touches), commit the `.glb`, the extracted `crowd_*_body.jpg`,
  `_body_nrm.jpg`, `_hair.png` and every `.import`. The contract every crowd system keeps (checked
  by `_check_crowd_rigs()` in the smoke test): the 24 crowd bones and three clips; ONE skinned
  **Body** surface on character.gdshader whose vertex colour says what each vertex is - R top
  garment, G bottom garment, B hair (the painted scalp), A skin, none of them shoes / eyes - so
  the shader recolours a look exactly (`region_mask`, with the source's shading kept as a ratio
  to each region's mean, `Pedestrian._region_means()`) and a garment can be marked `keep` (the
  overalls); and a **Hair** mesh of cut-out cards on `shaders/crowd_hair.gdshader`
  (`Pedestrian.hair_material()`, the look's hair colour, never in a shadow pass). The crowd keeps
  its own hair colours (`hair_strength` 0 on those looks). Everything that swaps a rig's
  material, cuts limbs, welds the middle / far bodies or bakes a camp figure works on the body
  and skips `Pedestrian.is_hair()`; past `mid_body_range` the hair is hidden (the painted scalp
  is the hair out there), and under a hat it is pressed flat or hidden (see Headwear); `plain_hair()` puts the
  photographed colour back for a uniform or a rough sleeper (dulled, `WORN_HAIR`). Judge rigs
  with `tools/glshot/crowd_lineup.gd` (several side by side, `SHOTS=` for several views from one
  load, `BODY=mid|far`, `LIGHT=street` for AgX and a tarmac ground) as well as
  `character_shot.gd`. Adding a person: a row in crowd_config.json, `build.sh <name>`, add it to
  `MODELS`; `FROM=crowd_atlas build.sh` redoes only the atlases and the export.
  **Our own garments** (2026-10-04; the shader work on MakeHuman's photographed clothes had hit
  its ceiling): a row with an `"outfit"` in crowd_config.json (its `"clothes"` then list only the
  shoes) wears garments modelled on its own body by `tools/crowd/garments.py` - a crew-neck
  **tee** (short or long sleeves, fitted / regular / loose), **trousers** (jeans, slim, chinos,
  leggings, denim shorts), a **button shirt** (stand-and-fall collar with points, placket and
  buttons, shirt-tail hem, cuffs or rolled sleeves, stripes or a check) and a **zip jacket**
  (stand collar, zip, rib cuffs and hem band); the keys are in its header. Each is a shell grown
  off a smoothed copy of the body (its UVs and weights), shaped by an `Envelope` (slice hulls,
  hung from the chest, blurred) and limb tubes, cut by planes and hemmed with a turned lip;
  collars, cuffs, bands, placket and zip are swept bands. They have no source photo: their atlas
  rects are "virtual" and `tools/crowd/garment_paint.py` paints every texel from what the garment
  is there in 3D (seams, topstitching, hems, waistband and belt loops, pockets, yoke, fly, denim
  wear and whiskers, rib wales, woven patterns box-filtered per texel) with a height field for the
  normal map; it re-reads the outfit, so colours and patterns need only `FROM=crowd_atlas`. The
  contract holds unchanged: the garments join the ONE Body surface with R / G at their fabric's
  level, buttons and the zip's teeth and pull are the "other" region (no colour, never
  recoloured), and the mid / far welds, camp figures, limb cuts and the police recolour see an
  ordinary rig. Rules that cost a debugging round each: a push-out ray must start at the point
  (cast from outside it jumps a fold - crotch, armpit - and throws the cloth past the far side);
  a top's push off the trousers is a smooth field (`push_smooth`) and the trousers under a top
  are cut away with their margin taking the top's weights (`hide_under`), or they poke through
  at every stride; the male crotch is flattened without letting a vertex cross the midline (its
  weights are its own leg's); the cover test counts torso skin outward from the torso's axis
  and a lone miss among covered neighbours (the armpits) as covered; and the garments' AO is
  gentle with a floor (`own_ao`), being baked on a coarse shell in a pose the game never shows;
  and the fold field's ankle stack is the hero's gathered track pant, which on hemmed jeans read
  as jogger cuffs, so crowd_atlas.py scales it per trouser style (`ankle_stack` / `ankle_reach`).
  A body in our garments is 11.7-12.9k triangles (10.5-12.7k in the library clothes). Eight
  people wear them (a, d, e, h, i, j, k, l); b, c, f and g keep library clothes - f's tailored
  jacket over a striped shirt read richer than our zip jacket, which is built but worn by nobody.
  Judge with `tools/crowd/preview.sh` first (Blender Cycles, no render lock, seconds: `FLAT=1`
  geometry only, `REGION=1` which mesh is which - green on a top is the trousers, black is skin)
  and finish with `crowd_lineup.gd` (`TURN=90` shows a row in profile).
  **Close-up detail** (owner, 2026-09-27: faces and garments at 2-4 m): faces are not the
  average MakeHuman head - `build_character.py` rolls MPFB's own face targets (nose, jaw, chin,
  cheeks, eyes, mouth, ears, brows, forehead; `FACE_PAIRS`, `face_var`, `face_seed`, explicit
  "targets" win); men get **stubble or a beard** painted into the atlas over a beard zone worked
  out on the head round the eyes (`stubble`, `beard`, `beard_rgb`; stubble is a cool shadow, not
  the beard colour laid on - brown paint read as orange smudges); trousers are **dyed** per
  person (`dye` / `dye_contrast`: dark indigo, black, grey, charcoal, khaki, or the washed
  photo); **garment folds** are `tools/hero/folds.py`'s field (elbow and cuff stacking, hem
  blousing, knee and ankle folds, hip creases) evaluated on every garment texel from the
  triangles and landmarks `build_character.py` dumps (`folds.npz`, `fold_landmarks.json`), added
  to the garments' own normal maps and darkening their valleys (`fold_gain` per garment). The
  body mesh carries **UV2 in metres** (1 unit = 1 m of surface, per atlas rect), on which
  character.gdshader tiles `assets/textures/crowd/crowd_detail.png` (`tools/crowd/make_detail.py`:
  skin pores and mottle, jersey knit and heather, denim twill and slub streaks, a plain weave;
  RG normal, B roughness, A tone; `detail_strength`, `detail_normal`, `detail_tone`,
  `detail_rough`) with one fetch. What a garment is made of rides in its region level: R or G
  at 1.0 jersey, 0.85 denim, 0.70 woven, a "keep" garment 0.45 lower in R (build_character's
  `FABRIC_DEFAULT`, "fabric" per garment in the config), each fabric with its own roughness and
  rim sheen (`FABRIC_ROUGH` / `FABRIC_SHEEN`); eyes are B + A both full and get a wet, glossy
  cornea (`eye_roughness`). Skin gets Forward+ subsurface scattering (`skin_sss`,
  `Pedestrian.CROWD_SKIN_SSS`; `sss_mode_skin`, the Compatibility renderer ignores it) and a warm
  `skin_backlight`. A crop without a hair mesh gets a 512 px hair atlas (brows and lashes).
  The photo's skin relief is on the head only (on the body it was JPEG noise turned into lumpy
  skin). Brows are shaded round the hair colour from their own mean and their fringe is let
  through the cut coloured toward the skin (`BROW_*` in crowd_atlas.py): cut as they came, every
  brow was a solid near-black bar. crowd_atlas.py re-reads the config's look keys (`_LOOK`), so
  `FROM=crowd_atlas tools/crowd/build.sh` is enough after a change to them - before, the atlas
  plan's copy from the last Blender run won and a tuned `skin_normal_strength` never landed.
  The covered skin that is kept (the ring inside each garment edge, the chest under a V-neck or
  an open collar) is tucked up to `cover_tuck` (6 mm; 14 mm on crowd_j) in along its normal by
  `build_character.py`: at 5 mm under the shirt, a walk's chest turn pushed skin triangles out
  as pale slivers. **The tuck is a smooth field** (the covered flag averaged over
  `cover_tuck_smooth` neighbour passes): moved as a step it made every neckline, cuff and hem a
  crease, the importer's LODs held far more triangles for it and the downtown crowd drew 46 %
  more (355k -> 519k); smoothed it measures flat. Anything else that reshapes a crowd body must
  stay smooth for the same reason - measure the pedestrians' `SPLIT=1` line after it.
  **Shader files use `//` comments, not `##`** - a `##` line is a syntax error and Godot falls
  back to a blank white material, which looks like a missing texture rather than a broken shader.
- Crowd life (GAME_PLAN G5, 2026-10-04: "make the street feel inhabited"): within
  `Pedestrian.life_range` (60 m) of the player people do more than walk - the "Life" section of
  `pedestrian.gd`, with the shared data in `CrowdLife` (`scripts/npc/crowd_life.gd`). At the end
  of a walk (`life_chance`), or at once when they appear (`life_spawn_chance`, so a street you
  arrive in is already busy), someone stops (`_act`, `CrowdLife.Act`): TALK (`_plan_talk()`
  recruits one or two free walkers on the same ring within `talk_reach` round a spot, facing
  its middle; who speaks is worked out from the clock, so the group needs no leader; listeners
  nod and look at the speaker), STAND (the phone, texting, a coffee, idle, folded arms), SIT
  (`CrowdLife.add_seat()` registers both places of every FULL chunk bench and bus-stop bench on
  the chunk; `_plan_sit()` takes the nearest free one, sit_down / sit / sit_talk / stand_up, the
  hips put on the bench by a two-bone leg solve in `_sit_pose()` because the clip's chair is
  10-20 cm higher than `SEAT_HEIGHT`), LEAN and WINDOW (one world-layer ray toward the
  buildings, `_plan_wall()`: no wall, no lean). Each person rolls what they carry
  (`_carry`: CALL, TEXT, CUP, BAG, SMOKE; `*_share`) and whether they jog or walk a dog
  (`jogger_share` / `dog_share`, the higher share in SUBURBS, BEACHTOWN and on the Esplanade) on
  their own stream (`_life`, `hash([seed, "life"])`). Carrying is an arm pose laid over the walk
  in `_life_pose()` (a frame of the phone or talk clip, or the coffee forearm aimed forward,
  `CrowdLife.CUP_FOREARM`) and a prop on a BoneAttachment3D (`_hold()`: `CrowdLife.prop_mesh()`
  in the GRIP frame - x thumb, y fingers, z out of the palm, `grip_basis()` measured on the rigs
  - on `shaders/crowd_prop.gdshader`, the screen glowing and the cigarette's ember lit by
  `lamp_factor`; the bag is set plumb every tick). Joggers play `life/jog`
  (`CrowdLife.JOG_CLIP_SPEED` 3.0) at any range; dog walkers have a `CrowdDog`
  (`scripts/npc/crowd_dog.gd`, a child of the owner's node, Quaternius' CC0 Shiba Inu,
  `assets/models/dog_shiba.glb`, a lead to the owner's left hand within the look range).
  **Dog walkers are off** (`dog_share` 0, lead's call at merge): that Shiba is low-poly and
  flat-shaded, which breaks the realism rule; turn them back on with a realistic dog.
  Rules: out of range a stop just ends (`_life_range_changed()`); `_scare()` ends it at once;
  only plain Pedestrians and ReplicaWalkers live (`_lives()`), never officers or rough
  sleepers; all life timing is the physics clock (`_life_now_ms()`), never the wall clock (a
  slow render or the wheel's slow motion). **The clips**: `tools/crowd/life_clips.gd` retargets
  14 clips from Quaternius' Universal Animation Library 1 and 2 (CC0; `tools/crowd/
  fetch_life_clips.sh` puts the free Standard files in the ignored `build/ual_src/`) onto every
  crowd rig IN GODOT, writing `assets/models/crowd_life/<rig>_life.res`, which `CrowdLife.attach()`
  adds to the rig's AnimationPlayer as the "life" library AFTER `fix_arm_pose()` and the loop
  loop (never let fix_arm_pose see these clips). Do not retarget in Blender: its glTF import
  re-orients the bones. The method is retarget_lib's world delta, so neither rest pose matters;
  per clip it scales the legs' swing about their mean (the jog, 0.55) or settles them toward the
  rig's stance (every standing clip, 0.6: the library's idles stand like a fighter). Rerun it
  (two seconds a rig) whenever a crowd rig is rebuilt; add a clip by a row in `CLIPS`. The body
  contract is untouched (no new bones, the same Body and welded bodies). `CROWD_LIFE=0` in the
  environment turns the layer off (the A/B). Look with `tools/crowd/crowd_lab.tscn` SCENARIO=life
  (a pavement, a wall, two benches), props, dog (CAM / LOOK / FOV place the camera); check with
  `tests/crowd_life_checks.gd`; time it with MODE=bench.
- Headwear (2026-10-04: the old box caps "read as plastic bowls"): `CrowdHat`
  (`scripts/npc/crowd_hat.gd`) builds a six-panel cotton baseball cap (button, sweatband, a bill
  with a taped edge, a strap and slide buckle across the opening at the back), a cuffed 2x2-rib
  beanie with a little slouch, a twill bucket hat and the police peaked cap (black braid band,
  flared navy crown, patent peak, chin strap, badge), each **modelled round the rig's own head**:
  `tools/crowd/hat_fit.gd` (opengl3 under Xvfb, never --headless: it needs mesh data; seconds)
  measures every crowd rig into `scripts/npc/crowd_hat_table.gd` (`CrowdHatTable`: eye centre,
  ear tops, a centre, the skull's radius on a 17 x 32 grid of directions with the ears put back
  on the skull, the hair's thickness over it), and the hats are built in the HEAD FRAME (metres,
  skeleton axes, origin at the Head bone's rest) from it: the band edge at a height over the eyes
  per kind (`EDGE`, never below the ear tops plus `EAR_CLEAR`), the cloth `standoff()` off the
  skull (cloth, room for the pressed hair, the cap's structured front, the beanie's slouch).
  **Rerun hat_fit.gd whenever a crowd rig is rebuilt** (`REPORT=1` builds every hat on every
  rig and measures it against the real head: how close the outside comes to the skin, the gap at
  the band; the smoke test fails when the table misses a rig). Everything up close is
  `shaders/crowd_hat.gdshader` on the mesh's coordinates - twill, panel seams with topstitching
  and eyelets, rows of stitching round a bill, the stockinette knit and rib, the crown's
  decreases, a bucket's vent eyelets, one of three small original embroidered marks (never a team
  or a brand) or a woven label - each faded to its average under a pixel, both faces drawn (the
  inside is the lining: no inner geometry), colourways muted (`CAP_COLORS` ...). A hat is one
  mesh per rig and kind with three levels in one buffer (every 1st / 2nd / 4th row and column of
  its grids, `LEVEL_EDGES`; ~1.7k / 450 / 130 triangles), one material per colourway, one draw
  per wearer, never in a shadow pass, gone past `accessory_distance`. **The hair is pressed, not
  hidden** (`pressed_hair()`): vertices under the crown moved inside it, easing out over a few
  centimetres below the band so hair shows at the back and sides, strands far off the scalp (a
  ponytail through the opening, a braid) left alone, triangles left wholly inside and the cards
  that would hang in front of the face (a fringe) dropped; one copy per hair mesh, rig and kind.
  No mesh data (the headless check) or a rig marked `"hide"` (hair too thick to press) hides the
  cards as before. `Pedestrian._add_accessory()` makes the same three `_style` rolls as the box
  hats did (CampFigure.seed_for() depends on them; a bucket hat is the top tenth of the old cap
  roll), the ragdoll a hatted person becomes wears it too (`_dress_doll()`), `PoliceOfficer` uses
  `CrowdHat.Kind.PEAKED`. The loading screen builds them all (`CrowdHat.warm()` from
  `Pedestrian.warm_far_mesh()`: ~12 ms a hat, ~10 ms of hair a kind on this box). Look with
  `tools/glshot/crowd_lineup.gd` `HATS=cap,beanie,bucket,police` (`HAT_PICKS=` the colourways);
  checks: `tests/crowd_hat_checks.gd`.
- The hero (owner, 2026-09-24: "Blender with real fingers from scratch AAA studio level"):
  `assets/models/hero.glb`, built by **`tools/hero/`** in Blender 4.2 with MPFB2 from CC0
  MakeHuman assets plus our own tracksuit, rib tank, rope chain, watch, ring, laced sneakers and
  hair cards (sources in `docs/ASSETS.md`). `tools/hero/setup.sh` fetches Blender, MPFB and the
  asset pack into the ignored `build/hero_src/` (it gets a `.gdignore`); `tools/hero/build.sh`
  runs the steps (body, tracksuit, jewellery, shoes, hair, texspace, textures, finalize, export;
  `build.sh <step>` restarts from one, `--only` runs just it, `--render` adds Cycles previews),
  about 15 minutes; every number is in `tools/hero/hero_config.json`. Then `godot --headless
  --path . --import`, `python3 tools/fix_texture_imports.py assets/models` (put back any
  unrelated `.import` it touches) and commit the `.glb`, the `hero_hero_*` textures Godot
  extracts, the `hero_x_*` maps and every `.import`. 54 bones: the crowd rigs' 24 names plus 30
  finger bones, cm under a 0.01 armature, facing +Z, the same three clips, bound with the arms
  lower than MakeHuman's A-pose (`rest_pose` in the config) so hanging arms skin without square
  shoulder pads. Garment edges are plane cuts with real cross-section bands (a face-by-face
  pick left the collar ragged), and **fold normals are never ray-baked**: `folds.py` is a fold
  field on the 3D surface and `texspace.py` rasterises the UV layout to rest-pose points so
  `prep_textures.py` derives every map analytically (the bake put inverted normals in both
  armpits - the dark shoulder patch). The same field gives a second, closed-joint fold map and a
  per-joint mask. Three things that each looked like a modelling fault and were not: the
  collar takes its weights off the head and most of the neck (`off_the_head()` in
  `tracksuit.py`; with the skin's own weights the idle, which looks round 60 degrees, wrung it
  into shards); the shadow twin is pulled `shadow_inset` (6 mm) under the real surface
  (`finalize.py` 5b; where a decimated twin stands proud it throws its facets across the cloth
  as jagged black patches); and the painted scalp fades over a distance measured on the head
  from the hairline, not over height (a height fade is a razor edge where the hairline runs
  vertical, at the temples). `HeroLook` (`scripts/player/hero_look.gd`) dresses him in the game: by
  material name it swaps skin, hair, brows and tracksuit onto `shaders/hero_skin.gdshader`
  (tiling pores and stubble over the body maps, T-zone oil, SSS and transmittance on Forward+,
  BACKLIGHT on Compatibility), `hero_hair.gdshader` (root-to-tip colour, the card's own
  occlusion from UV2, dithered alpha scissor, anisotropic highlight along the strands) and
  `hero_cloth.gdshader` (rest and bent fold maps mixed per joint, velour pile and sheen), wets
  the eyes and the watch glass with a clearcoat, and draws his shadow from `hero_shadow`, a
  9k-triangle twin (`SHADOWS_ONLY`; the body casts none). The `hero_x_*` maps are not in the
  glTF: they sit next to it and must be committed. `HeroLook.update()` turns the elbow and knee
  angles into the folds' `wrinkle_weights` on `Skeleton3D.skeleton_updated` - read anywhere
  else, a pose is the clip's, without the IK. Knobs on Avatar: `skin_sss`, `stubble`, `pores`,
  `hair_anisotropy`, `velour_rim`, `velour_sheen`. Cycles previews that match the game:
  `tools/hero/render.py --hero` (the same recipe in nodes) and `--pose` (see Player body). The
  crowd tracksuit code (`Pedestrian.tracksuit_material()`, `add_piping()`) is kept for dressing
  a crowd rig.
- Player body: `Avatar` (`scripts/player/avatar.gd`, built by `Player._build_avatar()` from
  `avatar_model`, one of `Pedestrian.MODELS`): idle / walk / run clips picked by speed, frozen or
  slowed stride in the air, forward lean while boosting. The orange capsule in `player.tscn` is
  only the fallback when the model file is missing. Guns are held, not hung (owner, 2026-09-24:
  "the weapons not even in the hands"): `Avatar.hold_gun()` puts the WeaponMount relative to the
  hero's LIVE right shoulder (the clips carry the shoulders 12 cm above the rest pose, so a rest
  shoulder put every grip out of reach) at `Weapon.hold_hip` with the `hold_hip_rot` low-ready
  carry, raised to `hold_aim` while aiming or firing; a `TwoBoneIK3D` on the skeleton pulls both
  wrists onto `Weapon.grip_right` / `grip_left` (elbows steered by poles), and `GripHands` (a
  SkeletonModifier3D after it) turns each hand to `grip_*_fingers` / `grip_*_palm`. On these
  rigs a hand bone's +Y runs along the fingers. Keep every grip within 0.52 m of its shoulder or
  the arm locks straight short of it. Before the IK, `AimTwist` (`scripts/player/aim_twist.gd`)
  holds the chest in a shooting stance: it blades the spine by `Weapon.hold_twist` (hip, aimed
  degrees) with the neck and head turned back to the sights, and with `Avatar.stance_hold` it
  takes back the clip's own turn of the shoulders - the idle swings them 75 degrees as it shifts
  weight, which took the support shoulder 30 cm off the gun and the hand with it. The gun is
  placed from the shoulder the stance leaves (`AimTwist.shoulder`), not the clip's. The hero has
  finger bones: `GripHands.fingers` closes every joint round the gun by the gun's own curls
  (`Weapon.curl_right`, `curl_trigger`, `curl_thumb`, `curl_left`, `curl_left_thumb`, degrees
  per joint; the crowd rigs have no fingers and ignore them). Every hold number is **fitted,
  not guessed**: `tools/grip_fit.gd` runs the IK headless and scores the hands against each
  gun's grips as measured from `tools/make_weapons.py` (palm on the grip, fingers round it,
  index on the trigger, thumb round the far side, support hand round the handguard / pump / fore
  grip, the butt in the shoulder pocket, the launcher on top of the shoulder); `FIT=1` walks the
  numbers downhill and prints the lines to paste into the gun's `_init()`, `TRACE=150` prints
  the reach over time, `POSE_OUT=` dumps the pose for `tools/hero/render.py --pose` (Cycles
  close-ups of the same hold). Let the gun finish rising before measuring (`raise_speed`; three
  frames in, a report reads the gun a third of the way up). Judge it with
  `tools/glshot/hero_shot.gd` (WEAPON, AIM, YAW, CAM_DIST, CAM_Y, CAM_FWD, DEBUG).
  `Pedestrian.prepare_rig()` is the shared fix
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
  Past `Pedestrian.mid_body_range` (50 m) a pedestrian swaps to a welded middle body (at most
  `mid_triangles`, ~2,070) and past `lod_far` (140 m) to a welded far body (at most
  `far_triangles`, ~515), both from `Pedestrian.far_mesh()` and built during loading (~45 ms a
  model more than the far body alone cost): the models are unwelded, so the importer's LODs
  stop at 8,300 / 5,500 of 16,600 triangles and at 1080p most of the 45-140 m crowd drew 8,300
  a figure; welded, the simplifier goes as low as asked. Three traps, all paid for: welding
  keeps one UV per position, so each body triangle takes back the seam copies of its corners
  from one UV island, closest together (`_unweld()`); a triangle that still spans two islands,
  or stretches over more than `STRETCH_LIMIT` times the atlas its size should, takes ONE
  corner's texel on all three corners (interpolated, it smeared face and shoe across a white
  top); and the bodies have NO LODs of their own - the simplifier's errors are in the mesh's
  metres, the renderer weighs them by the instance's 0.01 armature scale, and the old far body
  was drawn at its last level, an 18-35 triangle stick. Past ~35 m the model itself turns to
  brown speckle (its tiny UV islands bleed together in the mips), so the welded bodies read
  truer to the close-up clothes than the model does at that range. Judge a body against the
  model with `character_shot.gd` (`BODY=mid|far`, `FOV=75`, `CAM_DIST` 15-140, crop and scale
  up). Downtown bookmark: crowd 1.88 M -> 1.10 M triangles, frame 8.23 M -> 7.44 M (HANDOFF 9x).
  Pedestrians cast shadows only inside `Pedestrian.shadow_range` (45 m) and drop to coarser
  mesh LODs with distance (`LOD_BIAS`): on a downtown street the crowd was 6.4 of 15.7 million
  triangles a frame, most of it shadow passes of 16k-triangle rigs; now 2.4. Cars do the same
  (`Vehicle.body_shadow_distance`, `BODY_LOD_BIAS`). Street props have a per-model triangle
  budget, `PropFactory.TRI_BUDGET`: the Poly Haven scans are film assets (a lamp was 30k
  triangles, a barrier 61k) and a MultiMesh batch draws every instance at the LOD of its nearest
  point, so over budget `model_mesh()` makes a generated LOD the base mesh. Add new hard-surface
  props to it; not foliage, whose leaf cards a simplifier collapses.
  **Shadows come from lighter twins.** `tools/gpu_profile.gd` (Godot's `--gpu-profile` per-pass
  timings under lavapipe) put the opaque pass, the depth pre-pass and the directional shadows at
  ~90 % of a frame, so it is triangles, not effects; `tools/tri_split.gd` then showed trees were
  the biggest single cost, 2.4 of their 3.2 M triangles in the shadow cascades - a batch takes
  one LOD for every instance from its bounding box (distance 0 while the camera is inside it),
  so every tree in the blocks around the player went into all four cascades at full detail. Now every imported model and the palms get `PropFactory.shadow_proxy()` (the
  scanned trees' comes from their measured ladder, see below) - the
  coarsest generated LOD that keeps 45 % of a leaf surface or 25 % of anything else, with the
  same materials so cut-out and sway still match - and `MultiMeshBatch.build()` draws it as a
  SHADOWS_ONLY twin (`BatchShadow_<key>`, sharing the instance buffer; `hide_instance()` hides
  both) while the batch itself casts nothing. Godot's own `shadow_mesh` cannot do this: it only
  serves materials with no cut-out and no vertex motion. Car bodies do the same with a twin of
  the body mesh at `Vehicle.BODY_SHADOW_LOD_BIAS` (a car's box is small, so plain LOD bias
  works there). Palms had no LODs at all until this (22.6k triangles at any range). Lettering
  (`text_` batches) casts nothing. Street frame 9.4 M -> 7.7 M triangles with no visible change
  (before/after renders in the handoff).
  **Palms carry a hand-built LOD ladder** (`PropFactory.PALM_LEVELS`, 2026-09-27). The
  simplifier cannot thin a palm - it will not merge separate leaflet cards - so its LODs stopped
  at ~10k of ~24k triangles and reported ~1.6 m of error, which the renderer only accepts past
  ~560 m at 960 px: every palm in the city drew at full detail, and MacArthur Park's ring (in the
  LOD chunks) cost ~2 M triangles from the masjid. Each level is the same tree from the same
  random stream with `stride` neighbouring leaflets merged into one blade of the same area,
  fewer leaflet segments, a coarser trunk, and the boots, coconuts and rib dropped far out
  (22.6-27k, 8-10k, 4-5k, ~500 and ~200 triangles). All levels share one vertex buffer, the
  coarser ones as the LODs, each at an `edge` that is its real geometric departure in metres, so
  Godot switches them under a pixel by its own rule; the shadow twin is the same ladder from
  `PALM_SHADOW_LEVEL` (1). The smoke test checks every level's crown extents, leaf area and tone
  against level 0, and `PALM_AB=1` on `still_shot.gd` renders the same frame again with
  full-detail palms (`<OUT>_palmfull.png`). Frames -7 to -23 % at the bookmarks, same draws
  (HANDOFF 9aa). **The scanned trees carry measured ladders** (`FoliageLod`,
  `scripts/world/foliage_lod.gd`, 2026-09-27, roadmap #36). `generate_lods()`'s errors on the Poly
  Haven trees were wrong both ways: the trunks and the jacaranda's 30k-triangle twig cards said
  3-10 times their real departure and never switched, while the leaf cards said 7-24 cm as the
  simplifier DELETED cards (tree_a's leaves kept 71 % of their cover at the first LOD and 0 % at
  the last, from ~85 m at 960 px: canopies thinned and went bare with distance, and so did their
  old shadow stand-ins). Now each of `PropFactory.foliage_ladder_files()` (CITY_TREES and
  HILL_TREES at full size; the budgeted chaparral and gully oaks and the knee-high plants keep
  the generated LODs - for those a cover-keeping ladder measured MORE expensive) gets, per
  surface, a ladder from a table (`scripts/world/foliage_lod_table.gd`) that
  `tools/foliage_lods.gd` measures and writes: the candidates are the generated levels and
  THINNED copies of surfaces made of many small pieces (every stride-th leaf card or twig in
  Morton order, the phase that keeps the tone, each grown so the level's textured cover - area
  times the atlas cut-out - is exactly level 0's, slid back inside the surface's bounds; limbs
  never thinned); each is measured by exact point-to-triangle distance both ways, its edge is
  the larger 98th percentile, a leaf surface may not lose 15 % of its cover, a thinned level may
  not move its 1 %/99 % outline more than its edge, and the trade-off front is kept. One vertex
  buffer per surface, the coarser levels its LODs, as the palms. A batch of these scales its LOD
  edges by its biggest instance (`lod_bias`, `MultiMeshBatch.build()`: a batch picks its LOD
  from the node's scale only; street trees are planted at 0.5-1.5x, landmark groves up to
  3.6x); the shadow twin starts at the coarsest level under `FoliageLod.SHADOW_EDGE` (0.22 m at
  the species' tallest street planting, `PropFactory.foliage_planted_scale()`) and runs at
  `SHADOW_LOD_SCALE` (0.5) of the batch's bias (a 0.9-degree sun gives a crown a 10-20 cm
  penumbra; the cars' twins run at 0.3). **Re-run `tools/foliage_lods.gd` (about five minutes) whenever a tree `.glb` is
  re-exported or the engine is upgraded**: `FoliageLod.build()` falls back to the generated LODs
  when the table stops matching and `_check_foliage_ladders()` fails. The ladders are warmed on
  the loading screen (0.1-0.5 s a species here). `TREE_AB=1` on `still_shot.gd` draws the same
  frame on the old meshes (`<OUT>_treeold.png`) and prints `TRUE` lines (every instance counted,
  see measurement trap 3); `TREE_AB=2` adds per-species and shadow-bias parts. Trees, every
  instance counted: downtown noon 5.47 -> 3.41 M (-38 %), freeway 11.38 -> 8.80 M (-23 %),
  masjid 8.11 -> 5.75 M (-29 %), camera pass -34 to -44 %, same draws (the engine's GEO, which
  counts a LOD'd batch as one instance: -3.5 to -4.2 % of the whole frame; HANDOFF 9af); and the
  crowns 60-200 m away that the old leaf LODs had stripped to bare twigs are back.
  **Foliage batches split into distance cells were tried and measured worse**
  (the wt/tree-lod WIP, 69c6662): the cells drew +650 k triangles and +54 draws on the freeway
  bookmark against the same batches whole (a whole batch's LOD distance is not its box's
  nearest point, and a block-wide box usually ends up coarser than per-tree), and nothing on
  the other bookmarks. Do not bring it back without a `GEO` A/B. Never run two lavapipe renders at once: each city is
  6-7 GB of RAM and the box has 16. Occlusion culling is on
  (`rendering/occlusion_culling/use_occlusion_culling`): one `OccluderInstance3D` per chunk made
  of its building boxes (`CityChunk._build_occluder()`), inset by `OCCLUDER_INSET` so it never
  sticks out past a wall - an occluder bigger than what it stands for culls things in plain
  sight. Diff a shot against `OCCLUSION=0` on `tools/glshot/city_shot.gd` after changing it.
  CPU: parked cars past `PhysicsBudget.vehicle_script_radius` stop their own per-step script
  (the physics body is untouched), and see the physics-layers note on masks. The HUD shows the level and a frame-time line (cpu / physics / gpu ms, draws,
  objects, tris): ask the owner for a screenshot of it before guessing at lag. Building window
  frames are flat quads drawn out to `Building.FRAME_DRAW_DISTANCE`.
  **Static boxes are never a node each.** `CityChunk._add_slab()` merges a chunk's solid boxes
  (big-box walls, pilasters, parapets, planters, yard pads) into one mesh per material at the
  finish (`_commit_boxes()`), and `MultiMeshBatch.merge_meshes()` does the same for the far
  landmarks' primitives: 300-530 box nodes a view and ~800 far-landmark nodes were a draw call
  each, and again per shadow cascade (hills bookmark 1,202 -> 942 draws, same triangles). It
  only merges opaque BaseMaterial3D / world-mapped materials and auto-named, unscripted nodes;
  `MERGE_STATIC=0` on `still_shot.gd` is the A/B, and its GEO / `SPLIT=1` lines are the frame
  cost of any bookmark (baseline table in docs/HANDOFF.md 9x). **Nor are a building's pieces**
  (2026-09-27, see the Buildings note): buildings went from 3,344 to 869 of the downtown frame's
  draws (5,815 -> 3,360), 3,270 -> 858 on the freeway (docs/HANDOFF.md 9ai). `SPLIT=1` also
  prints `BSPLIT` lines, the Building category by kind of node. For a before/after pixel diff
  shoot both sides with `DIFF=1` on `still_shot.gd` (shader TIME, the clock and the signals held,
  everything that moves by itself hidden - two plain runs differ in 41 % of their pixels) and
  compare with `tools/glshot/img_diff.py`. **Trap:** on the Compatibility renderer a MultiMesh's
  INSTANCE_CUSTOM and instance COLOR arrive as half floats; never put a position in them.
- Road surfaces use `shaders/road.gdshader` (via `PropFactory.road()`, picked in
  `CityChunk._road_look`): tiled asphalt plus world-space mottling, resurfacing patches on a
  jittered grid with darker seams, ridged-noise cracks and sparse oil staining, so the road never
  repeats visibly and never reads as a flat grey plane. Wetness comes from the `road_wetness`
  global that `PropFactory.set_wetness()` sets, not from walking materials one at a time.
  **Streets dry the way real ones do** (`shaders/wet_drying.gdshaderinc`, shared with
  `road_patch` and `road_paint` so patches and paint dry in step with the tarmac): while it rains
  the street is evenly `road_wetness`, exactly as before; once the water is leaving, Weather ramps
  the `road_drying` global to 1 (`drying_switch_seconds`) and the same water is spread by a
  per-pixel `hold` (0 dries first, 1 last): slow blotchy noise, the puddle field (puddles shrink
  from their edges and outlast the tarmac, `sqrt` of the wetness), the camber (kerb side wetter
  than the crown), two wheel tracks per travel lane (`CityPlan.lane_center()`'s lanes, drier),
  pavements drain sooner and dry slab by slab, and a ragged band of running water at each kerb
  (`gutter_width`, a mirror with its own sliding ripple, there while it rains too) is the last to
  go. A spot's `film` (gloss) goes before its `damp` (darkening). The road finds its kerbs from
  the slab UV (0..1 across the rect) and its size in metres from the ratio of screen derivatives
  of the plan position and the UV - only a long street slab counts, so junction squares, skirts
  and replica pieces get the noise alone. All of it is behind `ground_detail` (the web and low
  levels keep the even look) and `road_wetness` > 0.01 (nothing runs on a dry street; set_wetness
  always pushes the final 0). Force it for stills with `--wetness=0.45 --weather=clear` (web
  `wetness=`), which starts that wet and already drying and HOLDS it there (`Weather._wet_hold`:
  a still's loading frames are seconds long each and dried the street before the first frame).
  **Rain rings the standing water**: while `rain_intensity` (a global, Weather's `rain_level`)
  is up, puddles and the gutter run get three offset layers of expanding raindrop rings in the
  normal (`rain_ripples()`, `ripple_*`), faded out once a ring is under a few pixels.
  **At night the water mirrors a city**: SSR only mirrors what is on screen, and a puddle at
  your feet mirrors the facades above the frame, so it fell back to the night sky and read as a
  black hole (the web and the low levels have no SSR at all). `mirrored_city()` looks the
  reflected ray up in a procedural street canyon (lit shop fronts along the foot, office windows
  above, the roofline) and EMITS it by Fresnel and `lamp_factor`: sharp in puddles and the
  gutter, and on the wet film only the brighter shop fronts, as streaks toward the viewer
  broken up by the tarmac (`mirror_*`). Forward+ adds its SSR on top, so there it runs at
  `mirror_forward` (0.5, via `CURRENT_RENDERER`); it fades out by `mirror_fade` metres. The
  normal is now built as a slope (`NORMAL_MAP_DEPTH` 1, xy scaled by hand), so mixing the
  asphalt, the gutter and the rings is a sum; a dry street draws the same as before.
  `tools/road_cost.gd` times one full-screen street slab in each weather (read the ratios).
  **Tyre spray**: `TyreSpray` (`scripts/world/tyre_spray.gd`, built by Weather) is a pool of
  six mist emitters (three on the web, none at LOWEST) handed every `scan_interval` to the
  fastest grounded cars within `reach` of the player on a wet street, riding each car's rear
  axle; speed comes from true-world position deltas, so it works for kinematic traffic too.
  **Vertical faces** (kerb faces, seat walls, steps, slab edges) wear the same material, so the
  shader maps a face steeper than 60 degrees side-on (along it and down it) and keeps water,
  street glow and the night mirror off it. It tells a wall by the face's own normal from the
  screen derivatives, not the mesh normal: the replica's walkway shares a smooth group, which
  averages a wall's normals with the ground on top, and mapped from above every wall was a band
  of vertical streaks.
  Pavements use the same shader with `joints` (expansion-joint spacing in metres) and a lower
  `wear`, so they read as poured slabs rather than a grey plane. It also kills the visible tile
  grid, which is the first thing the eye finds on a plaza or a long pavement: it samples the
  texture a second time, rotated and at a different scale, and cross-fades on slow noise. That
  second fetch is gated on the `ground_detail` global, which `Quality` clears on web and below
  MEDIUM. Car parks, port yards and plazas go through `PropFactory.road()` for the same reason. The hill terrain shader does the same thing with the same global: its
  texture has a directional grain, so at a 5 m tile a long slope turned into corduroy. The hills' ground
  itself is a splat (`shaders/terrain.gdshader`, `PropFactory.terrain_material()`): tawny dry grass
  (the lawn texture's blades recoloured by luminance, the `hill` scan as a large-tile mottle),
  dark olive chaparral in ragged stands and far thicker on north-facing slopes, dirt / decomposed granite (`hill_dirt`) on the steep
  quarter and on a few trails, rock outcrops (`hill_outcrop`) on the steepest tenth, hillside-scale
  brightness swings, snow only above `snow_line`. Its colours are LINEAR, in plain uniforms in
  `hill_splat.gdshaderinc`, which the horizon plane reads too, so a range is one ground across
  the handoff; the shader works in linear on both renderers (`color_space.gdshaderinc`: the
  textures through `cs_in()`, the albedo out through `cs_out()` - see the measurement traps), and
  it reads TRUE world XZ (`world_offset`, pushed by `CityStreamer`) so nothing jumps on a
  re-centre. The stands follow the land (`topo_weight`: aspect, the erosion's drainage in
  COLOR.g, gentle ground; the patch noise only rags their edges - at 0.45 it drew camouflage
  blobs over the hill regardless of its shape). **Leopard spots, twice more** (2026-09-27): a
  threshold sitting at the stand noise's mean splits the ground 50/50 into that noise's blobs,
  so the land has to push it off the mean nearly everywhere - `chaparral_amount` 0.8 (steep
  faces are brush with small openings), `gentle_grass` 0.55 on ALL gentle ground (benches and
  valley floors are grass; it used to be halved off the sunny side, so flat ground was half and
  half) - and the octaves that decide an edge must be fine: the stand noise
  (`hill_stand_noise()`, weights `STAND_*_W` in hill_splat.gdshaderinc, mirrored and checked) is
  0.2 patch, 0.1 of the 8 m clumps, 0.4 of the 3 m bushes and 0.3 of a 1.1 m octave, because a
  3 m value noise cut by a threshold is itself round blobs, and from 150 m, once the shrub
  crowns are gone, that WAS the leopard. As each octave fades it widens the edge by its spread
  (`hill_stand_edge()`), so a hillside too far off to resolve it draws the brush SHARE as a tone.
  `macro_ground.gdshader` paints the same field (it includes the splat).
  **The ranges' look** (2026-10-04, "real LA ranges from the air"): gold grass on the open south
  slopes and their spurs, dusty grey-green chaparral in the folds and on the north faces, pale
  rock along the crests. `south_grass` 0.35 and `drain_brush` 0.6 split a south face into gold
  ribs and dark gullies (front range: south faces 86 % -> 54 % brush; gullies 97 %, mid-slopes
  51 %, spurs 6 %; north faces stay ~89 %); straw (0.200, 0.158, 0.076), chaparral (0.046, 0.058,
  0.040), dirt (0.205, 0.176, 0.133) and rock (0.172, 0.164, 0.150), linear. HillPlanting
  mirrors the two numbers. Canyons are shaded darker (`drain_shade`,
  `erosion_shade`), and the detail is lit: **the terrain mesh has no UVs and so no tangents,
  and a NORMAL_MAP without tangents does nothing** - every hillside was smooth plastic between
  its vertices. The shader works its detail out as world-XZ slopes (the ground textures' normal
  maps, `nm_slope()`; the brush canopy's own bumps from the noise that places the bushes,
  `brush_relief` / `leaf_relief`; the fine erosion orders) and sets NORMAL itself. Past
  `CityChunk.hill_brush_distance` (110 m) the shrub models are not drawn: their alpha-cut leaves
  mip to a few dark texels and a stand drew as black dashes; out there the painted stands are
  the brush. Keep all of it subtle: the first
  pass used strong patch blends and dark joints and the ground read as a printed pattern rather
  than a surface.
  The "patch" batch (resurfacing patches, oil, wheel tracks, braking polish, locate paint -
  StreetDetail) wears `shaders/road_patch.gdshader`: the asphalt texture times the instance's
  grey shade (1.0 = the road) with a ragged, feathered rim, oil soaked in blotchy and
  see-through, saturated instance colours drawn as spray paint. As flat grey boxes every patch
  read as a square hole cut in the road.
  Road paint (the `CityChunk.PAINT_KEYS` batches: dashes, centre lines, crosswalk bars, stop
  lines, arrows, stalls) wears `shaders/road_paint.gdshader`: worn through to the asphalt in
  patches (a discard - the boxes sit on the road, so a hole shows the road), speckled where it
  is thinning (the aggregate poking through, faded out once a speck is under a pixel; a smooth
  grey blend there read as dirt smudges), grit, dirt toward the wear, and a wet sheen from
  `road_wetness`. Flat perfect white was the most CG thing in
  any street shot. Limbs are cut and the effect materials compiled during the loading screen
  (`Ragdoll.warm_limbs()`, `WeaponFX.warm_materials()`), so the first rocket does not stall.
  Far buildings emit most of their glass's mirror too (`reflect_emit` / `reflect_energy`, kept
  level with `building.gdshader` so a tower does not change brightness at the LOD line, and
  faded to the facade's glazing average with the rest of the distance blend).
  Far (LOD) chunks lay their merged ground on an 8 m grid (`CityChunk.lod_ground_grid_step`) and
  sample the relief on a 9 m lattice (`LOD_RELIEF_STEP`): at the near 2.2 m step a far block was
  ~12k triangles of flat ground and 32 of its 40 ms build, and a fast flight outran the LOD ring.
  Now 7.6 ms, its worst step 2.9 ms (inside `build_budget_ms`). Far boxes decode their instance
  colour on Forward+ (`building_lod.gdshader` `instance_color_is_srgb`, set by
  `PropFactory.building_lod_material()`): it was declared and never set, so the whole far city
  was drawn 1.4-4.3x brighter than the same buildings up close on the Mac.
  **Far buildings are coded copies of the near ones** (2026-10-04, GAME_PLAN G7, docs/HANDOFF.md
  9bd): `FarBuilding` (`scripts/world/far_building.gd`) turns a planned Building into the LOD
  chunk's `lod_box` instances (which the far city captures as they are): each part one box with
  the near building's whole facade in its CODE - window style, finish, roof covering, wall
  texture set, palette indices of its glass tint, lit colour and frame paint, storefront and
  shop runs, bays and storeys (`Building.part_grid()`, the one function the near walls use too),
  base course, crown, seed - its plinth folded into the parts on the ground and its parapet's
  height on top; then its roof plant as boxes, the very units the near building builds
  (`Building.roof_plan()`: the plant rolls on its own stream, `_roof_rng`, so its layout is known
  without building the facade). The LOD chunks draw every unit; the far city keeps only
  `FarBuilding.SILHOUETTE` (bulkheads, tanks, cooling towers, billboards, spires and antennas
  with their red beacons, masts drawn at least `mast_min_px` wide) and prints the rest
  (`print_small_plant` on its own material, `PropFactory.building_lod_material(true)`).
  `building_lod.gdshader`'s coded branch draws the near wall cell for cell (the same `u`, bays,
  storeys, window masks, spandrels, shops and their night rolls, base course, crown, grime, the
  wall texture's mean), faded to the cell's average past a few pixels - its lit offices too.
  **The code rides in the instance transform**: a part's basis is diagonal, so its six
  off-diagonal entries carry 20-bit codes as code * 2^-28 (exact in float32, and a 4 mm shear the
  bounds can ignore), and the shader rebuilds the box from the diagonal (`skip_vertex_transform`)
  - because Compatibility hands INSTANCE_CUSTOM and COLOR over as half floats. Proven bit-exact on
  both renderers (HANDOFF 9bd). Rules: never rotate a coded part (houses and estates use the old
  path, INSTANCE_CUSTOM.a 0); anything the near and far shaders must agree on rolls from INTEGERS
  (`shaders/window_lights.gdshaderinc`: lit offices, spandrels; the shop rolls) - a float hash of
  the same inputs is only as exact as two compilers' instruction scheduling; a colour the far shader
  copies from Building goes through `cs_as_uniform()` (color_space.gdshaderinc: the near shader's
  own space, decoded on Forward+, raw on Compatibility) and its palette copies are checked by
  `tests/far_city_checks.gd`. A shader parameter may not share a uniform's name (building.gdshader
  has `seed` and `lit_ratio`): the compile fails and every building turns blank white. And
  `VIEWPORT_SIZE` read 0 in the far shader's vertex stage in the city: the first mast widening
  divided by it and drew every antenna a kilometre out a kilometre and a half wide (the pair
  scene showed nothing) - anything sized in pixels in a vertex shader needs a fallback and a cap.
  `tools/glshot/far_building_shot.gd` renders a row of buildings near and far from one camera,
  `far_pair.py` compares them building by building; `tools/far_census.gd` counts the far city and
  the LOD ring and times their build (`FAR_CODED=0|1`). The old path (no code) still draws the
  replica houses, estates, slabs and plates: its window grid sampled with a view-direction offset,
  per-room brightness, slab-edge bands, reveal shading and a vertical gradient.
- **Four measurement traps, each of which has already cost a session.** All fail by reporting
  success, which is the worst way to fail.
  1. **Godot serves a CACHED import of a `.glb`.** Rebuild a model, render it, and you are
     looking at the *old* file. Run `godot --headless --path . --import` between writing the
     `.glb` and rendering it, every time. A shot script that prints the model's AABB catches it:
     if that does not match what the generator just printed, the render is stale.
  2. **`--headless` is the dummy rendering server**, where every `Performance` monitor reads
     exactly zero - `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, draw calls, objects, all of them. A
     geometry change of any size measures as no change at all. `MultiMesh.get_instance_transform()`
     is the same trap: it returns identity under `--headless`, so a check that reads instance
     transforms back out measures nothing and reports a clean bill of health (and a MultiMesh's
     box is empty there, and its `buffer` reads back empty). It does PARSE shaders, though: a
     Godot shader-language error prints `SHADER ERROR` on load even headless, which
     `tools/shader_check.gd` uses as a ten-second compile check (GPU-side GLSL errors still need
     a real renderer).
  3. **The renderer's triangle counter does not count MultiMesh instances the same way twice.**
     Compatibility adds a surface that HAS LODs once per draw call, whatever its instance count,
     and a surface with NO LODs once per instance (`rasterizer_scene_gles3.cpp`,
     `_fill_render_list`). So every LOD'd batch - trees, palms, street props - counts as ONE
     instance in `GEO` / `SPLIT` / the HUD, and a change that gives a surface its first LOD, or
     takes its last one away, moves the count by the batch's instance count while the GPU does
     the same work (Forward+ does the same). It cost the tree-LOD pass (HANDOFF 9af) a false
     +2.5 M on the freeway bookmark; the tree ladders now end every surface with a copy of its
     last level at an edge nothing reaches (`FoliageLod.COUNTER_EDGE`) so they count like
     every other LOD'd batch. Compare foliage with `TREE_AB` on `still_shot.gd`, whose `TRUE`
     lines count every instance at the LOD the renderer picks (frustum-culled, shadows per
     cascade).
  4. **The two renderers disagree about colour space, and every opengl3 still hides it.**
     Forward+ (the Mac) decodes `source_color` uniforms - their defaults too - and `source_color`
     textures from sRGB, and lights in linear; Compatibility (the web, every opengl3 still)
     decodes nothing and lights the raw numbers. Plain uniforms' defaults, vertex colours,
     MultiMesh instance colours and `color` shader globals (`sky_tint`) arrive raw on both; a
     Color SET from script is decoded on Forward+ even into a plain uniform (a Vector3 is not).
     So a linear number in a `source_color` uniform is
     decoded TWICE on the Mac and looks right in every still: the horizon plane's whole palette
     was that (0.150 straw drew as 0.020, the far mountains near-black olive against the near
     hills), and so were the far boxes before them (`instance_color_is_srgb`). Any shader that does
     arithmetic on colours includes `shaders/color_space.gdshaderinc` and works in linear on both
     (`cs_in()` on every `source_color` input, plain uniforms written linear, `cs_out()` on
     ALBEDO / EMISSION / BACKLIGHT; the renderer is told at compile time by `CURRENT_RENDERER`):
     the hill ground, the shells, the plane and the far canopy do (docs/HANDOFF.md 9au has the
     probe table).
     Prove a colour change on Forward+ with a SMALL scene under lavapipe
     (`tools/glshot/hill_ground_shot.tscn GROUND=1 MASKS=1 NOFOG=1` for the hills; the city does
     not fit), never on the opengl3 stills alone.
  `tools/geo_count.gd` counts triangles, draw calls and objects for one frame and has the working
  invocation in its header: it must run under `--rendering-driver opengl3` with Xvfb, never
  `--headless`. `AB=Batch_sig_*,BatchShadow_sig_*` counts the same frozen frame again with the
  matching nodes hidden, so one kind of geometry's cost comes out of one run. Measure a geometry change before and after with it rather than arguing about it.
- Native screenshots without a browser: `tools/glshot/building_shot.gd` (one building),
  `tools/glshot/block_shot.tscn` (a few FULL city blocks alone, no far city: a block's ground and
  furniture) and `tools/glshot/city_shot.gd` (the city at a `--spawn`) render with the real
  OpenGL renderer under Xvfb + llvmpipe in ~20 s; usage lines in the files. Use these before the web harness.
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
