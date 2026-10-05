# Rando Game — Claude session guide

Read this file, `docs/GAME_PLAN.md` and `docs/HANDOFF.md` at the start of every session. The first
two are the source of truth; the handoff is the narrative (state, workflow, gotchas, next steps)
for a session on any account. Update all of them whenever a design decision changes. Every
session starts with no memory.

**State on 2026-10-05 (fleet wave 2):** `main` is integration-a (19 fleet branches) plus fixes,
gated green. A second fleet of 100 sessions is running (`fleet/brief`: BRIEF.md, tasks.tsv,
sessions.tsv; each on `wt/<slug>`, stills on `shots/<slug>`); integration-b's memory bug is fixed
on `wt/oom-fix`. Start at docs/HANDOFF.md section 0000000; the fleet tooling is in `tools/fleet/`.

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
tools/                 meshy.py, shrink_glb.py, smooth_normals.py, make_road_cars.py, make_more_cars.py, webshot/ (screenshot harness)
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
- City acoustics (2026-10-05, docs/HANDOFF.md "City acoustics"): **spaces, echoes, footsteps,
  the new sources**. Ambience's probe (eight wall rays, one up) now keeps the distances (`walls`,
  `ceiling`) and `space_for(scene)` weighs the listener's SPACE (`Ambience.SPACES`: open, street,
  canyon, alley - two facades within 16 m with the way along open -, underpass - a lid over 7 m -,
  garage - a lid under 4.5 m with walls round -, tunnel / trench - `LightRail` TUNNEL / TRENCH
  samples with the ear under the street -, channel - down in the LA River -, beach, hills);
  `reverb_for()` blends the presets onto the World reverb (wet, room, damping, pre-delay, its own
  high-pass; `Sfx.set_reverb()` takes the last two now). **Gunfire echo**: `echo_for()` turns the
  same rays into taps (the two nearest facades' round trips, then the flutter across; a tight
  cluster under a lid; the far bank in the channel; a rolling 0.45-2.9 s tail in the hills; nothing
  on the beach), `Sfx.set_echo()`; `Sfx.play()` of any `Sfx.ECHO_NAMES` (shot, shotgun,
  explosion, rocket) queues delayed copies of the very take on the **Echo bus** (low-pass + its
  own tail, sends to Game), placed toward what reflects, 3 dB down per doubling of the shot's
  distance, none past `ECHO_REACH`. No weapon code knows. **Footsteps** (`Footsteps`,
  `scripts/player/footsteps.gd`, one line in `Player._ready()`): a step is a foot coming down in
  the animation (each foot's height watched, a step in the bottom `contact_share` of its swing),
  the surface `surface_at()` (pure: a car or train is metal, the freeway / river / rail concrete,
  then the zone, the road vs the pavement ring of the block, parks, rec facilities, yards, a pier
  over the sea wood); Sfx `footstep_<surface>`. **Sources**: river (`amb_river`, an emitter on the
  centre line, loud only down in the channel), fountains (PLAZA blocks), playgrounds (Parks
  facilities, school hours), `construction` one-shots (working hours, by urban density); the
  traffic voice of a bus or truck is the `diesel_idle` loop; `VehicleAudio`
  (`scripts/vehicles/vehicle_audio.gd`) - a bus at a stop chimes, its doors hiss and it kneels
  (`BusFittings.set_doors()`), a light rail car carries a `TrainVoice` (synthesized `rail_motor`
  whine pitched by speed and loudest under effort, `rail_hum` off the wire, `rail_chime` at the
  doors); `ParkBall` plays `ball_dribble` on each floor hit. Clips are cut by
  `tools/city_audio.py` (sources and spans in docs/ASSETS.md); `tools/audio_probe.tscn` prints
  the space, reverb, echo taps, beds and footing at named places. Checks: `tests/audio_checks.gd`.
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
- Sky (2026-10-05, "an AAA sky"; HANDOFF 9ci): `sky.gdshader` plus `SkyExtras`
  (`scripts/world/sky_extras.gd`, made by DayNight as its child). **The cumulus are a volume on
  Forward+** (`cloud_volume` 1 once SkyExtras hands over the noise; `cloud_detail` on): a march
  through a slab `cloud_base` 1.45 km up, `cloud_depth` 1.7 km deep, in Godot's HALF-RES sky pass
  (`render_mode use_half_res_pass`, guarded by `CURRENT_RENDERER`; the full pass composites
  `HALF_RES_COLOR`, rgb premultiplied, a = transmittance), dithered per frame (TAA resolves it).
  Shape: a weather map (`assets/textures/sky/cloud_weather.png`, R where, G how tall) gives each
  column, a dome over a flat base that REMAPS a 64^3 Perlin-Worley (the noise is the cloud; the dome says how much survives, so margins and crowns are turrets), its margin torn by Worley fbm scaled to ~3 pixels at that distance, coverage moved by region (a 4x read of the map) (`cloud_shape3d.png`; both by
  `tools/sky/make_cloud_noise.py`, imported as Images and turned into textures by
  `SkyExtras.textures()`); light: four taps toward the sun (or the moon), three octaves of multiple
  scattering, a dual-lobe phase, powder, ambient from the sky above and the ground / city below;
  aerial haze by distance. Steps grow with distance and go fine (x0.3) after **backing up** on
  entering a cloud: a fixed count, or no back-up, drew every edge as a comb. Billows fade to a
  coarser copy where a pixel spans more than they do (the volume has no mips). Coverage over 0.8
  turns the columns into a flat stratus ceiling (weather). Compatibility and Forward+ below
  MEDIUM keep the painted 2D cumulus (`painted_cumulus()`), and the mid deck is thinned next to the
  volume. Cost on lavapipe, 1280x720 sky-only: +0 to +4 % of the frame (`tools/sky/sky_shot.gd`
  BENCH, `SHADER=` the A/B). **Photographic shape** (HANDOFF 9cn): flat base cut at the
  condensation level with sideways-only billows near it, crown thinned so billows make turrets,
  warped footprints and downwind lean, a 4x-finer fragment population (`fcol`), three-octave
  torn edges and fractus; five-tap light march and an ambient occluded in dense cores. The half pass also carries the sky-space crepuscular rays
  (`sky_rays()`: eight weather fetches toward the sun; Forward+ only). **Contrails**: SkyExtras
  flies `contrail_jets` airliners straight across at 9-12 km (not AirTraffic's, which fly under
  1.5 km); a trail is ONE segment (head minus (heading x speed - wind) x age), passed as
  `trail_a/b/c` (camera-relative km), intersected with its height in the shader, spreading and
  fading over `trail_life`, sunlit after the street's sunset; `CONTRAILS=n` / `--contrails=n`.
  **The moon's date**: `DayNight.moon_age_days` (+ `day_count` + the hour) puts the moon age /
  29.53 of a day behind the sun, so phases come from the date (`--moonage=` / `?moonage=`); its
  light energy scales with the phase (unchanged at the default gibbous). The face: maria as the
  near side's seas, crater relief lit by the real sun direction, Tycho's rays, Lommel-Seeliger
  shading, earthshine on a crescent; it lights the night cloud edges (the march's key light).
  **Night**: three star layers, round antialiased points, thinned by `sky_dark` (the city round
  the camera) and washed out under the light dome and round a bright moon; the milky way only
  from a dark sky. **The light dome** (`city_glow`, `city_dir`, `city_wrap`): SkyExtras surveys
  the map's zones on three rings round the camera every 1.5 s (`_survey()`) and pulls the dome
  toward downtown; orange on the horizon, lighting the cloud bases, `lamp_factor`-driven, brighter
  under overcast. Look in seconds with `tools/sky/sky_shot.gd` (the city's Environment and
  DayNight, no city; HOUR, YAW, PITCH, MOONAGE, COVERAGE, CONTRAILS, DOME, DETAIL=0 the painted
  path, BENCH). Checks: `tests/sky_checks.gd`.
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
- Los Angeles weather (2026-10-05, "beyond clear / overcast / rain / storm"): `Weather.State`
  gains MARINE ("June gloom") and SANTA_ANA (appended: every per-state table has six rows, the
  pause menu's chips are Auto + one per state in order, `--weather=marine|santa_ana`, aliases in
  `Weather.STATE_ALIASES`). The auto roll takes `odds_at(hour)`: the marine layer
  `marine_morning_gain` x overnight and in the morning, `marine_day_gain` x in the afternoon;
  both states last `*_length_gain` x longer. **Where the deck is is ONE number**,
  `LaWeather.edge_x()` (`scripts/world/la_weather.gd`, pure): the stratus covers everything WEST
  of it (`edge_offset(hour)` from the coast plus `edge_wobble(z)`, which
  `shaders/marine_layer.gdshader` mirrors - checked): overnight far inland, burning off inland
  first (downtown ~10:30, the beach ~12:00), an offshore bank all afternoon, rolling back in from
  16:30 (a wall ~600 m off the beach at 18:30, `bank_amount()`), over the city by 22:00.
  `MarineLayer` (Weather's child) draws the deck's underside (`DECK_BASE` 255 m) and top
  (`DECK_TOP` 520 m) as two camera-following planes and the evening bank as a ribbon stood on the
  edge in the vertex shader; three transparent draws, shadowless. Under the deck at the camera
  (`marine_here` = weight x cover x `under_deck(cam y)`) Weather adds cool haze and switches
  Godot's height fog to a NEGATIVE density from `FOG_START` (thicker going up: tower tops and
  hill crests fade into the deck), and DayNight's `marine` hook greys the sky, cuts the sun
  (`marine_sun_cut`), softens its shadows (`shadow_opacity`) and lifts the sky fill; above the
  deck it is a sunny day over a white sea. SANTA_ANA: `fog_by_state` ~0 (long views), DayNight's
  `santa_ana` hook (deep zenith, dusty horizon and fog, warm sun, no smog, fewer clouds),
  `wind_factor` + `santa_ana_wind` and the new `wind_lean` global (vec2, world XZ toward the
  south-west, `LaWeather.SANTA_ANA_DIR`) that `foliage.gdshader` / `foliage_tex.gdshader` add as a
  steady lean in model space; `SantaAnaFx` drives a litter-and-leaves pool and low dust round the
  player and a brush fire at `LaWeather.fire_site()` (a hash-picked crest of the front range):
  a CPUParticles3D smoke column in LOCAL coords (it rides the origin shift) on
  `shaders/brush_smoke.gdshader` (lit as balls by script colours, the fire's glow on its
  underside after dark), an upright additive glow and flame line (`shaders/fire_glow.gdshader`)
  and, on Forward+ desktop, an OmniLight on the slope. Purely visual. `HeatHaze`
  (`shaders/heat_haze.gdshader`): one full-screen quad reading the screen at render_priority MIN
  (the explosion shimmer's rule), displacing grazing rays past `near` m on hot afternoons
  (`Weather.heat`: clear, Santa Ana, a burnt-off marine day); built only on Forward+ desktop and
  shown only at HIGH / MEDIUM. `RoofRain`: one MultiMesh of crown splashes animated in GDScript on
  the roofs (`Vehicle._model_top_y` over the cabin) of the nearest cars while it rains. Checks:
  `tests/weather_la_checks.gd`; stills in docs/HANDOFF.md 9ck.
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
- The map (2026-10-05, "a minimap and a full-screen map with a GPS, GTA style"): the minimap and
  the full-screen map draw the same thing through `MapPainter` (`scripts/ui/map_painter.gd`,
  static; a `MapPainter.View` says where: world-to-canvas transform, pixels per metre, the
  canvas rotation): `draw_geo()` the ground plan (blocks by district and kind, rec-park and
  school facilities from `Parks.plan_for()`, streets as rects with casings - avenues are roads
  at least `avenue_width - 1` wide, so downtown's 18-22 m streets are streets - hill roads, the
  Esplanade, MacArthur's lake, the river, runways, piers, freeways and their ramps, the Coral
  Line solid in the open and dashed underground), `draw_marks()` what stays upright and screen
  sized (freeway shields with `FreewayKit.route_number()`, rail stations, landmark glyphs by
  `GLYPHS` with names, district names and street names on the full map), then the GPS route,
  units (police and `emergency_unit` blips) and the player arrow. Widths are metres with a floor
  in pixels (`View.w()`). The mountains and the sea under it are `shaders/map_relief.gdshader` on
  a ColorRect, painted from the horizon plane's own bake textures (`relief_material()` reads
  them off CityStreamer's `_ground_material`): hill shading, 100 m contours, sand, surf. The
  blocks come from `MapData` (`scripts/ui/map_data.gd`, `MapData.of(plan)`): the basin's land
  blocks and their two roads as records with a 500 m cell index, built a slice a frame by the
  HUD from load (`warm()`, ~1 s in all), `ensure_rect()` for the minimap's own neighbourhood
  first; it rolls nothing. **Trap: a PackedInt32Array in a Dictionary is a value**, appending
  to `dict[k]` appends to a copy (the first index was empty). `WorldMap`
  (`scripts/ui/world_map.gd`, a CanvasLayer at 4 that DebugHud adds, group `world_map`) is the
  `map` action (M / pad Back; respawn's pad button moved to L3): it pauses the game, draws the
  plan ONCE into a Node2D in world metres that pan and zoom only move (redrawn when the zoom
  moves 35 % or the view leaves what was drawn), the marks as a screen overlay, and glass
  panels (`glass_hud.gdshader` mode 1) for the title, the legend and the controls. Drag / wheel
  / click (stick / triggers / A) pan, zoom and set or clear the waypoint. The waypoint lives
  there map open or not: `GpsRoute` (`scripts/ui/gps_route.gd`: A* on a binary heap over the
  intersection grid, edges `StreetRoute.drivable()` and `CityPlan.road_open()`, avenues at
  `AVENUE_COST`, both ends snapped to the nearest open stretch and entering at either end of it;
  time-sliced, `route_budget_us` a frame), recomputed past `off_route` m, cleared within
  `arrive` m; and a beacon in the world (`shaders/waypoint_beacon.gdshader`: an additive,
  fog-free beam and ground ring, widened with distance; a Node3D under the CanvasLayer placed
  from true world coordinates each frame, so origin shifts never touch it). Stills:
  `tools/minimap/map_shot.gd` (`SHOTS=mini;map:x,z,ppm;beacon`, `WAYPOINT=`); probe:
  `tools/minimap/probe.gd`; checks: `tests/minimap_checks.gd`.
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
- Photo mode (2026-10-05, `PhotoMode`, `scripts/ui/photo_mode.gd`, a CanvasLayer (6) the pause
  menu adds beside itself in the city scene): `photo_mode` (P / right stick click) pauses the tree
  AND sets `Engine.time_scale` 0 - the render step is scaled by it, so shader TIME stops too
  (clouds, water, sway, grain hold) - re-set every frame at `process_priority` 1000 because the
  weapon wheel puts time back to 1 every frame the tree is paused. It never opens over the pause
  menu (`can_open()`: not while paused) and eats Esc / P itself in `_input`. Its OWN Camera3D
  (the camera in force copied, attributes duplicated), so its depth of field (near + far round
  `_focus`, width 3.5 % of the distance per f-stop; Forward+ only, the section hidden on
  Compatibility) and `exposure_multiplier` never touch the player's CameraPost. Free flight on
  the REAL clock (WASD / left stick, Q / E or triggers, Z / C or bumpers roll, Shift / Alt,
  right mouse held to look), clamped to `max_radius` of the player and above
  `ground_height_at()`. Panel (`shaders/photo_panel.gdshader`, screen-mip glass): FOV, roll,
  speed, DOF, exposure, the hour (`DayNight._apply()`), the weather (`force_state()` + a
  `weather_settle_seconds` run with the Weather node ALWAYS and time back at 1, so rain fills
  the air), filters (`GRADES`: the scene's own look LUT re-written per channel by
  `grade_texture()` plus `adjustment_saturation`; Noir / Mono are saturation 0), CityStreamer's
  Vignette layer's strength and grain, letterbox bars (part of the photo), hide the player.
  TAKE PHOTO hides the panel two frames, reads the root viewport back and saves a PNG to
  Pictures/Rando Game (user://photos fallback; `JavaScriptBridge.download_buffer` on the web).
  Leaving restores the snapshot: camera, time scale, pause, hour, Weather's `WEATHER_KEYS` and
  process mode, the env's adjustment fields, vignette / grain, player visibility, every HUD
  layer it hid (all CanvasLayers 0..127; < 0 is part of the picture). Stills:
  `tools/glshot/photo_shot.gd` (`ROOM=1` the test room for a Forward+ DOF shot); checks:
  `tests/photo_mode_checks.gd`.
- Input actions live in `project.godot` under `[input]`. Current actions: `move_forward/back/left/right`,
  `jump`, `boost` (Shift / gamepad B), `look_left/right/up/down` (right stick), `fire`, `alt_fire`,
  `next_weapon`, `prev_weapon` (mouse wheel only), `weapon_1..3`, `weapon_wheel` (Tab / gamepad
  LB: a quick LB tap is still "previous weapon", see the weapon wheel note), `interact` (E / gamepad Y),
  `respawn`, `toggle_mouse`, `toggle_hud`, `photo_mode` (P / right stick click). Add new actions there. There is no sprint; boost replaced it. In a
  `respawn`, `toggle_mouse`, `toggle_hud`, `map` (M / pad Back). Add new actions there. There is no sprint; boost replaced it. In a
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
- Light rail (2026-10-04, "a light rail line, like LA Metro's, with its own original name, colour
  and livery"): the **Coral Line** of the invented **Basin Metro** (coral `LightRail.LINE_COLOR`,
  bullet "C"). **The line is a DATA TABLE** (`LightRail`, `scripts/world/light_rail.gd`: `ROUTE`,
  `PORTAL`, `STATIONS`, the speeds and timetable numbers), resolved once per plan
  (`LightRail.of(plan)`, cached; `RAIL=0` in the environment turns it off): downtown it is the real
  Flower St corridor at 1:1 (`DowntownReal`) - underground from a terminus at 7th St, a portal
  ramp in the median south of 11th St (`PORTAL.daylight`), at grade down the middle of Flower
  past Pico, then onto an aerial structure that climbs over the 10, curves west (radius 28 m) onto
  the seeded boulevard that plays Exposition (the first AXIS_Z road south of `turn.south_of` at
  least `min_width` wide: River Blvd on the default seed), crosses over the 110 and the 105 on the
  structure, comes down to grade and runs down the boulevard's median to a terminus in the beach
  town. Samples every `STEP` 2 m: `pts`, `dirs`, `run` (s), `rail` (rail top), `street`, `half`
  (half the track spacing: 2.1, spread round each island platform), `mode` (TUNNEL, TRENCH, GRADE,
  AERIAL). **The structure is the upper envelope of MAX_GRADE (5.8 %) cones** from every point it
  must clear (each freeway deck crossed at grade, `AERIAL_CLEAR` over the deck top, across the
  deck's whole width however oblique) and from each aerial station (held level over the
  platform), eased, never under the street - grade-limited by construction, like the freeway's
  `_clear_ground()`. Stations: `name` fixed or "<street> / <nearest crossing road>"; an at-grade
  one is slid into the nearest block that holds the platform and its ramps clear of the crosswalks
  (`_fit_in_block()`). Crossings: every junction the line crosses at grade (`crossings`: node,
  axis of the road crossed, gates outside downtown, signal pre-emption inside). Poles every
  `POLE_SPACING`, slid off junctions (`poles`, `span_at()`). Queries: `sample(s)`,
  `track_point(s, side)` (right-hand running: a train running +s uses side +1), `indices_in(rect)`
  (segments by midpoint, built once), `street_rail(axis, index)`, `blocks_rect()` (lots keep off
  the structure: `CityChunk._lot_under_freeway()` asks it), `cut_rects()` / `cuts_in()` (the
  trench: `CityChunk._road_slab()` lays the road round it in pieces and `_mark_road()` paints
  nothing over it). **The timetable is worked out, never ticked**: per direction a trip of
  (time, nose s) from the speed limits (`_limit()`: tunnel, trench, street downtown and out, the
  structure, the curve) by a forward accelerate / backward brake pass, `DWELL` at each station and
  `TURNAROUND` at the start; the fleet fills the round trip at about `TARGET_HEADWAY` and the
  two directions' phases make the train that arrives at a terminus the one that leaves it
  (double-ended cars, the pantographs on the ends that swap). `trains_at(clock)` (id, dir, s, v,
  dwell, doors), `crossing_state()` / `crossing_phase()` (seconds closed, or minus seconds open:
  the gates are posed from it), `clock_at_station()` / `clock_at_crossing()` / `clock_at_s()`
  (tests and stills). `LightRail.clock` is the shared clock; `LightRail.closed` the crossings closed
  this tick (node -> axis of the road stopped). **`LightRailKit`** (`scripts/world/light_rail_kit.gd`,
  extends FreewayKit for its tri/quad/box/prism/letters and its structure, paint and pool
  materials; `CityChunk._build_light_rail()`, a step after the freeway, never in capture mode):
  at grade a concrete trackway a hair over the asphalt with the rails' heads and flangeways
  flush in it; the trench (U-walls with a parapet, a headwall and a dark bore at the mouth, wall
  collision); the box-girder structure with parapets, a ballast bed, concrete sleepers and RAIL
  PROFILES (`RAIL_PROFILE`, a 115 lb section, FULL only), round columns with hammerhead caps every
  `COLUMN_SPACING` (never in a junction or over a freeway: the span grows), deck collision;
  centre poles with cantilevers, stays and registration arms, the messenger sagging between
  poles, droppers and the contact wire staggered +-0.2 m pole to pole (FULL); island platforms
  (tactile edges, ramps to the crosswalks with handrails, or a lift tower on the structure), a
  canopy on a row of columns with a coral band and lit strips, benches, ticket machines, a lit map
  case, a lit name pylon and hanging name signs (lettering in the paint mesh), light pools; the
  underground terminus as two stair kiosks in Flower's median; level crossing masts (flasher
  hoods, crossbuck, bell, mechanism) with a `RailGate` node each (`scripts/world/rail_gate.gd`:
  the striped arm on its pivot, its lamps and the alternating flashers - posed from the phase,
  arm down `PRE_FLASH` after the lamps start, over `ARM_SECONDS`); traction substations under the
  structure; and `RailRider`s waiting on the platform (`scripts/npc/rail_rider.gd`, a Pedestrian
  that drifts along the island and mostly stands, on the platform's deck height, in the crowd
  cap). Three meshes a chunk (RailStructure, RailSigns, RailGlow) plus RailBody and the gates; LOD
  chunks keep the structure, the trackway, poles as boxes, platforms and canopies, no wires.
  **`LightRailSystem`** (`scripts/world/light_rail_system.gd`, the `LightRail` Node3D in city.tscn)
  advances the clock each physics tick (`RAIL_HOLD=1` holds it; `RAIL_AT=<station>:<dir>[:<s>]`,
  `RAIL_CROSS=<crossing>:<dir>[:<s before>]`, `RAIL_S=<s>:<dir>` set it for stills) and works out
  the rest: the nearest `max_detailed` trains within `detail_range` are pooled `LightRailTrain`s
  (`scripts/vehicles/light_rail_train.gd`: two cars of two sections of `assets/models/light_rail_car.glb`
  from `tools/make_light_rail.py`, Blender headless - see its header for the node and slot
  contract - each section a `RailSection` AnimatableBody3D on the props layer, mask 0, laid on its
  two bogie pivots by `section_world()`, bogies turned to the track, the platform-side doors
  (the train's left) sliding open while it dwells, the lead cab's headlights, display and a
  SpotLight3D on Forward+, the rear's tail lights, windows on `shaders/lrv_glass.gdshader` (the
  saloon traced in model space: seats, ceiling strip, far windows; emitted mirror), the interior
  box on `lrv_interior.gdshader`, a rolling loop); the rest within `far_range` are lit boxes in one
  MultiMesh (`lrv_far.gdshader`, windows glowing after dark); trains in the tunnel are drawn by
  nobody. It closes the crossings near the player (`LightRail.closed`, which TrafficManager's stop
  rule reads beside the signals - `LightRail.crossing_closed(node, axis)`; and `_lane_offset()` /
  `place_car()` keep a rail street's traffic to its outer lane), poses every `RailGate`, rings a
  bell at the nearest closed ones, sounds the horn at a player ahead and the gong before a
  crossing, sends waiting riders to the open doors and lets others off (`_passengers()`), knocks
  down whoever stands in front of a moving train (the player launched and hurt; pedestrians
  knocked, never the player's crime: `Police.innocent`), and draws the line itself past the
  streamed chunks (`_build_far_line()`, `shaders/light_rail_far_line.gdshader`, dithered in from
  `far_line_start`; it is not a Skyline capture, because the line is not a block). Weapons hit a
  train like anything with `take_hit()`; WeaponFX calls the `rail_vehicle` group metal (sparks,
  the ping, holes parented to the section); it keeps running. Sfx `rail_bell`, `rail_horn`,
  `rail_gong`, `rail_roll`. Probe: `tools/light_rail/probe.gd` prints the line (modes, stations,
  crossings, flyovers, the timetable); `tools/light_rail/compile.gd` compiles the scripts in
  seconds. Checks: `tests/light_rail_checks.gd`. Known gaps: police cruisers still drive lane 0
  (over the trackway) on a rail street; the player can stand on the invisible GroundBody plane in
  the trench.
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
- What a blast leaves behind (2026-10-05, fleet task "explosions", docs/HANDOFF.md, section at
  the end): `Explosion.blast()` ends with ONE call, `BlastAftermath.blast()`
  (`scripts/weapons/blast_aftermath.gd`): a CRATER where it hit the ground (generated albedo +
  normal maps, `crater_textures()`; a Decal on Forward+, a lit cut-out quad on Compatibility; a
  ring of broken asphalt slabs heaved up round it, one MultiMesh; `crater_seconds` 300,
  `max_craters`), RUBBLE (RigidBody3D chunks, PhysicsBudget debris for `rubble_seconds` 180,
  `max_rubble`), a low dust wave out along the ground, dust shaken off the roofs round it (rays
  from above), leaves torn off the nearest trees (`leaf_burst()`), then `TreeFire.blast()` and
  `CarAlarm.blast()`. A car's own blast (`exclude` a Vehicle) scorches but digs no pit.
  **Trees burn**: `TreeFire` (`scripts/world/tree_fire.gd`) - every FULL chunk hands its
  `tree_<n>` / `palm_<n>` batch instances over around `_batch.build()` (`collect()` before,
  `attach()` after: two lines in CityChunk), so it knows every tree near the player with no
  physics shape. A blast lights crowns in reach, a burning car (CarDamage._burning, polled) an
  overhanging crown, a burning tree its neighbours (`spread_*`); `max_burning` 8. A burning
  crown is the car fire's material scaled up (tongues, billows, burning bits falling, embers down
  the wind, black smoke, a flickering light on desktop, `fire_loop`). At `char_share` of the burn,
  under the flames, the instance is hidden (`MultiMeshBatch.hide_instance`) and drawn again from
  a CHARRED copy in the chunk (`Charred_<key>`, `charred_mesh()`: the same mesh and LODs with
  burnt materials - palms through `foliage.gdshader`'s `burnt` uniform, fronds burnt back to ribs;
  street trees' leaves thinned by foliage_tex's own `thin_max` with the instance's custom.x 1,
  bark x0.15). `WorldState.charred` keeps it across rebuilds (cleared with the destruction).
  **Smoke columns**: TreeFire's node (one, under the scene root) clusters the fires every second;
  a cluster of `column_weight` (a tree 2, a palm 1.5, a burning car 1) gets a `SmokeColumn`
  (`scripts/world/smoke_column.gd` + `shaders/smoke_column.gdshader`): ONE mesh of 56 quads all
  placed in the vertex shader from TIME, rising 150-420 m, leaning with Weather's `rain_wind`, lit
  by hand (sun, sky, the city's glow at night, the fire on its foot), `max_columns` 4.
  **Car alarms**: `CarAlarm` (`scripts/vehicles/car_alarm.gd`, a node made on the car when it goes
  off): an empty parked car (`alarm_share` of them, a hash) near a blast or hit itself
  (`Vehicle.take_hit()` -> `on_hit()`) sounds one of three real CC0 recordings (Sfx `car_alarm`)
  for 24-46 s with its hazards (`Vehicle.alarm_left` -> `lights_running()` and `light_signal` 2),
  staggered by distance, `max_alarms` 7. A/B: `TREE_FIRE=0`, `BLAST_AFTERMATH=0`,
  `CAR_ALARMS=0` in the environment. Stills: `AFTERMATH=palms|burning|charred|column|crater` on
  `still_shot.gd` (`tools/glshot/aftermath_stage.gd`). Checks: `tests/explosion_aftermath_checks.gd`.
- Building damage (2026-10-05, docs/HANDOFF.md 9cf): `BuildingDamage`
  (`scripts/world/building_damage.gd`) keeps up to `MAX_RECORDS` (32) records per building in
  `WorldState.building_damage` (key: seed and lot) - a point in the building's own space and a kind
  (CRACK, SHATTER, BLAST, HOLE, POCK) with a radius in `w` (kind * 100 + radius) - and writes them to
  the facade material (`damage[32]`, `damage_count`); `shaders/building_damage.gdshaderinc` draws
  them in `building.gdshader` (a pane's state from its own cell centre in model space, so boxes and
  the towers' `uv_facade` walls alike; holes traced as a burnt room behind a broken edge; soot;
  scars). `damage_count` 0 is one branch. A Building's facade material is its own; a tower's is
  shared, so a damaged tower's detailed copy gets surface-override copies (never write the shared
  one). Rims (`DamageRim`) and pavement glass (`DamageLitter`) are rebuilt from the records;
  `hole_radius()` / `record_seed()` are the include's lines (checked). Hooks: the rifle, shotgun
  and police rounds call `bullet()`, `Explosion.blast()` calls `blast()`, `Building._ready()`
  `restore()`, `LandmarkDowntown.build()` `restore_tower()`. Sanctuaries take none; curtain walls
  get no hole. `BUILDING_DAMAGE=0` is the A/B; stills `tools/glshot/damage_shot.gd`; checks
  `tests/building_damage_checks.gd`.
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
- Billboards (2026-10-04, VISUAL_ROADMAP #57, docs/HANDOFF.md 9bo): `Billboards`
  (`scripts/world/billboards.gd`, static) builds LA's outdoor advertising in code at real sizes:
  14 x 48 ft BULLETINS (`BULLETIN` 14.63 x 4.27 m) on I-beam legs on low (5-17 m) MIDTOWN,
  downtown-edge (skyline boost 0) and a few INDUSTRIAL roofs, facing the street or standing across
  it back to back (`ROOF_CHANCE`; a "strip" - `is_strip()`, a hash of a wide road - raises it to
  `STRIP_CHANCE` and makes `STRIP_DIGITAL` of them LED); 12 x 24 ft POSTERS where Building's
  roof-plant "billboard" roll stood (Building keeps every roll and adds `rolls.ad`, a hash, and
  draws nothing there when Billboards is on; FarBuilding's far box is the poster's); V-shaped
  MONOPOLES (`monopoles()`, pure: every `POLE_EVERY` deck segments by hash, `POLE_OFFSET` past the
  deck edge, only inside a corridor lot, both faces' ends clear of every deck and of any lot whose
  building reaches them, the faces `POLE_FACE_RISE` over the deck, the V's point toward the road);
  perforated vinyl SUPERGRAPHICS on the street face of GLASS / PANELS towers over
  `SUPER_MIN_HEIGHT`; and a double-sided lightbox in every bus shelter (`shelter_instance()`, one
  more instance of StreetDetail's bus-stop prop). Every face is a unit of a frame kit in its own
  frame (face plane z 0 facing +Z, bottom at y 0): trim, back sheet, stringers, uprights,
  X-bracing, grated catwalk and rail, lighting arms and fixtures (`frame_mesh()`), legs with a
  kicker and a ladder (`legs_mesh()`), a monopole's head, column (unit tube scaled) and base.
  Meshes are built once in code (`Billboards.Geo`, flat-shaded, clockwise front faces like
  FreewayKit's); ONE batch per kind per chunk (`bb_face_b/_p/_super`, `bb_frame_*`, `bb_legs_*`,
  `bb_head`, `bb_pole`, `bb_base`, `bb_shelter`). FULL builds plan in `on_building()` (called by
  `_build_lot()` after each Building, both levels) and `block_step()` (after Industrial's), and
  `commit()` places every board as a breakable `"billboard"` prop (collision on StreetProps) in a
  deferred step before the finish, so the block's props keep their ids; LOD chunks and the far
  city's capture lay each face as the roof plant's PANEL far box (`building_lod.gdshader`:
  custom.b 1 lit at night, 2 LED, 0.5 unlit) and a pole as a MAST. **The art** is ONE atlas,
  `assets/textures/billboards/billboard_ads.jpg` (2048 x 3072: 12 bulletins 1024 x 298, 12 posters
  512 x 256, 6 portraits 341 x 512), drawn by `tools/make_billboard_art.py` (PIL; twelve INVENTED
  campaigns, 555 phone numbers, SUNCREST AIR is the airport's sunset carrier; never a real brand),
  which also writes `scripts/world/billboard_table.gd` (each cell's linear mean, for the far
  boxes). `shaders/billboard_face.gdshader` wears it per instance (INSTANCE_CUSTOM: ad / 32,
  format / 4, wear, lit; exact as half floats): paper sheets a hair off register with seams, sun
  fade, torn patches showing the poster under them; the vinyl's sheen and edge pull; the mesh
  vinyl's perforations, welds and hem; the lightbox; LED slides (`slide_seconds`) with the dot
  pitch; the fixtures' night wash (`lit_energy` x `lamp_factor`). The steel is
  `shaders/billboard_steel.gdshader` (kind in the vertex alpha; lenses lit at night). Both work
  in linear (color_space). `BILLBOARDS=0` in the environment is the A/B; `BB_DEBUG=1` prints
  each face with an EYE; `tools/billboard_probe.tscn -- --spawn=x,z` counts the boards round a
  point. Checks: `tests/billboard_checks.gd`.
- Night lighting: the city has no real lights except the sun, so at night it was pitch black.
  Every street lamp now carries an `OmniLight3D` in the `lamp_light` group (FULL chunks only,
  distance-faded, no shadows) whose energy `DayNight` sets from `night_factor` on a 0.35 s tick
  - not only when the value changes, or lamps that streamed in since the last change stay dark -
  and `Quality` zeroes `DayNight.lamp_scale` below MEDIUM; while the level is zero the lights
  are HIDDEN (`DayNight.hide_dark_lamps`): a light at zero energy still costs every pixel it
  reaches (Forward+'s clusters, Compatibility's light lists). The level is
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
- More everyday bodies (2026-10-05, "the street stops repeating"; HANDOFF 9bq):
  `tools/make_more_cars.py` (imports `make_road_cars.py`; `blender -b --factory-startup -P
  tools/make_more_cars.py -- hatchback suv minivan taxi beater [--render]`, then `--import`) adds
  a 5-door compact HATCHBACK, a full-size three-row SUV (flat roof on the van's ninth anchor,
  chrome-barred grille, roof rails), a MINIVAN (sliding doors, their tracks under the rear glass),
  the TAXI (the sedan + a lit roof sign) and an older BEATER (a 1990s notchback), body types
  14-18. The four lofted bodies' details are DATA (`spec["d"]`) for one builder,
  `everyday_details()`; `overhangs()` / `remap()` rescale a spec's overhangs keeping the
  wheelbase. **Rolls**: `Vehicle.ROLL_MAP` maps the 0-999 roll in ranges, every old type keeping
  the START of its old range and giving its end to a new type (`BODY_ODDS` is the shares, the
  smoke test checks they agree), so a seed's parked car changes only where a new type took the
  slice; `random_car()` still spends the caller's rng exactly as before. **The taxi is not
  rolled**: a sedan whose look rolls a taxi job (`TAXI_SHARE`) becomes `BodyType.TAXI`, so every
  seed's taxi is still a taxi. Its `taxi_sign` slot wears `shaders/taxi_sign.gdshader` (shared,
  "TAXI" stroked front and back in mesh space from the box the run prints, lit by
  `lamp_factor`), `Vehicle._add_taxi_lettering()` puts the invented company BASIN CAB and a fleet
  number (`look_seed`, random_car()'s look) on the doors, and `_cabin_seats()` gives a traffic
  taxi a fare on the back bench (`TAXI_FARE_SHARE`): **CarCabin seat bit 2** (value 4, the bench
  behind the passenger, drawn in the passenger's colours; `person()` now takes its seat back's z).
  **The beater's wear**: geometry where it is the truth (a dent in the right rear door,
  `BEATER_DENT`; the right tail lamp in pieces with a broken corner and silver tape) and paint
  wear in `car_paint.gdshaderinc` (`wear`, `wear_door` / `_side` / `_color`: another car's door
  in the body MESH's space; `wear_primer`; the clear coat chalky on what faces the sky; rust low
  on the sills) set only on a BEATER (`Vehicle.BEATER_DOOR`, `BEATER_PRIMER`, `BEATER_PAINTS`,
  `BEATER_DOORS`); every other car skips it on `wear == 0`. SUV and minivan have privacy glass
  (`CarCabin.PRIVACY_BODIES`). `car_shot.gd --each=14,15,16,17,18` (the taxi comes in its livery;
  `LOOK=n` a beater's door / a taxi's number). Checks: `tests/more_cars_checks.gd`.
- Night aerial (2026-10-05, VISUAL_ROADMAP #62, docs/HANDOFF.md "The night aerial"): past the
  streamed range the city's night is worked out per pixel in the far shaders, never simulated
  or placed. **Traffic lights**: `shaders/far_traffic.gdshaderinc` (`traffic_lights()`,
  `street_traffic()`): cars in `FT_CELL` cells along a road's `s`, a hash per cell / lane decides
  one is there (`traffic_level(city_hour)`), moving with TIME; keep right (+x of +s moves +s);
  headlights toward the camera, tail lights away; drawn at least `FT_MIN_PX` and dimmed by less
  than their area, then the lane's mean once a car is under a couple of pixels (times
  `FT_FAR_BLOOM`). Worn by the far city's freeway decks (building_lod deck mode: Skyline puts
  the segment's start in the pattern's period in custom.g, `NightCity.PERIOD`, the route in
  .b), its block plates (along the TRUE world axis via the `origin_shift` global, so streams
  run on plate to plate), the LOD ground past `traffic_fade_start` (`far_ground.gdshader`, the
  road's width from the slab UV's derivatives like road.gdshader) and the LOD freeway decks
  (`FreewayKit._traffic_skin()`, an additive `FreewayTraffic` mesh on
  `shaders/far_traffic.gdshader`, faded in past TrafficManager's `freeway_range`; FULL decks
  have none). **Lamps**: `street_glow.gdshaderinc` adds `lamp_led()` / `lamp_ratio()` (sodium or
  LED per `LAMP_CELL` patch of true world, an integer roll, LED likelier near `LAMP_CENTRE`) and
  `street_lamp_heads()` (the heads as points where the pools are); the far plates and LOD ground
  multiply their glow by `far_glow_gain` and hold junction squares at `junction_glow` (a flat
  orange tile otherwise); the near lamps' OmniLight3D and pool colours come from
  `NightCity.lamp_light()` / `pool_color()`, the same roll in GDScript (`tests/night_city_checks.gd`
  holds it bit-exact). **Hours**: DayNight publishes `city_hour`; `traffic_level()` and
  `window_hour_scale()` (window_lights.gdshaderinc, scales every building's lit ratio near and
  far alike) are key tables mirrored by `NightCity.LEVEL_KEYS` / `WINDOW_KEYS`. Far roof masts'
  beacons flash on their own phase (building_lod, kind 2); near ones still burn steady. Stills:
  the four EYEs in the HANDOFF section.
- Big vehicles (2026-10-04, "buses and trucks in traffic"): `BigVehicles`
  (`scripts/vehicles/big_vehicles.gd`) - a 40 ft city bus (`BodyType.BUS`, the invented agency
  BASIN TRANSIT: white over a teal skirt), a cab-over box truck (`BOX_TRUCK`, invented fleets on
  the box) and a sleeper semi with a 53 ft dry van (`SEMI`). They ARE Vehicles (appended to
  `BodyType`, `BODY_ODDS` 0 so `random_car()` never rolls them; `BigVehicles.make(type, look)`
  builds one), so kinematic traffic, `drop_out_of_traffic()` / `take_hit()`, CarDamage, CarCabin
  glass and drivers, CarLights, PhysicsBudget and the pools all work unchanged; `tune()` scales
  mass (x5.5-11) with engine, brakes and suspension. Bodies: `tools/make_big_vehicles.py`
  (Blender; imports `make_road_cars.py` and reuses its loft, booleans, raycast parts, slots and
  far twin - run `blender -b --factory-startup -P tools/make_big_vehicles.py -- bus box_truck
  semi [--render]`, then `--import`; it prints the WHEEL_POSE / `_dims()` rows, the sign rects,
  the door hinges and the kingpin). Two slots more: `sign` (the bus's LED destination signs,
  `shaders/bus_sign.gdshader`, 5 x 7 glyphs from `LedScreen.GLYPHS`, one shared material per
  line and destination, `BigVehicles.sign_material()`) and `glass_door` (plain glass: a door
  leaf moves, the cabin trace works in the body's space). Extra nodes by name: `door_fa/fb/ra/rb`
  (each leaf's origin its hinge; `BusFittings` swings them open at a stop and kneels the body
  toward the kerb), `road_semi_trailer(_far)` (origin the kingpin; `Hitch` moves it onto a pivot
  and drags the trailer's axle toward the kingpin each tick - a tractrix - so a snapped junction
  turn swings it round behind, `MAX_ANGLE` 1.35 rad; physical, the rig straightens and is rigid;
  the trailer's collision is one box on the car moved with the pivot). **The body is centred and
  scaled without the trailer or the doors** (`_add_body_model()`); a semi's `_dims()` are the
  tractor's, with `kingpin`, `trailer_rear` (TrafficManager's `rear` extent: a car queues behind
  the END of the trailer) and `light_len` / `light_z` (the lamp mesh runs the whole rig). Wheels:
  WHEEL_POSE `axles` ([z, dual]) and `trailer_axles` go to `BigVehicles.add_wheels()`: truck
  wheels (`wheel_mesh()`: tyre, painted steel or polished disc with ten hand holes, hub, nuts;
  ~1.3k triangles near, a dual PAIR one mesh), each rig carrying its own near/far mesh at [6]/[7].
  `_dims()` `tyre_r` for these is the PHYSICS radius, set so a parked one stands where traffic
  stands it (car_shot.gd CONTACT). Lettering is a shared TextMesh per (name, size, colour) on each
  side, 55 m, not on the web. **Lines and stops are worked out, never placed**:
  `route_of(plan, axis, index)` (half the avenues, a hash), `block_stop(plan, axis, index, k,
  dir)` (where the nose stops on the block between crossings k and k+1, far side, about every
  other block), `in_stop_zone()` (the chunk's parked cars keep off the stop's kerb, after their
  rolls), `build_bus_stops()` (a shelter by the front door, from `_build_sidewalk_props`, no
  rng). TrafficManager: `_street_kind()` (on a line `BUS_SHARE_ON_ROUTE` are buses, in the kerb
  lane, no turns of their own, signs lit; box trucks and semis a few %, x3 in INDUSTRIAL),
  `_new_car(kind)` pools by kind, a bus treats its stop as a standing car, pulls `STOP_SHIFT`
  toward the kerb and dwells (`_bus_dwell`: doors, kneel, `DWELL`), freeway semis and box trucks
  in the slow lane, gaps counting `rear`. CarCabin draws a bus's rows of seat pairs and
  passengers (`bus_rows`, `interior_lamp`: the cabin lit after dark) and seats only its driver.
  Stills: `BIG=bus` (a bus at the stop nearest the camera, doors open, a pavement EYE), `BIG=semi
  BIG_ROUTE=110` on `still_shot.gd`, `STREET=queue STREET_BIG=10` (a box truck in the queue),
  `car_shot.gd --each=9,10,11` (`BUS_DOORS=1`). Checks: `tests/big_vehicle_checks.gd`.
- Emergency services (2026-10-04, "fire engines and ambulances that answer the chaos"; HANDOFF
  9bm). `Emergency` (`scripts/npc/emergency.gd`) is a node in `city.tscn` (group `emergency`),
  built like Police: every `scan_interval` it opens CALLS within `call_radius` of the player -
  `fire` (a car in `CarDamage._burning` / `_wrecks` still `on_fire()`: an engine), `blast`
  (`Explosion.blast_count` moved, no fire call within `merge_radius`: an engine stands by
  `stand_by_seconds`), `down` (a fresh `Ragdoll` in PhysicsBudget's debris group, not a responder's:
  an ambulance; its debris clock is pushed back while the call is open) - and after
  `response_delay` sends a unit (`send()`, caps `max_engines` / `max_ambulances`, pooled) out of
  the nearest fire station within `station_reach` (`FireStation.exit_lane()`, the bay doors roll
  up) or along a street out of sight like a cruiser. A wreck with an engine on the way is held
  burning (`CarDamage.hold_fire()`), or there would be nothing left to put out. **`EmergencyCar`**
  (`scripts/npc/emergency_car.gd`, extends Vehicle; body types FIRE_ENGINE 12 / AMBULANCE 13,
  `BODY_ODDS` 0, `BigVehicles.is_big()`) drives the lanes kinematically with PoliceCar's lane
  geometry and StreetRoute routing (the code is copied, not shared: PoliceCar carries the police's
  groups and crimes), siren on (`siren` wail for the engine plus a `fire_horn` blast every few
  seconds, `siren_yelp` for the ambulance) - TrafficManager's `_siren_list()` takes the group
  `emergency_unit` too, so traffic pulls over - and pulls up at `StreetRoute.kerb_stop()` stood off
  the scene (`engine_stand_off` 14 m, `ambulance_stand_off` 7 m), STILL kinematic (ON_SCENE), then
  `Emergency.deploy_crew()`. Hit, it goes physical like any car; leaving, it is put back on the
  nearest lane if it stands upright and still (`_back_to_lanes()`: wheels off BEFORE the freeze).
  Its warning lenses are the model's `beacon_red` / `beacon_white` slots on
  `shaders/emergency_lights.gdshader` (a wig-wag worked out from each lens's mesh-space position:
  left / right banks half a cycle apart, front / rear a quarter; red held to green 0.1 and 2.6x,
  or AgX turns it salmon), the `stripe` slot a retroreflective material, an OmniLight3D on the roof
  at night (desktop). **`EmergencyCrew`** (`scripts/npc/emergency_crew.gd`, extends Pedestrian, so
  shot / knocked / ragdolled and a crime like anyone, `responder` group, NOT `pedestrian`): GO ->
  WORK -> RETURN; jobs NOZZLE (stands `nozzle_distance` off the fire on the line from the pump
  panel, a hose laid as a tube mesh, `shaders/hose_water.gdshader` streaks on
  CPUParticles3D `particle_flag_align_y`, spray where it lands; `Emergency.water_on()` ->
  `CarDamage.douse()` -> `extinguish()` past `douse_seconds`: flames out, steam, the smoke goes
  pale and runs its course, a burning car is left SMOKING and a wreck stays a wreck), BACKUP, PUMP,
  PATIENT (kneels at the body with a bag for `treat_seconds`), STRETCHER (fetches the cot from the
  back, pushes it to the body, loads it - the ragdoll is freed, a blanketed patient lies on the cot -
  and wheels it back). Uniforms through the character shader's garment split
  (`uniform_material()`: turnout khaki, paramedic navy) on PoliceOfficer's rigs, plus the TRIM
  (2026-10-05, docs/HANDOFF.md 9bs): `EmergencyCrew.trim_mesh()` bakes, once per rig, where each
  vertex sits on the body (CUSTOM2: metres above the soles, metres along its arm or leg from the
  shoulder / hip - continuous over elbow and knee -, the limb code + the rig's height / 10, the
  upper segment's length + the limb's in cm; CUSTOM3: facing forward, facing out, metres off the
  midline, the trousers' waist), keeping the mesh's LODs (`_surface_lods()`, read back from the
  RenderingServer) and handing the welded middle / far bodies over unbaked; `character.gdshader`
  `uniform_kind` (1 turnout, 2 paramedic; 0 everyone else, who skip it) draws from it: turnout
  bulk (the coat stands `turnout_bulk` cm off the body and covers bare forearms), the lime /
  silver / lime triple trim round sleeves, chest, hem and shins - retroreflective at night,
  `lamp_factor` x a cone ahead of the camera x facing (`trim_retro`, `trim_reach`) -, a darker yoke
  and wristlets, knee patches, gloves; the paramedics' shoulder patch (original: a heartbeat trace,
  never a real emblem), placket, buttons, badge, cargo pockets and duty belt; black boots for both.
  The code is a `flat` varying: interpolated across a joint it passes through the codes between.
  An unbaked mesh (the headless check) gets the plain recolour. `crowd_lineup.gd CREW=fire|medic
  [NIGHT=1]` shows them in seconds. Kneel, hose
  and push are RoughSleeper-style aim tables solved per rig over the idle (`POSES`); a CharacterBody
  does not step, so a crew member blocked while moving steps up 0.34 m when there is room (kerbs).
  The helmet is **`FireHelmet`** (`scripts/npc/fire_helmet.gd`): a shell with a ridge, a duckbill
  brim and a brass-rimmed leather front shield built round each rig's head from CrowdHatTable
  (`CrowdHat.head_for()`), yellow (a white one for 1 in 8), hair hidden under it. A responder's
  ragdoll carries meta `responder` (never another call). **`FireStation`**
  (`scripts/world/fire_station.gd`, static): the map is cut into `CELL` 850 m squares, a hash of
  seed + cell says whether one has a station (`ODDS`) and where; the block there, if it is
  BUILDINGS in a station district (not the downtown core or a landmark's), gives up its biggest
  edge lot that is `MIN_LOT` deep and clear of the freeway - `CityChunk._build_lot()` asks
  `FireStation.claims()` after its corridor check and the pad roll, so no roll moves. FULL: a
  two-storey brick firehouse (one mesh, a surface per material), two sectional bay doors as their
  own nodes (`open_door()` tweens them up `DOOR_TIME`, holds, closes), a bay interior with lights,
  an apron and a ramp across the pavement to the kerb, "STATION nn" and the department's name
  (TextMesh), a flagpole, one collision box, the occluder; LOD / far city: one `lod_box` (old path,
  rotated). Names are original (`RANDO CITY FIRE DEPT`, `RCFD` on the cab doors, `BASIN MEDICAL` on
  the box): never a real department's or company's. Bodies: `tools/make_emergency_vehicles.py`
  (Blender, imports `make_big_vehicles.py`; `build/car_src/.../blender -b --factory-startup -P
  tools/make_emergency_vehicles.py -- fire_engine ambulance [--render]`, then `--import`); slots
  beyond the cars' are `beacon_red`, `beacon_white`, `stripe`, `satin` (roll-ups, pump panel,
  ladders, diamond plate: chrome would mirror them) and `hose`; kerb side +X. Stills:
  `EMERGENCY=fire|hose|medic|station` on `still_shot.gd` (`Emergency.stage_for_shot()`: a wreck
  burning on the kerb ahead of the camera, an engine with its hose on, an ambulance at a body,
  crews posed at once); close-ups `car_shot.gd --each=12,13,1` (`LIGHTS=0` dark). Checks:
  `tests/emergency_checks.gd` (the smoke test keeps `Emergency.enabled` off elsewhere). The bus's
  windscreen (same pass): `CarCabin.BUS_DAYLIGHT` lights a bus's traced cabin 2.2x (and lets more of
  it through the glass) and a bus's far twin starts at 60 m (`BigVehicles.tune()`), since from the
  pavement at noon its front read as a black slab.
- Police stations (2026-10-05, "police stations the cruisers come out of"; HANDOFF 9bz):
  `PoliceStation` (`scripts/world/police_station.gd`, static). WHERE is worked out like
  FireStation's, never placed: `CELL` 1500 m squares, a hash of seed + cell, up to `TRIES` hashed
  points; the first block that is MIDTOWN or downtown off its tower core (skyline boost < 0.3),
  BUILDINGS, not a landmark's, a park's, the river's or the fire station's, gives a SITE: a centred
  run of its lot-grid cells along one street (`SITE_TARGET` 56 x 50 m, at least `SITE_MIN`, ground
  within `MAX_RELIEF`, clear of the freeways, every cell's lot present). Every lot whose centre is
  in the site is claimed (`claims()`, asked by `CityChunk._build_lot()` after FireStation's - the
  pad roll is made either way) and the first of them in lots() order builds it (`build_lot()`); the
  headquarters (`hq()`) is the whole block grid-south of City Hall, eight storeys. `layout(L, D)` is
  the plan in the site's street frame (Industrial.frame: u along the street, v in from it):
  forecourt `sb` deep, the building, a DRIVE_W driveway at the high-u end with the sliding gate on
  the street fence line, the car park behind (`pv0..pv1`, one or two stall rows). FULL: ONE mesh
  (a surface per material, `PoliceStation.Geo`: precast concrete with glass bands, spandrels and
  full-height fins, `shaders/police_station_glass.gdshader` lit window by window after dark, a
  glazed lobby pavilion lit all night under a cantilevered canopy with the name band, a stair tower,
  roof plant, flagpoles, bollards, planters, the monument sign, palisade and barbed chain-link, the
  fuel island, the sally port, floodlight poles, CCTV, the lattice radio mast with its blinking
  beacon), the `Gate` node (`open_gate()` tweens it along behind the palisade; its AnimatableBody
  moves with it), the parked cruisers as ONE MultiMesh of the sedan's far twin in the livery
  (`cruiser_mesh()`, the car_paint shader with stripe_mode 5) plus their dark light bars, the
  floodlit pools, two `lamp_light` omnis (not on the web), TextMesh lettering (not on the web), one
  collision body. LOD and the far city: the building and the mast as `lod_box`es. Names are
  invented (`DEPT` RANDO CITY POLICE, `DIVISIONS`). **Dispatch** (`Police`): within
  `station_reach` (520 m) of the player, `_dispatch()` sends the cruiser out of the nearest
  station's gate (`_dispatch_from_station()`: it starts in the car park, the gate opens, it is
  driven along `PoliceStation.exit_path()` by `_tick_drives()` with `PoliceCar.scripted` set - its
  own driving off - then dispatches from the lane like any other), one at a time per gate
  (`_gate_busy()`); a cruiser out of a station is not despawned short of `station_reach + 150`. A
  recalled one (`board()` with no stars) heads for the nearest station (`_home_for()`), turns in
  along `enter_path()` once level with the gate (`_maybe_enter()`; a physical one is stripped and
  frozen first, wheels before the freeze) and is pooled behind the gate. Parked cars keep off the
  kerb in front of a gate (`keeps_clear()`). `POLICE_STATIONS=0` in the environment turns them off
  (the A/B). Stills: `tools/glshot/block_shot.tscn` EYEs and `tools/glshot/police_station_shot.gd`
  (the gate sequence); checks: `tests/police_station_checks.gd`.
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
  **Kerbs** (`Kerbs`, `scripts/world/kerbs.gd`, 2026-10-05): a FULL block's pavement is an
  inner slab (`_block_surface`) plus a ring `RING` 2.6 m wide built by Kerbs in the pavement's own
  material with one trimesh collision: corner ramps cut in line with the crosswalks (dome pads),
  driveway aprons where YardFill's drives meet the kerb, dirt tree wells, root-heaved slabs; then
  ONE marks mesh per 64 m tile (`shaders/kerb_marks.gdshader`: zone paint red / yellow / green /
  white / blue with stencils, house numbers in SUBURBS / BEACHTOWN, domes, dirt, the `tree_grate`
  batch's cast-iron grate, cracks). Built as steps after the pavement furniture; nothing is cut
  under an upright prop; red kerbs and aprons keep this chunk's own parked cars off
  (`blocks_parking()`); it replaces StreetDetail's `_kerb_paint` there. LOD and far keep the plain
  slab. Hash-seeded. `KERBS=0` is the A/B; probe `tools/kerbs/probe.tscn`; checks
  `tests/kerbs_checks.gd` (`tools/kerbs/checks_only.tscn` alone).
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
  **Nor are the houses boxes** (HouseKit + HouseBuild, 2026-10-04, docs/HANDOFF.md 9be; the house pass: every house lot in the suburbs and the
  beach town was a flat-roofed `Building` box with a storefront band). `HouseKit`
  (`scripts/world/house_kit.gd`) PLANS a Los Angeles house per lot - RANCH, SPANISH revival,
  CRAFTSMAN bungalow, MIDCENTURY, STUCCO_BOX, DINGBAT (the beach town's tuck-under apartment),
  cumulative odds per district (`SUBURB_STYLES`, `BEACH_STYLES`) - and `HouseBuild`
  (`scripts/world/house_build.gd`) builds it. **The plan is pure** (`plan_house(plan, bx, bz,
  lot, district)`: hashes of seed + lot, never a chunk or block rng): it is laid in the lot's
  yard frame (`YardFill.lot_front()` + `YardFill._frame()`: `u` along the street, `v` back from
  the front edge; the front of a wing is its low-v face) within setbacks (`SUBURB_FRONT` / `_BACK`
  / `_SIDE`, `BEACH_*`), as wings (main, garage, carport, a front `wing` whose roof runs back
  into the main roof, `roof_back`), a porch / stoop / canopy (`_fit_porch()` keeps it clear of
  the other wings), the garage door's span, the drive (`drive`, `drive_v`), the front door
  (`door_u`, `door_v`), chimney, vents, solar, a breeze-block screen, colours. YardFill reads
  the house (`HouseKit.yard_entry()`): the driveway runs from the kerb to the garage door, the
  front walk to the porch or stoop, the yard faces the way the house does; GroundCoverage and the
  smoke test ask the same plan. **Cells the lot grid leaves empty** (CityPlan's gap roll drops a
  cell under 6 m: two in five in the suburbs) get a house of their own on a synthetic lot
  (`HouseKit.extra_lots()`, hash-seeded, after every rolled lot; not on a landmark's square, the
  approach clear zone or the freeway's right of way). **FULL chunks**: every house of the chunk
  is ONE mesh per material (`HouseKit.MATS`: stucco `h_wall`, `h_siding` on
  `shaders/house_siding.gdshader` - lap / board and batten / stained tongue and groove by
  COLOR.a -, `h_brick`, `h_trim`, `h_door`, `h_metal`, `h_dark`, clay `h_roof` (ReplicaHouses'
  material, UV in metres), `h_shingle` on `shaders/house_shingle.gdshader` (courses, three-tab or
  laminated by COLOR.a, granules, streaks), `h_flat`, `glass` (`house_glass.gdshader`), `h_solar`,
  `h_breeze` on `shaders/house_breeze.gdshader`), built into per-chunk SurfaceTools during the
  lot steps and committed at the finish (`HouseKit.commit()`), collision on one `Houses`
  StaticBody3D. `HouseBuild._tri()` writes each triangle's flat normal and its tangent from the
  UVs itself: `generate_normals()` / `generate_tangents()` over a chunk's houses cost 10-30 ms in
  one step. Walls are cut round every opening (`_wall()`, ReplicaHouses' cell grid), arches fill
  their spandrels and follow the curve with the reveal (`_arch()`). **LOD chunks and the far
  city** (capture mode) get one `lod_box` per wing (window style 1, as ReplicaHouses') and, for a
  pitched wing, two tilted slabs in the roof colour (`CLAY_FAR` or the shingle) over a prism in
  the wall colour - a box turned 45 degrees about the ridge - that closes the gable ends, so the
  far city draws the roofscape with no code of its own. **Traps:** a slab must lie on its local X
  face (building_lod.gdshader paints any local +-Y face as a flat roof with plant on it), and its
  basis must be rotation times scale, never scale times rotation (a MultiMesh normal is not the
  inverse transpose, so a skewed box lights wrong). The suburbs' yards are YardFill's beach plan
  with `YardFill.SUBURB` odds; the block's own lawn is the lawn (lawn pieces are not laid there,
  the rest is laid at `PATH_LIFT` and added to `_lot_rects` so the blades keep off it); a
  suburban pool sits in the lawn on a concrete apron. The walk street is now worked out from the
  lot rects (`YardFill.walk_for()`, pure), so a house knows it fronts one before the block step.
  `HouseKit.enabled` false (the A/B; `HOUSES=0` on `still_shot.gd`) builds `Building` boxes on
  the house lots again. Checks: `tests/house_checks.gd`.
  **Nor is an industrial block** (`Industrial`, `scripts/world/industrial.gd` +
  `IndustrialKit`, `scripts/world/industrial_kit.gd`, 2026-10-04; INDUSTRIAL bare 40 % -> 0 %,
  docs/HANDOFF.md 9bh). East of the 110 down to the port (Vernon, the Alameda corridor) and east
  of Vignes (the Arts District, `Industrial.arts()`). A lot whose planned Building is a WAREHOUSE
  is built by Industrial instead (`build_lot()`, called by `_build_lot()` once the Building is set
  up; it frees it): a tilt-up concrete warehouse planned in the lot's street frame
  (`lot_plan()`: u along the street, v in from it; `lot_side()` faces it to the street it is
  deepest from) - panels with joints and reveals, an accent wainscot, a parapet and coping, a
  membrane roof with skylights and rooftop units, a glazed office corner with a canopy, and where
  the lot is `COURT_MIN_LOT` deep a TRUCK COURT in front: dock doors every `DOCK_PITCH` with seals,
  bumpers and dock lights (`lamp_factor` lit, light pools), trailers backed on (`TRAILER_ODDS`, a
  tractor on some), a concrete apron, stall stripes, chain-link with barbed wire and an open gate
  along the street; a shallow lot gets grade-level roll-up doors. In the Arts District 80 % are
  BRICK (steel multi-pane windows, lit lofts at night, no court: they stand at the back of the
  pavement) and street-facing walls carry MURALS (`MURAL_ARTS`; invented in the shader, abstract:
  never an artist's work, lettering or a brand); the Building lots there get brick finishes. Any
  other lot keeps its Building. `block_step()` (after YardFill's) lays the block's ground from
  `block_plan()`: every lot cell less its building is a court, apron, storage yard, drive strip or
  setback (`G_*`: cracked asphalt with weeds, concrete, gravel, dirt, weeds), some blocks get a RAIL
  SPUR between their two rows of lots (`spur()`: ballast and ties, rails, bumper stops, boxcars and
  tank cars, rail doors on the warehouses backing onto it), storage yards hold pallets, drums,
  bins, PortKit containers, a corrugated shed or storage tanks in a containment wall, now and then
  a water tower. Nothing of it stands under a freeway (`clear_of_freeway()`; downtown_checks holds
  every far box to that). **Plans are pure** (`lot_plan()`, `block_plan()`, `block_entries()`:
  GroundCoverage asks the same question, `FILL=yard` on `tools/lot_coverage.gd` is the before);
  every roll is a hash of seed + lot / block, never a chunk, block or Building rng. A FULL chunk
  is ONE ground mesh (`IndustrialGround`, `shaders/industrial_ground.gdshader`, kind in COLOR.r,
  no shadow) and ONE
  upright mesh (`IndustrialWalls`, `shaders/industrial_walls.gdshader`, kind in COLOR.a in 32nds,
  paint in COLOR.rgb as written, UV metres in the face's frame, UV2 = height, a per-box
  parameter) that also holds every prop - trailers, tractors, rail cars, pallets, drums, bins,
  tanks, the tower - written into it by `IndustrialKit.place()` (a batch per prop kind was 15-20
  batches and their shadow cascades a chunk); the light pools are one shadowless batch
  (`ind_pool`), containers PortKit's batch. LOD chunks and the far city get the warehouses, trailers, rail
  cars, tanks and the tower as plain `lod_box`es and the yards as ground slabs. The warehouses are
  in `StreetDetail._footprints()` (encampments and service drops see their walls) and the
  occluder. Both shaders work in display numbers (`disp()` / `to_lit()`, like YardFill's). A/B:
  `INDUSTRIAL=0` on `still_shot.gd`, `block_shot.tscn` and `tools/geo_count.gd`; build times:
  `tools/industrial_bench/industrial_bench.tscn`; checks: `tests/industrial_checks.gd`.
  **Nor is a park just a lawn** (`Parks`, `scripts/world/parks.gd` + `ParkKit`,
  `scripts/world/park_kit.gd`, 2026-10-04, docs/HANDOFF.md 9bn): LA from the air is stamped with
  diamonds, courts, fields, tracks and pools. Two block ROLES, rolled by `CityPlan.block()`
  through `Parks.role_for()` AFTER every other roll and override (a hash of seed + block, never the
  block rng): `"rec"` (`REC_ON_PARK` of the PARK blocks in SUBURBS / MIDTOWN / BEACHTOWN, and
  `REC_ON_BUILDINGS` of the BUILDINGS blocks: a rec park, kind PARK) and `"school"` (`SCHOOL_ODDS`
  of BUILDINGS blocks: the new `CityPlan.BlockKind.SCHOOL`). Either sets `block.grounds`, and
  `CityPlan.lots()` is then empty (so LOD, Skyline, AirTraffic, HouseKit see no buildings). Never on
  a site, beside one, under a freeway, near a landmark, the replica, the runway clear zone or
  downtown. **Plans are pure** (`rec_plan()` / `school_plan()` / `plan_for()`, cached in
  `Parks._cache`): facilities are axis-aligned rects at regulation size in a frame (`c`, `u` the
  long axis, `v` = (-u.y, u.x), `L` x `W`; `fp()` / `frect()`), packed by `_fit()` (bottom-left
  fill against the edges and what is placed). A rec park: a softball diamond in a corner (home in
  the corner, foul lines down the edges, 60 ft bases, fence 48-69 m), a soccer field, basketball
  and tennis courts, a playground, a rec centre, a 25 m pool, picnic shelters, a car park
  (LotFill's `_car_park`), a DG walking loop with trees, benches and light poles. A school:
  classroom wings with covered walkways and a drop-off loop along the front, a car park, and
  either (a long block, a HIGH school) a track sized to the block (`_track()`: 1.22 m lanes, 400 m
  when it fits, else the largest that does - most blocks give 300-390 m) round a football field
  (regulation or scaled) with goal posts, bleachers and a press box, or (an elementary school) a
  grass field, a playground, painted yard games, bungalows and a lunch shelter; a chain-link fence
  round the rest. **Drawn**: a FULL chunk's ground is ONE shadowless mesh (`ParkGround`,
  `shaders/park_ground.gdshader`, kind `G_*` in COLOR.r 16ths, the facility frame in UV, its
  numbers in UV2, its u axis in TANGENT) whose lines are drawn analytically and box-filtered;
  the pool is TRACED (the view ray refracted into a tiled tank, lane T-lines, caustics, absorbed
  to turquoise, the sky emitted by Fresnel, lane ropes); everything upright is ONE casting mesh
  (`ParkWalls`, `shaders/park_walls.gdshader`, kinds `ParkKit.K_*` in COLOR.a 32nds, written by
  IndustrialKit's box / cylinder writers); floodlights glow (`K_LAMP`, `lamp_factor`) and throw
  `park_pool` light pools (shadowless). LOD chunks and the far city's capture get the ground as
  slabs that PARTITION the site (`minus()`: never one slab over another) and the buildings and
  stands as `lod_box`es. **Trap:** the block's pavement slab is at SIDEWALK_TOP; anything below
  SIDEWALK_TOP + `LIFT` (0.05) is under it (the pool's water is 3.5 cm down, not 12). **People**:
  `ParkGoer` (`scripts/npc/park_goer.gd`, a Pedestrian kept to its facility: JOG laps of a track
  lane on an oval, LOOP the walking loop, PLAY pickup games, FIELD fielders, HANG the playground),
  `Parks.people_steps()`, under the crowd cap, `MAX_PEOPLE` a chunk; a `ParkBall` (scripted, no
  physics) dribbled and shot at the rim on a court with players. No children (no child rigs).
  `PARKS=0` in the environment is the A/B (before the plan is made). Checks:
  `tests/park_checks.gd`; coverage: `tools/lot_coverage.gd` rows `REC` / `SCHOOL`, kind `sport`.
  **Public schools** (`Schools`, `scripts/world/schools.gd` + `SchoolKit`,
  `scripts/world/school_kit.gd`, 2026-10-05, docs/HANDOFF.md 9ch): on top of Parks' campuses, a
  school per `Schools.CELL` (640 m) map cell from a hash of seed + cell (FireStation's approach,
  `TRIES` points a cell): `CityPlan.block()` hands each block it makes to `Schools.apply()` AFTER
  every roll and Parks' role, and the cell's decision (`decide()`, cached by seed) marks its blocks
  `BlockKind.SCHOOL` with grounds `"school_e"` / `"school_h"` (so `lots()` is empty). Only blocks
  whose centre is in the cell are ever asked for, with apply() off while a decision runs
  (`_deciding`), so nothing recurses and a block is decided before anyone sees it. Eligible: plain
  BUILDINGS or PARK blocks in SUBURBS / MIDTOWN / BEACHTOWN no one else claimed (Parks' role,
  sites, landmarks, the replica, the river, the freeway, the light rail, the approach). An
  ELEMENTARY school is one block (wings of 1-2 storeys with covered walkways, the office by the
  entry gate, a side wing with a primed end wall left for the murals pass, portables up on blocks
  with ramps, blacktop courts, yard games and a painted map (`Schools.G_MAP`, kind 13 in
  park_ground.gdshader), the lunch shelter, a play structure, a grass field with a kickball diamond
  and backstop, the marquee sign, the flagpole, chain-link); a HIGH school is a ROW of 2-3 blocks
  (`_row_fits()`: local, unpinned streets) whose streets between are CLOSED
  (`Schools.road_closed()` from `CityPlan.road_open()`, and a pavement slab across them from the
  chunk that owns the street) - the stadium (Parks' `_track()`, bleachers, press box, scoreboard,
  `SchoolKit.light_standard()`s lit on a game night, `pl.game_night`), two-storey classroom wings,
  the office, the auditorium with its fly tower, the gym, tennis, courts, a quad, a car park.
  Plans are PURE (`plan_for()` / `plan_for_school()`, laid in the site's street frame). A high
  school spans chunks: every ground piece is clipped to the chunk's owned rect (`_gp()`: the frame
  and so the painted lines carry across the cut) and every upright piece is built by the chunk its
  anchor is in. Ground and sports kit go into the Parks meshes (`ch._park`, committed by
  `Parks.commit()`), the buildings, signs, flag, scoreboard and light standards into ONE mesh a
  chunk (`SchoolWalls`, `shaders/school_walls.gdshader`: stucco, brick, T1-11, glass with a
  TRACED CLASSROOM behind every window - whiteboard, cork boards, desks, troffers, a blind per room
  - letters from `FreewayKit.text_geo()`, LED boards, the waving flag; window layout per wall face
  in UV2.y = style + 16 x bays, `SchoolKit.wall()`). LOD and the far city: slabs and far boxes.
  Names are invented (`SCHOOL_NAMES` or the front street's), mascots invented. **No children**:
  the campus is empty (the brief: crowd rigs scaled down are not children). **The school bus**:
  `BodyType.SCHOOL_BUS` (appended), a Type D built by `tools/make_school_bus.py` (Blender, on
  make_big_vehicles; `RANDO UNIFIED SCHOOL DISTRICT` in the model), parked in each school's loading
  zone as real Vehicles (`Schools.park_buses()`, `bus_spots()`; `keeps_clear()` keeps parked cars
  off it and off a closed street) and joining street traffic within `BUS_REACH` of a school during
  `BUS_HOURS` (`Schools.traffic_bus()` from `TrafficManager._street_kind()`, reusing its roll);
  CarCabin draws its rows empty. `SCHOOLS=0` in the environment is the A/B; probe
  `tools/schools/probe.gd` (every school, its facilities, bus spots and an EYE); checks
  `tests/schools_checks.gd`.
  Shopping plazas, big-box stores, fast-food and gas-station pads are `Commercial`
  (`scripts/world/commercial.gd`); block kinds `MALL` and `BIGBOX` and the `pads` odds live in
  `CityPlan.DISTRICTS`. Shop names are original, never brands.
- Service alleys (2026-10-05, docs/HANDOFF.md "Service alleys"): the backs of downtown
  (outside the financial core: skyline boost under `Alleys.MAX_BOOST`) and midtown blocks.
  `Alleys` (`scripts/world/alleys.gd`) and `AlleyKit` (`scripts/world/alley_kit.gd`). **The band
  is pure**: `Alleys.spec(plan, bx, bz)` (cached) puts it on the lot grid's seam across the
  block's long axis (`HALF_BAND` 3.6 m either side; `ODDS` per district, a hash; never on a site,
  a landmark's square, the runway clear zone, a block with a freeway corridor lot, a fire
  or a police station), from `CityPlan.lots()` alone, so the lots' own builders keep off it while they are
  built: `LotFill.after_building()` lays its paving on `Alleys.trim()` of the cell and keeps its
  forecourt furniture off `keep_out()` and the lot's `back_strip()` (the building's back to the
  band: the alley's service ground), `LotFill.surface_lot()` trims the car park, the parked cars
  skip `keeps_clear()` (red kerb at the mouths) and the pavement's lamps, trees and bushes skip
  `in_mouth()` - **after their rolls** (a tree or bush is planted into a scratch MultiMeshBatch so
  the block rng runs the same). `CityChunk` sets `Building.back_face` (`Alleys.back_face()`, 1 +X,
  2 -X, 3 +Z, 4 -Z): that face's vertices carry no storefront flag (`_append_part()`), and it gets
  no piers, kit storefront, shop names, spill, awnings or canopy - the alley face is the
  building's back, not another row of shops. **The runs are not pure**: `Alleys.block_step()`
  (after the lots, every level) walks the band from each mouth while the buildings LotFill
  recorded (`record()`) leave `MIN_WIDTH` (3.2 m) clear on a straight line (`runs()`, up to
  `WIDTH` 6.1), so a run can stop short (a dead end). FULL: ONE ground mesh (`AlleyGround`,
  `shaders/alley_ground.gdshader`, no shadow; kinds `G_*` in COLOR.r 16ths, UV the alley's own
  frame (along, across)): concrete or (a hash of the run) asphalt round a concrete V-gutter
  ribbon, slab joints, cracks, dug-up patches with sealant, oil in the wheel paths, grit and
  leaves at the walls, a cast-iron grate every ~24 m, speed bumps, NO PARKING stencils (TextMesh
  triangles conformed to the crown), aprons across the pavement and a wedge down to the road;
  and ONE casting upright mesh (`AlleyWalls`) on IndustrialKit's material and writers
  (`IndustrialKit.place()`), dressed by `AlleyKit.dress()` along every building back within 16 m
  of the run: steel doors under caged bulkhead lamps (`alley_pool` light pools, a few
  `lamp_light` omnis, `MAX_LAMPS` / `MAX_LIGHTS`), docks with steel stairs and roll-ups, fire
  escapes with drop ladders, condensers on brackets, panels, and on the ground a weighted walk -
  dumpsters stencilled with invented haulers (`Alleys.HAULERS`), grease bins, carts, pallets,
  crates, meters, a mattress - with a lane of `AlleyKit.LANE` kept clear; gates at some mouths;
  a box van backed in; wooden poles, wires, transformers and service drops on StreetDetail's own
  batches; StreetWear's tags and grime on the alley walls (`StreetWear._walls()` handed the
  centre line as a kerb, one cap with the street's); a cook on a smoke break (`AlleyCook`, a
  StreetVendor with a cigarette, in the crowd cap). dress() only DECIDES (a couple of ms) and
  queues each prop's SurfaceTool writes as its own time-sliced build step. LOD chunks and the far
  city's capture lay the band, the runs and the back strips as concrete slabs (`FAR_COLOR`).
  Every roll is a hash of seed + block / run / face, never a chunk, block or Building rng.
  `ALLEYS=0` in the environment is the A/B; `tools/alleys/probe.tscn` lists alleys (`WALLED=`
  walled-in ones, an EYE each) and builds one block (`BUILD=bx,bz`: props by kind, triangles;
  `ALLEY_TIME=1` the steps' times); checks `tests/alley_checks.gd`.
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
- Port life (2026-10-05, "the container terminal comes alive"; docs/HANDOFF.md, the port-life
  section): `PortLife` (`scripts/world/port_life.gd`, a plain Node the first FULL port chunk adds
  under the city root, `PortLife.ensure()`) draws everything that moves, **worked out from the
  clock** (`PortLife.clock`, physics time; `PORT_T=` sets it for stills, `PORT_HOLD=1` holds it),
  never simulated. **Cranes**: a working STS crane (`_build_quay`: within 95 m of the moored ship,
  gantried to the ship's nearest bay, `bay_x()`, BAY_REACH 32 m) is built at FULL as
  `PortKit.sts_frame_mesh()` (the posed crane less its trolley, cab, ropes and spreader - the
  split pieces add up to the old mesh, checked) plus a marker child (group `port_crane`, meta
  `plan` = `crane_plan()`); LOD chunks keep the posed meshes. Its **dual cycle** (`crane_pose()`):
  two half cycles, each a swap window (one tractor leaves, the next pulls in, `SWAP_WINDOW`), then
  lift the chassis' export box, trolley out, set it in ship slot A, pick slot B's box, back,
  set it on the chassis; the next half swaps A and B, so the cycle closes. The two slots are the
  top boxes of two rows of the crane's bay in the ship's deck batch, replayed exactly by
  `ship_boxes()` (seeds 4242 / 4243, Landmarks._build_cargo_ship's order) and HIDDEN from that
  batch while the crane works (the ship's batch is in group `port_ship_boxes`); the boxes PortLife
  draws there carry looks hashed per half cycle. Two yard tractors per crane (code-built
  `PortLifeKit` tractor + 40 ft chassis, the chassis HITCH metres behind on the path, so it
  articulates) alternate halves on a loop round the yard on the aisles between the port's chunks
  (`grid()`: aisle centres from the chunks' stack layout), trapezoid speed profile (`drive_s()`).
  **Gantries**: a FULL yard chunk's RTG is a marker (`mark_rtg()`, its piles from
  `CityChunk._port_piles`, `pile()`), drawn as `rtg_frame_mesh()` + `rtg_trolley_mesh()` + spreader
  and shuffling a 40 ft top box to the next column's lowest pile and back (`rtg_plan()` /
  `rtg_pose()`); the box's instance in the chunk's container batch is hidden while it is away and
  put back after. **Straddle carriers** (`PortLifeKit.straddle_mesh()`, 9.6 x 4.9 x 13.4 m) loop
  the interior blocks clockwise on the aisles (`straddle_loops()`), most with a box. Drawn as one
  MultiMesh per kind (`Layer`, buffers written whole each frame, true world -> `WorldState.to_local`),
  nothing past `draw_range`; machines within `body_range` of the player get an AnimatableBody3D
  (props layer, mask 0). Night: `port_steel.gdshader` parts 11 (amber beacon), 12 (head / work
  lamp), 13 (red lamp), additive pools under the trolleys, ahead of the vehicles and on the ship's
  deck. Sound: Sfx `crane` at every lock / release in `sound_range`; Ambience's crane one-shots
  come from a working spreader (`PortLife.clank_at()`). **The gate** (`PortGate`,
  `scripts/world/port_gate.gd`): the north-west port chunk (`PortLife.is_gate()`) builds no stacks
  (after the rolls) but eight lanes (six in, two out), booths on islands, a canopy with the
  invented terminal name, an OCR / radiation portal with lane numbers and an office, and drayage
  semis (BigVehicles SEMI, parked Vehicles of the chunk, a build step each) with their dry van
  hidden and a chassis and box hitched instead (some bobtails). LOD / far: boxes. A/B:
  `PORT_LIFE=0`. Probe: `tools/port_life_probe.gd` (cranes, step times, poses at `T=`). Checks:
  `tests/port_life_checks.gd`.
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
- The four-level stack (VISUAL_ROADMAP #81, 2026-10-05, docs/HANDOFF.md, the stack section):
  where the 110 meets the 101 at the real four-level interchange. **The plan is
  `FreewayStack`** (`scripts/world/freeway_stack.gd`, `Freeway.stack`, made in `Freeway.build()`
  BEFORE `_separate_crossings()`, which then leaves that crossing alone): the 110 at level 1, the
  101 at level 4, four LEFT-turn connectors at levels 2 and 3 (the pairs that cross go on
  different levels). **The heights are the whole problem**: the 101 leaves westward on its 2 km
  climb to the pass at the 7 % grade limit, so both main lines are held LEVEL through a window
  round the crossing (raise only, the `_clear_ground` relaxation) - the 110 three separations
  under the 101, its short north stub climbing away past the crossings (`STUB_*`) - and each
  connector's profile is solved between grade-limited envelopes (`GRADE_SOLVE`): tied to its
  parent and target over the touch runs, over the 110 and under the 101 where their footprints
  overlap, then the crossing pairs pushed apart (`LINK_SEP`, 7 m: 2 m girders, 5 m headroom) by
  each one's room; `prepare()` tries extra run on the climbing leg and spreads of levels until
  one solves, and with none there is no stack (the old crossing). On the default seed the stack
  is ~26 / 34 / 42 / 50 m: tall, because of the climb. Geometry: a connector leaves its parent
  EDGE TO EDGE (`TOUCH`: `open_edges` opens the parent's outer barrier there, so you can drive
  off), runs beside it (`TAPER`, `EXT` on the legs that can be held level), curves left on a
  Bezier circle of about `RADIUS`, and comes back the same way; points every `LINK_STEP`, `pt`
  the parent / target run in the leads, `bank` the superelevation (left turns lift the right
  edge). **Connector segments come out of `segments_in()` / `blocks()`** with `route` =
  `LINK_BASE` + k and `link` true (`Freeway._line()`): lots, trees, the bake, AirTraffic, the
  far city's decks see them with no code of their own; FreewayKit skips them and **`StackBuild`**
  (`scripts/world/stack_build.gd`, called from `CityChunk._build_freeway()`) builds them into the
  SAME four meshes (banked asphalt, 2 m box girder, barriers, two lanes of paint, davit lights
  every `LIGHT_EVERY` segments in a curving row, pools) plus banked collision boxes. Columns are
  lazy (`FreewayStack.columns(plan)`: they need the street plan): one round shaft with a
  hammerhead every `COLUMN_SPACING`, slid off any deck below and off the carriageways; a main
  line bent whose columns would stand on a lower deck is skipped (`skips_bent()`, FreewayKit and
  Skyline) for a single hammerhead column; `covered` drops main-line light standards and gantries
  under a deck. **Traffic**: `StackTraffic` (`scripts/npc/stack_traffic.gd`, the streamer's
  child) drives each connector by `s` and hands cars over BOTH ways - a TrafficManager freeway
  car reaching a diverge is taken (`take_share`) and drifts across the open touch run; at the
  end the car drifts onto the target's outer lane and joins `TrafficManager.freeway_cars` - and
  spawns away from the player when there is nobody to take. `STACK=0` in the environment builds
  the old crossing (the A/B); `STACK_DEBUG=1` prints the solver. Probe: `tools/stack/probe.gd`;
  compile: `tools/stack/compile.gd`; checks: `tests/stack_interchange_checks.gd`.
- The Los Angeles River (VISUAL_ROADMAP #58, 2026-10-05, docs/HANDOFF.md 9bp): the concrete
  flood channel, as data (`LaRiver`, `scripts/world/la_river.gd`, `MacroMap.river`, built in
  `MacroMap.setup()` after the replica and BEFORE the hill roads and the freeway) and a chunk
  builder (`RiverBuild`, `scripts/world/river_build.gd`; bridges `RiverBridges`,
  `scripts/world/river_bridges.gd`). **Where**: `CONTROL` points east of Vignes past downtown (the
  Arts District between them), under the 101 near its east end, the 10 and the 105, through Vernon
  to the bay's north shore east of the port (Long Beach) - the real river's ORDER, not its
  distance (at 1:1 it would stand in the east range); the 110 never crosses the real river and
  does not here. It runs south all the way (`nearest()` relies on z rising along it). **The
  section**: bed `bed_half()` (22 m north of WIDEN_Z, 30 m south), banks at SLOPE 1.6 : 1 up
  `depth()` (6.6 / 6.2 m), the low-flow notch (LF_*) with a WATER_DEPTH sheet, a coping kerb,
  a BANK_ROAD maintenance road and the fence; `corridor_half()` is where the city ends.
  **The land**: the bed must stay over the GroundBody (top y 0, under the whole map), so the
  river does not cut down: `terrace()` is the channel's top level (`top_at()`, the relief along
  the centre line smoothed, never under MIN_BED + depth, the bed only falling downstream), and
  `MacroMap._relief_at()` blends the city's relief toward it inside the corridor and over
  TERRACE_FADE outside (`_relief_natural()` is the relief without it). Everything on the relief -
  roads, bridges (a bridged street's own road slab IS the deck), the freeway's deck height -
  follows with no code of its own. **The grid**: `LaRiver._classify()` takes every road segment
  whose rect (with its end junctions) reaches the corridor, in runs (a crossing); a run is a
  BRIDGE (a single crossing of the centre line, skew under MAX_SKEW_DEG, both ends clear; the
  real bridged streets by NAMED_BRIDGES, avenues 55 %, the rest OTHER_BRIDGE_ODDS) or CLOSED
  (it ends at the bank: `CityPlan.road_open()` asks `LaRiver.road_open()`, so traffic, police,
  the respawn and the minimap all know). A chunk whose owned rect reaches the corridor is a
  **river block** (`CityPlan.river_block()`): no lots, no seeded block; CityChunk runs its own
  `_build_roads` (the bridges' decks), `RiverBuild.attach()` and the intersection; LOD gets no
  relief floor (it would lie over the channel). Walkers never plan a crossing onto one
  (`Pedestrian._crossable()`). **RiverBuild** (time-sliced steps: SEGMENTS_PER_STEP segments,
  one land row, one prop kind, one bridge job a step): the channel per owned centre-line
  segment on ONE concrete material (`shaders/river_concrete.gdshader`: COLOR.r kind/8 - bank,
  bed, notch, coping, wall, bridge, pier, dark -, COLOR.g the bank, UV metres along and across,
  UV2 the height over the bed and |o|; joints, streaks, tide line, algae, outfall stains on the
  same slots as `LaRiver.outfall_at()` (`ihash()` = the shader's lowbias32, checked), graffiti
  from the street wear tag atlas, buffed patches), the water (`river_water.gdshader`: riffles,
  foam streaks, algae fringe, sky emitted by Fresnel), outfall headwalls and pipes, sediment bars
  with reeds and shrubs, ramps (RAMP_GRADE, a kerb wall, the coping opened at the head), the
  headwall with box culverts at the north end, end walls and an apron at the mouth; the land per
  cell, cut exactly with Geometry2D (bank roads, the closed streets' stubs with barrier rows,
  a pavement ring with lamps, the yard - Industrial's ground and walls materials: fences
  `Industrial._fence()`, storage yards `Industrial._store()`, trailer drop rows, freight tracks
  with boxcars along the river TRACK_OUT past the fence); ONE trimesh `RiverBody` (backface
  collision) for all of it. **RiverBridges**: ARCH (three open-spandrel arches on cutwater
  piers, turned balustrade - the balusters a batch, `rv_baluster` -, twin-lantern standards,
  stepped corner pylons), RIBBON (6th St: three spans of white tied-arch rib pairs leaning out,
  hangers, LED strips on `river_lamp.gdshader`), GIRDER (box girder on column bents, barrier,
  cobra heads), RAIL (plate girders, the track set in the bank roads, buffer stops); lit lamps are
  `lamp_light` OmniLights (every LIGHT_EVERY-th) and `lamp_pool` pools. Freeway bents standing in
  the channel go down to its floor (`FreewayKit`, `LaRiver.channel_floor()`); no off-ramp lands
  in the corridor (`Freeway._place_ramps()`, the side still alternates). **Far**: the capture
  (`RiverBuild.capture()`) records thin land slabs in z slices, the channel as tilted boxes and
  the decks; Skyline sinks a river block's plate to the bed (`far_plate_drop()`) and plants no
  street trees on it; `MacroMap.bake()` paints the channel; the minimap draws it and its bridges.
  `RIVER=0` in the environment (or `-- --no-river`) builds the city without it (the A/B). Probe:
  `tools/la_river/probe.gd` (route, profile, bridges, ramps, rail, river blocks, freeway
  crossings; seconds); timing `tools/la_river/river_bench.tscn`; stills
  `tools/la_river/river_shot.tscn` (CAR=1 a car down a ramp) and `still_shot.gd` EYEs (HANDOFF
  9bp). Checks: `tests/la_river_checks.gd`.
- The marina (VISUAL_ROADMAP #70, 2026-10-05, docs/HANDOFF.md 9cb): the small-craft marina
  between the beach town and the airport, the form of LA's big man-made one, names invented.
  **Data**: `Marina` (`scripts/world/marina.gd`, `MacroMap.marina`, built in `setup()` after the
  river, before the hill roads), a pure plan from the coast and the seed's grid: the site is the
  whole blocks between the roads nearest `SITE_*` (5th to 7th, Lake Blvd to Birch on the default
  seed), a terrace at `QUAY_Y` (`terrace()`, folded into `MacroMap._relief_at()`, never on the
  sand), a basin quad (west seawall following the coast a promenade behind the sand, straight
  east / north / south bulkheads), an entrance channel band (`zc` +- `CHANNEL_HALF`) out past
  the waterline between two rubble jetties, a detached breakwater offshore, main docks every
  `DOCK_PITCH` with fingers both sides, a headwalk on each seawall, pilings, gangways, ~160
  boats in slips and ~35 on stands in the boat yard (types SAIL / MOTOR / FISHER / RUNABOUT,
  `TYPE_ODDS`, lengths and paints by hash), towers, restaurants, a shed, car parks, palms, lamps,
  benches, the bike path, nav lights, the channel boats' loop. Every roll is `h01()` (seed +
  key). The grid: `CityPlan.road_open()` asks `Marina.road_open()` (the site's inner roads, any
  road across the channel, the streets' beach ends under the bridge's ramps), `marina_block()`
  blocks build no lots, walkers never cross onto one, GroundCoverage skips them. **The coast
  highway** crosses the channel on MarinaBuild's bridge: its strip has a gap (`pch_gap()`,
  snapped to HillRoads' own points; `MarinaBuild.filter_segments()` in `_hill_segments()`;
  segments carry no name, `is_pch()` finds them by their line), the deck follows
  `bridge_y()` (`BRIDGE_CREST` 3.9 m clear: only runabouts pass, sailboats stay in). **Build**:
  `MarinaBuild` (`scripts/world/marina_build.gd`), attached at the top of
  `CityChunk.begin_build()` for a marina block whatever its zone (its roads, the sand where it
  holds the shore, the PCH, water, land by ground kind, bulkheads with copings, the planted bank
  up from the sand, docks, piles, gangways, boats, buildings, props, the yard and travel lift,
  the extras, lights, commit), and `extras()` for any other chunk the channel, jetties,
  breakwater or bridge reach (CityChunk appends it before the freeway); `_build_beach` cuts the
  channel's band out of the sand (`sand_rects()`) and keeps the palms' and lifeguard tower's
  rolls. One mesh per material a chunk, one trimesh `MarinaBody`; the water is
  `shaders/marina_water.gdshader` at the sea's 0.15 (the GroundBody under it: you wade, as in
  the sea; `MacroMap.bake()` marks it water so the horizon plane sinks). **Boats**: `BoatMesh`
  (`scripts/world/boat_mesh.gd`), code-built at real size (lofted hull sections - round bilge to
  deep V, flare, sheer spring, raked stem, transom -, deck, cabins with window bands, masts,
  booms, sail covers, furled jibs, standing rigging, pulpits, lifelines, flybridges, hardtops,
  tuna towers, outboards), NEAR / MID / FAR ~2k / 0.6k / 0.13k triangles; region in COLOR.a,
  `shaders/boat.gdshader` paints by it (paint and canvas from INSTANCE_CUSTOM, the instance
  colour white: it multiplies COLOR), bobs each boat about its waterline phased by its TRUE
  world position (`origin_shift`), lights lit cabins and anchor lights after dark. Boats are
  MultiMeshes grouped by type, variant and a 60 x 44 m cell, three nodes a group with
  visibility ranges (a batch takes one LOD for all its instances); one box shape each on
  `MarinaBoats`. Glows (anchor lights, dock pedestals, nav lights - red south / green north
  jetty, white breakwater, flashing) are one billboard mesh on aircraft_lights.gdshader.
  `MarinaTraffic` (child of the chunk holding the loop's start) runs three runabouts out the
  channel and back. **Far**: LOD chunks build the water, land, docks as slabs, FAR boats and the
  masts as `lod_box` MASTs (drawn at least a pixel wide: the mast forest from the hills); the
  capture records land slabs, docks, hulls, masts, buildings, jetties, breakwater and the
  bridge deck; Skyline's plate for a marina block is the water at the water. `MARINA=0` in the
  environment is the A/B. Probe: `tools/marina/probe.gd` (headless, seconds); quick checks:
  `tools/marina/marina_check.tscn` (the marina's checks alone, a minute); checks:
  `tests/marina_checks.gd`.
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
- Climbing plants (2026-10-05, "planting that grows ON things"): `ClimbingPlants`
  (`scripts/world/climbing_plants.gd`, static) - bougainvillea (magenta, orange, white) domed out
  from walls and spilling over their coping with canes hanging, ivy and creeping fig climbing,
  star jasmine through chain-link / pickets / board fences, wisteria or grape on back-yard
  pergolas (built here, timber in YardFill's walls mesh), trumpet vine up utility poles, and
  agave, aloe, red-hot poker, lavender and lantana in YardFill's mulch and DG beds. A build step
  of every FULL chunk (after StreetWear) that MOVES ITSELF behind the deferred steps (the yards'
  walls are laid by them), then runs in `STEP_BUDGET_US` slices. It reads what the chunk built:
  `ch._yard_walls` (merged into runs, `_yard_runs()`; a wall within `FRONT_REACH` of the block's
  edge is planted on its street side, `FRONT_GAIN` more often), house faces with their openings
  and the spans other wings hide (`house_face()`, one hook line in `HouseBuild._wing()`), LotFill's
  car-park walls and chain-link (`note_run()`, one line in `LotFill._edge_run()`), low-rise
  Building walls only where `StreetWear._paintable()` says plain wall, `upole` batch instances,
  and `_yard_ground`'s decks / tiles (pergolas) and mulch / DG (accents). Leaf and bract cards
  built in code (`_card()`: centred, bent, normal leaned toward the mass's outward direction so a
  mass lights as a volume; wind weight in COLOR.a, flower flag UV2.x, fade distance UV2.y) from
  ONE atlas painted by `tools/make_climbers.py` (8 x 6 cells of 256 px: sprigs for silhouettes,
  dense MASS cells for the inside of a plant - sprigs alone read as sticks; the `C_*` cell
  constants are the contract) on ONE shader (`shaders/climbers.gdshader`: sway by weight, alpha
  cut lowered per mip so masses do not thin to stems, translucency, wet leaves, colour-space
  include, a dithered fade by distance). Meshes are TILES of `TILE` (64 m) per kind - leaves
  (no shadow), a shadows-only twin of every `SHADOW_STRIDE`-th card, accents - because a node's
  visibility range is measured to its bounds' centre and a chunk-wide mesh on a 400 m beach
  block vanished from its own near end. Caps `MAX_CARDS` / `MAX_ACCENT_TRIS`; shares per
  district `DISTRICT_SHARE` (beach town 1, suburbs 0.85, downtown 0.08). LOD chunks and the far
  city get nothing. Every roll a hash of seed + wall / face / pole / bed. `CLIMBERS=0` in the
  environment is the A/B. Probe: `tools/climbers/climbers_probe.tscn` (headless, seconds: cards
  per species, step time, an EYE for every plant); checks: `tests/climbing_plants_checks.gd`
  (`tools/climbers/checks_only.tscn` runs them alone).
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
- Pier park (2026-10-05, "an amusement park on a pier, Santa Monica-style, original"; HANDOFF 9ca):
  RANDO PIER (the `pier` landmark, (-940, -350)) is `PierPark` (`scripts/world/pier_park.gd`):
  the pier plus GULLWING PARK on a platform off its south side. Everything sits in the PARK'S
  FRAME (a node at (anchor.x, 0, anchor.y), x out to sea negative, z south) as constants:
  decks `MAIN` / `NORTH` / `SOUTH` at `DECK_TOP` 6.4 (the three piers' deck height), the rail
  `OUTLINE`, `WHEEL_AT`, `CAROUSEL_AT`, `ARCADE`, `BUMPER`, `STANDS`, `BOOTHS`, `TABLES`, the
  crowd's `WALK_NODES` / `WALK_EDGES`; `tests/pier_park_checks.gd` holds them apart (nothing in
  anything, no walk through a ride or a coaster foot). All geometry is code (`PierMesh`,
  `scripts/world/pier_mesh.gd`: packed arrays per material slot, triangles turned to face the
  way asked like LandmarkGeo) on ONE shader, `shaders/pier_park.gdshader`: the surface KIND per
  vertex in UV2.x (`PierMesh.K_*`: paint, galvanised, striped canvas, bulb, LED, lit sign,
  window, boards, rubber, neon, chrome, gold), paint in COLOR (sRGB, decoded on both renderers),
  UV in metres; lights follow `lamp_factor`. **The rides move in the vertex shader from TIME**
  (`ride` 1 wheel / 2 carousel / 3 bumper cars, UV2.y the gondola / horse / car index + 1):
  `FerrisWheel` (`scripts/world/ferris_wheel.gd`, a direct child of the chunk / far holder, the
  smoke test finds it there) turns about +Z, each gondola TRANSLATED with its pin so it hangs
  plumb; after dark its spoke and rim LEDs run four chasing patterns (`led_pattern()`);
  `PierCarousel` turns about +Y with its horses bobbing. The coaster, `PierCoaster` (the KELP
  CRACKER, `scripts/world/pier_coaster.gd`), is DATA: a rounded-rectangle plan, a height
  `PROFILE`, banking from speed; the ride is worked out once into a (time, s) table (tyres, chain
  `LIFT`, gravity less `FRICTION`, `BRAKE_*`, `DWELL`), `lead_s(clock)` places the five cars each
  frame (only in the detailed build), screams (Sfx `scream`) at `DROP_S`, rolls with `rail_roll`.
  Shot, the wheel, the track and the cars are `PierRideBody` / `CarBody` in "rail_vehicle"
  (WeaponFX: metal sparks) and keep running; you can stand on the deck, the track and the
  platform. Shadows: lights, piles, rails, lamps and strings cast nothing; the wheel and the
  track cast through their FAR meshes as SHADOWS_ONLY twins; the horses not at all. The crowd
  are `PierGoer`s (`scripts/npc/pier_goer.gd`, the deck's height, routes by the walk graph),
  spawned by `PierPark.people_steps()` through the new `Landmarks.people_steps()` hook in
  `CityChunk._build_landmarks()`, in the crowd cap; the rides', stands' and booths' queues are
  the chunk's `vendor_queue` spots and the benches its `life_seats`, so the life layer fills
  them. The far copy is the same builders at low detail (4 k triangles, the LEDs 0.9 m wide so
  the wheel reads from the beach and the hills). Meshes are cached and built on the loading
  screen (`PierPark.warm()`). Stills: `PIER_COASTER_S=<s>` (or `PIER_COASTER=<seconds>`) holds
  the train; EYEs in HANDOFF 9ca. Probe: `tools/pier/compile.gd` (compiles, builds near and far,
  prints the cost, runs the layout checks; seconds, headless).
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
- Broadway's theatre district (2026-10-05, HANDOFF "Broadway"): `Broadway`
  (`scripts/world/broadway.gd`) places eleven invented movie palaces by their REAL house numbers on
  S Broadway (`THEATRES`, `address_z()` through the real cross streets) on the Broadway-fronting lot
  of the seeded block there (`palaces()`, cached; `CityChunk._build_lot()` asks `claims()` after
  the fire station, so no roll moves). `BroadwayTheatre` builds one in its frame (x along the
  street, +z out): shopfronts, a recessed entrance with terrazzo, doors, poster cases and the
  ticket booth, a FRENCH / SPANISH / DECO pavilion (`Style`), brick wings, the auditorium and fly
  tower; the marquee (`marquee_plan()`: vee, flat, drum) and the blade sign with stacked letters.
  Masonry on `landmark_facade`; the whole street front is ONE surface on
  `shaders/broadway_sign.gdshader` (kind in COLOR.a x 16, `K_*`: bulbs chase, neon, letters spell
  out row by row - UV.y carries 100 x the row -, boards, soffit, brass, glass, posters, terrazzo).
  LOD / far: boxes plus the sign and marquee as lit PANEL plant boxes. `BroadwayStreet`: the lamps
  on Broadway's pavements take the chunk's lamp slot (`Broadway.lamp()`, same prop kind and
  counter) with an original cast-iron lantern; goods racks, gowns and sale tables (hashes); the
  street clock (`broadway_clock.gdshader`, `ClockSync` sets the hour). `Broadway.dress()`:
  masonry, `HEIGHT_LIMIT`, Spanish/English shop names via `Building.name_pool` (indices into
  `SHOP_NAMES`, Broadway's appended after the first `BASE_SHOP_NAMES`; nothing else's roll moves).
  `BROADWAY=0` is the A/B; `tools/broadway_probe.gd` lists the palaces with EYEs; checks
  `tests/broadway_checks.gd`.
- The ballpark in the ravine (2026-10-05, docs/HANDOFF.md "The ballpark in the ravine"): the FORM of LA's
  famous hillside ballpark, in its real place - home plate's real point through
  `DowntownReal.game_xz()`, 2.9 km grid-north of Pershing Square on the embayed hills above the
  110 / 101 junction, facing the real centre field (game north, 6.4 degrees west) - with an
  invented name (SUNRIDGE BALLPARK) and no team, sponsor or logo. **The data is `Ballpark`**
  (`scripts/world/ballpark.gd`): the frame (`HOME`, `FWD`, `RIGHT`; `world(u, v)`, `local()`),
  the regulation field (`BASE`, `RUBBER`, `fence_r()`: 330 / 375 / 395 ft), the four `TIERS`
  (front offset from the foul lines, height, rows, rake, how far down the lines, the pastel seat
  colour, how full), the pavilions and scoreboards, the SITE (a rounded rectangle in local u, v)
  cut into the hills at fixed levels - the lower pad `PAD_Y` and the upper terrace
  `TERRACE_RISE` over it behind home, joined by a planted slope - with 1:1 cut / 1:1.5 fill banks
  out to `BANK_REACH` (`carve()`, folded into `MacroMap.height_at()` before the hill roads), and
  the lots (`LOT_*`, `ground_kind()`, `stall_car()`, `poles()`, `palm_spots()`). `covers()` keeps
  the hills' scatter, planting (`CityChunk._near_pad`), shells (`shell_marks()`) and Skyline's far
  oaks off it. Two roads, appended to HillRoads after everything else (`Ballpark.add_roads()`, so
  no roll moves; the hill chunks draw and carve them): Sunridge Dr north to the valley floor,
  Stadium Way switchbacking down the south face to Hill St (ground-following, grade-limited to
  `ROAD_GRADE`, never climbing on the way down). **The meshes are `BallparkBuild`**
  (`scripts/world/ballpark_build.gd`), in world space, cached per level ("near" / "far", the near
  set built on the loading screen with the far copy): the tiers' stepped rows (real geometry), parapets,
  fascias, soffits, lit concourses, facades and end walls; the pavilions under zig-zag folded-plate
  roofs, the stretched-hexagon scoreboards on legs, light banks on the roof lines with a glare
  sprite per lens (`aircraft_lights.gdshader`, kind 4); the field as a polar grid; the outfield
  wall, foul poles, dugouts, backstop net, batter's eye, bridges from the terrace; the plaza and
  lots as one grid following the levels. Shaders: `ballpark_struct` (kind in the vertex alpha),
  `ballpark_seats` (the crowd: a riser shows the torso of whoever sits in the row below, the
  tread their head and the seat or a lap; under a pixel the tier's average), `ballpark_field`
  (lines, dirt, the mow, analytic and box-filtered), `ballpark_lot` (stall rows, medians,
  planting, the plaza, and the parked cars PAINTED into the very stalls `Ballpark.stall_car()`
  fills with 3D cars near - the integer hash is the same lowbias32, checked), `ballpark_glow` (the
  night game's haze, integrated along the view ray through an ellipsoid, cut by the depth
  texture). **The night game is emitted**: every surface the banks see adds its albedo times the
  flood term (`bp_flood()`, off `lamp_factor`); three OmniLights in `lamp_light` light the field
  on desktop. Shader copies of Ballpark's numbers are checked (`tests/ballpark_checks.gd`).
  `BALLPARK=0` in the environment leaves it out (the A/B; it also restores the hills).
  Probe: `tools/stadium/probe.gd` (ground, cut and fill, the roads' earthwork), timing
  `tools/stadium/bench.gd`.
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
- The canals (2026-10-05, "a canal neighbourhood in the beach town - the form of the Venice
  canals"; docs/HANDOFF.md, the canals section): MARISOL CANALS, an original name, on the 2 x 2
  blocks inland of the boardwalk (x -824..-645, z -403..0 on the default seed). `Canals`
  (`scripts/world/canals.gd`) is a site like MacArthur Park's: its `Landmarks.all()` entry carries an
  `"area"` with no kept roads, so CityPlan snaps it to the four perimeter streets (open, the
  neighbourhood's residential ring) and closes every street inside (no cars). `layout(plan)` is
  PURE and cached per plan: NS_COUNT canals north-south and EW_COUNT east-west, CANAL_W 15 m bank
  top to bank top, a walk WALK_W each side, the islands between the bands cut into rows of
  LOT_W lots that FACE their canal (an edge island one row backing onto the pavement ring, a
  middle one two back to back), a bridge in the middle of every stretch, a dock for DOCK_ODDS of
  the lots. The houses are HouseKit's (`HouseKit.plan_fronted()`, front = the canal, the canal's own
  `STYLES` table, no garage - the garage wing becomes a room -, `glass_front` on modern boxes:
  a wall of glass to the water in `HouseBuild._openings()`); a GARDEN strip in front of each yard
  carries a picket / stucco / slat fence with a gate, a paver path to the door, flowers, a porch
  lantern (`CanalKit.add_porch_light()`, its glass on `shaders/canal_lamp.gdshader`, a light pool).
  The section: bed at FLOOR_Y -1.2 out to BED_HALF, a bank up to the coping (`bank_y()`), water at
  WATER_Y -0.62, the walk at SIDEWALK_TOP. The banks are a height field per canal over the
  section's breakpoints (crossings exact), `shaders/canal_bank.gdshader` (grass, a wet band,
  algae); end walls and a railing where a canal meets the pavement. **The water is below the
  GroundBody**: one Area3D a chunk (`CanalWater`, a box per piece) lets bodies through it
  (`Canals._sink`, refcounted across chunks - a body in two chunks' volumes keeps its exception
  until it leaves the last). **The water mirrors a canal that is not on screen**
  (`shaders/canal_water.gdshader`): the reflected ray is followed to the bank, the fence line and
  the row of house fronts (planes at known offsets), each drawn from a hash of the lot it lands
  on - wall colour, windows lit at night, the porch light smeared down the water, the roof line -
  and the sky above; EMITTED by Fresnel, at `mirror_forward` on Forward+ where SSR adds the real
  thing. `CanalKit` (`scripts/world/canal_kit.gd`) builds in code: the arched footbridge (a
  segmental deck, white spandrels and railings with pickets and newels, two lantern posts, ONE
  mesh instanced per chunk, one `lamp_light` OmniLight each), the timber dock with steps and
  pilings, the rowboat / kayak / canoe (lofted hulls, `shaders/canal_boat.gdshader`, paint in
  INSTANCE_CUSTOM - the instance COLOR would tint the wood too), fences and railings straight into
  the chunk's per-material meshes. FULL chunks: one mesh per material, ONE trimesh collision body
  (`CanalGround`), batches for bridges, docks, boats, lanterns, reeds; LOD: ground slabs, the water
  at y 0 out to the bank tops, the houses' far boxes; the far city: `Landmarks.capture_steps()`
  (hooked in `CityChunk._begin_capture()` for site blocks) records the ground and the houses.
  Every roll is a hash of the seed and the lot. `CANALS=0` in the environment is the A/B (no site,
  the blocks are ordinary beach town). Probe: `tools/canals/probe.gd` (layout, styles, bridges,
  road closures). Checks: `tests/canals_checks.gd`.
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
- Memorial parks (2026-10-05, fleet task "cemetery"; docs/HANDOFF.md, the memorial park section):
  `Cemetery` (`scripts/world/cemetery.gd`) claims a 2 x 2 (or 2 x 1) group of SUBURBS blocks per
  `CELL` (1.5 km) from hashes and the ROADS alone (`decide()`: never `CityPlan.block()`, so the
  answer is order-independent; Parks' role checked through `_rolled_kind()`), marks them PARK with
  grounds "cemetery" in `CityPlan.block()` BEFORE Schools' hook and closes the inner streets
  (`road_closed()` in `road_open()`). The plan is pure (`plan_for()`): a rise (`height()`), a
  loop drive, a Mission chapel by the gate, a classical mausoleum on the crown, an old section,
  trees, the stones (`graves()`, ~3,000). `CemeteryBuild` builds each chunk's part (the hook is
  the top of `CityChunk._block_steps()`, which it replaces): lawn mesh, drive, wall with the
  cut-out iron fence (`cemetery_fence.gdshader`), the lit gate with the name in gilt letters,
  LandmarkGeo buildings, one batch per stone kind (`CemeteryKit`, `cemetery_stone.gdshader`),
  code-built cypresses (`cemetery_cypress.gdshader`), lanterns, visitors (`CemeteryVisitor`),
  the outer pavement's lamps and trees. **A sanctuary**: all collision in one sanctuary body, a
  zone over each chunk's part at FULL and LOD; nothing breaks. `CEMETERY=0` is the A/B; probes
  `tools/cemetery/probe.gd` (`EYES=` heights on the rise) and `build_probe.gd`; checks
  `tests/cemetery_checks.gd` (`tools/cemetery/checks_only.tscn` alone).
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
- Tower roofs (2026-10-05, "tower roofs are what the player sees most while flying"):
  `Rooftops` (`scripts/world/rooftops.gd`, static) puts on a building's highest roof (not a
  podium) a raised HELIPAD (towers from `PAD_MIN_HEIGHT` 75 m, `PAD_SHARE`: steel deck
  `PAD_RISE` over the plant on columns that skip what stands under them, the touchdown paint, green
  perimeter lights and floods, a safety-net shelf, a windsock, the access stair, a parked
  helicopter in a private livery on `HELI_SHARE`), a POOL DECK or a ROOF GARDEN (a traced pool,
  loungers, umbrellas, glass balustrade, a cabana bar with its lit invented name, string lights,
  potted palms; RoofGoer people on the deck, `scripts/npc/roof_goer.gd`, in the crowd cap - lawn,
  planters, pergola), a louvred MECHANICAL PENTHOUSE, a TELECOM MAST and on glass towers a
  WINDOW-WASHING MACHINE on rails, its cradle parked or hanging part-way down the facade. **The
  plan is pure** (`plan(b)`: the parts, the plant Building already placed - `roof_props` - and
  hashes of seed + "rooftops"; never `_rng` or `_roof_rng`), so a generating building and its far
  boxes (`FarBuilding.boxes()` after `roof_plan()`) plan the same roof. Pieces stand off the
  plant they may not cover (bulkheads, tanks, cooling towers, signs, spires; a pad only off spires
  and tanks) and IN PLACE of the small plant (`HIDEABLE`: units, ducts, solar, skylights; and an
  antenna under a pad): `hidden()` names those props, `clear_plant()` takes them off the near
  building after `_build_roof_props()` (each prop's primitives start at its `rolls.prims`), and
  FarBuilding skips them - their rolls are still made, nothing moves. The kit's own roof plant is
  handed the pieces' rects (`keep_out()`, its private stream). Drawn as ONE mesh a building
  (`RooftopGeo` -> `shaders/rooftop.gdshader`: kind in the vertex alpha /32 - the pad's paint from
  UV, the net cut out and dithered under a pixel, louvres, decking, pavers, turf, lamps,
  bulbs and signs lit by `lamp_factor`; the pool TRACED in the mesh's own space, UV = building
  space from the pool's centre, UV2 its half size) plus a glass surface, the planting in one
  MultiMeshBatch, collision on the building. Far: `FarBuilding.Plant.HELIPAD` / `POOL`, painted on
  the box top by `building_lod.gdshader`. LandmarkDowntown towers whose real roofs are flat carry a
  `"helipad"` row in `TOWERS` (local centre on the roof, deck, turn; `Rooftops.landmark_helipad()`).
  `ROOFTOPS=0` is the A/B. Look with `tools/glshot/rooftop_shot.gd` (`FEAT=helipad|pool|garden|
  penthouse|mast|bmu`, `NIGHT=1`, `GOLDEN=1`, seconds), find them in the city with
  `tools/rooftops/find.gd -- --at=x,z --radius=m` (an EYE per pad and pool), count with
  `tools/rooftop_probe.gd`. Checks: `tests/rooftops_checks.gd`.
- Wilshire deco (VISUAL_ROADMAP #86, 2026-10-05, docs/HANDOFF.md "Wilshire's deco boulevard"):
  `DecoBoulevard` (`scripts/world/deco_boulevard.gd`) gives midtown's boulevard frontage its
  1920s-30s character. A MIDTOWN BUILDINGS block's edge lot whose cell faces a road
  `BOULEVARD_WIDTH` (24 m) or wider is deco by a hash (`WILSHIRE_ODDS` 0.75 on Wilshire - pinned
  real street, its midtown stretch runs x ~500-1600 between MacArthur Park and the 110 -,
  `ODDS` 0.3 on other boulevards) and builds one of five kinds instead of its Building: a zigzag
  moderne TOWER (three-storey base, a shaft set back twice, piers on every bay line, majors rising
  into stepped finials, chevron spandrels, zigzag friezes, a fluted lantern crown, ziggurat steps
  and a spire; lots planned 26 m+), a streamline CORNER on a block corner (glass block round the
  curve, ribbon windows, speed lines, a canopy with downlights and a neon strip, a pylon fin with
  the name in neon; under `CORNER_MAX_HEIGHT`), a THEATRE (`THEATRE_BLOCKS` of blocks, one a
  block; fluted pilasters, stepped tower, vertical blade sign, marquee with readerboards and
  chasing bulbs, an OmniLight under it at night on desktop), deco APARTMENTS (stepped centre bay
  and pediment, portal, the name over the door: gilt by day, lit at night) and Spanish COURTYARD
  apartments (three stucco wings, clay gables, a tiled fountain, an arched gate with the name,
  LotFill's planting and two palms inside). **The plan is pure** (`block_plans()` / `lot_plan()`,
  hashes of seed + lot, cached by block): the planned Building is never made, the pad roll is
  spent before `CityChunk._build_lot()` asks, so nothing else on the block moves. Every lot's
  massing (`massing()`) is what the LOD chunks and the far city draw - **plain `lod_box`es on
  building_lod's OLD path** (facade colour + window style, INSTANCE_CUSTOM.a 0), not FarBuilding's
  coded copy - and what the collision (`DecoBody`, one box a massing box) and the occluder are.
  `DecoBuild` (`scripts/world/deco_build.gd`) writes a FULL chunk's deco into ONE ornament mesh
  (`DecoOrnament`, `shaders/deco_ornament.gdshader`: kind in COLOR.a as a code in 4/255 steps,
  plus 32 for floodlit crown surfaces; paint in display numbers; UV face metres; UV2 a panel's
  size; TANGENT the face's +u - terracotta, glaze, chevron / sunburst / zigzag / fluting relief,
  metal, glass block lit at night, neon, bulbs, readerboards, clay tile, Spanish tile, water) and
  one walls mesh per palette (`DecoWalls_<key>`) on **building.gdshader with `uv_facade` AND
  `part_attributes` on**: Building's CUSTOM0-3 layout per vertex, UV.x metres along a face (a
  whole number of bays, so the piers and spandrels DecoBuild places line up with the shader's
  windows: PUNCHED glass is 0.27-0.77 of a storey), UV.y the face index (100+ blank) - so the
  windows keep their traced rooms, lit offices and storefronts. Building frame: x along the
  street, +z toward it, front at z 0 (`frame_xform()`). Mature palms on the kerb in front
  (`block_step()`, after the sidewalk furniture, clear of it by `PALM_CLEAR`), night pools in
  their own `deco_spill` batch. The plan has no medians, so none are built. Names are invented
  (the checks hold a list of the real boulevard's out). `DECO=0` in the environment is the A/B;
  `tools/deco_probe.gd -- --spawn=x,z,0,0` lists the deco round a point with an EYE each;
  checks `tests/wilshire_deco_checks.gd`.
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
  is twenty rigs, `assets/models/crowd_a..t.glb` (m..t added 2026-10-05: older people, teens,
  heavier, very short and very tall builds, more complexions, a headscarf), built by **`tools/crowd/`** with the hero's
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
  A body in our garments is 11.7-13.9k triangles (10.5-12.7k in the library clothes). Sixteen
  people wear them (a, d, e, h..t); b, c, f and g keep library clothes. **The second set
  (2026-10-05, docs/HANDOFF.md 9cg)**: the jacket takes `collar` (stand / rib / hood),
  `closure` (zip / buttons / none), `pocket` (welt / kangaroo / none) and `knit` - a windbreaker
  (m), a crew-neck cardigan (n) and a pullover hoodie with its hood DOWN (`hood_down()`: a roll
  round the neck that folds onto the shoulder blades only round the back - spread from the sides
  it was a sailor's collar) and drawcords (o); the shirt takes `sleeve: short`, `placket_len`,
  `pique` and rib cuffs: the polo (q); trousers `style: joggers` (rib leg cuffs, `leg_cuffs()`,
  an elastic waist); `skirt` (n, p) is a band SWEPT round a vertical axis from the waist, falling
  from the hips' widest ring and flared, measured on the pelvis and legs alone (with the hands
  in it, it stood out in two square wings), weights both thighs and the hips blurred round it;
  `vest` (s, hi-vis, region `keep`) is the top's shell without sleeves over the tee, armholes cut
  down the sides; `scarf` (r, hijab-style, region `keep`, built last) is a shell off the head,
  neck and shoulders whose head part lies on a SPHERICAL envelope of the skull with the ears left
  out (their holes filled; the ear skin is deleted under it, `build_character.py`), the throat
  bridged from the jaw, the drape's edge cut by distance from the neck base (a vertical-plane hem
  is a sawtooth on the shoulder), an oval face opening (`cut_oval()`). A vest or a scarf deletes
  the top it hides (`hide_under`). `Pedestrian.NO_HAT_MODELS` (r) never wears a hat, and the
  camp figures are dressed from the first twelve rigs only (`Encampment.FIGURE_POOL`).
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
  its grids, `LEVEL_EDGES`; cap 1,812 / 464 / 121 triangles, the others 1.6-2k / 430-520 / 110-150), one material per colourway, one draw
  per wearer, never in a shadow pass, gone past `accessory_distance`. **The hair is pressed, not
  hidden** (`pressed_hair()`): vertices under the crown moved inside it, easing out over a few
  centimetres below the band so hair shows at the back and sides, strands far off the scalp (a
  ponytail through the opening, a braid) left alone, triangles left wholly inside and the cards
  that would hang in front of the face (a fringe) dropped; one copy per hair mesh, rig and kind.
  No mesh data (the headless check) or a rig marked `"hide"` (hair too thick to press) hides the
  cards as before. A dropped fringe leaves the scalp painted under it (a black eye on crowd_h
  and crowd_c), so a hat wearer's body draws on a copy of its material with `hat_face` on
  (`CrowdHat.fit_face()` / `face_fix()`, docs/HANDOFF.md 9bg follow-up): below the band, a
  texel less skin-like than its mirror image across the face takes the mirror's (the mirror is a
  reflection in the atlas fitted per rig from the head's own mirror vertex pairs). `Pedestrian._add_accessory()` makes the same three `_style` rolls as the box
  hats did (CampFigure.seed_for() depends on them; a bucket hat is the top tenth of the old cap
  roll), the ragdoll a hatted person becomes wears it too (`_dress_doll()`), a rough sleeper's is
  the worn colourway (`material(kind, pick, true)`: dulled, faded, grime), `PoliceOfficer` uses
  `CrowdHat.Kind.PEAKED`. The loading screen builds them all (`CrowdHat.warm()` from
  `Pedestrian.warm_far_mesh()`: ~12 ms a hat, ~10 ms of hair a kind on this box). Look with
  `tools/glshot/crowd_lineup.gd` `HATS=cap,beanie,bucket,police` (`HAT_PICKS=` the colourways);
  checks: `tests/crowd_hat_checks.gd`.
- Street vendors (VISUAL_ROADMAP #52, 2026-10-04: "taco trucks at night, fruit carts under
  umbrellas"): `StreetVendors` (`scripts/world/street_vendors.gd`, static) - taco trucks at the
  kerb with a lit menu board, the serving window open under its propped flap, a lit kitchen
  inside, a generator on the back (Sfx `generator`, a real CC0 loop); fruit and elote carts under
  striped market umbrellas; bacon-wrapped hot dog carts with a string of bulbs; paleta push carts;
  flower and balloon sellers at corners. Every mesh is code at real size on ONE shader
  (`shaders/street_vendor.gdshader`: what a face is in the vertex alpha - steel, paint from
  INSTANCE_CUSTOM.rgb, canvas stripes by the angle round the pole, lightbox, food pictures, lit
  interior, bulbs, glass, food, LED; codes 0.05 apart), one batch per kind a chunk (`vend_*`),
  lettering from TextMesh merged in (invented names and menus, `TRUCKS`). **The instance COLOR
  multiplies every vertex colour** (it would tint the umbrella's pole), so the canvas's second
  stripe is the shader's `CANVAS2[INSTANCE_CUSTOM.a * 8]` copy of `CANVAS` (checked). Placement
  is pure (`plan_block(plan, ix, iz, hour)`): by place (`Place`: downtown, midtown, industrial
  lunch trucks, parks, the faces across from MacArthur Park, round the arena, the beach town) and
  face (`ODDS`), by the hour the chunk is built at (`SCHEDULE`, hashed shifts, trucks at night,
  carts by day; `force_hour` for tests), all hashes of seed + block + face + kind. A FULL block's
  step after the camps: a truck parks in this chunk's own parking lane (+x / +z faces only),
  serving side to the kerb, as a `_add_prop` that never breaks (rounds spark off it as metal; its
  collision leaves the window open, so a round through it finds the cook); the parked cars skip
  its stretch AFTER all their rolls and count it as parked (`blocks_parking()`), so the block's
  stream is unmoved. A cart is an `EncampmentItem` (tips over as a real body, stays gone). Night:
  pools in the chunk's `shop_spill` batch and one `lamp_light` omni per truck / hot dog cart.
  People: `StreetVendor` (`scripts/npc/street_vendor.gd`, a Pedestrian with the life clips) at
  the stand, talking to whoever waits; a cart vendor flees gunfire and walks back; a truck's cook
  is kinematic on the truck floor (`lift`) and ducks. Customers are walkers: chunk meta
  `vendor_queue` spots, taken by `Pedestrian._plan_queue()` (no roll on a chunk without vendors).
  `STREET_VENDORS=0` turns it off (the A/B). Look with `tools/glshot/vendor_shot.gd` (the stands
  alone, seconds; `NIGHT=1`) and find them with `tools/vendor_probe.gd`; checks:
  `tests/street_vendors_checks.gd`.
- City birds (VISUAL_ROADMAP #54, 2026-10-04: "nothing alive in the city but people"):
  `Birds` (`scripts/world/birds.gd`, a Node3D in `city.tscn`, so origin shifts carry it; birds
  live in its own space). **Nothing is per chunk**: every `survey_interval` it plans flocks round
  the player from the plan (`_spots_near()`, all hashes of seed + block / 60 m cell + slot, so a
  plaza always has its flock): pigeons on PLAZA / PARK blocks and landmark sites (12-40), on a
  downtown / midtown / campus pavement by a corner (`pavement_odds`), crows on a suburban lawn or
  the block's power line (`_wire_spans()` rebuilds StreetDetail's spans from its constants and
  `_has_poles()`; `wire_point()` is the very polyline it draws, and a span is only used where a
  ray finds the pole), sparrows by pavements, gulls on BEACH and PORT cells and on pier decks
  (OCEAN cells near a `*pier` landmark, a ray must hit a deck). Flocks past `spawn_radius +
  despawn_margin` are dropped; `max_birds` (Quality scales it), fewer at dusk, none at night or
  in a storm (`DayNight.lamp_now`). Ground height is a ray from the PLAN's street height (the
  valley is a plateau 140 m up), rejected over a bench, a car, a roof or a slope. **Behaviour**
  (plain GDScript, far ground flocks at a quarter rate): walk / peck / stand with separation
  against two neighbours a frame, one bird a frame re-rays its ground; gulls squabble in pairs;
  coos, caws and chirps in earshot. **Flush**: the player within `flush` + speed x
  `flush_speed`, `Birds.startle()` (called first thing in `Pedestrian.alarm()`, so every gun,
  blast and police round), a car through the flock faster than 6 m/s (a shape query on layer 3
  at 2 Hz, speed from position deltas - kinematic traffic has no velocity). Takeoff staggered
  nearest-first with wing claps (Sfx `wings`), a formation flock round an orbit (leader + fixed
  offsets, glide spells by species), then `_choose_landing()`: a power line, a roof edge (a ray
  onto a roof, then marched out to where it drops; downtown / midtown pigeons), or open level
  ground 15-45 m off that is not a carriageway (inside a block rect), a flare and down. **Shot**:
  `Birds.hit_ray(from, end)` from `AssaultRifle.fire_ray()` and `Shotgun.fire_pellet()` (no
  physics bodies: segment vs bird spheres, flock bounds first); the bird drops in a puff of its
  own covert feathers (a one-shot CPUParticles3D from the atlas) and lies `corpse_seconds`; a
  blast (`Explosion.blast_count` polled) kills within 7 m. No crime, no alarm of its own.
  **Models** are built in code (`BirdMesh`, `scripts/world/bird_mesh.gd`: lofted body along a
  curved spine, eyes, legs and toes, feather cards cut from painted feathers - secondaries,
  tertials, primaries fanned to the tip, alula, a covert sheet, the tail fan - at real size;
  NEAR ~2.5k / MID ~450 / FAR ~100 triangles; the near loft is 28 x 22 with its normals welded
  and averaged, `_smooth_normals()`, and the folded feathers and coverts take the body's flank
  normal, `flank_normal()`, so the wing shades as part of the bird) with TWO poses per vertex: VERTEX in flight,
  CUSTOM0.xyz on the ground (wings folded onto the flanks by `_snap()`, primaries crossed flat
  over the rump, tail closed, legs standing), CUSTOM1 that normal and a weight. Code, not
  Blender: a glTF cannot carry the second pose. `shaders/bird.gdshader` blends them by
  INSTANCE_CUSTOM.x, flaps (shoulder + wrist, hand sweep on the upstroke), pecks and bobs the head,
  walks the legs, recolours pigeon morphs (COLOR.rgb, sRGB, black = the painted bird) and adds the
  neck / crow sheen; a wing or tail card's BACK face is the underwing (`under_cov` /
  `under_flight` / `under_keep` / `under_mix` per species in `BirdMesh.LOOKS`: grey on a pigeon,
  white on a gull, the crow's own black); linear on both renderers. Plumage is `tools/birds/make_bird_textures.py`
  (original procedural art; its atlas layout and spine landmarks are a contract with
  `BirdMesh.SLOTS` / `S_*`, checked). ONE MultiMesh per species and LOD (12 nodes), the whole
  buffer written each frame, `custom_aabb` from the birds; FAR casts no shadow. Look with
  `tools/glshot/bird_shot.gd` (the lineup, seconds; `LOD`, `YAW`, `MORPHS=1`, `CAM`/`LOOK`, `ONLY=<pose>` one bird close up) and
  `still_shot.gd BIRD=ground|flush|wire` (`BIRD_SPECIES`, `BIRD_DIST`, `BIRD_COUNT`, `BIRD_FLY`;
  staging calms the flock against the player, whom a free camera drags along). `BIRDS=0` in the
  environment removes them. Ambience's gull one-shots come from a real gull when one is in earshot
  (`Birds.gull_at()`). Checks: `tests/bird_checks.gd`.
- Beach life (VISUAL_ROADMAP #60, 2026-10-05: "a Los Angeles beach on a warm afternoon"):
  `BeachLife` (`scripts/world/beach_life.gd`, static) fills the sand `CityChunk._build_beach()`
  lays. **Everything is a hash of seed + a WORLD cell of shore (`CELL_Z` 6.5 m) + the hour the
  chunk is built at** (`hour_now()`, `force_hour`; `density()`: nobody before 6:30 or after 20:30,
  full 13:00-16:30, a few at dusk; `weather_factor()`: half on a grey day, nearly none in rain),
  never the block rng: `_build_beach`'s palms and tower roll exactly as before (a palm rolled onto
  the bike path is nudged off it after its roll). `plan_stretch(plan, z0, z1, dens, obstacles)` is
  pure (people, props, the court) and world-anchored: two halves plan what the whole does; groups
  of 1-4 by `BANDS` across the sand, the front rows first (`shape()`), poses from `POSE_ODDS`,
  towels, umbrellas, low chairs, coolers, totes, boogie boards, surfboards. Nothing within
  `KEEP_OFF` of the boardwalk and the piers; the replica's coast gets people but no path or court.
  **People are `BeachFigure`s** (`scripts/world/beach_figure.gd`, extends CampFigure): each
  (crowd rig, pose) is baked once on a real `BeachGoer` (the camps' trick) and each suit is that
  bake with the suit's look; a chunk's figures merge into `BeachFigureMesh` (32 m cells along the
  shore, the middle bodies inside `near_range` 42 m, the far bodies past it and as the shadow), so
  a chunk of ~120 people is a draw per rig per cell. Woken (shot, knocked, `CampFigure.wake_near()`
  from an alarm, or `BeachActivity._scatter()`: up to `scatter_max` of the nearest, a few a tick)
  they become a live `BeachGoer` (`scripts/npc/beach_goer.gd`, extends RoughSleeper) that runs up
  the beach and walks back. **Swimwear** is `BeachGoer.swim_mesh()`: a copy of the crowd body, each
  triangle by its rest-pose height (`TRUNKS_BAND`, `BOTTOM_BAND`, `TOP_BAND`) left in its garment
  region (the suit: `swim_material()` colours both regions from `SUITS`) or turned into skin (the
  skin region on one texel of the person's own neck), border vertices split; shoes are bare feet.
  `STYLE_OF` (trunks, bikini, one-piece) per rig in `BEACH_MODELS`; no new bones or surfaces, so
  the welds, the ragdoll (`knock()` dresses the doll again) and limb cuts work. Poses: RoughSleeper's
  table format, `BEACH_POSES` (on the back, front, hands behind the head, sitting leaning back, a
  low beach chair, astride a board, paddling, riding a wave side-on, skating, the volleyball arms).
  **`BeachActivity`** (`scripts/world/beach_activity.gd`, a node per FULL beach chunk): swimmers
  (standing bakes sunk to the chest) and surfers on boards past `Surf.break_distance()` who sit,
  paddle in, ride a wave in side-on along the face (`Surf.crest_height()`) and paddle back out;
  riders on the path (`BeachRider`, `scripts/npc/beach_rider.gd`: an AnimatableBody3D on the npc
  layer, a cyclist is a flipbook of `BeachGoer.RIDE_FRAMES` bakes from `BeachFigure.ride_meshes()`
  - each frame `BeachGoer.ride_pose()` solves both legs onto the pedals by two-bone IK and the
  cruiser `BeachLife.bike_mesh()` is built round that frame's saddle, crank, pedals and grips - a
  skater one bake with the board); a volleyball game on the chunk's court (four live BeachGoers
  with `volley_home`, the ball on parabolas: pass, set, attack, misses, serves); walkers
  (`BeachWalker`, `scripts/npc/beach_walker.gd`) carrying boards to the water and strolling the
  wet sand; the lifeguard (a figure on the tower's deck, `LIFEGUARD_*`). A shot rider becomes a
  live BeachGoer and the bike is thrown as an EncampmentItem. The tower is `BeachLife.tower_mesh()`
  turned to the sea; the path a strip mesh at `PATH_AT` (`path_x()`), joints and centre line in
  `shaders/beach_props.gdshader` (one shader for all of it; codes in the vertex alpha, paint in
  INSTANCE_CUSTOM, `CANVAS2` mirrored and checked). `ground_at()` / `sand_y()` are the sand mesh's
  own rows (not `_sand_y()`'s curve). LOD chunks: towels and umbrellas as dots (`build_lod()`),
  the path and the court tapes. The loading screen bakes every rig in every pose and the riders'
  flipbooks (`BeachFigure.kinds()`). `BEACH_LIFE=0` is the A/B; `BEACH_STAGE=z` on `still_shot.gd`
  gathers riders and surfers there; `tools/beach/probe.gd` walks the coast (`PEOPLE=1`),
  `tools/beach/chunks.gd` lists the built chunks, `tools/beach/checks.gd` runs the checks alone.
  Checks: `tests/beach_life_checks.gd`.
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
- Hero moves (VISUAL_ROADMAP #64, 2026-10-05): the hero (not the officers' crowd-rig Avatars)
  carries a second AnimationLibrary, `moves` (`assets/models/hero_moves.res`, written by
  `tools/hero/hero_clips.gd`: Quaternius' CC0 UAL clips retargeted in Godot like the crowd's life
  clips, each carrying the hero Idle's finger keys, and four idle variants KEYED in the script
  over the library's idle as overlays - turns, aims and rolls of bones in skeleton space; rerun it
  whenever hero.glb is rebuilt, then `--import`). It is added AFTER `fix_arm_pose()` and the loop
  pass. `Avatar._drive_moves()` picks clips: idle variants after `idle_variant_after` seconds
  still (`moves/idle_*`; a clip's meta `free_left` says when the left hand is off the gun), the
  walk in place to step round a turn, the sprint past `sprint_threshold`, `jump_start` on
  `jumped()`, `jump_air` in the air, and `landed(fall, run)` by LandingFX's scale (`land_dip`
  30, `land_hard` 60 m/s; a roll at `roll_speed`). One-shots run to their end unless movement
  cuts them after their breakable point. **`HeroMotion`** (`scripts/player/hero_motion.gd`) is
  the FIRST modifier on his skeleton (moves, GunTwist, GunHandsIK right, GunHandsIKLeft,
  GunHandsTurn - the smoke test checks the order): the flight pose (legs together, left arm
  back, head up by `look_up`), the fall pose (left arm out), the flinch (a skeleton-space vector,
  a spring in Avatar kicked by `hit_from()` from `PlayerHealth.hit_taken`) and the foot IK (two
  world-layer rays a physics frame while standing; hips down by the deeper foot, an analytic
  two-bone leg solve). The arms are TWO TwoBoneIK3Ds so the left can let go by its `influence`
  (and `GripHands.left_weight`); the gun stays in the right hand in every move: drawn up from
  the hip on a weapon change (`draw_time`), out to the side falling (`FALL_GUN`), in against the
  thigh in a roll / hero landing (`LOW_GUN`), ahead of the head flying (`FLY_GUN`, in the laid
  body's frame); raising the gun (aim, fire) always wins. The flight lays the Avatar node along
  the velocity about the hips (`fly_lay`) and banks it (`fly_bank`). Look with
  `tools/glshot/hero_moves_shot.gd` (several stills a load: a clip frozen or a staged move -
  fly, fall, hit_*, draw, land_<speed>, roll, idle_*; `STEP=1` for the foot IK); checks
  `tests/hero_moves_checks.gd`.
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
  **Shadows are cut where the shadow map cannot hold them** (2026-10-05, docs/HANDOFF.md 9bf:
  the shadow passes were 46 % of the downtown frame). `MultiMeshBatch.set_shadow_reach(key, m)`
  casts a batch only while one of its instances is within `m` of the camera (a SHADOWS_ONLY
  twin, of the batch's own mesh when it has no lighter one); the facade kit's cornices and coping
  use it (`Building.kit_roofline_shadow_reach`, 80 m: past it the cascades are 10 cm a texel and
  more, and the band inside the moulding casts the cornice's shadow). **`set_shadow_distance()`
  only reaches a lighter twin: on a code-built mesh it does nothing** (the airport's and the car
  parks' fence posts ask for one in vain). A FULL chunk's raised ground slabs (pavement, lawns,
  plazas within `GROUND_RIM_TOP` of the pavement) cast from their skirt and edge cells alone
  (`GroundRim`, `CityChunk.ground_skirt_shadows`); the roads cast whole (without them the paint
  and patches on them came out lighter along their edges). A/B: `SHADOW_REACH=0`, `GROUND_SHADOW=0`,
  `LAMPS_AT_ZERO=1` on `still_shot.gd` and `gpu_profile.gd`. The whole city no longer fits
  lavapipe (12.7 GB, OOM-killed with another session's process): never render it there;
  `gpu_profile.gd LIGHT_WORLD=1` is for a bigger box.
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
- Cut corners on the far boxes (2026-10-05, docs/HANDOFF.md "Cut corners on the far boxes"):
  a chamfered part (`part_grid()` cut_x > 0) is three instances of the unit box in the `lod_box`
  batch - its own entry as the middle piece, two end pieces appended after the plant (so part i
  stays box i) - with the piece in INSTANCE_CUSTOM.r (`FarBuilding.PIECE_*`);
  `building_lod.gdshader`'s vertex stage pulls the corners in by one bay (the code's cols) and
  gives the cut faces their normals. Every piece computes a corner by the same expression, or the
  roof cracks. No new mesh or draw (+24 triangles a cut part). `FAR_CORNERS=0` is the A/B;
  `far_building_shot.gd CHAMFER=1`; checks `tests/far_corners_checks.gd` (mirror the reshape).
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
