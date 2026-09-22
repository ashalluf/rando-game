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
scripts/weapons/         weapon.gd base, assault_rifle, rocket_launcher, rocket, explosion, gravity_gun, weapon_fx, weapon_manager
scripts/world/           city_streamer, city_chunk, city_plan, macro_map, hill_roads, landmarks, building, prop_factory (primitives + model_* merged Poly Haven models), street_props, trash_can, physics_prop, day_night, ferris_wheel
scripts/vehicles/        vehicle.gd (cars), aircraft.gd (jets)
scripts/npc/             pedestrian.gd, ragdoll.gd, traffic.gd
scripts/util/            physics_budget.gd, world_state.gd, sfx.gd (autoloads)
scripts/ui/              debug_hud, minimap, minimap_frame, minimap_border, crosshair
shaders/                 building, grass, terrain, sky
assets/textures/         CC0 PBR sets from ambientCG (1K JPG)
assets/models/           Meshy .glb models, their .json manifests, extracted textures, .import files, thumbs/
tools/meshy.py           Meshy API pipeline (generate, texture, rig, animate, download)
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
- **The smoke test is now 210 checks and takes most of the 420 s timeout in
  `tests/headless_check.sh` on an idle box.** Under load from a large fleet it *times out* at
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
