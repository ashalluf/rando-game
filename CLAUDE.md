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
  `debris` (short-lived props that get freed after a timeout), `wanted` (the one `Police` node),
  `police` (officers on foot - NOT in `pedestrian`, so alarms, the crowd cap and trimming never
  touch them; `LockOn` looks in it), `police_car` (cruisers, also in `vehicle`).
- Autoloads: `PhysicsBudget` (`scripts/util/physics_budget.gd`), `WorldState`
  (`scripts/util/world_state.gd`), `Sfx` (`scripts/util/sfx.gd`:
  `Sfx.play(name, position)`, `Sfx.loop_player(name)`).
  Sound is **real CC0 recordings** (`assets/audio/`, 111 clips - the siren is public domain - sources in `docs/ASSETS.md`) with
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
  and play the plain mix.
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
  `global uniform float night_factor;`. Clouds are lit by stepping the same noise field toward
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
  Rain at night is judged by the wet street, so: `Weather` starts as wet as the weather it
  starts in (soaking from dry spent the first 16 s on dry tarmac under a downpour); a soaked
  road is roughness 0.07 with mirror puddles at 0.02 (`road.gdshader`, spreading as it soaks),
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
  glass by a dark texel, but the sedan, pickup and van textures do not (the van's darkest 5 %
  is 0.49), so those find glass by shape - above `Vehicle.GEO_GLASS_BELTLINE`, tilted between
  roof and door skin - or every white car was one pale ice-sculpture shape. That was only half of
  it: the other half was the sky. The radiance map is what every lacquer, window and puddle
  mirrors, and the drawn sky fades to haze over 27 degrees below the horizon, so every car door
  (which faces a little downward) mirrored pale-blue sky - a dark red pickup read as ice-blue,
  and with the clearcoat off the same car was dark red. `sky.gdshader` now puts the street
  (`reflect_ground`, a warm grey following the horizon's brightness) under the horizon in the
  cubemap pass only (`AT_CUBEMAP_PASS`); the sky you see is unchanged. The basecoat metallic is
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
- HUD: `scenes/ui/debug_hud.tscn` holds the stats, weapon list, crosshair, the round minimap and
  the wanted stars and health bar (`WantedHud`, see the Police note).
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
- Pause menu (`scenes/ui/pause_menu.tscn`) owns Esc: pause, mouse release, seed rebuild via
  `WorldState.pending_seed` + `reload_current_scene()`.
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
  (`uniform_material()`, only on the rigs in `OFFICER_MODELS` - k's yellow blazer and h and l's khakis do not take
  it) and a peaked cap; COVER at the ends of its cruiser, ENGAGE, SEARCH the area, REBOARD when
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
  and stop for a siren behind them (`siren_yield_distance`). Police cruisers are not in the
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
- Aircraft: `Aircraft` (`scripts/vehicles/aircraft.gd`) extends `Vehicle`; kinds PRIVATE and
  AIRLINER, flight numbers are exports at the top, models in `MODELS`. Jets spawn at
  `MacroMap.apron_spots` from the airport chunk. Terrain bodies carry `CityChunk.TERRAIN_LAYER`
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
  runway (`MacroMap.arrival_runway`); departures line up on the middle runway (the hangars
  stand across the east ends of the other two) and climb out west over the sea.
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
  reads across the basin. Above `disc_rpm` the rotor blades are swapped for
  `shaders/rotor_disc.gdshader` (real blades strobe). Sound: Sfx `jet_loop` / `rotor_loop`,
  real CC0 recordings, with a long falloff and a cheap Doppler. **Trap:** give an aircraft its
  transform BEFORE `add_child()` (`AirTraffic._place_before_entry()`). Godot derives a kinematic
  body's velocity from how far it moved in a step; one that entered at the origin and was put
  two kilometres away moved at ~170 km/s for a step, and a player standing at the origin took
  that as platform velocity and left the map. The checks (`tests/air_traffic_checks.gd`, loaded
  by the smoke test) step aircraft with `advance(dt)` in a loop - minutes of flight in a frame.
  Stills: `AIR=final|takeoff|news|police` on `tools/glshot/still_shot.gd`. The helicopter
  model is `tools/make_helicopter.py` (Blender, headless; ASSETS.md).
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
  the forend (the script moves `grip_left`). Sfx `shotgun` (three real CC0 pump guns) and `pump`.
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
  far city with no far-city code. Around it: one plate per block over `CityPlan.owned_rect()`
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
  a tower's placement is ONE table, `LandmarkDowntown.TOWERS`**: anchor, radius, height (real
  metres: the 335 m sail with a spire, the 310 m round tower with the lit glass crown, the 262 m
  white slab, ...), plan (checked against the built geometry), crown, and an APPROXIMATE real
  position in metres east/north of `REAL_ORIGIN` with a real footprint, for the planned 1:1
  re-lay (`real_grid()` turns it into the real street grid's frame). `Landmarks.all()` appends
  `LandmarkDowntown.entries()`, so a re-lay changes the table, the pinned grid and the core
  rects. The current plan is the real grid laid one real block to one game block (about 2/3
  scale) with footprints near real size. Each tower is built by
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
  on this seed and another). The blocks are fixed because **`CityPlan.PINNED_ROADS`** pins the
  downtown street grid for every seed - the default seed's own roads to the last bit, so that
  city did not move; on other seeds the seeded blocks either side stretch or split to meet them
  (`CityPlan._next_road()`). Between the towers, `MacroMap.downtown_core` (two rects) +
  `core_margin` make the district DOWNTOWN and the skyline boost 1, and DISTRICTS DOWNTOWN's
  `core_height` / `core_curve` / `core_shapes` / `core_finishes` / `core_courtyard` turn the
  infill into a field of 40-205 m towers, a quarter of them over 130 m (never over the named
  ones; no SLAB, which caps itself at 40 m and would disagree with the far tier's box; more
  stone than glass). The minimap only labels a pin with `LABEL_ROOM` pixels of
  room. Stills: the skyline from the south-west `--spawn=-50,1250,-43,5,80`, from the hills
  `--spawn=350,-950,-170,-9,380`, on the avenue `--spawn=589.2,860,0,16,2`, with `HIDE=Visual`
  on `tools/glshot/city_shot.gd` (hides the player, who otherwise stands in the middle of it).
  **Downtown at 1:1 is prepared but not landed**: `DowntownReal` (`scripts/world/downtown_real.gd`,
  DATA ONLY, nothing calls it) holds the real grid fitted from OpenStreetMap (bearing 37.86
  degrees, every avenue's and street's position, width and residual), the geocoded landmark
  points, the freeway alignments and the frame (real origin, turn, game anchor - the Esplanade's
  replica-area idea); the re-lay that consumes it is `tools/downtown_relay/relay.patch`, with the
  landing steps in docs/HANDOFF.md 9p. The `real` metres in the tower and civic tables are from
  memory with the wrong bearing (45 / 36) - use DowntownReal's points instead.
- Downtown civic set (owner, 2026-09-24: "downtown must match real downtown LA, we need staple
  center"): the same exception as the skyline - the real buildings' FORMS in their real places
  relative to the core, every NAME invented (no real arena, sponsor, team, hotel, museum,
  hall or station name anywhere, the LED slides' brands included). South-west of the core, `LandmarkArenaDistrict` (`scripts/world/landmark_arena_district.gd`):
  `arena` (RANDO ARENA: oval bowl on a stepped podium, glass ring leaning out, banded metal drum,
  domed roof you can land on, corner marquee with LED screens), `live_plaza` (STARLIGHT PLAZA with
  the STARLIGHT THEATER, screens, neon, crowd), `live_hotel` (HOTEL ALTAIR, 200 m slab with a lit
  crown), `convention_center` (white hall, two tilted green-glass pavilions). North-east,
  `LandmarkCivicCenter` (`landmark_civic_center.gd`): `ziggurat_hall` (CITY HALL - moved off the
  road at x 824 and out from under the 110 deck, floodlit), `civic_park` (CIVIC PARK: fountain
  terrace, lawn, pink furniture), `concert_hall` (SYMPHONY HALL, steel sails from
  `tools/make_concert_hall.py`), `lattice_museum` (THE LATTICE), `pueblo_station` (PUEBLO
  STATION). **One table places them all: `CivicSites.SITES`** (`scripts/world/civic_sites.gd`):
  anchor, footprint (own frame), yaw (quarter turns) and the real building's lat/long, size and
  facing; `CivicSites.real_en()` is the real position in the SKYLINE table's frame (metres east
  / north of `LandmarkDowntown.REAL_ORIGIN`, like a tower's `real`; `real_metres()` has z south,
  `real_grid()` turns it onto the real street grid) - the owner's long-term goal is downtown at
  1:1, and a re-layout should change only the two tables and the pinned grid. Builders work in a frame centred on their site; `CivicSites.build()` puts a turned
  pivot with its own static body in the world, and anything that needs world coordinates (crowd
  rects, the chunk's grass) goes through `CivicSites.to_world()` / `rect_to_world()`, with the
  chunk in `CivicSites.ctx`. They are **block sites**: `"site": "block"` in `Landmarks.all()` makes
  `Landmarks.claims()` true for the block the anchor falls in, so `CityPlan.lots()` returns
  nothing there and `CityPlan.block()` overrides its park/plaza/mall roll (AFTER the roll, so no
  seed moves); every builder lays itself out inside `Landmarks.site_rect()` (the block inside its
  pavement ring), so nothing ever stands on a road whatever the seed. Anchors are the default
  seed's block centres; radius only flattens relief and stays inside the block. Crowds:
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
  **The park is OFF by default** (`LandmarkMacArthurPark.enabled`; docs/HANDOFF.md 9p says why and
  what is left); the encampments are on. Its entry's table is `"area"` (the civic set's
  `"site": "block"` is a different thing).
  `LandmarkMacArthurPark` (`scripts/world/landmark_macarthur_park.gd`) keeps everything real in
  ONE table, `SITE` (lat/long, the real offset from Pershing Square, real size, Wilshire's real
  heading, the lake outline in the south half's 0..1 frame) plus today's compressed placement
  (`anchor`, desired edges). Its `Landmarks.all()` entry carries a `site`, which
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
  `_build_sidewalk_props`) on DOWNTOWN `BUILDINGS` blocks only, some streets far more than
  others (`CAMP_STREET_SHARE`, `FACE_ODDS*`), runs laid along the building line (walls from
  `StreetDetail._footprints()`) with doorway gaps, corner and prop clearance and a kerb-side
  `PATH_KEEP` the block's walkers keep to. **Every roll is a hash of seed, block and face,
  never the chunk rng.** Pieces are `PropFactory.encampment(piece)` from
  `assets/models/encampment_kit.glb` (`tools/encampment_kit.py`, Blender), batched as
  `camp_<piece>` with colour and a per-instance sun-bleach in the instance custom
  (`shaders/encampment*.gdshader`); each knockable piece is an `EncampmentItem` static body
  (props + npc layers, mask 0: bullets, blasts and bumpers hit it) that turns into a
  `PhysicsProp` debris copy when hit and stays gone (WorldState). Caps `MAX_ITEMS` 34 /
  `MAX_SLEEPERS` 6 a chunk, FULL chunks only, `DRAW_DISTANCE` 190 / 120 m. The people are
  `RoughSleeper` (`scripts/npc/rough_sleeper.gd`, extends Pedestrian, so shot, knocked, bled and
  ragdolled like anyone, and counted in the crowd cap through `take_crowd_room()`): poses SIT,
  LIE and SLUMP held by overriding bone poses over a paused idle clip, solved per rig from its
  own rest pose (aim a bone's child direction, like `fix_arm_pose()`), with breathing and sway;
  gunfire makes the sitting and lying get up and FLEE (then RETURN and settle) and the slumped
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
  `masjid_lattice.gdshader`, `masjid_marble.gdshader`. It replaced the original design Masjid
  Al Noor on the same parcel, whose south pavement plays Exposition.
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
  generates in `_ready()`. Every box part uses `shaders/building.gdshader` with its own
  ShaderMaterial (see the decisions log for why). Rooftop props are primitives built in code.
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
  **Shader files use `//` comments, not `##`** - a `##` line is a syntax error and Godot falls
  back to a blank white material, which looks like a missing texture rather than a broken shader.
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
  Past `lod_far` (140 m) a pedestrian swaps to a welded far body (`Pedestrian.far_mesh()`, at
  most `far_triangles`, built during loading): the models are unwelded, so the importer's LODs
  stop at ~4,150 of 16,600 triangles and a figure eleven pixels tall still cost 4k; welded,
  the simplifier goes down to a few hundred. Street frame 7.7 M -> 6.6 M.
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
  one LOD for every instance from its nearest point (and distance 0 whenever the camera's plane
  crosses its box), so every tree in the blocks around the player went into all four cascades
  at full detail. Now every imported model and the palms get `PropFactory.shadow_proxy()` - the
  coarsest generated LOD that keeps 45 % of a leaf surface or 25 % of anything else, with the
  same materials so cut-out and sway still match - and `MultiMeshBatch.build()` draws it as a
  SHADOWS_ONLY twin (`BatchShadow_<key>`, sharing the instance buffer; `hide_instance()` hides
  both) while the batch itself casts nothing. Godot's own `shadow_mesh` cannot do this: it only
  serves materials with no cut-out and no vertex motion. Car bodies do the same with a twin of
  the body mesh at `Vehicle.BODY_SHADOW_LOD_BIAS` (a car's box is small, so plain LOD bias
  works there). Palms had no LODs at all until this (22.6k triangles at any range). Lettering
  (`text_` batches) casts nothing. Street frame 9.4 M -> 7.7 M triangles with no visible change
  (before/after renders in the handoff). Never run two lavapipe renders at once: each city is
  6-7 GB of RAM and the box has 16. Occlusion culling is on
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
  `--headless`. `AB=Batch_sig_*,BatchShadow_sig_*` counts the same frozen frame again with the
  matching nodes hidden, so one kind of geometry's cost comes out of one run. Measure a geometry change before and after with it rather than arguing about it.
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
