# Handoff: Rando Game (written 2026-09-19; section 9a added 2026-09-21 with the LA pass and the grade)

This is the narrative handoff for whoever picks the project up next, from any Claude Code account
or as a person. `CLAUDE.md` is the rulebook and `docs/GAME_PLAN.md` is the roadmap plus the
decisions log; both stay the source of truth. This file is the story: where things stand, how
the day-to-day work goes, what is fragile, what to do next. Read all three before touching code.

## 1. What this is, in one paragraph

A 3D open-world chaos sandbox in Godot 4.7.2 (GDScript, Forward+ on desktop, Compatibility on the
web). Overpowered player (super jumps, unlimited boost, no fall damage), unlimited guns, an endless
seeded city with a west-coast layout (ocean, beach, pier, hills with a big sign, downtown skyline,
campus, airport, port, a peninsula in a bay), drivable cars, flyable jets, pedestrians that
ragdoll, traffic, day/night, a real sky. Everything original: no real names, logos or maps.

## 2. The owner and how they work (this decides everything)

- Prompts from a phone, usually cannot open the Godot editor. Everything must be doable by editing
  text files. Never leave a step that needs a click in the editor.
- Plays two ways: the macOS app from GitHub Releases (https://github.com/ashalluf/rando-game/releases/latest,
  first launch needs "Open Anyway" in Privacy & Security) and the browser build at
  https://ashalluf.github.io/rando-game/ (GitHub Pages, deployed by the same workflow).
- **Push straight to `main`. No branches, no pull requests.** Their explicit decision. Small pushes
  with "How to test" in the commit body and in the chat reply, plus the tunable values most likely
  to need changing. End every push report with the build number (`build-N`, the release tag).
- Standing rules they gave: **high-poly and realistic, never a low-poly look** (2026-09-19, they
  are aiming at consoles); **no more Meshy, Poly Haven only** (2026-09-19: "your Meshy assets
  suck, you can't color them properly"); the rifle is an AK-47; boost replaced sprint; **every Meshy prompt
  asks for the most ultra-realistic result possible**; they want more NPCs, a GTA-5-like skyline,
  a gorgeous sky, hills with roads and estates, a campus, a peninsula in the ocean, a bigger
  airport with flyable jets (all delivered in builds 46 to 51, see section 6).
- They report feel problems in plain words ("jump feels floaty", "can't turn"). Fix by tuning the
  `@export` values at the top of the relevant script and say exactly what changed.
- Tone of replies they like: short, direct, no fluff, tell them what to try. **Always attach
  screenshots in the chat** (owner, 2026-09-19: "so I don't need to do a git fetch every time").

## 3. Repository map

```
project.godot            main scene scenes/levels/city.tscn; autoloads; input map; shader globals
CLAUDE.md                rules and conventions (read first)
docs/GAME_PLAN.md        roadmap, queued requests, current state, decisions log (newest on top)
docs/ASSETS.md           every external asset with source, license, credits spent
docs/HANDOFF.md          this file
scenes/levels/city.tscn  the game: CityStreamer root, WorldEnvironment (sky shader), Sun, Player, DayNight, HUD, pause
scenes/levels/test_box.tscn  greybox test room used by the smoke test
scenes/player/player.tscn    CharacterBody3D + camera rig + weapon mount
scenes/ui/               debug_hud (stats, hints, crosshair, round minimap), pause_menu (Esc, seed)
scripts/player/          player.gd (movement, boost, jumps, vehicles, fall recovery), camera_rig.gd
scripts/weapons/         weapon.gd base, assault_rifle, rocket_launcher, rocket, explosion, shotgun, weapon_fx, weapon_manager (models: assets/models/weapon_*.glb from tools/make_weapons.py)
scripts/world/           city_streamer, city_chunk, city_plan, macro_map, hill_roads, landmarks, building, prop_factory (primitives + model_* merged Poly Haven models), street_props, trash_can, physics_prop, day_night, ferris_wheel
scripts/vehicles/        vehicle.gd (cars), aircraft.gd (jets)
scripts/npc/             pedestrian.gd, ragdoll.gd, traffic.gd, police*.gd, street_route.gd (the police's street routes)
scripts/util/            physics_budget.gd, world_state.gd, sfx.gd (autoloads; sfx.gd also builds the audio buses), ambience.gd (the city's sound, a node in city.tscn)
scripts/ui/              debug_hud, minimap, minimap_frame, minimap_border, crosshair
shaders/                 building, grass, terrain, sky
assets/textures/         CC0 PBR sets from ambientCG (1K JPG)
assets/models/           Meshy .glb models, their .json manifests, extracted textures, .import files, thumbs/
tools/meshy.py           Meshy API pipeline (generate, texture, rig, animate, download)
tools/ambience_audio.py  Freesound CC0 search / verify / fetch and the ambience clip cutter (section 9m)
tools/shrink_glb.py      shrinks embedded textures to 1K JPEG, --desaturate for car paint
tools/pack_gltf.py       packs a Poly Haven .gltf + .bin + textures into one .glb
tools/decimate_tree.py   reduces Poly Haven trees, bushes and rocks to game size (needs pymeshlab: pip install pymeshlab, apt-get install libopengl0)
tools/webshot/           Playwright screenshot harness for the web build (see section 5)
tests/                   headless_check.sh + smoke_test.tscn/.gd (126 checks)
.github/workflows/godot-check.yml  CI: check, export macOS + web, publish release, deploy Pages
export_presets.cfg       macOS and Web presets (no credentials)
```

## 4. The loop for every change

1. Edit text files. Keep feel numbers as `@export` with a `##` comment.
2. Run the headless check (about 4 minutes):
   ```
   GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 tests/headless_check.sh
   ```
   It imports the project and runs `tests/smoke_test.tscn`. It fails on any script error, parse
   error or NaN. Never push red.
3. Optional but recommended for visual work: export the web build and screenshot it (section 5).
4. Update `docs/GAME_PLAN.md` (decisions log entry, newest on top) and `CLAUDE.md` if a convention
   changed. Update `docs/ASSETS.md` for any asset.
5. Commit with a short imperative subject and a body that says why and how to test. Push to
   `main`. The remote also has a mirror branch `claude/new-session-gm161g` that earlier sessions
   force-pushed to keep in sync; it is not needed and can be ignored or deleted.
6. Wait for the workflow (about 2 to 4 minutes). It publishes `build-N`. Tell the owner the number.
   Check it really passed; CI run 46 failed once on a physics-flaky check, fixed in build 50.

## 5. Setting up a fresh session (nothing is preinstalled anywhere)

```
# Godot headless (Linux) and export templates
curl -sSL -o godot.zip "https://downloads.godotengine.org/?version=4.7.2&flavor=stable&slug=linux.x86_64.zip"
unzip -q godot.zip && chmod +x Godot_v4.7.2-stable_linux.x86_64
curl -sSL -o templates.tpz "https://downloads.godotengine.org/?version=4.7.2&flavor=stable&slug=export_templates.tpz"
mkdir -p ~/.local/share/godot/export_templates/4.7.2.stable && unzip -q -j templates.tpz -d ~/.local/share/godot/export_templates/4.7.2.stable
# (github.com downloads were blocked by the proxy in the previous environment; downloads.godotengine.org worked)

# Web build + screenshots
Godot_v4.7.2-stable_linux.x86_64 --headless --path . --export-release "Web" build/web/index.html
cd tools/webshot && npm install && QS='?spawn=8,30,0,-12&showroom&hour=11' SHOT=shot.png node webshot.js
# Chromium: the previous environment had it at /opt/pw-browsers/chromium-*/chrome-linux/chrome;
# edit the executablePath in webshot.js or set PLAYWRIGHT_BROWSERS_PATH. Playwright's own
# `npx playwright install chromium` also works if the network allows it.

# Meshy tooling
pip install pillow
export MESHY_API_KEY=...   # never in the repo; the owner has it
python3 tools/meshy.py balance
```

Screenshot harness facts that cost hours to learn: the web build runs at about 1 FPS under
SwiftShader and Godot clamps frame time, so a 1 ms key tap in Playwright walks the player meters
and a 25 s in-game timer takes minutes of wall time. The harness presses no keys. Place the
camera with `?spawn=x,z,yaw,pitch[,y]` (desktop: `-- --spawn=...`), jump the clock with
`?hour=17.5`, and use `?showroom` to line up every car, pedestrian and jet at the spawn. Web
lighting is flat: judge geometry, materials and layout, not light. Forward+ effects (SDFGI, SSR,
volumetric fog, glow) have never been seen by any Claude session; only the owner's Mac shows them.

**Native renders without a browser (added build 64, `-- --nohud` hides the overlay):** the container has Xvfb and Mesa llvmpipe, so
Godot's real Compatibility renderer runs headless-ish and screenshots in ~20 s instead of the
web harness' minutes. `tools/glshot/building_shot.gd` renders one generated `Building` (env
`OUT`, `BSEED`, `FINISH`, `LOT`, `HMIN`, `HMAX`), `tools/glshot/city_shot.gd` renders the city
scene at a `--spawn` (env `OUT`, `FRAMES`). Both start with
`LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3
--display-driver x11 --audio-driver Dummy --path . --script tools/glshot/<file> --resolution 960x540`
(the usage line in each file has the full command). Use the building one to check any facade or
rooftop change before exporting: the build-64 "cage towers" (window frames at twice the wall
height, because a face center that already held the part's Y got the absolute row height added
again) took a whole session of web screenshots to diagnose and one native render to see.

## 6. Where the game stands (build 139)

Everything in the roadmap is done (milestones 1 to 8) plus the LA-style map, the realism passes,
the "map character" batch, the 2026-09-20 owner batch and the 2026-09-21 PS5 push. Recent builds,
newest first:

- 139: the two finished hi-fi car bodies (222k and 217k triangles) plus their generators.
  **Committed but NOT wired in**: `Vehicle.BODY_MODELS` still points SUPER and HYPER at the old
  `exo_*` pair. Flipping those two lines is the next thing anyone should do, because the `exo_*`
  bodies have no wheel arches at all - their own critic measured the front tyre standing 11.8 cm
  proud of the bodywork with bare sky above its outer 12 cm.
- 138: `docs/ASSETS.md` gains a section for the cars we generate ourselves - neither downloaded
  nor Meshy, so they had fallen through the documentation entirely. Records the six material
  slots every car must expose (`paint`, `glass`, `trim`, `tyre`, `light_front`, `light_rear`),
  because `Vehicle._add_body_model()` binds by name.
- 137: two measurement traps written into CLAUDE.md. Both report success, which is the worst way
  to fail, and both cost real time this session. See section 9.
- 136: `tools/geo_count.gd`, the triangle/draw/object counter the geometry work was measured with.
- 135: the geometry budget. 4.65M -> 10.7M triangles at the spawn camera for **twelve** extra draw
  calls: denser grass blades with a crease, palms rebuilt at real density (40 trunk rings, 60
  frond steps, 4 segments a leaflet), and per-surface subdivision numbers for terrain, ground
  grids and the ocean. Every number is an @export in a "Geometry budget" group on `CityChunk`.
  Nobody has measured the frame rate on real hardware - that needs the owner and the F1 stats line.
- 134: surf and shoaling on the ocean, and three fixed defects: the rain curtain fell UPWARD
  (sign error), the lens rain slid UP the glass (`SCREEN_UV.y` runs downward in a canvas_item
  shader), and the five coast uniforms were never pushed at all, because a child's `_ready()` runs
  before its parent's and `CityStreamer._ready()` is what creates `plan`. That last one only
  looked correct because the shader's hardcoded defaults happen to match `MacroMap` exactly.
- 133: bullets know what they hit. Surface-aware impacts, plus two fixes: every shot at the ground
  was classified METAL (the chunk's `StreetProps` body carries every road, pavement, plaza and car
  park as well as the props - measured 400/400 rays METAL before, 400/400 CONCRETE after), and
  warehouse walls rained glass. `tools/classify_probe.gd` aims rays at each case.
- 132: neon anchored to the buildings it hangs on (blade signs were rendering MIRRORED, and neon
  lifted per-instance by the relief while its structure was lifted once came apart on slopes);
  power lines that reach an actual wall instead of stopping in mid-air; poles no longer driven
  through the freeway deck; twilight that ramps instead of snapping 0 -> 0.22 in one frame twice a
  day; god rays that still point at the sun after twenty minutes of play.
- 131: docs only.
- 130: four measured defects, each found by an agent that went looking rather than by play.
  **Pedestrian clothing had never worked on the Mac build at all**: Forward+ and Mobile hand a
  `source_color` texture back LINEARISED and the Compatibility renderer hands back raw sRGB, and
  every threshold in `character.gdshader` was written against the sRGB numbers, so on desktop the
  shader called every garment skin and recoloured nothing. `Pedestrian._texture_value()` now moves
  the thresholds into the current renderer's space at material build time. Hair recolouring was
  also a no-op (0.8% of head pixels reached it; hair is the dark half of the head, so it is found
  by darkness now) and `pedestrian_c` got no garment split at all, because its jacket and trousers
  are the same warm brown as its skin - skin now has to be bright as well as warm. Plus: chamfered
  buildings were missing cornices, copings, string courses, plinths and parapets on two of every
  four cut corners (a left-handed Basis on those corners meant CULL_BACK threw away exactly the
  outward faces); one loudness reference for every sound plus a hard limiter on the master bus
  (peak-normalised recordings are not equally loud - three takes of the rifle were 9.3 dB apart).
- 129: freeways fly over each other instead of through each other. Nothing in the routing ever
  looked at the other routes, so the Coast and Cross decks met with 1.2 m between two 34 m wide
  carriageways. `Freeway._separate_crossings()` lifts the later route 7.5 m clear, easing in and
  out at `MAX_GRADE` so the flyover is drivable.
- 128: Forward+ headless rendering with no GPU. `tools/glshot/forward_shot.sh` runs Godot through
  lavapipe (Mesa's software Vulkan driver), so SDFGI, SSR, TAA, AgX and volumetric fog can all be
  screenshotted from this container. **This matters more than it sounds**: every visual judgement
  in this project's history before build 128 was made on the Compatibility renderer, which has
  none of those, and that is not the build the owner plays. Six minutes a frame, so use
  `city_shot.gd` on opengl3 to iterate and this to sign off.
- 127: real wheels - correct track, radius and per-type ride height (they were all on a 2.0 m
  track with 0.84 m wheels).
- 126: exotics on the street: supercars, spiders and hypercars, as original marques. The owner
  asked for Ferraris, Bugattis and Rolls-Royces; copying their trade dress is not something this
  project will do, so these are cars in the same classes with their own shapes and names.
- 122 to 125: car jumping is unlimited so cars can be flown continuously; kerbside parking fixed;
  lawns stop glowing at night (twice - the albedo boost, then the missing `night_factor` term,
  because roads are lamp-lit and grass is not); facade relief, neon signage and street clutter.
- 112 to 121: the foliage and colour pass. Five city tree species and four hill species at their
  own measured heights (a shared 6-10.5 m target was stretching a 2.61 m model 3x, which is why
  trees read as bare branches), per-instance leaf thinning, hue and shape variation through
  `INSTANCE_CUSTOM` so fifty apparent variants cost zero extra draw calls, jacaranda boulevards
  that actually bloom lavender, flowers and ground cover at knee height, and lawns that read as
  ground rather than green rectangles.
- 104 to 111: real recorded CC0 sound instead of synthesized tones, and the CC0 audio sources
  recorded in `docs/ASSETS.md`.
- 100 to 103: palm fronds folded and swept forward; more colour on the streets;
  `tools/fetch_polyhaven.py`.
- 99: lane paint on the freeway decks (it was being built face-down and culled).
- 98: traffic on the freeways, both carriageways, riding the deck's height profile.
- 97: the horizon map's mountains match the terrain shader, so ranges have no tide-line.
- 96: no grey wall round the valley or along the city/hills seam (two separate height bugs).
- 95: the basin is ringed by real mountains (front range, back range, east range, peninsula)
  with the horizon plane displaced so they have a silhouette; the inland valley is a city built
  on a plateau; and three long curved **freeways** ride an elevated deck across the city on
  pillars, with barriers, lane paint, sign gantries and off-ramps.
- 93: a car's five night lights are one mesh, not five nodes.
- 92: the sea. Real wave normals (it had none, so it was lit as a flat sheet), tight foam, the
  sky mixed in by fresnel with a sun glare path, the sea-floor box dropped below the troughs,
  and the horizon plane sunk away from the camera so it stops z-fighting the water. Plus a
  subtle lens vignette over the whole frame.
- 91: the trees' leaves move too.
- 90: palms sway in the wind, softer trunk bark.
- 89: the HUD starts clean (F1 cycles clean / stats / hidden), the hills burn gold, lawns run
  from watered to burnt, the baked horizon map is jittered so sprawl reads as a city. (88 was a
  docs-only push; the build number is the workflow run number, so it still burns one.)
- 87: the ground stops tiling visibly; car parks, yards and plazas go through the wear shader.
- 86: lamps come on in a storm, the horizon plane stops painting grass over the sea and sand,
  seven skin tones across the crowd, six palm variants, chunkier pilasters.
- 85: shop names on the storefront sign bands, unlit rooms properly dark at night, pilasters
  on LOD commercial boxes too.
- 84: night lighting (street lamps with real lights and pools of light on the pavement, head
  and tail lights and beams on every car), the characters' arms brought down out of their
  scarecrow A-pose, a rebuilt AK-47 at real proportions, and pilasters and base bands on the
  blank walls of big-box stores and strip malls.
- 83: the horizon. Everything outside the streamed chunks used to be a 4 km flat green plane
  whose own edge was the skyline. It is now 14 km across and shaded from a baked image of the
  whole basin (`MacroMap.bake()`), with relief shading and haze that hands over to the sky.
  Clouds are lit by sampling toward the sun (bright shoulders, grey undersides) with a cirrus
  deck above them; palm trunks carry the frond-base lattice.
- 82: dark asphalt (road and pavement had measured to the same grey), crack and stain noise at
  the right scale, real shopfronts (sign band, bulkhead, mullions, doors), feathered palm
  fronds with smooth normals, and the naked orange pedestrian removed (pedestrian_b came back
  with no clothes on it; a smoke check now measures this).
- 81: glass reflects sky and street by fresnel, rooms exposed for daylight, grime that runs from
  the sills, per-window frame tints, fire-escape ironwork that reads as metal.
- 80: fire escapes on brick walk-ups.
- 79: roof coverings (membrane / gravel / bitumen) and much more rooftop plant.
- 78: far skyline gets parallax windows and floor bands; ground wear toned down; aerial shots
  hold their height in tools/glshot/city_shot.gd.
- 77: balconies on residential facades; muted awning canvas colours.
- 76: pavements get expansion joints and per-slab shade through the same wear shader.
- 75: worn asphalt shader: mottling, resurfacing patches, cracks, oil staining, wet roads.
- 74: interior mapping on every window: real rooms with blinds behind the glass.
- 73: character pass: per-person clothing colour, height and gait, proper skin and cloth
  shading. Further realism is blocked on a Sketchfab API token (see the decisions log).
- 72: real generated palm trees and palm-lined streets across the city.
- 71: cars fly (stabilised air control, boost thrusts along the camera), rebuilt explosions
  (light flash, fireball, smoke, sparks, shockwave, scorch, camera shake), `tools/glshot/fx_shot.gd`.
- 70: cinematic realism pass: AgX tonemapping, sky-coloured ambient, SSIL, aerial-perspective
  and height fog, TAA + FSR 2.2, auto exposure, clearcoat car paint with a realistic palette,
  real grass blades.
- 69: quality levels scale crowds and traffic too; frame-time breakdown on the HUD.
- 68: starts fullscreen (F11 toggles), Meshy textures VRAM-compressed.
- 67: spawn lifted onto the rolling ground, under-ground recovery in city zones, 60 FPS cap.
- 66: populated city: people and parked cars per district (downtown core 2x), traffic density by
  distance from downtown, airport drop-off loop road with 90 crawling cars and a curb crowd.
- 65: animated main character (`Avatar`), ragdolls keep the real model, first lag pass
  (`Quality` node, flat window frames with a draw distance, pedestrian update throttle).
- 64: facade geometry (frames, cornices, awnings), Poly Haven rooftop AC units, `tools/glshot`.
- 63: weather (overcast / rain / storm, lightning, wet streets) and tsunami-size waves.
- 62: shopping plazas, big-box stores, fast-food and gas-station pads, lawns, pocket gardens.
- 61: street detail (stop lines, arrows, street-name signs, poles and cables, bus shelters).
- 60: cars drive forwards, two-tone paint shader, far-box windows, new minimap, unlimited jumps.
- 59: city relief (rolling ground under the blocks), seeded surface variation per district.
- 52 to 58: Poly Haven props, trees, rocks, PBR wall textures, sky haze fix, screenshot rule.
- 51: bigger airport (3 runways, hangars, jet bridges), flyable jets (`Aircraft`), AK-47 bullets
  now hit pedestrians (they were on the wrong physics layer for months of session time).
- 49: campus district and the campus hall landmark ("RANDO U").
- 48: hill road network with carved terrain, estates (villa, pool, palms), peninsula in a bay,
  ocean visible again (it had been rendering as grass under the ground follower plane).
- 47: skyline: taller downtown core, setback and crown towers, spires, the needle, twin towers.
- 46: custom sky shader: sun disc, clouds, golden hour, stars.
- 45: all seven Meshy models regenerated realistically; crowds doubled (160 people, 24 traffic
  cars on desktop; 80 / 14 on the web).
- 44: cars and pedestrians use Meshy models; `?showroom`.
- 43: the "stuck under the world" bugs (three real causes, see the decisions log).
- 42: fall-through recovery, Space jumps the car, round rotating minimap.

Meshy credits: 1,680 at the start, 1,221 after the owner topped up; each car 30, each rigged
pedestrian 44, each jet 30. `docs/ASSETS.md` has the table.

## 7. Architecture in ten bullets

- `CityStreamer` is the scene root: streams `CityChunk`s around the player (FULL near, LOD far),
  keeps a 4000 m ground follower under the player (40 m thick), re-centers the origin when far
  from 0 (`WorldState.world_offset`; everything that must survive that is a 3D child of the root),
  handles `?spawn`, `?showroom`, `surface_height_at()` and `ensure_loaded_at()`.
- `CityPlan` is lazy endless data keyed by block index; `MacroMap` decides zone, district and
  height for any world XZ; `HillRoads` carves roads and mansion pads into the terrain height.
- `CityChunk` builds one block: roads, sidewalks, lots of `Building`s (shader-driven boxes), props
  via `MultiMeshBatch` with breakables on the chunk's `StreetProps` body, parked cars and jets
  spawned under the city root and freed with the chunk unless driven, terrain / water / sand /
  tarmac for other zones, hill roads and estates, landmarks in its rect.
- `Landmarks` is a static list with builders; far copies always exist, detailed ones per chunk.
- `Vehicle` is a VehicleBody3D built in code (box collision, Meshy body model tinted by paint);
  `Aircraft` extends it with an arcade flight model; `TrafficManager` drives kinematic ones.
- `Pedestrian` is a CharacterBody3D wandering a sidewalk ring with a rigged Meshy model
  (`custom_aabb` needed, faces +Z, material sanitized), becomes a box `Ragdoll` when knocked.
- `Player` handles movement, boost, jumps, weapons, riding, exit-spot search, and recovery from
  falling through the world or ending up under hill terrain (terrain has its own physics layer).
- `DayNight` drives the sun, the sky shader's colors and `night_factor`.
- Physics layers: 1 world, 2 player, 4 props, 8 npc, 16 terrain. `Player.AIM_MASK` = 1|4|8.
- `PhysicsBudget` caps live rigid bodies and never freezes vehicles (frozen wheels give NaN).

## 8. Hard-won gotchas (the full list is the decisions log)

- The city ground is not flat: `MacroMap.relief_at()` rolls up to 16 m. Chunk code samples it
  through `_gy()`; the multimesh batch and `_add_slab()` / `_add_prop()` add it for you, nodes
  you position yourself need it added once. Buildings carry a concrete plinth for the slope.
- Never `reparent()` a VehicleBody3D; never freeze one; never give a kinematic one wheels.
- Godot's `engine_force` pushes toward local +Z; the car negates it.
- Physics queries are stale for a frame after an origin shift (`_query_hold`).
- Bodies spawned overlapping a static shape get shot through thin floors; far chunks now carry
  collision for buildings and terrain so nothing sits inside a footprint when detail arrives.
- Every Meshy car model has its nose along +X: `Vehicle.MODEL_YAW` -PI/2 puts it at -Z, the
  physics forward. Car paint is `shaders/car_paint.gdshader` (luminance split), not a tint.
- Meshy: rigs have a cm skeleton under a 0.01 armature; animated exports drop PBR maps and set
  metallic 1 + emissive; models come out along +X or -X (`MODEL_YAW` tables); car paint needs the
  base color greyscaled (`shrink_glb.py --desaturate`) so the tint works.
- The smoke test is physics-driven and can flake; the driving checks now start on a cleared
  road with traffic and crowds removed, and the jet taxi lane must stay clear of landmark parts.
- The `.import` files and extracted `_N.jpg` textures next to `.glb` files are import output and
  are committed; stale `*_texture_0.png` files from older imports get deleted before committing.
- `project.godot` must stay in Godot's own section order or the editor rewrites it.
- `import_etc2_astc=true` must stay on or the universal macOS export fails.

## 9. Known gaps and things nobody has verified

Rewritten 2026-09-21 at build 130.

- **Two measurement traps that report success.** Both are in CLAUDE.md; both cost time this
  session. (1) Godot serves a CACHED import of a `.glb` or a texture, so a render taken after
  rebuilding a model shows the OLD file - run `--import` in between, and print the model's AABB
  in the shot script to catch it. (2) `--headless` is the dummy rendering server: every
  `Performance` monitor reads exactly zero and `MultiMesh.get_instance_transform()` returns
  identity, so a geometry change of any size measures as no change and an instance-transform
  check measures nothing while reporting a clean bill of health. Use `tools/geo_count.gd` under
  opengl3 with Xvfb.
- **Agent work is not finished work.** Most of what landed in builds 130-139 came from fleets,
  and roughly half of what they produced was wrong in a way only a render or a probe would show:
  rain falling upward, blade signs mirrored, every ground shot classified metal, shut lines that
  measured as cut and were sub-pixel, wheels that were actually the arch lining. The pattern that
  worked was build -> adversarial review -> repair, with the reviewer rendering independently.
  The pattern that failed was trusting a summary. Also: a critic saying `ok: false` means do not
  ship it, and a reviewer's claim you cannot reproduce means do not "fix" it - one seam fix was
  made for a seam that was never there.
- **A human has still never confirmed what the Mac build looks like.** Build 128 made Forward+
  screenshots possible from this container (`tools/glshot/forward_shot.sh`), which closes the
  worst of the gap, but lavapipe is not a GPU and the owner's eyes are still the only real test.
  Build 130's crowd fix is the cautionary tale: a whole subsystem had been broken on desktop only,
  invisibly, because every screenshot taken of it for weeks was the web renderer.
- **Characters are the weakest thing in the game and are blocked on a source.** Three rigs, 8,300
  triangles, one 1024 texture each, no normal or roughness maps. Everything reachable in code -
  arms, clothing colour, skin tone, height, gait, accessories - has now been done, twice. What is
  left needs better models. Poly Haven's "rigged" category is articulated props (clocks, tools),
  not humans. The owner would have to supply a Sketchfab API token
  (sketchfab.com > Settings > Password and API).
- **The surface street grid is still axis-aligned.** The freeways and the hill roads curve; the
  streets between the blocks do not, and the owner has asked about it directly.
  `CityPlan.road_pos()` is one scalar per axis and every consumer (blocks, lots, traffic lanes,
  the minimap) assumes axis-aligned rects, so this is a rewrite of the city plan, not a tweak.
  Decide with the owner before starting it - it is days of work and it moves every seed.
- Ragdolls are one tumbling rigged body, not a simulated skeleton (PhysicalBoneSimulator3D).
- Traffic drives the city grid and the freeways; hill roads and the airport aprons have none.
  Parked cars do not spawn on hill roads. Pedestrians do not walk the campus quad or the hills.
- Jet landing has not been exercised beyond the smoke test's takeoff. Gear is tiny and hidden
  under the model; the flight model is arcade and may need tuning (`aircraft.gd` exports).
- The moon is the sun light re-aimed at night; the sky draws its disc where LIGHT0 points.
- LOD terrain (6 subdivisions) vs FULL (14 or 28) can pop at the swap; hill road cut walls are
  steep where the road profile drops well below the raw terrain.
- The web build carries all the models and runs slowly on weak machines; caps are lower there.
- The Meshy API key the owner pasted in chat during this project should be rotated. Meshy itself
  is retired (owner, 2026-09-19), so nothing needs the new one.

## 9a. The LA pass, 2026-09-21 afternoon (newest work)

The owner asked for the map to be a miniature of the real Los Angeles, naming PCH, Palos Verdes,
Redondo and Manhattan piers, Santa Monica, Venice, Malibu, Del Amo, Urth Caffe, a masjid, USC and
the 405 / 110 / 105. The basin already had LA's shape; what it had no version of was the coast
road, the chain of beach towns, or any of the named places.

Delivered, all green and on main:
- **Pacific Coast Highway**, from the northern cliffs to the far side of the headland, held 46 m
  in from the waterline so it inherits the shore's own bends. It needed a **coastal shelf** in
  `MacroMap.raw_height_at()` first: up north the front range runs into the water, so the road
  would have been a cutting in a 560 m mountainside. The shelf cuts a 300 m bench at 26 m along
  the shore north of z -700 - mountain, bench, road, sea - fading out southward and never
  touching the headland, whose cliffs into the water are the point of it.
- **Eight named beach towns** (Malibu, Santa Monica, Venice, Playa, El Segundo, Manhattan,
  Hermosa, Redondo) plus Palos Verdes, surfaced through `MacroMap.place_name()`, which the HUD
  prefers over the zone and district names. A **BEACHTOWN district**: denser than the suburbs
  and much lower, heavy weathering, metered kerbs, the palmiest district on the map.
- The headland moved from z 1500 to **1980**, because at 1500 it started exactly where Manhattan,
  Hermosa and Redondo needed coastline.
- A fourth freeway (**110**, downtown to the port) and real numbers on the other three.
- **Six landmarks** built by an agent fleet, each a self-contained `scripts/world/landmark_*.gd`
  wired into `Landmarks`: Venice boardwalk, Manhattan pier, Redondo pier, South Bay Mall,
  Verde Cafe, Masjid Al Noor.
- **The beach follows the shoreline** instead of being a chunk-sized slab, with a two-slope
  profile that breaks at the waterline, and is laid by whichever chunk the waterline crosses
  (`_owns_shoreline()`) regardless of that chunk's zone.

**Naming rule applied, and worth keeping.** Geography and route names are used as-is: Malibu,
Santa Monica, Venice, Manhattan Beach, Redondo, Palos Verdes, PCH, 405, 110, 105. Business and
institution trademarks are not: Del Amo became South Bay Mall, Urth became Verde Cafe, and the
mosque is an original design named Masjid Al Noor rather than a model of a real one. Same rule
the project already used for RANDOWOOD and the exotic marques.

**Two silent errors, both fixed, both had been passing the gate.** `tests/headless_check.sh` only
tripped on "SCRIPT ERROR", and Godot prints engine errors as plain "ERROR", so a run reporting
195 passes was logging 310 of them: the beach generated tangents with no UVs (so its normal map
did nothing) and freeway traffic was positioned before being added to the tree (253 a run, every
car placed against no parent transform). The gate now catches both. **If you add a system, check
the log for bare ERROR lines - a green run is not proof.**

**Depth of field now opens with altitude** (`CameraRig._update_focus`). It was fixed at 260 m,
which reads as a lens on the street and is simply wrong in the air, where the owner spends much
of their time: every pixel past that distance went soft, so aerials looked like watercolours.

**The render pass is half done.** An agent fleet was raising four subsystems - sea, foliage,
facades, colour grade - and was stopped partway because four concurrent Forward+ renders on a
four-core box drove the load average to 45 and starved everything else. The sea and foliage work
IS on main (depth-graded water colour, subsurface scattering through crests, gathered foam,
physically correct fresnel at F0 0.02). **Facades and the colour grade were never started.**

**The colour grade: done, and here is what it actually was.** The symptom was right - a Forward+
aerial was pastel with no value contrast - but the cause was not the fog. Measure a frame instead
of looking at it:

```
python3 -c "from PIL import Image; import numpy as np; g=np.asarray(Image.open('shot.png').convert('L')).astype(float); print([round(float(np.percentile(g,p))) for p in (1,5,50,95,99)])"
```

The midday downtown aerial came back `[51, 78, 103, 137, 214]`: **the whole city lived between 78
and 137 of 255**. The same scene through the opengl3 path measured 51 to 185. The difference is
**AgX**. AgX rolls an enormous range into the screen and, unlike ACES, it is designed to have a
"look" - a contrast curve - applied after it. There was none, so every frame came out as the flat
middle of the AgX curve. The fog made it worse but the fog was never the cause; turning the haze
down alone moved p95 by six levels.

What is on main now:
- A **look LUT**: a `Gradient` / `GradientTexture1D` pair in `city.tscn` wired to
  `Environment.adjustment_color_correction`. Godot runs each channel through it separately after
  tonemapping, so it is a per-channel curve, not a tint: an S with a slope of about 1.6 around a
  0.45 pivot, cool in the toe and warm in the shoulder. `adjustment_contrast` is back to 1.0 -
  the LUT owns contrast now, and stacking the two crushes the toe.
- **Exposure that opens after dark** (`DayNight.day_exposure` 1.25, `night_exposure` 2.1, lerped
  on `night_factor` onto `Environment.tonemap_exposure`). Eye adaptation for free, and it is what
  stops the punchier curve from turning a lamplit street into mud.
- **A key light that out-runs the fill.** `day_sun_energy` 1.0 -> 1.3, `day_ambient_energy`
  0.55 -> 0.30, `ssil_intensity` 1.0 -> 0.5, `sdfgi_energy` 1.1 -> 0.85. A real midday shadow is
  a fifth as bright as the lit side; it was two thirds.
- **Shadows that reach.** `Quality.shadow_distance` was 320 m at HIGH, so everything past three
  blocks was lit but never shadowed - half of every aerial had no contrast available at all. Now
  700 m, carried by four PSSM splits and a fade (`city.tscn`) instead of two.
- **Haze in the distance instead of over everything**: `fog_aerial_perspective` 0.7 -> 0.32,
  density 0.00012 -> 0.00009, volumetric 0.0025 -> 0.0014, and `DayNight` now owns the fog colour
  as three tunables (`day_fog`, `dusk_fog`, `night_fog`) so the far distance goes gold at sunset
  instead of staying blue.

The smoke test guards all of it: the LUT exists, the sun beats the fill by more than 2.5x, and
HIGH shadows reach at least 500 m. The old guard demanded `fog_aerial_perspective > 0.5`, which
had quietly made the washed-out look a requirement; it now only checks the effect is on.

**Fifteen numbers that live in two files.** An audit fanned out over the repo looking for pairs
of constants that have to agree across a file boundary with nothing in code connecting them -
the class of bug where nothing errors and the picture is just wrong. Fifteen survived an
adversarial second pass. The worst by far: `shaders/ocean.gdshader` carries a hand-transcribed,
sRGB-decoded copy of `MacroMap`'s sea palette (`BAKE_OCEAN_DEEP/SHALLOW/SURF`, `BAKE_SURF_WIDTH`
and `bake()`'s `/600.0` shelf ramp), because past `handover_start` the water chunks stop drawing
their own sea and re-draw the far plane's. Re-tune the bake alone and you get a hard-edged
rectangle of differently coloured water about 500 m across, locked to the player, following him
round the bay - which is exactly what that shader's own 25-line header is about.

Two fixes, in this order of preference:
1. **Remove the coupling.** `coast_wobble` (180), `coast_period` (700) and `peninsula_bulge`
   (520) were literals inside `coast_x()`, so the shader had to carry its own copies;
   they are MacroMap fields now and `Weather._push_ocean_shape()` sends them over with the rest.
2. **Guard what cannot be removed.** `tests/smoke_test.gd` now reads the second copy out of the
   other file's source (`Shader.code`, `GDScript.get_script_constant_map()`) rather than writing
   the number a third time, and checks: the ocean shader's sea palette and coastline defaults
   against MacroMap; `valley_height` against `built_amount()`'s 420 m gate; `Commercial.TOP`
   against `CityChunk.SIDEWALK_TOP`; and every per-index table against its enum
   (`MacroMap.ZONE_NAMES`, `Minimap.DISTRICT_COLORS`, `Vehicle.BODY_NAMES/MODELS/ODDS` including
   the sum-to-1000 rule, `Weather`'s five per-state tables, `Quality`'s three per-level ones).
   All six guards were checked by breaking each value and watching the right one fail.

The other nine are in the audit and still unguarded, mostly duplicated geometry: the airport
tarmac top (0.1) is written in four places, the terminal kerb rect and its drop-off lane paths
are two independent sets of coordinates, `StreetDetail.POLE_HEIGHT` is 9.0 and so is the `upole`
cylinder in `PropFactory`, and `Building.gd` places shop-name meshes at 0.845 of the storefront
while `building.gdshader` paints the sign band at 0.76..0.93. **When you add a number that
something in another file has to know, make it a field and push it, or add the guard in the same
commit.**

**Facades: the whole downtown was pixel art, and it was one line.** A Forward+ street render at
10:00 showed every tower as a random checkerboard of gold and black rectangles, one per window
bay, with no glass in it - no highlight, no sky in the panes, no mullion. `building.gdshader`
already had interior mapping, a Schlick fresnel sky reflection and spandrel panels; four things
were burying all of it, and a three-agent diagnostic fleet found them:
- `float on = 0.12 + 0.88 * night_factor` in the `lit` branch. A window the lit roll picked
  still carried a warm emission at ten in the morning, and `lit_ratio` runs to half the bays.
  **That is the checkerboard.** Same daytime floor in `building_lod.gdshader`, so the distant
  towers did it too.
- The inset shadow that sets a pane back into the wall used `max(du - 0.2, dv - 0.18)` whatever
  the window style. Those two numbers are exactly `win_h - 0.07` for style 0 (PUNCHED) and for
  nothing else, so on a curtain wall (win_h 0.475/0.47) it darkened 86 % of the pane by 45 %:
  every bay a dark rectangle with a lighter card floating in it.
- `frame_color` for GLASS was 0.14, darker than the panes it frames, so the grid a curtain-wall
  tower is made of was drawn and then invisible.
- Window pitch took exactly four values and two thirds of downtown shared 1.8 m.

**The whole city was dressed in black, and it took two goes.** First attempt widened the ranges
and kept the mechanism; the mechanism was the bug. `cloth_value` multiplied the SOURCE texture's
own brightness, and pedestrian_a's garments measure 0.21-0.32 with its trousers lower still -
there is no multiple of near-black that is a white shirt. `cloth_value` / `pants_value` are the
garment's own brightness now, 0 to 1, with the source's value kept as *shading* around it.
`CLOTH_VALUE_BAND` also moved to 0.030..0.075: the rigs' trousers sit at about 0.10, which put
them halfway up the old 0.045..0.13 band, so trousers took barely half the recolour however they
were rolled - colour above the waist, black below it.

**Measure the texture, not the code.** Both of those were found by reading a number out of the
asset rather than out of the source:
```
python3 -c "from PIL import Image; import numpy as np; im=np.asarray(Image.open('assets/models/pedestrian_a_0.jpg').convert('RGB')).astype(float)/255; v=im.max(axis=2); print([round(float(np.percentile(v,p)),3) for p in (10,25,50,75,90)])"
```

**Land no longer stands in the sea.** `zone_at()` draws the shoreline as a hard line and
`raw_height_at()` is a noise field that knew nothing about it, so the two disagreed - most
visibly off the Redondo pier, where the coast bulge (a function of z alone) cut clean across the
headland (a circle) and left a sail of hillside hanging over the water. `MacroMap._shore_mask()`
now brings the land down to zero across `shore_rise` metres wherever the zone says water, at the
coastline and around the bay, and the smoke test sweeps the whole coast and the bay for land
above 4 m.

**Practical note on the fleet.** Cap concurrent agents at two on this box, and do not let agents
run Forward+ renders - have them use the fast opengl3 loop and sign off the result yourself.

## 9b. Paused mid-flight on 2026-09-21 (read this first if you are picking up)

The session was paused with three agent fleets running. They were stopped, their finished work is
on `main`, and what was half-written is saved as patches under **`docs/wip/`** with a README
explaining each one and what is unverified about it. `main` is green at 190 checks with none of
them applied, so you can ignore them entirely if you would rather start fresh.

**The single highest-value thing available, and it is two lines.** `Vehicle.BODY_MODELS` still
points `BodyType.SUPER` and `BodyType.HYPER` at `exo_super_coupe.glb` / `exo_hyper_a.glb`. Those
bodies have **no wheel arches at all** - their own critic measured the front tyre standing 11.8 cm
proud of the bodywork with bare sky above its outer 12 cm, and called it "wheels bolted onto the
outside of a slab". The finished replacements are committed and unused:
`hifi_super_coupe.glb` (223k tris) and `hifi_hyper_coupe.glb` (217k tris), both built the right
way (see `docs/ASSETS.md`) and both carrying their own wheels. Swap the two lines, run the check,
look at a showroom render, push.

Order of the rest, hardest-earned first:

1. Finish the wheels patch. The wheel mesh is already on `main` as dead code (see the correction
   at the end of `docs/GAME_PLAN.md`); only the `Vehicle` wiring is missing. The real insight from
   that work: the four Meshy bodies are 88% of traffic and each has its wheel modelled into the
   painted body surface, so it wore the car's paint. Never a missing wheel - a wrong material.
2. Finish the character PBR maps. `pedestrian_b` was never generated. This one deletes a whole
   class of bug, not just a symptom.
3. Finish the signs patch, minding the u/a mirror trap.
4. Re-run the horizon-ground and road-surface tracks; they died at the spend limit and never
   produced anything. `docs/wip/` has no patch for them because there was nothing to save.

**Blocked on the owner:** the monthly spend cap was hit mid-session and killed four fleets. And
nobody has ever measured the frame rate on real hardware - build 135 took the city from 4.65M to
10.7M triangles at the spawn camera, which is a real jump, and the F1 stats line would settle it
in one screenshot.

## 9c. Session of 2026-09-22 (read this first if you are picking up)

This session was handed over so the owner could move to another account. Everything below is on
`main` and green. Nothing is half-applied and there is no `docs/wip/` to reconcile this time.

### What shipped

**The colour grade (builds 155-168).** AgX filmic tonemapping expects a contrast curve applied
*after* it, and there wasn't one, so every frame was the flat middle of the AgX ramp. That curve
is now a Gradient / GradientTexture1D pair on the city Environment's `adjustment_color_correction`
(`scenes/levels/city.tscn`). `adjustment_contrast` deliberately stays at 1.0 - the LUT is the
curve, and stacking a second one on top is what the first attempt got wrong.

`DayNight.moonlight` was added alongside `night_factor` because `night_factor` reaches 1.0 three
degrees after sunset, which is right for switching the lamps on and wrong for the light: driving
exposure and the sun's colour off it washed the whole city lavender at 18:30. `moonlight` is the
slower ramp; `night_factor` still drives lamps, windows and the shader global.

**The volumetric haze (build 169).** The fog volume was 220 m, which is shorter than the first
block of buildings past the camera. Godot clamps the froxel lookup at `volumetric_fog_length`, so
*everything* beyond it got one flat, distance-free curtain - the mountains and the tower two
streets away hazed by the same amount, which is the opposite of aerial perspective. It is 900 m
now with the density cut to match (0.00014 clear), forward anisotropy 0.45, and ambient/sky
injection at zero so the volume is lit by the sun rather than by a flat fill.
`DayNight.haze_gain` scales that density by the sun's height - full on the horizon, a third of it
overhead - because haze is forward scattering through a long path of lit air, which is most of
what a hazy sunset looks like and almost none of what a hazy noon looks like.
**Trap:** `Weather._process()` overwrites `volumetric_fog_density` every frame from
`volumetric_by_state`, so tuning that value in `city.tscn` does nothing at all. That cost an hour.

**Seven geometry and colour-space bugs (final build of the session).** Three of them are the same
mistake, and it is worth internalising because the code makes it easy to make:

> `Basis.scaled()` is a **left** multiply - Godot scales the basis *rows* - so its factors land on
> the **world** axes *after* any rotation, not on the mesh's own axes.

`scripts/world/street_detail.gd:17` documents the rule and `scripts/world/signage.gd:139` has a
`_scale_basis()` helper that avoids it, and three call sites still got it wrong. A probe under
`--headless` settles any instance of this in seconds; what it printed:

```
tipped.scaled(13, 13, 1) -> quad spans 13.0 x 1.0    every street and pier lamp threw a
tipped.scaled(13, 1, 13) -> quad spans 13.0 x 13.0   13 x 1 m BAR, not a 13 m disc of light
yaw.scaled(1, 1, 3)      -> the 3x landed on the stripe's 0.6 m WIDTH, not its 3 m length
sign basis, fit 0.5      -> old: along 1.0, up 0.5   the horizontal fit was on the VERTICAL axis
                            new: along 0.5, up 0.5
```

So: every lamp in the city lit a bar; runway centreline dashes were 3 m long and 1.8 m wide and
the edge lines were white slabs roughly 200 m *across* the runway; and on the two faces of every
building whose along-vector runs down world Z, the shop name kept its full width - running into
the shop next door - while being squashed vertically. The two ladder-crosswalk branches had each
other's basis. All fixed, and `tests/smoke_test.gd` now *measures* the lamp pool's real world
extents rather than trusting the argument order, so it cannot silently revert.

The other two:

- `shaders/terrain.gdshader` `dry_tint` was hinted `source_color`, which Godot sRGB-decodes. It is
  a **multiplier** on sampled grass, so fully-dry hillside rendered at luminance 0.096 - *darker*
  than the live grass beside it at 0.126, and rust rather than gold. This is the same mistake
  commit `890ad3d` fixed in nine places on the ground; check any new tint against which side of
  the decode it is on.
- The 14 km ground follower had `cast_shadow` at its default. At 200 x 200 quads that is 80,000
  triangles drawn into all four shadow cascades every frame, to shadow nothing (it is the plane
  *under* everything). It still receives, which is what matters.

### The one thing still open, and where the evidence points

**A midday aerial reads washed out: p5/p50/p95 went from 49/137/174 to 107/209/227 - a uniform
lift across sky, mountains, far basin, city blocks and near ground alike.** Ruled out, each by
experiment rather than by argument:

- **Volumetric fog.** Disabling it entirely gave a byte-identical histogram. Exonerated.
- **The day/night clock and the camera exposure multiplier.** `tools/glshot/city_shot.gd` now
  prints both with every render; it reported `clock 13:11, night_factor 0.00, exposure multiplier
  1.000, auto true`.
- **Quality stepping.** Every render log says `Quality: high`.

A lift that is uniform across the *sky as well as* the ground is exposure or tone curve, not haze.
Two measurements at the end of the session narrowed it to a specific answer, and both refuted a
guess worth not repeating.

**The guess that was wrong:** that the Compatibility renderer ignores `adjustment_*`, making the
whole washout a harness artifact. It does not ignore it. Same camera, one toggle:

```
grade ON   p1/p5/p50/p95/p99   8  12  185  231  242
grade OFF                      18  27  165  212  230
```

**So the grade is most of the lift, and it is doing exactly what it was written to do**: the LUT
deepens shadows (27 -> 12) and raises everything above its pivot (165 -> 185, 212 -> 231). On a
bright midday frame nearly every pixel sits above that pivot, so the net result is a lift with the
midtones pushed up. The curve's upper half is simply tuned too hot for a noon frame. The knob is
the `Gradient_grade` sub-resource in `scenes/levels/city.tscn`; pulling the 0.62 and 0.78 stops
down toward the identity line (they currently map to 0.722 and 0.886) is the change to try, and
`adjustment_contrast` must stay at 1.0 - the LUT *is* the curve.

**The second finding, and it invalidates every brightness number taken on the fast path.** The
opengl3 render log says, in plain text:

```
WARNING: Auto-exposure is only available when using the Forward+ renderer.
    at: camera_attributes_set_auto_exposure ... [0] _apply_render (res://scripts/util/quality.gd:167)
```

The player camera runs auto exposure at sensitivity 200..620 (`scenes/player/player.tscn`), and on
the owner's Mac that adaptation pulls a bright frame back down. `city_shot.gd` silently drops it.
So a noon frame measured on opengl3 is *brighter than the game* by whatever auto exposure would
have taken off, and no amount of tuning against that path converges. **Judge the grade only on
`tools/glshot/forward_shot.sh`** (real Forward+ via lavapipe, ~6-10 min a frame).

The one render still not done: HEAD through `forward_shot.sh` at a midday camera. A midday city
frame wants p5/p50/p95 near 87/123/175; 78/103/137 is the washed-out look the grade was added to
fix. Take that number *before* touching the gradient stops, because the gap between it and the
opengl3 numbers above is the size of the auto-exposure correction and nobody has ever measured it.

Measure, do not squint:
`python3 -c "from PIL import Image; import numpy as np; g=np.asarray(Image.open('shot.png').convert('L')).astype(float); print([round(float(np.percentile(g,p))) for p in (1,5,50,95,99)])"`

### Practical notes for the next session

- **The container restarts.** It did twice here, killing four agent fleets and a render batch
  mid-flight. The repo and the Godot binary in the scratchpad survived both times. Commit often.
- **The smoke test is now 324 checks (2026-09-24) and the shell timeout in
  `tests/headless_check.sh` is 600 s (it was 420, which the test had outgrown).** Under load from a large fleet it *times out* at
  around 150 checks with zero failures, which looks alarming and is not a failure. Do not run a
  big fan-out and the gate at the same time, and do not read exit code 124 as a pass.
- **The eight-dimension sweep did finish** (56 agents, no errors) and its 26 verified patches are
  on `main` in `2638fec`. Every lead listed above was real: the whitecap threshold was not rare
  but *unreachable*, so the sea had zero foam at every weather state; far buildings were 2.4-7.9x
  brighter than near ones from an un-decoded MultiMesh instance colour; two leaf materials were
  flagged OPAQUE so their black photo background drew solid; ocean chunks and the sea-floor box
  cast shadows from under opaque water; storefront bands never emitted unless the block was
  Commercial. All fixed.
- **One thing the sweep got wrong, and it is the failure mode to watch for in this pattern.** Its
  adversarial verifier approved the patch that *declares* the character normal-map uniforms and
  rejected the two that sample and bind them. Applied as returned, that ships `normal_tex` and
  `normal_strength` as uniforms nothing ever reads: it compiles, it passes the check, and it looks
  from the outside exactly like the feature is in. The wiring was finished by hand
  (`NORMAL_MAP` in the fragment, `Pedestrian._normal_map_for()`, and `pedestrian_c_nrm.png.import`
  which the sweep fixed on `_a` only). **Read a fan-out's patches as a set and ask what is missing,
  not just whether each one is individually correct** - per-finding verification cannot see a hole
  between findings.
- The owner's four reference images are analysed in `docs/GAME_PLAN.md` under "Graphics references
  (owner, 2026-09-21)": a Horizon Zero Dawn forest, a skyline above a cloud sea at sunrise, the
  GTA V Los Angeles overlook, and Miami Ocean Drive at sunset with neon. The unstarted items drawn
  from them are neon signage as a light source, wet-road reflections, layered undergrowth, and a
  bigger, softer sun.

## 9d. The people, 2026-09-22 evening

The owner said the characters "look stupid, their arms are floppy", then "we need entirely new
assets for the humans", and un-retired Meshy for characters only (their key lives outside the
repo; `MESHY_KEY_FILE`). What shipped:

- **New rigs d to l** (`Pedestrian.MODELS`), 16k faces, only the `_anim.glb` committed, each with
  a baked `_nrm.png`. a, b and c stay on disk, unloaded. The player's body is d.
- **The arm fix is now a retarget, not a guess.** Every Meshy rig is bound in whatever pose its
  mesh came out in and the clips assume straight arms, so a fixed shoulder rotation (the old
  `ARM_DROP`) put the new rigs' hands up by their ears. `Pedestrian.fix_arm_pose()` rebuilds
  the arm keys from the rig's rest pose and needs no per-model numbers. Check any new rig with
  `tools/glshot/character_shot.gd` (`MODEL=... YAW=0` and `YAW=90`, `CLIP=run_fast_3_inplace`
  and `CLIP=Idle` too) before adding it to `MODELS`. Measure, too: the first version of it
  looked fine in stills and was still wrong (slumped collarbones, arms trailing the torso's
  lean, hands held off the thighs), which only a bone-by-bone sample over the clip showed.
- **`tools/meshy.py` was throwing the subject away at the texturing step** (a subject-free
  texture prompt), which is why the people asked for as Black, Latino, and in an orange vest
  came back pale and grey. Fixed; j, k and l were made after it and follow their prompts.
- Known flaws in the set: e's jacket sleeves are painted skin-coloured from the elbow down (a
  texture defect from the generator). The outfit recolour now leaves half the crowd in the
  model's own clothes and the skin tints are small: with nine real models the variety comes
  from them, and darkening a pale face with a multiplier gave grey mud, not a darker person.

**Far ground, 2026-09-23.** Anything placed on the ground follower (beyond ~700 m) must go
through `shaders/macro_relief.gdshaderinc`, not `MacroMap.height_at()`: the drawn surface is a
coarse bake plus crags, tens of metres off the real terrain on ridges. `far_canopy.gdshader` is
the worked example: Skyline's hill planting and hill houses go through it, and so does the far
ridge sign (its rigid mode moves the whole name by one amount so it stays level). Other far
landmarks on slopes (the observatory, the hills sign) still stand at `height_at()`; they are
small or low enough that nothing has shown, but they are the next thing to move if it does.
`HIDE=Planting_*,Sky_*` on `tools/glshot/city_shot.gd` hides named nodes, which is how the
floating houses were told apart from the floating trees.

## 9e. Making it run, 2026-09-23

The owner: "I need the game to be playable and not slow without taking away from graphics or
quality at all." What the measurements said and what shipped is in the decisions log (same
date). What a next session needs to know:

- **Measure CPU with a throughput bench, not `Performance.TIME_PHYSICS_PROCESS`.** That monitor is
  the max over the last second of the whole per-frame physics block (all its steps), so it moves
  with how many catch-up steps ran. Wall-clock ms per game second, standing and flying, headless,
  A/B against a `git worktree` of the previous commit, two rounds each: this machine's noise is
  +-10 %, so one run proves nothing.
- **A symbol-carrying Godot for perf** takes 34 minutes: the 4.7.2 source tarball from the GitHub
  release, `scons platform=linuxbsd target=template_release debug_symbols=yes -j4`. Release
  templates refuse `--path` and the working directory (`disable_path_overrides`), so either
  rebuild with `disable_path_overrides=no` or export a pck with the editor binary and pass
  `--main-pack`. `perf` is `apt-get install linux-tools-generic` and then the versioned binary
  under `/usr/lib/linux-tools/*/perf` (the wrapper refuses this kernel); only software events
  (`-e cpu-clock`) exist in this VM.
- **Collision masks cost CPU** (CLAUDE.md, physics layers): static bodies mask 0, detector areas
  not monitorable, placed kinematic bodies without masks. Adding a body with a wide mask is how
  this comes back.
- **Chunk builds are steps** (CLAUDE.md, City): anything new in a chunk build goes in as a step
  or inside one; a big self-seeded job goes through `_run_or_defer()`.
- **Sleep is the single biggest lever and the easiest to lose.** Three separate things had kept
  every parked car in the city simulated every step: VehicleBody3D waking itself in its own
  state callback (`Vehicle.settle()` from PhysicsBudget's *physics* tick is the fix), a weak
  brake letting cars roll, and the ground's collision box being re-placed eight times a second
  (moving a static body wakes all its neighbours). Check the TRUE state with
  `PhysicsServer3D.body_get_state(rid, BODY_STATE_SLEEPING)` - the node's `sleeping` flag reads
  true on a car that is awake - and check it in the release build, where it first showed.
- Driving the release template for perf: it ignores `-s` and refuses `--path` / `--main-pack`,
  but it loads `<binary>.pck` beside itself and honours an `override.cfg` there, so an autoload
  added in `override.cfg` (an absolute path to a scratch script) drives it. Set
  `application/run/flush_stdout_on_print=true` there too, or its prints never arrive. Use
  `perf report --no-inline`: without it, report stalls for many minutes on addr2line.
- After all of that the release build runs at real time on this slow test box, standing and
  flying, and the profile is flat (scripts ~15 %, broadphase updates ~7 %, then animation and
  transform propagation). GPU cost on the Mac is still unmeasured here; the owner's F1 stats
  line is the next evidence to ask for if it still stutters.

## 9f. Stills, rain, fire and the GPU side, 2026-09-23 afternoon (builds 203-208)

The owner asked for Steam-quality gameplay stills and, again, for it to run well "without
taking away from graphics at all". What shipped, newest last:

- **CI had been red for two builds** on "lowest quality trims the crowd": staged chunk builds
  counted crowd room once and kept spawning into a cap Quality had lowered. Walkers now go
  through `CityStreamer.take_crowd_room()`. Two more smoke checks were flaky for the same
  reason - picking `peds[0]` / `peds[1]`, which can be in a chunk that is about to swap - and
  now pick the nearest pedestrians. Check the Actions run after every push; a red run publishes
  nothing and the owner silently keeps the old build.
- **Parked cars on the boardwalk shop roofs**: the shop strip follows the shore across the ends
  of straight streets. `Landmarks.covers()` keeps parking out of it.
- **Explosions** read as fire now (deep orange after one white-hot instant, smoke drawn behind
  the fire, soft particles, per-puff age and tint so it is not one flat cloud). Judge them only
  in Forward+: the Compatibility preview clamps and flattens all of it.
- **Rainy nights**: streets start wet, glossy tarmac with mirror puddles (SSR does the rest -
  check `raintest` style renders with the whole road forced to a mirror if you doubt it works),
  lit drops that fade near the lens, and the lens rain cut from ~1,800 drops to a few dozen at
  the edges. Freeway traffic pitches with the deck.
- **GPU**: `tools/gpu_profile.gd` + `tools/gpu_profile.py` (per-pass timings) and
  `tools/tri_split.gd` (per-category triangles, with and without shadows) are the measuring
  kit. The frame is triangle-bound: opaque, depth pre-pass and sun shadows are ~90 %. Note the
  depth pre-pass is disabled by Godot itself on Apple GPUs (`disable_for_vendors`), so on the
  owner's Mac the opaque and shadow passes are what count. Foliage, props and car bodies now
  cast shadows from lighter twins (CLAUDE.md, Performance): 9.4 M -> 7.7 M triangles on a
  downtown street, with before/after renders of the boardwalk's palm shadows matching.
  What is left, by the same measure: pedestrians 2.4 M (already LOD-biased and shadowless past
  45 m - the next lever is the crowd's own LOD chain), trees' main pass ~1 M (a batch per chunk
  is LOD0 whenever the camera's plane crosses it; smaller tree cells would fix it but cost draw
  calls), street props 0.9 M, cars 1.2 M.
- **Memory**: a city under lavapipe is 6-7 GB; two renders at once thrash the 16 GB box until
  even `ps` hangs. One render at a time. And `pkill -f` with a pattern that also appears later
  in the same shell command kills that shell - use a script file or a `[x]yz` pattern that the
  command line itself cannot match.
- **Later the same day (builds 210-215)**, owner: "the day/night cycle is too fast", "NPCs
  screaming ... limbs flying off from the rocket launcher", "graphics ... while ensuring the game
  is always still playable". Shipped: a 48-minute day; `Pedestrian.alarm()` panic with 12 real
  scream takes; rocket dismemberment (`Ragdoll.dismember()`, `LimbHider`, blood); worn road
  paint; shape-found glass on the sedan / pickup / van (their textures do not darken the
  windows, which is what made white cars look like ice); far pedestrians on welded bodies
  (6.6 M triangles on the street, from 9.4 M in the morning); limbs, far bodies and effect
  materials all prepared during the loading screen so the first rocket does not hitch. The
  `--nohud` flag skips the loading screen, so harness runs pay those costs on first use - do not
  mistake that for a regression. Debris lifetime is wall-clock, so in a 1 fps software render
  limbs vanish after a few frames; `still_shot.gd` raises it.
  Then the "ice-blue cars": with parking seeded (it used the global rng, so no two renders parked
  the same cars) an A/B with `CAR_PARAM=clearcoat_amount=0` showed the pale-blue pickup is dark
  red and the pale-blue sedan grey (`CAR_REPORT=1` prints every car's paint). The lacquer was
  mirroring the sky's lower hemisphere, which was pale haze for 27 degrees under the horizon;
  the cubemap pass now puts the street there. Same shot: glass towers in shade went from 16/255
  to ~75 once their reflection became emission instead of albedo.
- **Builds 216-220, same evening** (owner: "the sickest screenshots ... gameplay stills in
  steam"). Each of these was found by looking at a still and measuring it, not by guessing:
  reflections see the street (cars), glass reflection is emitted (black towers in shade), glass
  mirrors a fake skyline with bowed panes, the fireball has its own hot-core shader, debris is
  small wedges, crosswalk wear is speckled, the far chunks' ground has its colour back (it was
  black in every aerial - `append_from()` drops `set_color()`), far streets glow at night, sand
  is tiled at 2 m (footprints were half a metre), and rainy nights are dark and warm instead of
  daytime grey.
  Harness notes: edit a batch script only when nothing is running it - bash reads a script
  from disk as it goes, and inserting a line mid-run broke one after its last shot. Copy it
  and run the copy.
- **2026-09-24** (owner: "it's looking like gta San Andreas ... I need it to look like RDR2"):
  lock-on aim, guns held by IK, and every window is now a traced recess (`window_recess` in
  `building.gdshader`): set-back glass, lit jambs and sills, head shadow from the sun. The owner
  had been judging the GL previews, which have flat light; send Forward+ stills (or say which
  renderer a picture is from). Four agents were running on worktrees: weapon wheel, weapon
  models, a Blender hero and a Meshy hero; the owner then asked for the hero in a New Jersey
  mob tracksuit, which the current rig wears in the meantime (`Player.avatar_tracksuit`).
  The weapon wheel (hold Tab / LB: quarter-speed time, frosted-glass wheel,
  `scripts/ui/weapon_wheel.gd` + `shaders/glass_ui.gdshader`) came in from its agent branch the
  same night; it has only been judged on opengl3 stills so far.
- Store stills: `tools/glshot/still_shot.gd` (FX_AT / FX_SIDE / FX_TIME for explosions,
  `FX_AT_PED=1 FX_PED_PLACE=1` for limbs). The good ones: the gore shot downtown at 17:25
  (`--spawn=734.9,330,0,-5 --hour=17.4`, FX_AT=13 FX_RADIUS=9 FX_TIME=0.32), the skyline at
  17:45, the boardwalk at 17:50, the freeway at 18:00 and downtown rain at 21:20. The hills are
  still weak (next steps item 3).

## 9g. The guns, 2026-09-24

The owner called the box guns "horrible assets" and asked for RDR2, then swapped the gravity gun
for a shotgun. All three guns are now models from `tools/make_weapons.py` (Blender 4.2, run
headless with two threads; the CLAUDE.md Weapons bullet has the command and the node-name
contract). A full build is one to three minutes a gun, almost all of it the mask bake (a Bevel
node edge mask and local AO, 16 samples); `--nobake` exports flat colours in a second for shape
work. Look at a gun with `tools/glshot/weapon_shot.gd` (`WEAPON=0/1/2`, `YAW`, `PITCH`, `ZOOM`,
`FOCUS`; it lights with the city's own AgX, sun and fill numbers, so a finish judged there holds
in the street) and in the hands with `hero_shot.gd` (`DEBUG=1`). Only the opengl3 path was used.
On a machine shared with other agents, wrap Blender and every Godot render in `flock` on one lock
file; two lavapipe renders at once get OOM-killed.

Open: the rigs have no finger bones, so the hands sit flat on the grips rather than curling round
them (the wrist targets are right; the pose is the limit). The rocket that leaves the launcher is
still `rocket.gd`'s red primitive cylinder, not the olive warhead the model shows in its muzzle.
The shotgun's fire rate and knock numbers are first guesses (`fire_rate` 1.25, nine pellets of
9 impulse, `knock_base` 12 + 5 a pellet).

## 9k. The living sky, 2026-09-24

Owner: "helicopters, police choppers, news choppers, private jets flying thru the sky,
commercial jets taking off and landing at LAX". Built on an agent worktree; the rules are the
Air traffic bullet in CLAUDE.md. What a next session needs to know:

- **Where things fly and why.** Arrivals come up the basin from the south (a downwind leg at
  `AirTraffic.downwind_x`, x 1950), turn onto a 3 degree final along z 960 and land westbound
  on the south runway, touching down about x -210; departures line up at x -35 on the middle
  runway and climb out west over the sea, turning north-west or south-west. The real field's
  arrivals come straight in from the east over the city; ours cannot, because the east range is
  400 m high two kilometres from the fence (measured: `MacroMap.height_at()` along
  z 960 reads 145 m at x 2400 and 330 m at x 3000). A route that crossed it would reach the
  runway 100 m up even at a 5 degree descent.
- **The wanted system is `Police` (section 9h).** AirTraffic reads the most stars any node in
  the "wanted" group reports, and a police helicopter in pursuit whose searchlight holds the
  player with a clear line (`Helicopter.has_eyes_on()`: within 6 degrees of the beam, nothing
  solid between) calls `Police.report_sighting()` every quarter second, so the stars do not
  drop while it has him. Losing the helicopter (out of its light, under a bridge, inside) is
  how you lose the stars.
- **The runway protection zone** (`MacroMap.runway_clear_zone()`, 700 x 90 m off the east end of
  the south runway): `CityPlan.lots()` builds nothing in it, so the near and far city both lose
  the same lots. Without it the glide path met 20-30 m midtown roofs 150-400 m from the fence.
- **Every height the traffic avoids is read, not guessed**: `obstacle_top()` replays the plan's
  own lots and `lot_height()` (like Skyline), adds 10 m of roof plant, reads the freeway decks
  that really pass over a cell (`Freeway.segments_in()` returns its whole 160 m index cells,
  which first put a 24 m "deck" on the runway), and measures the landmarks from the far copies
  CityStreamer keeps. Change the city and the routes follow.
- **The one bug that mattered**: a kinematic body's velocity is derived from its motion per
  step, so spawning an aircraft at the origin and then moving it launched the player at
  ~170 km/s (he left the map in one frame, and every later check ran 60 km away). Aircraft are
  placed before they enter the tree now; anything else that spawns kinematic bodies far from
  where they are created has the same trap.
- **Tuning.** Traffic: `arrival_interval` 70 s, `departure_interval` 76 s, `private_interval`
  55 s, `max_aircraft` 10 (web 6). Approach: `glide_slope_deg` 3, `aim_inset` 190 m,
  `final_turn_radius` 750 m. Jets (`AmbientJet`): `approach_speeds` (92, 72, 61, 54) m/s,
  `rollout_decel` 4.0, `roll_accel` 3.5, `liftoff_speed` 56 - fast for an airliner, because the
  runway is 740 m. News: `news_orbit_radius` 170, `news_orbit_height` 140, `news_linger` 90 s.
  Police: `police_stars` 3, `police_orbit_radius` (80, 96), `police_orbit_height` 62. Helicopter:
  `cruise_speed` 42, `orbit_speed` 17, `searchlight_energy` 22, `searchlight_angle` 6.5.
  Damage: helicopters 80 hp (one rocket), private jets 70, airliners 140.
- **Cost, measured headless on this box**: the routes at load 77 ms (once, in the loading
  screen), a crossing route 7 ms and a private-jet arrival route 18 ms (each built when one
  spawns, every minute or so), a tick of eight aircraft including two police in pursuit
  0.24 ms. The obstacle cells are cached; the lots are only read for route points within
  420 m of the ground.
- **Stills**: `AIR=final|takeoff|news|police AIR_DIST=<m> AIR_SIDE=<m> AIR_CLEAR=1` on
  `tools/glshot/still_shot.gd` (opengl3 only for this work; see the usage in the file).
- **Not done / not verified**: nobody has heard the loops in the game or seen the searchlight
  shaft through real volumetric fog (Forward+ was off limits for this agent). Aircraft do not
  avoid each other: two arrivals are spaced by the schedule only, and a helicopter's route
  over a jet's is not checked. Departures pop into existence behind a fade at the line-up
  point; a watcher sees them appear. Arrivals fade out rather than taxiing to a gate. Smoke
  trails left in the air jump a kilometre on an origin re-centering (CPUParticles in world
  space; the rocket smoke already does this). Nothing shows aircraft on the minimap, and the
  lock-on does not target them. The runway protection zone reads as bare block paving up close
  (a lawn there would read better; the skyline would need the same green plate). The smoke
  log gains four `Parameter "material" is null` lines at shutdown, from the dummy renderer,
  only when the test's shot-down helicopter crashes in the street; a crash away from the street
  and two rockets into the road both leave none, and the gate does not match them, but the
  cause was not pinned down.

## 9h. Police and the wanted level, 2026-09-24 (agent branch)

The owner asked for "a police and star system", GTA-style but original. What is in, and what a
next session needs to know (the rules are the Police note in CLAUDE.md):

- **One node, one property.** `Police` in `scenes/levels/city.tscn`, group `wanted`, `stars` a
  plain int. The police helicopter was built on another branch at the same time and reads that;
  it can also call `report_sighting()` so its eyes keep the stars from dropping.
- **Crimes are hooked where they already happen**, not in the weapons: `Pedestrian.alarm()` (the
  one call every gun and blast already makes), `Pedestrian.knock()` and
  `Vehicle.drop_out_of_traffic()`. A new gun gets reported for free. Anything the police do
  themselves sets `Police.innocent` round the knock; forget that and a cruiser that clips a
  pedestrian gives the player a star.
- **Two driving modes, on purpose.** A physics car driving 200 m through a city grid on an AI
  will get stuck on a kerb, a lamp or a building in the first block; a kinematic car on the lanes
  cannot. So cruisers come in on the lanes (the traffic's own geometry, turning toward the goal
  at each crossing) and only become VehicleBody3D physics within `engage_range` of a player they
  can see - close enough that "steer at them, back out when stuck, stop and get out after three
  tries" is enough AI. Pooling has to strip the VehicleWheel3D nodes before freezing the body.
- **Officers are Pedestrians with an Avatar body.** That buys the knock, the ragdoll, gibs and
  the LOD tiers from Pedestrian and the hand IK from the hero's Avatar, with a `PoliceGun` (a
  Weapon, model and grips only) in the hands. They are taken OUT of the `pedestrian` group after
  `_ready()`, so the crowd cap, `trim_pedestrians()` and alarms never touch them; `LockOn` looks in
  `police` as well.
- **The smoke test turns the police off** for everything except `_test_police`, which checks the
  whole loop in about 25 s of game time: gunfire near a witness gives a star, a cruiser joins
  60+ m out and drives in, officers get out and hurt the player, five stars stays inside the caps,
  going down respawns 30+ m away with the stars and units gone, and out of sight the stars flash
  and drop one at a time.
- **Screenshots:** `STARS=3 POLICE=standoff|pursuit` on `tools/glshot/still_shot.gd` stages the
  units in front of the camera (`Police.stage_for_shot()`), because a software frame takes
  seconds and waiting for cruisers to drive in would take hundreds of them. opengl3 only.
- **Two things that were wrong the first time, both found by measuring.** A knock-down has to be
  judged a tick late (`Police.knocked_down`): `Weapon.tick()` fires, and so knocks the target
  over, before it raises the alarm that says it fired, so judged at once the first kill of any
  spree belonged to nobody - and judged by distance alone, a car nudged at a chunk build gave the
  player a star. And the first officers fired 54 rounds without one reaching the player, because
  every one went into the cruiser they were crouched behind (`_line_of_fire()` and the sideways
  step are the fix; `PoliceOfficer.rounds_fired` / `rounds_hit` are there to measure it again).
- **Known gaps.** (Fixed the same day, section 9o: cruisers now route along the streets and pull
  up at the kerb nearest the player; the next sentence is how it was.) Cruisers under physics
  steered straight at their target with no path finding, so
  a player on a roof or deep inside a block gets a cruiser that noses up to the nearest wall,
  backs off three times and lets its crew out there. There is no ground response off the street
  grid (hills, airport, port): the stars still decay normally, and the helicopter is what covers
  those. Officers are built when they get out (an Avatar each, a small hitch), not pooled. The
  tactical unit has no helmets and nobody has finger bones. The siren is one wail cycle with no
  yelp at close range and no Doppler. Nothing of this has been seen in Forward+ or at 60 fps:
  the light bar's HDR lenses and the night OmniLight are tuned on opengl3 stills only.

## 9i. The facade kit, 2026-09-24 (G2, first real-geometry pass)

Owner: "it's looking like GTA San Andreas ... it must be the same quality as RDR2". The biggest
tell left was that every building is a shaded box. `tools/facade_kit.py` (Blender 4.2, headless)
now models a kit of seventeen pieces into `assets/models/facade_kit.glb`, and `Building` places
them from its seed on every building near the camera. What a next session needs to know:

- **Regenerating it**: `blender -b --python tools/facade_kit.py` (the scratchpad Blender works:
  `.../blender_char/blender/blender-4.2.23-linux-x64/blender`), then `godot --headless --path .
  --import` - the cached-import trap applies to it like any `.glb`. The script prints every
  piece's triangle count and x range; the x range of a roofline run must stay exactly -1..1
  (the smoke test checks it) or the corner mitres break.
- **One mesh fits every building** because `shaders/facade_kit.gdshaderinc` bends it per
  instance: roofline runs are mitred at any corner from `INSTANCE_CUSTOM.r/.g`, surrounds and
  awnings are three-sliced from `.b/.a`. The rules the Blender side has to keep are in the
  generator's header; break them and the geometry still loads, it just folds wrong.
- **Per building, not per chunk.** A chunk-wide batch is one node for the whole block: it is
  never occluded and it fades as one piece 100 m across. Per building, frustum and occlusion
  culling and the distance fade all work.
- **Top-floor clearance.** A classical cornice hangs ~1 m and the top window heads sit
  0.3-0.5 m under the roof line (a slot window's ~0.1 m), so `_add_facade_details` shrinks a
  rich cornice up to a quarter, then falls back to the plain one, and lifts what is left up to
  `KIT_CORNICE_MAX_LIFT` so it stands in front of the parapet rather than over the windows.
- **Measured** (`tools/geo_count.gd`, opengl3, 800x600, one frame, same cameras; the base
  numbers come from a clean export of the parent commit, re-measured twice identically):

  | Camera | Triangles before -> after | Draw calls before -> after | Objects |
  | --- | --- | --- | --- |
  | default spawn (midtown, origin) | 9.70 M -> 8.51 M | 8651 -> 8707 | 23411 -> 23467 |
  | downtown `--spawn=734.9,330,25,-4` (glass towers) | 4.107 M -> 4.115 M | 3050 -> 3071 | 3081 -> 3102 |
  | brick mid-rise `--spawn=-96,-230,-62,10` | 6.95 M -> 6.21 M | 6230 -> 6708 | 6361 -> 6839 |

  Triangles went DOWN because the old procedural balconies and fire escapes drew to 480 m and
  the old roof props had no range at all, while the kit fades at 110-320 m; the near blocks
  carry more geometry than before. Draw calls rise where the kit is (up to ~10 nodes per
  building plus shadows; +8 % on the brick street, nothing downtown, where the glass takes
  none of it). Chunk build: ~3 ms more per building on this box, ~20 ms worst for a big
  brick block with a hundred balconies (headless, warmed; `scratchpad/facade/kit_time.gd`).
- The opengl3 path is flat-lit; nobody has seen the kit on Forward+ yet - the main session
  should, since the shadows from cornices, balconies and awnings are most of what it adds.
  Close-ups: `tools/glshot/building_shot.gd` with `CAM_POS` / `CAM_LOOK` (and `KIT=0` for
  the same seed without the kit), and `tools/glshot/kit_shot.gd` (`SET=wall|roof`) for the
  pieces on their own.
- **Not done**: storefront glazing and interiors as geometry, a kit per LA style (bungalow,
  deco, mission), string courses and plinths as mouldings (still boxes), and a LOD/impostor
  step between the kit's range and the far boxes.

## 9j. Blood, 2026-09-24 (owner: "I want more blood when people get shot")

Built on an agent branch while another agent swapped the gravity gun for a shotgun. What a
rifle round into a person does now, all in `WeaponFX` (tunables `blood_*` at the top of
`scripts/weapons/weapon_fx.gd`) with the body's side in `Ragdoll`:

- **One entry point for every gun**: `WeaponFX.bullet_wound(node, hit, dir, strength, knock)`
  takes the ray hit and duck-types the victim (pedestrian -> `Pedestrian.shot()`, body ->
  `Ragdoll.shot()`, limb -> `blood_gush()`). The rifle's `fire_ray()` calls it with
  `AssaultRifle.blood_strength`. The shotgun (merged in from main the same day) sums each
  person's pellets - bodies already down included - into one call at `Shotgun.blood_per_pellet`
  (0.45) a pellet, capped at `blood_strength_max` (4): a close blast of nine is four rifle
  rounds' worth, a stray pellet a small wound. Called per pellet it would also work: the first
  puts them down and the rest land in the ragdoll, which bleeds more for each.
- **The wound** (`blood()`): backspatter, an exit spray of lit glossy droplet meshes along the
  bullet (a fast jet inside a wider spray), an unshaded mist that dims itself at night
  (`shaders/blood_mist.gdshader`; the lit version was grey dust), a spatter plus creeping runs on any wall within 2.8 m behind (one ray), and
  five drops traced ballistically to where they land, each leaving a splat at the moment it lands.
- **The body**: a pool spreads from under the hips over 8 s once it rests (widened by later
  hits), drag smears while it slides, drips from the exit wound, a per-body stain on the
  clothes (`character.gdshader` `wound_0..3`) that rides the nearest bone and soaks outward.
  Rocket gibs bleed at 2.2, the stumps pump, torn limbs drip in flight and mark where they land.
- **Marks** are generated textures (albedo + normal + ORM) on Decals in Forward+ and on flat alpha
  quads in Compatibility. **Nobody has seen the Decal path yet**: the opengl3 stills show the quad
  fallback, and agents may not run lavapipe. The first Forward+ still of a shooting is the thing
  to check - colour (decal albedo through the atlas), wetness (ORM roughness 0.5 where thick: anything glossier mirrored the sky at the grazing
  angle every road splat is seen at, and measured brighter than the road on opengl3; with SSR
  on Forward+ a little glossier may look better, it is one `lerpf` in `_shade_blood()`) and
  which way the wall runs go (they should run DOWN; the decal V axis is local +Z, set to the wall's
  down direction in `_wall_splatter`).
- Stills: `still_shot.gd` `FX_SHOOT=3 FX_AT=8 FX_AT_PED=1 FX_PED_PLACE=1` (spray at
  `FX_TIME=0.15`; aftermath at `FX_SCALE=1 FX_TIME=9`; `FX_PED_WALL=1.4` for a wall).
- Pre-existing, not from this work: every headless run logs thousands of `Cannot set a buffer on
  a Multimesh` errors and one `get_meta ... 'shadow_twin'` from `multimesh_batch.gd` (the
  shadow-twin commit e2d3a2a; `get_meta(key, null)` is an error when the key is missing). The
  gate does not match them, so it stays green; they are worth a look.

## 9o. Street life, 2026-09-24 (owner: "GTA-level street life")

Signals that work, traffic that queues at them, people who cross on the walking figure, and
police who drive the streets. Built on an agent worktree; the rules are the Street life bullet in
CLAUDE.md. What a next session needs to know:

- **Nothing per signal ticks.** One clock (`TrafficSignals.clock`, advanced by `TrafficManager`,
  pushed as the `signal_clock` shader global) plus a seeded offset per junction. The lens shader
  lights a head from its MultiMesh custom data (offset, axis) and the lamp id baked in UV2; the
  cars ask `TrafficSignals.light()`, the crowd `walk()`. Change the cycle in `TrafficSignals`
  only: `PropFactory.signal_lens_material()` pushes it to the shader and the smoke test checks
  the copy. To stage a light for a test or a still, `TrafficSignals.force()` moves the shared
  clock (so every junction moves with it - fine for one junction at a time).
- **The hardware** is `tools/make_signals.py` (Blender 4.2 headless: `blender -b
  --factory-startup --python tools/make_signals.py`, then `godot --headless --path . --import`,
  commit the `.glb` and its `.import`). Every piece is bevelled with face-area weighted normals.
  Triangles: pole 1,376, arm 404, vehicle head 2,132, bracket 128, pedestrian head 980, button
  328, cabinet 740 (guards in `PropFactory.TRI_BUDGET`). The dimensions the placing code uses are
  `PropFactory.SIGNAL_*`; `tests/street_life_checks.gd` checks them against the loaded bounds.
- **Layout** (`CityChunk._add_signal_corner()`): the far-right pole of each approach carries
  its mast arm, scaled along its length to reach the innermost lane (6.6 m on a 14 m street,
  11.4 m on a 24 m avenue), one head per lane plus a side-mount head at 4.6 m, two pedestrian
  heads at 2.7 m facing back across the two crosswalks ending at that corner, and two buttons.
  One controller cabinet per junction. Each pole is one breakable prop. Draw distances: heads
  420 m (a lit lens is what reads a junction from blocks away), pedestrian heads and the cabinet
  160 m, buttons 70 m.
- **Measured** (`tools/geo_count.gd` `AB=Batch_sig_*,BatchShadow_sig_*`, opengl3, 800x600, the
  spawn camera, one frozen frame with and without): not taken yet - the shared render lock was
  queued for hours. Take it before the next geometry change here.
- **Traffic**: `TrafficManager._drive_streets()` - IDM car following per lane group, the stop
  line / stop sign / busy crosswalk / player's car as stationary cars ahead, a hard no-overlap
  clamp, stand-still once closed up (the IDM alone creeps forever), turns slowed and skipped when
  the target lane is occupied, pull-over for a siren. Tunables at the top of `traffic.gd`, group
  "Street driving": `accel` 2.4, `brake_comfort` 3.6, `brake_max` 9, `min_gap` 2.2, `time_gap`
  1.1, `stop_line_back` 3.7, `turn_speed` 6.5, `stop_sign_wait` 1.0, `amber_margin` 1.25,
  `siren_yield_distance` 40, `siren_shift` 1.2, `player_brake` 6. Signal cycle in
  `TrafficSignals`: `GREEN` 16, `AMBER` 3.5, `ALL_RED` 1.5, `WALK_TIME` 7 (42 s a cycle).
- **Pedestrians**: `cross_chance` 0.3, `cross_pace` 1.2, `kerb_wait` 0.7, `kerb_spread` 1.1,
  `stop_sign_patience` 0.8-2.6 s. They now walk round their ring by its corners
  (`_ring_route()`); straight lines between two sides of a block went through the buildings.
  **A real bug fixed on the way:** the walk steered by `global_position` (scene space) toward
  targets in the chunk's space (true world), so after the first origin shift - flying 1 km out -
  the whole crowd walked off toward points a kilometre away. It reads `position` now; `_scare()`
  converts the threat into the same space.
- **Police**: `StreetRoute` (A* over the intersection grid, `kerb_stop()`, `polyline()`), used
  by both of the cruiser's driving modes. Tunables on `PoliceCar`, group "Routing":
  `route_interval` 0.5 s, `route_moved` 10 m, `ram_range` 35 m, `corner_speed` 9,
  `u_turn_speed` 4, `route_brake` 7, `look_ahead` 6-16 m, `kerb_approach` 26 m. A dispatched
  cruiser stays on the lanes to the kerb point and only then goes onto physics to stop
  (`_pull_up()`). Handing it to physics on the last straight inside `engage_range` was tried and
  reverted: in the full smoke run, after the police and car checks had left wrecks about, the
  physics approach was knocked off the road and stuck 61 m short (175 of 934 samples off the
  carriageway); the lanes cannot be. Probed headless: dispatched 132 m out to a player mid-block,
  0 of 453 samples off a carriageway, parked 0.6 m from the kerb point; to a player at a
  junction centre from 168 m, parked in 10.9 s (the smoke test's engage window is 25 s since
  main raised it); a physics cruiser spawned 127 m out got there by road in 17 s, 0 of 1,060
  samples off - but that follower is the part to watch in a cluttered street (it has no idea of
  obstacles beyond backing off when stuck).
- **Checks** (`tests/street_life_checks.gd`, 16 of them, about 35 s of game time): the model and
  its placing numbers, the shader's copy of the cycle, heads on every signalised full-detail
  junction, the cycle's logic (never both green, an all-red, walking only across a red), live
  traffic never overlapping, a queue of three plus a fast fourth at a red (stops at the line,
  nobody over it, no overlap) and going on green, a car on green waiting for somebody on its
  crosswalk, a walker waiting through the steady hand, stepping out on the walking figure and
  joining the next block, and the cruiser to a mid-block player by road. The old "traffic car
  moved in 1 s" check now takes the farthest any car moved: the nearest car can simply be
  waiting at a red.
- **Stills**: `STREET=queue|crossing` on `tools/glshot/still_shot.gd` (opengl3 only for this
  work). Only two were rendered before the session ended - the render lock was queued for hours:
  `street_look1.png` (the spawn junction at noon, `--spawn=16,22,40,8 --hour=12`: signal heads,
  mast arms and walkers in the frame) and `street_queue_red.png` (`STREET=queue --spawn=14,50,8,4
  --hour=11.5`, framed badly: the camera is on the pavement and the queue is small in the
  distance). Still to take, commands ready: the queue from behind it, `FOV=50 STREET=queue
  --spawn=-0.8,50,-4,-3 --hour=11.5`; the same camera at `--hour=21.5` for the lit heads at
  night; people on the crosswalk, `STREET=crossing STREET_PEDS=10 --spawn=34,9.5,84,2
  --hour=16.5`. None has been seen in Forward+.
- **Bugs found on the way, all fixed:** a new street car was placed from `to_local()` under the
  already-shifted `TrafficManager` after an origin re-centre, so it appeared a whole shift away
  (cars now get their local transform before `add_child()`, which also avoids the kinematic
  velocity trap; loop, freeway and police spawns too); an officer could think once about a
  cruiser `Police.clear()` had already pooled (`is_inside_tree` errors); the smoke test's panic
  check picked the walker standing where the body it had just shot was flying, and the ragdoll
  knocked them down before their speed was read (it now skips anybody within 10 m of a fresh
  ragdoll). The smoke test's seed-rebuild check resets `WorldState.world_offset` under the live,
  still-shifted city, so the street checks run before it; anything positional after that point
  (the air traffic checks) is in a frame that disagrees with the nodes. The street checks put the
  player back where they found him, or the air checks' rocket leaves from a mid-block pavement
  and hits a building.
- **Not done / not verified**: nothing of it has been seen in Forward+ (HDR lamps, glow and the
  lens specular are tuned on opengl3 stills). Turning cars do not cross oncoming traffic with
  any care (a left turn is instant at the junction centre, as before), and cross traffic does not
  yield to a cruiser in the box. Stop-sign junctions stop everyone and then let them go without
  taking turns. Walkers still spawn and live on the ring of the chunk that built them; crossed
  to another block they vanish with their original chunk. Lamps throw no light on the street at
  night (the lenses glow; there is no OmniLight per head, deliberately). A physics cruiser that
  meets a traffic car head on is blocked by it (kinematic cars are immovable to physics) and
  backs off and tries again; traffic only pulls over for a siren on the lanes behind it.
  The geometry cost of the signals (`AB=Batch_sig_*,BatchShadow_sig_*` on geo_count) is not
  measured. **To continue:** take the three stills above and the geo_count A/B, then judge the
  lamps in Forward+ (`forward_shot.sh` at the queue camera, day and night) - the lens `energy`
  (3.2) and `ped_energy` (2.4) in `shaders/traffic_signal.gdshader` are the numbers most likely
  to need a change once glow is on.

## 9n. The downtown skyline, 2026-09-24 (owner: "a 1:1 match of DTLA skyline ... more buildings")

Built on an agent branch; the rules are the Downtown skyline bullet in CLAUDE.md. The decision
that shapes everything: **massing yes, names no.** Which towers stand where, their heights in
real metres, their silhouettes, crowns and facade character follow the real downtown; every name
(code ids `dt_*`, minimap labels) is invented and no crown carries lettering. What a next
session needs to know:

- **Where they are and why there.** The real grid is laid one real block to one game block on
  the default seed's downtown streets: the avenues at x 507.8 / 589.2 / 660.7 / 734.9 / 824.2
  and the streets from z 228 to 907. So the sail stands west of the first avenue; the drums,
  the black twins, the pyramid, the spire and the curved tower down the next column; the dark
  glass, bronze and white slabs and two South Park towers in the next; the round crown and the
  red pair up the hill; the rounded pair, the blue crown and the unfinished cluster to the east.
  City hall (`ziggurat_hall`, 810,160) is the civic branch's and sits north-east of the core, as
  the real one does; nothing of this branch is north of z 244 or west of x 416, so the civic
  centre, the station and the arena district (which another branch is placing west and south
  west of the core) have their ground.
- **The grid is pinned** (`CityPlan.PINNED_ROADS`, `_next_road()`): same roads on every seed,
  so fixed towers never land in a street. The pinned values are the default seed's, bit for bit
  (printed with `var_to_str`), so the default city is unchanged; a check walks another seed.
  If a future change moves the downtown grid, re-derive both the pins and the anchors in
  `Landmarks.all()` together, and the smoke test will say which tower left its block.
- **One mesh per tower.** `TowerMesh` extrudes outlines into tiers; the facade is the ordinary
  building shader in its `uv_facade` mode (UV.x metres round the outline, whole bays per face,
  UV.y 100+ blank wall), so curves get windows, rooms and lit offices. Crowns are a separate
  lit surface (`shaders/tower_crown.gdshader`), obstruction lights reuse the aircraft light
  billboards. A whole tower is 60-1,900 triangles (the balconied South Park towers 3-7k); all
  nineteen are about 25k and build in ~150 ms, once, at load - the far copy and the detailed one
  share the mesh. Each carries an occluder, so the towers now also hide the city behind them.
- **One table** (`LandmarkDowntown.TOWERS`) holds every tower's anchor, radius, height, plan
  (checked against the built geometry by the smoke test), crown, and an APPROXIMATE real position
  in metres east/north of `REAL_ORIGIN` (34.0500 N, 118.2550 W) with an approximate real
  footprint, for the owner's next step: the whole downtown re-laid 1:1 (real blocks, real
  streets, true distances), other real areas as 1:1 replica areas with seeded filler between.
  `real_grid()` rotates a real position into the real street grid's frame (avenues about 45
  degrees east of north). The real positions are from memory of public maps, good to perhaps
  +/-50 m: check them before building on them. `Landmarks.all()` appends the table's rows
  (`LandmarkDowntown.entries()`), so a re-lay changes the table, `CityPlan.PINNED_ROADS` and
  `MacroMap.downtown_core`, and nothing else.
- **The infill** (`MacroMap.downtown_core`, DISTRICTS DOWNTOWN `core_*`): the blocks between the
  towers get 40-205 m towers (median ~75, a quarter over 130 m), no slabs, fewer pocket gardens,
  more stone. The old downtown boost lerped the top to 368 m, so generic towers could out-top
  the landmarks.
- **Measured, and what was not.** Geometry, headless: the nineteen towers are 25k triangles in
  all and 3-5 surfaces plus one light billboard each (so roughly 60-100 draws for the whole
  skyline, casting included), built in ~150 ms at load. CPU, headless, the smoke test's
  downtown teleport (`update_streaming(true)` at 742,423): 10.7 s against 10.3 s on the parent
  commit, on a box loaded by other agents (+4 %, inside the noise). **tools/geo_count.gd, measured after the merge** (opengl3, 800x600, the avenue `-- --spawn=589.2,860,0,12,2`): 6.20 M triangles / 8,078 draws / 20,588 objects on the parent commit 044e076 against 5.20 M / 5,412 / 17,976 with the skyline - cheaper, because the towers' occluders hide the blocks behind them. The south-west aerial (`-50,1250,-43,5,80`) did not finish inside geo_count's 600 s on this box either side; measure it on a quieter one.
- **Not done / not verified**: nothing here has been seen in Forward+ (the renders were all
  opengl3; the box was full of other agents' lavapipe renders). Crown glow and the lit offices
  on curved towers want a Forward+ dusk still. The towers have no interiors or lobbies, no
  street-level retail beyond the storefront band, and the plazas (fountains, sculpture) are a
  few boxes. Bunker Hill is not a hill: the relief is flat under landmarks. Collision is one
  convex hull per tier, so the notches of the round tower's wings are filled in. The generic
  core towers are the city's usual boxes; the next step up is a glass-tower facade kit.

## 9l. How the 2026-09-24 session ran (read if you inherit a half-merged day)

- The owner asks for many big features at once and wants speed, so the work went out to
  background agents in git worktrees (`.claude/worktrees/`, ignored), each told to commit on
  its own branch, merge origin/main before reporting, and never push. The main session merges
  each branch, runs `tests/headless_check.sh`, pushes to main and sends screenshots.
- One 16 GB box is shared, and a Forward+ (lavapipe) city is 6-7 GB, so every render goes
  through `flock <scratchpad>/render.lock <command>`. Headless checks run without the lock.
  An OOM-killed render prints `Killed` in its log and leaves no png. flock is not a queue:
  whoever asks next may win, and on a busy afternoon jobs waited over an hour. A GL
  (opengl3) job is ~4 GB, so the main session runs its own GL-only jobs (geo_count, preview
  stills) under a second lock, `<scratchpad>/gl2.lock`, alongside whatever holds the main
  one; never put a Forward+ job on it (two lavapipe cities do not fit in 16 GB).
- Full smoke tests are ~2.5 GB each, and three of them plus a render OOM-killed a gate (exit
  137, `Killed`, `dmesg` shows `Memory cgroup out of memory`). Every full check now runs
  through `<scratchpad>/gate_slot.sh <command>`, two slots on `gate1.lock` / `gate2.lock`.
  An exit 137 is memory, never the code: rerun it inside a slot.
- A smoke check that fails once under heavy load (five or six Godot processes on the box) is
  rerun in isolation before it is believed: `air_probe.gd`-style scripts that load the city
  and run one checks file (`load("res://tests/air_traffic_checks.gd").new().run(t, city)`
  with a stand-in `t` that has `_check()`) take three minutes instead of fifteen.
- Merges conflict mostly in the docs (every agent appends a decisions-log entry and a handoff
  section): keep both sides and renumber the sections.
- CI's box is slower than this one and drops to Quality LOWEST (thinner crowd, fewer cars), so
  tests that pick "the nearest pedestrian" or "cars[0]" are timing-sensitive there. Two such
  checks failed on build 231 and were hardened; if a check passes here and fails on CI, look
  for that first.
- Merged that day: window recesses, tracksuit then the Blender hero, weapon wheel, Blender guns
  and the shotgun, rocket warhead and smoke trail, far-glass emission, police and wanted stars,
  facade kit, blood, air traffic, the city ambience, the lens pass (grain, fringe), night GI,
  the downtown skyline (9n), and a helicopter fix (an orbit holds its whole ring above the
  tallest thing on it: CI 241 caught the news chopper dipping between towers). In flight when
  this was written: a studio pass on the hero,
  the arena district and civic centre, traffic signals and crosswalks with police routing,
  the Redondo Esplanade into Palos Verdes at 1:1, MacArthur Park with street encampments, and
  GTA-style distance LOD tiers. Next after the civic merge: a 1:1 re-lay of the downtown grid
  (the skyline's `LandmarkDowntown.TOWERS` and the civic `CivicSites` tables both carry
  approximate real positions for it). The unused Meshy hero is
  on branch `worktree-agent-a5cb589744a1759b9` (not chosen).

## 9m. The city's sound, 2026-09-24 (agent branch)

Owner: "the city should SOUND like a real city, AAA-style". Until now the only ambience in the
game was the weather's rain loop: `ambience_city` and `wind` had shipped since build 104 and
nothing ever played them. The rules are the Sfx and Ambience bullets in CLAUDE.md. What a next
session needs to know:

- **Nobody has heard it.** Every level, rate and crossfade was set by measuring the files and by
  maths, under the Dummy audio driver; this container has no speakers and no ears. The first thing
  to ask the owner for is ten minutes of play with the sound on: downtown at noon, a freeway deck,
  the beach, the hills at night, a rocket at close range, the weapon wheel, rain from inside a car.
  The knobs they will ask about are `Ambience.ambience_db` (everything), `layer_db` (per layer),
  `ONE_SHOTS[*].db` / `unit` and the rates in `rates_for()`, `pass_db` / `car_roll_db` (the
  street's own cars) and `blast_duck_db` / `slow_duck_db`.
- **Levels.** Beds are all cut to -22 dB RMS and recorded so in `AMBIENCE_LOUDNESS_DB`, so after
  Sfx's trim they sit level with each other and `layer_db` is the whole mix. With the defaults,
  downtown at noon sums to roughly -28 dBFS RMS against a rifle round's -18 dBFS loudest window
  (point-blank): the city under the gun by about 10 dB, well under its peak. That is a guess on
  paper and the most likely thing to need moving.
- **What plays where** (checked by `tests/ambience_checks.gd`, which is the fastest way to see the
  mix: it prints every level it asserts): downtown noon city 1.0 with ~6 horns a minute; downtown
  night city 0.45, far traffic 0.85; the beach surf 0.83 from the west, 5 gulls a minute, none in a
  storm, louder surf in one; the hills birds 0.6 by day, crickets 1.0 and ~0.9 coyotes a minute at
  night, nothing in rain; the suburbs dogs and birds; the airfield 1.0 (downtown hears 0.08); the
  port hum plus ship horns and cranes; a freeway deck 1.0, 0.22 at 300 m; 400 m up the street
  goes and the wind and gale come in.
- **Sources.** Freesound's HQ previews, each page checked for the CC0 deed and nothing else, and
  each description read: two first picks were dropped on the description alone (credit made a
  condition; an AI-generated siren). `tools/ambience_audio.py` is the whole pipeline - `search`
  (CC0-filtered), `get` (verify the page, save it, fetch the preview into `build/audio_src/`),
  `build` (the clip table: spans, filters, loop cuts, levels) - and prints the loudness numbers
  Sfx wants. Re-run `build` for one clip by name prefix; then `godot --headless --path . --import`.
  The proxy is slow (~70 KB/s), so it fetches only the first 2.6 MB of each preview.
- **Performance.** 16 bed/emitter players (only the ones with a level play; a faded bed stops),
  5 pooled one-shot voices, 3 traffic voices, 2 pass-by voices. The survey measured 0.9 ms
  headless; per frame it only eases gains and moves at most nine voices. Bus effects: one reverb,
  two low-passes (switched off when open), one compressor.
- **Not done / not verified.** The web build plays the plain mix (sample playback skips bus
  effects: no reverb, no muffle, no ducker). Traffic voices ride only the TrafficManager's street
  and freeway cars - parked cars, police and the airport loop are silent unless driven (the police
  have sirens). The pass-by timing is maths on positions sampled every 0.15 s; it has never been
  heard lining up. The canyon reverb reads eight horizontal rays at camera height, so it does not
  know how tall the walls are (downtown density stands in for that). No interior sound (there are
  no interiors). The crowd walla is one Hawaiian shopping street; a second take would help. The
  near "traffic" bed is still the old IgnasD highway recording.

## 9o. Downtown's civic set, 2026-09-24 (agent branch)

Owner: "downtown must match real downtown LA, we need staple center we need all day". The
decision: real FORMS in their real places relative to the core, every NAME invented (the naming
rule in CLAUDE.md). The rules are the "Downtown civic set" bullet in CLAUDE.md; what a next
session needs to know:

- **Where things are (default seed 1337; each one fills the block its anchor falls in):**
  arena (352, 475) block 3,4; entertainment plaza (352, 378) block 3,3, north of the arena across
  the street; hotel tower (456, 378) block 4,3; convention centre (352, 596) block 3,5; city hall
  (876, 171) block 9,1; park (876, 59) block 9,0; concert hall (876, -50) block 9,-1; museum
  (782, -50) block 8,-1; station (1091, -50) block 11,-1. Downtown's own grid is narrow there
  (the blocks at x 520-723 are 48-57 m wide), which is why the arena district sits in the
  100 m wide column at x 302-402 and not closer in.
- **One table: `CivicSites.SITES`** (`scripts/world/civic_sites.gd`) holds each landmark's
  anchor, relief radius, footprint (its own frame), yaw (quarter turns, counter-clockwise from
  above), a note on which way it faces, and the REAL building's approximate lat/long, size and
  facing. `Landmarks.all()` takes its entries from it; `CivicSites.build()` puts a pivot at the
  site centre turned by the yaw, with the landmark's own StaticBody3D under it, and the builders
  (`LandmarkArenaDistrict.build(id, site, y0, ...)`, `LandmarkCivicCenter.build(...)`) work in
  a frame centred on the site; their crowd rects and the park's grass go back to the world
  through `CivicSites.to_world()` / `rect_to_world()`. `CivicSites.yaw_override` turns one
  without editing the table (the smoke test turns the station a quarter). For the 1:1 re-layout
  of downtown the real positions share the skyline table's frame (section 9n): `CivicSites
  .real_en(id)` is metres east / NORTH of `LandmarkDowntown.REAL_ORIGIN`, exactly like a tower's
  `real`, `real_metres(id)` the same point with z south, and `real_grid(id)` the point turned
  onto the real street grid the way `LandmarkDowntown.real_grid()` turns a tower. Approximately:

  | id | real east, north (m) | real size (w, h, d) m | game anchor now |
  |---|---|---|---|
  | arena | (-1135, -774) | 200 x 45 x 170 | (352, 475) |
  | live_plaza | (-1061, -597) | 280 x 30 x 180 | (352, 378) |
  | live_hotel | (-987, -531) | 70 x 203 x 35 | (456, 378) |
  | convention_center | (-1245, -1106) | 330 x 25 x 170 | (352, 596) |
  | ziggurat_hall | (1135, 409) | 140 x 138 x 110 | (876, 171) |
  | civic_park | (830, 663) | 500 x 0 x 110 | (876, 59) |
  | concert_hall | (480, 586) | 110 x 40 x 90 | (876, -50) |
  | lattice_museum | (443, 487) | 70 x 36 x 60 | (782, -50) |
  | pueblo_station | (1706, 686) | 260 x 38 x 70 | (1091, -50) |

  None of the sites overlaps a skyline tower: the towers stand east of x 416 and south of z 244,
  and the only civic block inside that corner is the hotel's (x 416-496, z 345-410), which is
  the block west of the five-drums hotel. Two things the re-layout has to decide that the
  tables cannot: the real grid is turned off north (`LandmarkDowntown.GRID_BEARING_DEG`) while
  the game's is axis-aligned, and the real
  footprints are bigger than one of today's blocks, so a 1:1 site needs a block that big (or a
  superblock with its through-roads closed, which traffic and the minimap do not support yet).
  Only quarter-turn yaws are supported, because a site is an axis-aligned block.
- **Block sites are the mechanism to reuse.** A landmark that says `"site": "block"` gets its
  block to itself (`Landmarks.claims()` in `CityPlan.block()` / `lots()`), and its builder reads
  `Landmarks.site_rect()` and fits inside it. The pavement ring, its lamps and trees, the parked
  cars in the kerb lanes and the block's own walkers all stay, which is right: these buildings
  have streets round them. `Landmarks.crowds()` adds plaza crowds as ordinary pedestrians.
- **Scale is compressed on purpose.** One block each: the arena's bowl is ~80 m across (the
  real one is ~200), city hall's tower tops out at ~140 m (real 138), the hotel slab is 196 m
  (real ~200). Merging blocks into superblocks would mean closing road segments, which traffic,
  the police, the minimap and the far tier all assume never happens - not attempted.
- **The toolkit**: `LandmarkGeo` (geometry), `LandmarkMats` (materials), `LedScreen` (screens),
  and six shaders sharing `shaders/landmark_common.gdshaderinc`. Nothing in them is specific to
  these buildings; a new hand-modelled landmark should use them rather than `Landmarks._box()`.
- **The concert hall is a Blender model** (`tools/make_concert_hall.py`, seconds to run, no bake)
  with a `Collision` object the game turns into a trimesh; re-import after regenerating it.
- **Checks** (`tests/civic_checks.gd`, about a second): every one listed and claiming its block,
  no freeway over a site, far versions, geometry inside its own block, collision, rays onto the
  roofs you can land on, crowds on open ground, the table itself, and a quarter turn by yaw.
- **Frame cost.** What each one adds when detailed (own triangles / draw surfaces / prop
  batches): arena 6.0k / 12 / 20, plaza 0.6k / 12 / 17, hotel 1.2k / 5 / 3, convention centre
  2.0k / 5 / 5, city hall 6.7k / 9 / 5, park 0.7k / 6 / 16, concert hall 36.2k (the model) /
  5 / 4, museum 12.9k / 4 / 3, station 2.6k / 13 / 15; a far version is 0.1-1.2k triangles in
  1-10 surfaces and at most one batch. Whole frames at the landmarks (opengl3 stills, the
  STATS line of `tools/glshot/landmark_shot.gd`): plaza by day 3.2 M triangles / 1,853 draws,
  city hall and park 4.4 M / 2,825, concert hall 3.2 M / 1,862, station 2.9 M / 1,892, arena
  at dusk 3.7 M / 2,321, plaza at night 3.1 M / 1,570. The same-camera before/after (`tools/horizon_probe.gd`, 800x600, spawn
  352,405 facing the arena) has only its before side, 5.33 M / 4,054 draws on the parent
  commit: the after run was OOM-killed and then timed out on the shared box. Take it first.
- **Not done / not verified.** Only judged on the opengl3 path (Compatibility): no Forward+
  render yet, so SSR on the steel and glass, SDFGI under the arena's canopy and the night
  floodlights under AgX are unseen. A detailed landmark is built in ONE chunk step. Warm
  (caches full) on this shared, loaded box: museum 68 ms (its veil is 12.9k triangles), arena
  35, city hall 35, station 15, convention centre 11, the rest under 8; a far version is 1-10 ms.
  Cold, in a bare tree with nothing loaded, the first detailed build was 0.1-0.8 s (the arena's
  palms, trees, textures and LED atlas; a running city has most of that loaded already, but it
  was not measured there). That is a hitch as the block streams in; splitting a builder into
  steps (like `CityChunk`'s own) is the fix. The concert hall's model is paid on the loading
  screen by its far copy. Far versions
  are the same builders at low detail with no LOD chain between. Yaw is quarter turns only.
  Names on the LED slides and signs are invented, but nobody has read every slide for an
  accidental real brand - worth a look.

## 10. Suggested next steps, in order of impact

Rewritten 2026-09-21 at build 130, after the PS5 push. The old list is done except where it is
recorded as blocked above.

1. **The 90s cinematic colour grade.** The owner asked for it on 2026-09-21 and deferred it the
   same minute ("we can explore that later tho"), so it is queued rather than started. The spec
   is in `docs/GAME_PLAN.md` under "Owner requests queued" - read it before starting, because the
   obvious implementation (crank saturation and contrast) is the wrong one. It is a post pass: a
   Texture3D LUT built in code on the city Environment's `adjustment_color_correction`, so no
   editor step and one switch to turn it off.
2. **Judge everything on Forward+ from now on.** `tools/glshot/forward_shot.sh`. This is a
   working practice, not a task, and it is first among them because the alternative has already
   cost this project one entirely broken subsystem (see build 130).
3. **The distance.** Beyond the streamed chunks the whole world is one plane wearing
   `shaders/macro_ground.gdshader`, shaded from a 256 px bake - 55 metres per texel. In any shot
   from the air, which is most of how the owner plays, it is dead flat grey-brown over a third of
   the frame. Far buildings (`shaders/building_lod.gdshader`) are the same story: coloured boxes
   with a window grid printed on them, no facade typology, no glazing specular, so a skyline has
   no value contrast. Both are shader work on geometry that already exists.
4. **Interiors.** Windows have traced fake rooms; doors and lobbies do not. A handful of enterable
   ground-floor interiors would be the biggest single step left in making the city feel real, and
   it is the one thing on this list that changes how the game plays rather than how it looks.
5. **Traffic and parked cars on the hill roads**; pedestrians on the campus quad and the pier.
6. **Wind on the bushes and hill scrub.** Palms and tree leaves sway
   (`shaders/foliage.gdshader`, `foliage_tex.gdshader`); `model_shrub()`, `model_scrub()` and the
   hill grass tufts are still dead still and would take the same treatment.
7. **Shop names at a distance.** Each name is a TextMesh and they stop at 75 m. Rasterising the
   whole name list into one atlas at load and sampling it in the fascia branch of the building
   shader would put a name on every band at any distance, with no geometry at all.
8. **Animation blending** for pedestrians (idle / walk / run, turning) and reactions to cars and
   gunfire.

## 11. Quick test script to give the owner after any push

"Grab build-N from the Releases page (or the browser build with ?showroom). Walk, shoot a
pedestrian, take a car across town and into the hills, get out on a slope, fly a jet from the
airport, watch a sunset (Esc shows the clock). Tell me what looks or feels wrong."
