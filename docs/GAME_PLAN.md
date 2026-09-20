# Game plan

3D open-world chaos sandbox. Godot 4.7.2, GDScript, Forward+. Overpowered player, unlimited guns,
seeded realistic city to wreck (high-poly, real assets; no low-poly look, owner's decision 2026-09-19). Silly and over the top. See `CLAUDE.md` for working rules.

## Roadmap

Build in this order, one milestone per PR or a few PRs.

- [x] **1. Player and test box.** Third-person CharacterBody3D controller: run, sprint, super-high
  jump, double jump, strong air control, no fall damage. Spring-arm follow camera with mouse look
  that does not clip through walls. Gamepad and keyboard/mouse input mapped. Greybox test level:
  large flat ground, ramps, tall boxes of varied heights, and a pile of RigidBody3D crates.
- [x] **2. Guns.** Weapon system with instant switching and unlimited ammo. Start with three: a
  hitscan rifle that shoves physics objects, a rocket launcher with an explosion that applies radial
  impulse, and a gravity gun that grabs and launches objects. Simple crosshair HUD.
- [x] **3. Building shader.** A single shader that makes a plain box look like a building:
  parameters for window style, window tint, facade finish and color, floor height, and randomly lit
  windows. A `Building` scene that takes a seed and picks a shape style, dimensions, shader
  parameters, and rooftop props (AC units, water towers, antennas, billboards) from small option
  lists. Generate one city block to prove variety.
- [x] **4. Seeded city generator.** Road grid with varied block sizes, a few intersection types,
  occasional parks and plazas, and districts defined by parameter ranges (downtown tall glass,
  midtown mixed, suburbs low brick, industrial warehouses). Sidewalk props and street trees
  scattered by the same seed.
- [x] **5. Chunk streaming.** Generate chunks around the player and free distant ones. Cheap box
  LODs for the far skyline. Persist a list of destroyed objects per chunk so destruction survives
  leaving and returning. Origin re-centering to avoid floating-point jitter far from the origin.
- [x] **6. Vehicles.** Drivable cars using VehicleBody3D with bouncy, overpowered arcade handling.
  Enter and exit. Modular car variety: a few body types, random paint, small add-ons. Parked cars
  spawned by the city generator.
- [x] **7. NPCs and traffic.** Simple wandering pedestrians that ragdoll when hit, basic traffic
  following road lanes. Strict caps on active counts.
- [x] **8. Foliage and polish.** Code-generated low-poly trees and bushes with random variation,
  MultiMesh grass with a wind shader in parks, day/night cycle, sound effects, pause menu with a
  seed input field.

## Owner requests queued

- **Miniature Los Angeles layout** (asked 2026-09-19): a coastline with beach and ocean, a hill with
  big letters, a pier with a Ferris wheel, a recognisable skyline of specific towers. Keep everything
  legally distinct: original sign text, original pier name, towers inspired by but not copies of
  real ones (the real sign, pier sign and some towers are trademarked).
  - [x] Push 1: macro map with ocean, beach, hills, peninsula, district placement (`MacroMap`).
  - [x] Push 2: the hill sign ("RANDOWOOD"), the pier ("RANDO PIER") with a spinning Ferris wheel,
    a coaster loop, booths and lamps, and the observatory with three domes and a terrace.
  - [x] Push 3: landmark skyline downtown (Crown Tower, Five Drums hotel, Ziggurat Hall, the
    Stack), an airport zone with two runways, a terminal, a control tower, a saucer restaurant on
    arches and parked planes, and a port zone with container stacks, gantry cranes, a harbor and
    a moored container ship.

- **Realism and character batch** (asked 2026-09-19), all done in builds 42 to 51: real models
  from Meshy for cars, pedestrians and jets (every prompt ultra-realistic), bigger crowds, a real
  sky, a GTA-style skyline, hills with roads and estates, the peninsula in a bay, a university
  campus, a bigger airport with flyable jets, bullets that hurt people. See `docs/HANDOFF.md`
  for the state after that batch and the suggested next steps.

- **Owner feedback 2026-09-20** (after builds 54 to 58): no more Meshy anywhere, real
  commercial districts (plazas, big-box stores, groceries, fast food, gas stations), everything
  ultra realistic (buildings still look like blocks from the air, streets need far more
  detail), tsunami-size waves, thunderstorms and weather, unlimited jumps, a much better
  minimap, sounds from Freesound (needs the owner's API key). Queue, in order: cars forward +
  paint + far windows + minimap + jumps (build 60), streets detail (build 61), commercial city (build 62),
  weather and waves (build 63), facade geometry and rooftops (build 64), Freesound sounds.

- **World character** (asked 2026-09-19): hills and slopes through the whole city; the
  illusion of uniqueness through cheap seeded surface variation, never hand placement.
  - [x] Push 1 (build 57): rolling relief through the city (`MacroMap.relief_at`).
  - [x] Push 2 (build 58): surface variation: each road keeps one of two asphalt sets and five
    tints plus a yellow or white, dashed or solid center line; each block picks a paving set
    and tint from its district, a dominant tree species and a lamp paint; crosswalks come in
    three styles per intersection; lawns range lush to dry; grime ranges per district.
  - [ ] Push 3: a less regular grid (merged double blocks, dead ends, a diagonal avenue).

- **High-poly realism** (asked 2026-09-19: "I don't want a low poly look, I want high poly"):
  replace the primitive props, buildings and foliage with real assets. Sources: Poly Haven and
  ambientCG (CC0, open APIs, no key) plus Meshy for anything that has to be made to order.
  - [x] Push 1 (build 54): Poly Haven street props (hydrant, trash can, bench, cafe set, planter,
    concrete barrier, barrel, tyre) merged into batchable meshes; district clutter.
  - [x] Push 2 (build 55): street lamps, bushes, manhole covers, real trees (Poly Haven trees
    reduced from millions of triangles with `tools/decimate_tree.py`), hill landscape (aerial
    ground textures, boulders, shrubs, dry scrub, grass tufts), clearer sky (less haze and fog).
    Meshy is out for good (owner: the tinted results looked wrong); Poly Haven only.
  - [ ] Push 3: traffic signals, stop signs, palms, beach and pier props. Poly Haven has no
    signal or stop sign, so those stay primitives until a CC0 source turns up.
  - [x] Push 3 (build 56): building facades: eleven Poly Haven wall sets picked per building,
    window reveals and inset shading, grime near the ground and streaks under windows.
  - [ ] Push 4: rooftop props, storefront awnings and signs as real assets.
  - [ ] Push 5: a Poly Haven HDRI for the Mac build's reflections.

## Current state

All eight roadmap milestones are in, plus the west-coast map with its landmarks.

Polish: parks get `grass_per_park` (2500) grass blades in a MultiMesh with `shaders/grass.gdshader`
(wind sway from TIME, per-blade phase in INSTANCE_CUSTOM) and bushes; suburbs get bushes along the
sidewalks. `DayNight` (`scripts/world/day_night.gd`, a node in the city scene) runs a 480 s day
from 09:00, moves the sun, tints sky and fog, and sets the `night_factor` shader global that makes
building windows glow (lamp heads are always emissive). `Sfx` autoload synthesizes every sound at
startup (no audio files): shot, rocket, explosion, grab, launch, jump, land, thud, break, yelp,
boost loop, engine loop. `PauseMenu` (Esc) pauses, releases the mouse, and has a seed field:
Rebuild sets `WorldState.pending_seed` and reloads the scene. HUD shows the clock and a round rotating minimap (bottom right). Debug:
`?hour=21` on the web or `-- --hour=21` on desktop.

NPCs: `Pedestrian` (`scripts/npc/pedestrian.gd`) is a CharacterBody3D that wanders between random
points on its block's sidewalk ring; chunks spawn `pedestrians_per_block` up to `max_pedestrians`
(70). It collides with the world only, and an Area3D on it detects anything fast: cars, thrown
crates, debris, or a boosting player above 14 m/s. Bullets and explosions call `knock()`. Knocked,
it becomes a `Ragdoll` (six pin-jointed pieces) registered as debris. `TrafficManager`
(`scripts/npc/traffic.gd`, child of the streamer) keeps `traffic_cars` (14) kinematic Vehicles
driving the lanes on the right, turning at random at intersections, spawning 120 to 260 m from
the player and despawning past 380 m or outside city zones. Bumper areas on every car knock
pedestrians and launch the player. A hit traffic car drops into real physics.

Vehicles: `Vehicle` (`scripts/vehicles/vehicle.gd`) is a VehicleBody3D built from boxes in code
with four body types (sedan, pickup, van, sports), ten paints and three add-ons (roof rack,
spoiler, light bar). Handling is arcade: 7000 N engine, 2.2x nitro on boost, grippy wheels, soft
bouncy suspension, steering that tightens at speed, air torque for flips and rolls, and a
self-righting torque when stuck upside down. Chunks park up to `cars_per_block` cars in the
lanes. Press interact (E / gamepad Y) near a car to get in; the player rides the seat and the
camera follows; interact again to get out. Weapons are hidden while driving.

`MacroMap` (`scripts/world/macro_map.gd`) is the big picture: ocean west of a curving coastline
(x about -900 at the origin), a 70 m beach with palms and lifeguard towers, mountains north of
z = -900 rising to about 260 m with noise, a hilly peninsula bulging into the sea to the
south-west, downtown centered at (700, 250), a second mid-rise cluster on the west side, and the
industrial port in the south-east. Chunks ask `plan.zone_at()` and build water, sand, or a terrain
tile (SurfaceTool mesh colored by height plus a HeightMapShape3D) instead of a city block. The
spawn stays at the origin, in midtown. Landmarks: the hill sign north of the city, the pier on the
north-west coast, the observatory on the ridge, four skyline towers downtown, the airport terminal
south-west, the container ship in the harbor south-east. Debug: open the web build with `?spawn=x,z` or
`?spawn=x,z,yaw,pitch` (yaw 0 = north, 90 = west) or run the desktop build with
`-- --spawn=x,z,yaw,pitch` to start anywhere. The main scene is `scenes/levels/city.tscn`; `test_box.tscn` stays as
the movement/weapons test room.

The city is endless. `CityPlan` (`scripts/world/city_plan.gd`) answers any road, block or
intersection index lazily and deterministically from the seed: streets 14 m, avenues 24 m, blocks
70 to 120 m, an intersection at the origin, districts by distance (downtown < 180 m, midtown
< 380 m, suburbs beyond, one seeded quadrant industrial past 260 m), block kinds (buildings, park,
plaza) and intersection kinds (plain, stop signs, signals, roundabout).

`CityStreamer` (`scripts/world/city_streamer.gd`, the scene root) keeps a 5 x 5 block area of
full-detail `CityChunk`s around the player and a 15 x 15 area of cheap LOD chunks (slabs plus one
colored box per building part, no props, no collision), building a few chunks per update, freeing
the rest. It moves the ground plane under the player and re-centers the world when the player is
1000 m from the origin (`WorldState.world_offset` holds the true offset; chunk nodes sit at minus
that offset so their children use true world coordinates).

Each chunk owns its block, the road on its +X side, the road on its +Z side and the corner
intersection. Street props (lamps, hydrants, benches, stop signs, signals) are MultiMesh instances
with collision shapes on the chunk's `StreetProps` body; each shape carries its prop record.
Bullets and explosions call `take_hit()`, props have health, and a broken prop hides its instances,
drops debris, and is recorded in the `WorldState` autoload so it stays broken when the chunk is
rebuilt. The HUD shows district, chunk counts, world position and how many things are wrecked.

Milestone 4 recap:
Milestone 3 recap: `shaders/building.gdshader` turns any BoxMesh into a facade: window
style (punched, ribbon, curtain, narrow), facade finish (flat, brick, panels, glass), colors, floor
height, storefront on the ground floor, seeded lit windows, gravel roof with a parapet.
`scripts/world/building.gd` (`scenes/props/building.tscn`) takes a seed and picks a shape (slab,
tower, stepped, podium + tower, L-shape), sizes within `lot_size`, a finish and window style, then
fits the window grid exactly to each box part and adds rooftop props (AC units, stair bulkhead,
water tower, antenna, billboard) that avoid each other and taller parts. The test level has a demo
city block of ten buildings 125 m in front of spawn.

Milestone 2 recap: Weapons live in `scripts/weapons/`: `Weapon` base class,
`AssaultRifle` (AK-47, full-auto hitscan, shoves what it hits), `RocketLauncher` (spawns `Rocket`,
`Explosion.blast` applies a radial velocity change to props and launches the player for rocket
jumps), `GravityGun` (grab, float at chest height, hurl). `WeaponManager` sits on the player's hand
(`Visual/WeaponMount`), builds all three from code, switches with 1/2/3, scroll, or bumpers.
`WeaponFX` makes tracers, flashes, impacts and explosions from unshaded primitives. The HUD shows
the weapon list and a ring crosshair that turns cyan while holding something.

Boost replaced sprint: hold Shift (gamepad B) for unlimited thrust up to 45 m/s on the ground; in
the air it follows the camera pitch with gravity cut to a quarter, so looking up and boosting flies.

Milestone 1 recap: Main scene: `scenes/levels/test_box.tscn`. The level script
(`scripts/world/test_level.gd`) generates a 400 m checkered ground, a jump gauge (boxes of 4 to
30 m with height labels), six ramps, forty tall boxes (some with a step on top), and ninety-five
crates (a pyramid and a wall) from `world_seed = 1337`. `PhysicsBudget` autoload caps props at 300,
freezes props more than 90 m from the player, and frees debris after 12 s. A debug HUD (F1) shows
FPS, speed, last jump peak, and prop counts.

Input actions for weapons (`fire`, `alt_fire`, `next_weapon`, `prev_weapon`, `weapon_1..3`) are
already mapped so milestone 2 is script-only.

## Decisions log

- **2026-09-20 Interior mapping on every window (owner: "set the bar for visuals extremely
  high").** Buildings were boxes with windows painted on them, which is what read as cheap up
  close however good the lighting was. The building shader now traces the view ray into a
  virtual room behind each pane and shades the inner surface it hits, giving real parallax: move
  along a facade and you see into each room from a different angle. Each room has its own paint,
  a floor darker than its ceiling, light falling off with depth, and a blind pulled down to its
  own height, which is what makes a facade read as occupied. At night the existing lit-window
  logic tints those rooms warm, so the skyline now has depth as well as brightness.
  Needed a wall-space frame in the shader (`world_pos`, `world_normal`, `world_tangent`
  varyings) and the window opening rectangle per style, which was previously implicit in the
  glass test.

- **2026-09-20 Character pass, and the hard limit on it (owner: "the 3D characters are horrible,
  I want this almost indistinguishable from reality").** What was wrong is measurable: each
  pedestrian is 8,300 triangles with a single 1024 colour texture, no normal map and no
  roughness map, and there are three models for the whole city. Their glTF material also asks
  for full white emission and double specular, i.e. a shiny self-lit mannequin.
  Fixed inside those limits: `shaders/character.gdshader` rebuilds surface response (skin vs
  cloth roughness, subsurface on skin, no emission) and recolours each character's clothes, so
  three models now read as many people; plus per-character height and width, and a random offset
  into the walk cycle so the crowd is not in lockstep. Checks: 14 outfits, 21 heights.
  **Not fixable in code:** 8.3k triangles and a 1K albedo cannot be photoreal, however good the
  shading. That needs scanned or sculpted humans at 30k+ triangles with normal and roughness
  maps. Sketchfab's search API works here without credentials and has rigged humans at 25k to
  130k triangles under CC Attribution (free commercially, credit in `docs/ASSETS.md`), but
  downloading returns 401 without a token. Mixamo is 403 here. So the owner needs to supply one
  API token before characters can improve further; everything else is already done.

- **2026-09-20 Real palm trees and palm-lined streets (owner: "need more foliage, more trees,
  it's Cali, put palm trees, make the nature more unique").** The old palm was a cylinder trunk
  with three flat boxes for fronds and lived only on beaches. `PropFactory.palm()` now generates
  a whole tree as one mesh: a tall slender curved trunk (Washingtonia proportions, 11-17 m, not
  the short fat coconut palm the primitive implied) with ridged bark, a crown of fronds whose
  leaflets are individual pointed blades rather than a continuous strip - a strip renders as a
  solid green fan, which was the first attempt - plus a skirt of dead brown fronds and coconuts.
  Palms now line whole blocks in the city, rolled per block from a district `"palms"` odd so
  they appear in runs the way boulevards do, heaviest in the suburbs and midtown.
  Two traps: the palm roll consumes a random number inside `_add_tree`, which shifts every
  block's seeded layout, so anything that depended on the old layout (the smoke test's parked
  car) moves; and giving street palms collision walls roads in, so they are built non-solid like
  the trees they replace. Reduced airborne gravity for cars (build 71) also means a car settles
  more slowly, so the test now waits for its wheels before jumping.

- **2026-09-20 Flying cars and a real explosion (owner: "make the car jump work without the
  front tilting over, I basically want to fly cars around the way I fly the main character",
  "make the explosion graphics a million times better").**
  - Cars: the old air control applied flip torque (W = front flip), which is exactly the nose
    tipping the owner objected to. Airborne cars are now stabilised: `Vehicle._fly()` drives the
    body toward a target attitude through `angular_velocity` (clamped by `max_turn_rate`, since
    a half-turn of error times the gain is a violent overshoot), the stick aims it, and boost
    thrusts along the camera with `fly_gravity_scale` 0.12. Gotcha: `apply_central_force` does
    nothing on a VehicleBody3D because the wheel solver clears the force accumulator; use
    `apply_central_impulse(dir * thrust * mass * delta)`.
  - Explosions went from two unshaded spheres to a layered effect: light flash, white-hot core,
    fireball, smoke, sparks, shockwave ring, lit debris, scorch decal and camera shake. Three
    engine traps, each of which silently produced nothing: billboarded particles need
    `billboard_keep_scale = true` or `scale_amount` is discarded and every puff is one metre; a
    `Curve` clamps to `max_value` (1.0 by default) so the growth factor did nothing; and a
    particle system's automatic bounds start empty, so `custom_aabb` has to be set. Fire is
    alpha-blended, not additive - additive fire only adds brightness and washes out to nothing
    in daylight - and the puffs are slow and fat so they overlap into one mass instead of
    scattering into separate dots.
  - `tools/glshot/fx_shot.gd` screenshots an effect. It slows the clock to ~0.4 % and waits on
    real elapsed time, because a software-rendered frame takes most of a second and counting
    frames lands the shot anywhere from the first millisecond to long after the fire has gone.

- **2026-09-20 Cinematic realism pass (owner: "make this ish look like an industry giant made
  it in terms of realism").** Nothing here needs new art; it is all lighting, camera and
  material physics, which is where the gap between a hobby build and a shipped game actually
  lives.
  - **Tonemapping ACES -> AgX.** ACES clips bright highlights to white and skews them; AgX rolls
    them off and desaturates as it goes, the way film does. Sky, headlights and sun-struck
    facades stop blowing out. `tonemap_white` 6 -> 8, saturation nudged back up (AgX is flatter
    by design).
  - **Sky-coloured ambient.** `DayNight` used to force `AMBIENT_SOURCE_COLOR`, a flat fill that
    makes every shadow the same dead grey. It now uses `AMBIENT_SOURCE_SKY` at full contribution
    by day, blending back toward a colour fill at night so the city is not pitch black. Shadows
    now read blue at noon and warm at dusk. Biggest single win in the pass.
  - **SSIL** (screen-space indirect light) for local bounce, **SSAO** retuned (smaller radius,
    less intensity) so it stops double-darkening next to SSIL.
  - **Aerial perspective + height fog.** `fog_aerial_perspective` 0.85 tints distance haze with
    the sky in that direction, and `fog_height` 34 m / `fog_height_density` 0.0085 pools haze in
    the streets so towers rise out of it. This is what makes a city read as huge. Height fog is
    very easy to overdo: the first attempt used `fog_height` 34 m with density 0.0085 and turned
    the whole street into blue milk. Street level is only ~6 m up, so anything more than about
    0.001 of height density swamps the view; keep `fog_height` near 16 m.
  - **Temporal antialiasing everywhere.** MSAA off (expensive, and useless against shader
    aliasing, which is what the window grids and foliage suffer from). TAA at native resolution
    on HIGH/MEDIUM; FSR 2.2 temporal upscaling at 0.75 / 0.6 on LOW/LOWEST, replacing the old
    bilinear downscale. Better image AND cheaper than before, which is how consoles do it.
  - **Auto exposure** on the player camera, deliberately narrow (ISO 200-620) so it adapts
    walking into a shadowed street without pumping.
  - **Car paint**: metallic basecoat + clearcoat lobe + aluminium flake + per-panel roughness
    ripple. Palette reweighted to real-world colour distribution (mostly white, black, grey,
    silver; muted colours; two loud ones). The saturated single-colour cars were the main reason
    traffic read as toys.
  - **Grass**: was one upright 14 x 55 cm quad per instance, which looked like green flags. Now
    a tuft of four tapered blades curving over, with normals bent toward up so the lawn lights
    as one soft surface, backlight for sun-through-blade glow, per-tuft colour variation, and a
    70 m draw distance (`MultiMeshBatch.set_draw_distance`). A tuft is far smaller than the old
    flag, so `grass_per_park` went 2500 -> 6500 or a lawn reads as scattered sprouts.
  - The sky's radiance cubemap now updates **incrementally** (`Sky.process_mode = 2`) instead of
    every frame. Ambient light reads from it, so a realtime rebuild at 256 px would have cost
    more than the ambient upgrade was worth; the day/night cycle is slow enough not to notice.
  - **Caveat for future sessions:** none of SSIL, SDFGI, SSR, volumetric fog, TAA or FSR exist in
    the Compatibility renderer, so neither `tools/glshot` nor the web harness can show them. Only
    the owner's Mac sees the real result. Judge those from the owner's report, not screenshots.

- **2026-09-20 Still laggy after the population pass (owner: "still just like super laggy").**
  `Quality` became the real performance system: desktop starts at MEDIUM (SDFGI, volumetric fog
  and depth of field are HIGH-only), steps down after 5 s + 3 s windows under 50 FPS, and the
  lower levels also cut the crowd and traffic caps (60 %, 35 %), trimming the farthest people
  and cars right away (`CityStreamer.trim_pedestrians()`, `TrafficManager._maintain()`), raise
  the pedestrian update throttle, halve the physics prop cap and shorten shadows. The sun uses 2
  shadow splits instead of 4 (half the shadow draw calls). The HUD's new frame line (cpu,
  physics, gpu, draws, objects, tris) is what the next lag report should be based on.

- **2026-09-20 Spawn under the ground, MacBook heat (owner: "spawning underneath the ground and
  can't get up over it", "making my macbook hot af").** Since the rolling city (build 59) the
  ground at the origin is 5.5 m up while the scene placed the player at 1.5 m: `CityStreamer.
  _settle_player()` now lifts the start point onto the ground, and `Player` recovers whenever it
  is below the relief in a city zone (`CityStreamer.under_city_ground()`, relief only: `height_at`
  carries hill noise the city ground does not stand on). The smoke test had been dropping its
  test car at y 0.6 under the same slab for weeks; it now asks the city for the road height.
  Heat: the desktop build had no frame cap and rendered as fast as the GPU allowed (120 Hz on a
  ProMotion display); `Quality` caps it at 60 (`max_fps`, off on web and in the headless check)
  and the adaptive step-down now triggers under 50 FPS instead of 42.

- **2026-09-20 A populated city (owner: "50x the amount of pedestrians and vehicles", "mostly
  concentrated in the downtown area and gradually less the further out", "except for the
  airport, which should be jampacked").** Pedestrians per block are a district parameter
  (downtown 46, midtown 20, campus 16, suburbs 6, industrial 3, the downtown core up to 2x),
  cap 650 (web 140); traffic scales with `TrafficManager.density_at()` (150 cars downtown,
  20 % of that at the edges, slower where dense) with the airport approach jammed too. The
  airport rect grew north to hold a drop-off loop road in front of the terminal
  (`Landmarks._build_dropoff()`: two-way road, median, curb strip with canopy pillars and
  DEPARTURES signs) that 90 cars crawl around bumper to bumper (`MacroMap.terminal_loops`) with
  45 people on the curb. Not literally 50x: hundreds of animated rigs are what a laptop takes;
  the far-pedestrian update throttle (build 65) is what makes 650 affordable.

- **2026-09-20 Animated main character, real ragdolls, first lag pass (owner: "GTA style main
  character instead of this orange blob", "they turn into low poly creatures" when hit, "it's a
  little bit laggy").** `Avatar` puts one of the rigged characters on the player (idle / walk /
  run by speed, stride frozen in jumps, lean on boost); the capsule is only a fallback. `Ragdoll.
  build_from_rig()` keeps the pedestrian's own model as one tumbling rigid body that flails its
  run cycle until it lies still; the six-box body remains for the box-person fallback. Lag:
  window frames became flat quads (20 tris instead of 60) drawn only within 240 m, SDFGI cells
  0.4 -> 0.8 m, rain particles trimmed, far pedestrians update every 3rd / 6th frame, and a
  `Quality` node steps the heavy effects down automatically when the frame rate drops under 42
  (HUD shows the level). Owner has been asked whether the monitor is 4K: screen-space effects
  scale with pixels.

- **2026-09-20 Facade geometry and real rooftop units (owner: "everything is still polygony",
  buildings "look like blocks").** `Building._add_facade_details()` puts real geometry on every
  part at FULL detail: a window frame (with a sill for punched and slot windows) at every cell
  the shader draws, sized per window style so frame and painted pane line up; a cornice around
  the roof edge and a string course over the storefront on brick, plaster and panel buildings;
  tilted awnings over ground-floor storefronts. Two MultiMeshes per part ("Frames", "Details"),
  frames left to the shader above 7000 cells. Rooftop "ac" props are now the Poly Haven
  `exterior_aircon_unit` (clean or rusted) on a concrete pad.

- **2026-09-20 Weather and tsunami waves (owner: "extremely realistic waves like tsunami size",
  "crazy ass thunderstorms and crazy weather").** `Weather` node (`scripts/world/weather.gd`,
  in the city scene) rolls clear / overcast / rain / storm every 70 to 160 s (odds and lengths
  are exports) and blends between them over 12 s. It drives: `DayNight.cloud_extra` and
  `weather_darken` (cloud cover, darker sky top and horizon, dimmer sun and ambient, grey fog),
  fog and volumetric density per state, a CPUParticles3D rain sheet that follows the player
  (1400 drops, 2600 in a storm, wind offset), wet streets (`PropFactory.set_wetness()` lowers
  the roughness of every cached road and sidewalk material), grass wind through the
  `wind_factor` shader global, lightning (random flashes every 3 to 11 s: a `flash` uniform on
  the sky, the sun's energy spiked through a meta the DayNight node reads, thunder from `Sfx`
  0.4 to 2.5 s later) and the sea. The ocean is now a subdivided plane per chunk with
  `shaders/ocean.gdshader`: three Gerstner swells scaled by the `wave_scale` global (1 calm, 6
  in a storm) plus a 420 m long tsunami wave (`tsunami_scale` global, 30 m tall at full
  strength) that rolls toward the shore for 40 s every 25 to 60 s during a storm. Foam on the
  crests, fresnel, a ripple normal. A solid box under the surface still holds the player up.
  Debug: `?weather=storm` on the web, `-- --weather=storm` on desktop. New synthesized sounds:
  `rain` loop and `thunder`.

- **2026-09-20 Commercial city (owner: "where's the shopping plazas, the home depots, the
  vons, the in n outs?").** Two new block kinds in `CityPlan` (`MALL`, `BIGBOX`, odds per
  district in `DISTRICTS`, only on blocks big enough) and pad lots (`pads` odds: an edge lot of
  a suburbs or midtown block becomes a fast-food drive-thru or a gas station). All built by
  `scripts/world/commercial.gd` from boxes, PBR sets, tinted glass, painted lots and 3D text:
  a shopping plaza is an L-shaped strip of shop units (anchor grocery, fascia band, storefront
  glass, pillars, awnings, bollards) around a parking lot with stalls, parked cars, lamps and a
  pylon sign; a big-box store is one huge box with a fascia sign, glass entrance canopy, garden
  center, cart corrals and a loading dock; a fast-food pad has a red band, glass front,
  drive-thru window, menu board and pylon; a gas station has a pump canopy, four pumps, a shop
  and a price pylon. Every name is original ("SUPER MART", "HOME & TOOL", "BURGER BOX",
  "GAS & GO"): no real brands, per the project rule. Bare blocks fixed too: suburbs and campus
  blocks get a lawn under the buildings, and skipped inner lots become pocket gardens
  (`_build_yard`). Minimap paints commercial blocks purple-grey.

- **2026-09-20 Streets detail pass (owner: "the streets need to be way more detailed").**
  `scripts/world/street_detail.gd` (static, called from the chunk) adds, all seeded: dark
  gutter strips and storm drain grates along every curb, asphalt patches per road, stop lines
  and lane arrows (straight and left turn, mirrored by heading) at signal and stop-sign
  intersections, painted parking stalls where cars park, named street signs on the +X +Z corner
  of every intersection (`CityPlan.road_name()`: north-south roads are avenues and boulevards,
  east-west roads are streets, a third numbered; `PropFactory.text_mesh()` caches a TextMesh
  per name), utility poles with three sagging cables in suburbs and industrial blocks, bus
  shelters with a glass back and the Poly Haven bench on avenues, tree grates under sidewalk
  trees, bike racks, news boxes, mailboxes and downtown bollards as breakable props. Flat
  markings are in `MultiMeshBatch.tilt_keys` so they lie on the relief.

- **2026-09-20 Cars face forward, real car paint, far buildings with windows, night minimap,
  unlimited jumps.** All four Meshy car models have their nose along +X, so `Vehicle.MODEL_YAW`
  is now -PI/2 for every type (with +PI/2 every car, driven or traffic, moved tail first: owner
  "a ton of the vehicles drive backwards"). The whole-model tint that made cars "one color,
  horribly painted" is replaced by `shaders/car_paint.gdshader`: bodywork (bright pixels of the
  greyscaled base color) takes the paint as glossy metallic, glass and tires (dark pixels) stay
  dark and glossy. Far LOD boxes use `shaders/building_lod.gdshader` through
  `PropFactory.building_lod_material()`: a fixed window grid per wall from the instance's
  scale, style / lit ratio / seed in `INSTANCE_CUSTOM`, lit windows at night, a plain flag for
  plinths; the skyline no longer reads as blocks from the air. Minimap redrawn dark with relief
  shading, outlined roads, landmark names, car chips, view cone, driving zoom.
  `Player.unlimited_air_jumps` is on. The harness takes `VW` / `VH` for big screenshots.

- **2026-09-19 The illusion of uniqueness (owner: "subtly changing things on the surface").**
  Nothing is hand placed; every choice is seeded. Roads: `CityChunk._road_look()` hashes the
  road's axis and index so one street keeps its look for its whole length: asphalt set
  (ambientCG or Poly Haven aerial asphalt), one of five tints, yellow or white center line
  (district `line_white` odds), dashed or solid. Blocks: `CityPlan.DISTRICTS[...].paving` lists
  the sidewalk sets a district uses (pavers, plain concrete, paving stones) and the block seed
  picks one plus a tint; `tree_weights` gives the block a dominant tree species (70 percent of
  its trees); `lamp_tint` paints the district's lamp posts through the instance color;
  `weathering` sets the grime range buildings draw from (downtown clean, industrial filthy).
  Intersections pick one of three crosswalk styles (zebra, wide continental bars, ladder
  edges) from their seed. Park lawns range lush to summer-dry. Dash meshes are now white and
  colored per instance.

- **2026-09-19 Hills and slopes through the city (owner: "we need hills and slopes throughout
  the city").** `MacroMap.relief_at()` is a second, gentler noise field (peak `relief_height`
  16 m, wavelength about 500 m, squared so flats outnumber ridges) that fades to zero on the
  beach, toward the bay, inside and 160 m around the airport, port and harbor, on the mountain
  hills (raw height above 2.5 m) and within 150 m of every landmark. `height_at()` includes
  it, so spawn, ground recovery and the showroom follow. In `CityChunk` everything samples it
  through `_gy()`: `MultiMeshBatch.ground` adds it to every instance origin (dashes, stripes,
  lamps, trees, props, LOD boxes), `_add_slab()` turns thin city ground slabs (roads,
  sidewalks, lawns, plazas, paths) into relief-following grids with a hanging skirt (the curb
  face) and trimesh collision, `_add_prop()` lifts the collision shapes, nodes (pedestrians,
  cans, barrels, parked cars, buildings) are lifted explicitly, avenue center lines are drawn
  in 6 m pieces, and LOD chunks get an invisible `ReliefFloor` trimesh so fast cars do not
  drop to the base plane. Buildings sit at the relief under their center and get a concrete
  `plinth_depth` box reaching below their lowest sidewalk corner; the shader's
  `ground_floor_height` and new `base_y` include the building's world Y so storefronts and
  grime stay at street level. Traffic cars sample the relief each frame and pitch along the
  slope ahead. Hills chunks are untouched (relief is zero there).

- **2026-09-19 Facade pass (owner: everything high quality).** Every building used one ambientCG
  set per finish; now `Building.WALL_SETS` lists several Poly Haven sets per finish (three
  bricks, four plasters and painted concretes, three concretes, corrugated iron and factory
  wall for warehouses) and `_pick_wall_set()` chooses one with the building's rng, so a block
  no longer repeats one brick. The shader got a `weathering` uniform (grime rising 5 m from the
  ground plus seeded streaks below windows), a wall "reveal" band around punched and slot
  windows, and glass that darkens toward its frame with a soft interior gradient so panes read
  as set into the wall. Screenshots now go into the chat on every visual change (owner's rule).

- **2026-09-19 Trees, lamps, hills and a clearer sky (owner: "everything high quality",
  "do the foliage and landscapes", "the sky is too hazy", and no more Meshy).** Poly Haven
  trees ship at 0.9 to 2 million triangles (every leaf modeled, thousands of twig tubes), so
  `tools/decimate_tree.py` rebuilds them: trunk and twigs through pymeshlab's texture-keeping
  quadric decimation (thinnest 65 percent of twigs dropped first, boundaries allowed to
  collapse), leaves replaced by one textured card per kept leaf (16 percent kept, scaled 2.5x,
  card UVs = that leaf's atlas region) in the leaf's PCA plane. Result about 40k triangles per
  tree; leaves render with alpha scissor (`PropFactory.model_tree()`) and take the instance
  tint. Street lamp is Poly Haven `street_lamp_01` with the bulb and glass surfaces made
  emissive in code. Bushes are `shrub_02` variants. Hills: terrain shader now samples Poly
  Haven `aerial_grass_rock` and `rocky_terrain_02`; `CityChunk._scatter_hills()` seeds
  boulders (with collision, on steep ground), shrubs, dry scrub and grass tuft clusters, kept
  off hill roads (`_near_hill_road`) and mansion pads. Sky: `DayNight.day_haze` 0.22 (was
  0.55), fog density 0.00022 (was 0.0006), volumetric fog 0.0025 (was 0.008), deeper sky top.
  Meshy is retired: 80 credits spent on three aborted jobs this session, none used.

- **2026-09-19 Real street props from Poly Haven (owner: high-poly, not low-poly).** The style
  rule flipped from clean low-poly to realistic high-poly. First batch: eight CC0 Poly Haven
  models packed to single `.glb` files with `tools/pack_gltf.py` (pure Python, embeds the .bin
  and 1K JPG textures). Poly Haven ships variants side by side in one file (fresh and aged
  hydrant, clean and rusty can, an unassembled bench kit), so `PropFactory.model_mesh()` picks
  nodes by name, bakes their transforms plus a variant offset, merges them into one ArrayMesh
  and runs `ImporterMesh.generate_lods()`; the result goes through `MultiMeshBatch` exactly
  like the old primitives and is cached per variant. The bench is assembled from the kit in
  code (seat back rotated 69 degrees onto the back supports) and faces -Z; park benches now
  face their path. Trash cans (`TrashCan`) and the new barrels and tyres (`PhysicsProp`) are
  rigid bodies with the model as their mesh. District params got `cafes`, `planters` and
  `clutter` counts (industrial blocks get barrels, tyre stacks and concrete barriers). The
  hydrant is 43k triangles per variant; that is fine on desktop with LODs, and the web build
  grew from 95 to 122 MB. Extracted texture imports use VRAM compression (`compress/mode=2`).

- **2026-09-19 Bullets hurt people (owner: "the AK-47 can't hurt anybody").** Pedestrians sat
  on physics layer 2 (the player layer) and the aim mask only covered world + props, so the
  hitscan ray passed straight through them. Pedestrians now live on layer 4 (`8`, "npc");
  `Player.AIM_MASK` and `BLAST_MASK` include it, and the car and jet bumper areas look for it.
  The smoke test fires the rifle at a pedestrian and expects a ragdoll.

- **2026-09-19 Bigger airport and flyable jets (map-character batch, part 5).** The airport is
  now 980 x 350 m with three 55 m runways (z 760 / 860 / 960) and reaches into the sea on fill.
  `Aircraft` (`scripts/vehicles/aircraft.gd`) extends `Vehicle`: a VehicleBody3D with tricycle
  gear (taxi with the throttle, steer when slow, S brakes) plus an arcade flight model in
  `_physics_process`: thrust along the nose, lift = airspeed^2 x `lift_coef` (level at ~43 m/s,
  capped), forward drag, strong sideways and vertical drag so it flies where it points, pitch
  and roll torques scaled by airspeed, a turn that follows the bank, self-leveling when the stick
  is centered. Shift = throttle up, right click = throttle down, W / S pitch, A / D roll. Two
  kinds (PRIVATE 20 m, AIRLINER 38 m) with Meshy models (30 credits each), scaled like the cars.
  Three jets wait on the apron (`MacroMap.apron_spots`), spawned by the airport chunk under the
  city root like parked cars; `Vehicle.enter_radius` lets the player board from under a wing.
  Landmark `hangars` (three barrel-roof hangars, fuel tanks, beacon) at the east end; the
  terminal got jet bridges and lost its static planes. Hill terrain bodies also carry physics
  layer 5 (`CityChunk.TERRAIN_LAYER`) so the "terrain above me" ray is not blocked by a mansion
  pad; the smoke test caught that. The smoke test boards a jet, rolls it down the field and
  pulls up (125 checks). `?showroom` now includes both jets.

- **2026-09-19 University campus (map-character batch, part 4).** New `CityPlan.District.CAMPUS`
  (brick and stone halls 8-24 m on big lots with wide gaps, 30 % quads, 12 % plazas, trees
  everywhere) inside `MacroMap.campus_radius` (250 m) of `campus_center` (-620, -520) on the west
  side. Landmark `campus_hall` at its center: brick main hall with a stone plinth, portico
  columns, twin towers with pyramid caps and a dome, grand steps, a 120 x 80 m quad with cross
  paths and a fountain, a bell tower with a lit belfry, a sign wall lettered "RANDO U" (the block
  font gained a U) and trees along the quad. Original design, no real campus copied. The minimap
  paints campus blocks tan; the HUD district reads "Campus".

- **2026-09-19 Hills with roads and estates, peninsula in a bay (map-character batch, part 3).**
  `HillRoads` (`scripts/world/hill_roads.gd`, built by `MacroMap.setup()`) plans a seeded road
  network in the hills: "Sunset Drive" winding along the hill foot from the beach east, four
  canyon roads climbing north (smooth random walks), two estate loops off each canyon, and a rim
  drive around the peninsula. Each road gets a height profile: raw terrain sampled at its points,
  smoothed twice, grade-limited to 11 %. `MacroMap.height_at()` now returns `raw_height_at()`
  carved by the roads (flat across the road width, blending back over a 14 m shoulder, so cut and
  fill slopes appear by themselves) and by mansion pads (17 m flat discs, 12 m shoulder). Hill
  chunks with a road use a 28x28 terrain tile and collision, draw asphalt strips on the road
  beds (clipped to the chunk) and build estates on the pads: paving pad, a low SLAB `Building`
  villa, pool, low wall, palms; far chunks draw the pad and a house box. 182 lots at seed 0.
  The peninsula is taller (150 m) with steeper sides, sits in a bay (`in_bay()`: water south of
  z 1000 and west of x 400 except the peninsula itself) and its low outer ring is beach, not
  city. Ocean surface moved to y +0.15: it was below the ground follower plane, which showed
  through as grass over the whole sea. The minimap draws hill roads as white lines.

- **2026-09-19 GTA-style skyline (map-character batch, part 2).** Downtown lots now get a
  height boost toward the center (`MacroMap.skyline_boost()`: min x2, max x2.2 at the core, so
  50-140 m becomes 100-300 m in the middle), denser lots (28-46 m, 2-5 m gaps) and mostly glass.
  Two new `Building.Shape`s: SETBACK (4-6 centered tiers) and CROWN (slim tower + crown box +
  spire). A "spire" roof prop (mast with a red beacon) goes on CROWN towers and most buildings
  over 140 m. Two signature landmarks: `needle` (tapering 320 m glass tower, lit crown ring, 70 m
  mast at (770, 330)) and `twin_glass` (two 210 m towers with a sky bridge at (600, 210)). The
  spawn override takes an optional fifth value, height, for aerial views.

- **2026-09-19 Picturesque sky (owner's "make the sky gorgeous", part 1 of the map-character
  batch).** `shaders/sky.gdshader` replaces the ProceduralSkyMaterial: zenith-to-horizon
  gradient with haze, a real sun disc and halo from LIGHT0 (the same light is the moon at night,
  so the disc shrinks and pales with `night_factor`), five-octave FBM clouds on a plane above the
  camera (coverage, softness, drift speed and lit/shadow tints as uniforms; fbm is stretched from
  its 0.3..0.75 band to 0..1 so coverage means what it says), twinkling stars at night. DayNight
  drives every color by hour, with a 1.5 h golden hour (`dusk` = 1 - |elevation| * 2.6) that
  turns the horizon orange and the clouds peach. Works on the Compatibility renderer. Remaining
  parts of the batch: GTA-style skyline, hills with roads and mansions plus the peninsula coast,
  a campus landmark, a bigger airport with flyable jets.

- **2026-09-19 Realism rule for generated assets.** The owner wants every Meshy prompt to ask for
  the most ultra-realistic result possible. `tools/meshy.py` appends that wording to every prompt
  and texture prompt itself and defaults to Meshy's standard model at ~8000 faces (20 + 10
  credits per model); the seven models were regenerated that way (252 credits). Car paint: the
  realistic textures came out colored, so `shrink_glb.py --desaturate` greyscales and brightens
  the base color and the seeded paint tint provides the color. Meshy's animated export drops the
  metallic/roughness and normal maps and leaves glTF's metallic 1 plus an emissive copy of the
  base color, which rendered as shiny self-lit mannequins; `Pedestrian._add_model()` sets
  metallic 0, roughness 0.85 and no emission on that material.
- **2026-09-19 Bigger crowds.** Pedestrians per block 4 -> 8, cap 70 -> 160, traffic cars 14 -> 24
  on desktop; the browser build keeps 80 / 14 (`web_max_pedestrians`, `web_traffic_cars`)
  because WebGL skinning of 8k-triangle characters is the expensive part there.
- **2026-09-19 Screenshot harness lesson.** The web build runs at ~1 FPS under SwiftShader and
  Godot clamps frame time, so a 1 ms key tap in Playwright moves the player several meters and
  timers take many wall seconds. The harness (`scratchpad/pw/webtest4.js`) presses no keys; a
  spawn query places the camera instead. Two hours were lost to "invisible pedestrians" that
  were simply behind the camera.

- **2026-09-19 Realism step 3: generated models from Meshy.** The owner has a Meshy account, so
  cars and pedestrians are now real models made through its API (`tools/meshy.py`: Smart
  Topology preview at ~3000 faces, PBR refine, rig + animation clips for characters; then
  `tools/shrink_glb.py` re-encodes the embedded textures to 1K JPEG so a model is ~0.5 MB).
  Cars: one white model per `Vehicle.BodyType`, scaled to the box car's length, yawed so the
  nose is -Z (`MODEL_YAW`), tinted by setting `albedo_color` on a duplicated material (so the
  seeded paint palette still works); the box parts stay as collision only and the wheel
  cylinders are hidden because the models have wheels. Pedestrians: three rigged characters
  with Idle / Casual_Walk_inplace / run_fast_3_inplace clips, picked by seed; the walk clip's
  `speed_scale` follows `walk_speed`. Gotchas: Meshy rigs face +Z (rotate PI) and put the
  skeleton in centimeters under a 0.01 armature while the mesh bounds stay in meters, so the
  imported AABB is 2 cm and the renderer culls the character: `custom_aabb` in skeleton units
  fixes it. The ragdoll is still the box one. Debug `?showroom` (web) / `-- --showroom`
  (desktop) lines every car type and pedestrian model up in front of the spawn point. Buildings
  and street props stay procedural; the API key lives only in the session environment.

- **2026-09-19 "Stuck under the earth", round two.** Three real causes found with the smoke test.
  (1) Parked cars were children of their chunk, so driving one a few blocks away freed it under
  the player, who was left invisible with no collision, falling and being lifted forever. Parked
  cars now spawn under the city root (chunk children are at world coordinates, root children at
  local ones, so `WorldState.to_local()`); the chunk remembers them and frees the ones without
  the `driven` meta when it unloads. Reparenting a driven car was tried first and rejected: a
  VehicleWheel3D re-entering the tree takes its current animated transform as its mounting
  point, and even with the wheels reset the car sometimes sank. `Player` also notices a vanished
  car (`_vehicle_lost()`) and becomes a person again on solid ground. (2) Far (LOD) hill chunks
  had terrain meshes but no collision, so a fast car outran the detailed chunks and dropped
  through a hill onto the flat ground follower, and the old "below -6 m" rule never fired. Hill
  chunks now carry a full-resolution `HeightMapShape3D` at every level on a `TerrainBody` tagged
  with meta `terrain`, and the player and car check every frame whether such terrain is above
  them (a ray straight up); if so they are lifted onto the real surface
  (`CityStreamer.surface_height_at()`, a downward raycast after loading the chunk). World queries
  are skipped for two physics frames after an origin shift because the broadphase lags a frame
  and reported the hills above the pier. (3) Far buildings had no collision either, so a car
  could sit inside a footprint; when the detailed chunk built around it, depenetration shot it
  down through the 2 m ground follower. LOD building boxes now get box collision on a
  `LodBuildings` body and the follower is 40 m thick. Getting out of a car tries the door side,
  the other side, behind, in front and the roof, and takes the first spot where the player
  capsule overlaps nothing.

- **2026-09-19 Fall-through recovery instead of a respawn loop.** The owner got out of a car
  before the chunk under it existed and fell forever (respawn put him back in the same hole).
  `Player` now watches its height: below `fall_through_y` (-6 m) it calls
  `CityStreamer.ensure_loaded_at()` (builds the FULL chunk under that spot right away, replacing
  any LOD placeholder) and stands back up on `ground_height_at()`. A driven car below that height
  is lifted the same way, and `exit_vehicle()` / `respawn()` make sure ground exists before
  placing the player. Streaming also got quicker (update every 0.25 s, 2 full + 8 LOD builds per
  update) so the hole is rare in the first place.
- **2026-09-19 Space jumps the car, handbrake moved to right click.** The owner expected the
  jump key to jump the car. `Vehicle.jump_speed` (9 m/s, `jump_cooldown` 0.6 s) applies an
  upward impulse along the car's up axis when at least one wheel touches the ground.
- **2026-09-19 Minimap restyled as Google-Maps-meets-GTA.** Round (a clipped `MinimapFrame`
  with a `MinimapBorder` ring), bottom right, 260 px, rotates with the camera heading so up is
  the way you look, an N marker rides the rim. Light street-map palette: pale land, white streets
  with grey edges, yellow avenues, green parks, sand and water tints, dark building dots, red
  landmark pins, blue player arrow. `rotate_with_player` and `radius_m` are exports.

- **2026-09-19 Realism step 2: real materials.** Eight CC0 texture sets from ambientCG (1K, Color
  + NormalGL + Roughness only, about 24 MB) live in `assets/textures/` and are credited in
  `docs/ASSETS.md`. `PropFactory.pbr()` builds world-triplanar StandardMaterial3Ds for roads
  (asphalt), sidewalks and plazas (paving), parks and the ground (grass), beach (sand), the port
  (concrete) and runways. The building shader samples a wall set in wall space (brick for brick,
  concrete for flat and panels, metal plates for warehouses and glass spandrels) with normal maps.
  Hills use `shaders/terrain.gdshader`: grass to rock by slope and height, projected from above.
  Texture imports are VRAM-compressed with mipmaps (set in the `.import` files, committed).

- **2026-09-19 Realism step 1: lighting and post.** City environment now has SDFGI (0.4 m cells),
  SSAO, SSR, glow, ACES tonemapping, volumetric fog, slight contrast and saturation, soft sun
  shadows (angular distance 0.6, blur 1.5, blended splits, 320 m) and a subtle far depth of field
  on the player camera. All of it is Forward+ only; the web build ignores what it cannot do.
  Claude cannot see Forward+ output, so these are conservative starting values for the owner to
  judge. Next steps in the plan: PBR textures, real models, characters, weather, performance.
- **2026-09-19 Minimap is drawn from the plan, not rendered.** `scripts/ui/minimap.gd` paints
  blocks by district and zone, roads, landmarks, nearby cars and a heading arrow from `CityPlan`
  data within 320 m, north up, ten times a second. Cheap, crisp, works on the web.

- **2026-09-19 Car physics rebuilt after the owner's first drive** ("drives backwards, can't
  turn"). Measured headless: Godot's `engine_force` pushes toward local +Z, our model's tail, so it
  is negated. The car also pitched onto its rear wheels under power because the center of mass was
  high and the suspension collapsed (travel was larger than the rest length). Now: custom center
  of mass 0.1 m above the axles, springs 60 with rest 0.35 and travel 0.2, max force 50000,
  damping 0.8 / 1.2, tire grip 10.5, roll influence 0.1, angular damp 0.5. The smoke test asserts
  the car drives toward its headlights and turns right on D while staying flat.
- **2026-09-19 Night got moonlight** after "too dark": the same directional light becomes a high
  blue-white moon at 0.55 energy, the sky and fog stay a deep blue instead of black, and ambient
  light is a fixed color (not sky-sampled) so streets stay readable.

- **2026-09-19 The smoke test is a scene, not a script.** Running it with `-s` compiled it before
  autoloads existed, which broke the moment Player referenced `Sfx`. `tests/smoke_test.tscn` runs
  as the main scene so every autoload is ready; it has a 300 s watchdog and the check script has a
  hard timeout, so a broken test fails instead of hanging CI.
- **2026-09-19 Sounds are synthesized**, not files: AudioStreamWAV data generated from noise,
  sweeps and sawtooths at startup. Keeps the no-external-assets rule and works on the web.
- **2026-09-19 Night is a shader global.** `night_factor` (0 day, 1 night) is declared in
  `[shader_globals]` and read by the building shader, so one number lights the whole city.
- **2026-09-19 Pedestrian cap counts only live pedestrians**; ones in chunks queued for deletion
  were blocking new spawns after moving around.

- **2026-09-19 Traffic cars are kinematic and wheel-less until hit.** A VehicleBody3D that is
  frozen (any mode) runs wheel math with zero inverse mass and turns into NaN, which then spreads
  through anything it touches. Traffic cars use plain wheel meshes and get real VehicleWheel3D
  nodes only in `drop_out_of_traffic()`. For the same reason PhysicsBudget never freezes vehicles.
  The headless check now fails on any NaN warning.
- **2026-09-19 Pedestrians do not collide with props or cars**, so cars never get stuck on them;
  a hit is detected by an Area3D and a speed check instead.

- **2026-09-19 Driving keeps the player node alive in the seat.** On enter the player hides,
  drops its collision layers and copies the car's seat position every tick, so the camera rig,
  HUD and re-centering all keep working unchanged. The car reads input directly while it has a
  driver. Exit places the player beside the car with half its velocity.
- **2026-09-19 Cars are physics props.** They join `physics_prop`, count against the PhysicsBudget
  cap and get frozen far away like crates. Cars in unloaded chunks are freed with the chunk; a car
  you drive out of its chunk stays alive because the chunk is loaded around you.

- **2026-09-19 Airport and port are zones, landmarks are points.** Big flat areas (runways,
  container yards, the harbor water) are `MacroMap` rects that every chunk inside builds
  seamlessly; one-off structures (terminal, ship, towers) are `Landmarks` anchored to a point.
  `MacroMap.height_at()` returns 0 inside those rects so they stay flat.
- **2026-09-19 Landmarks reserve lots.** `CityChunk._lots()` drops any lot whose rect touches a
  landmark's footprint square, after consuming the lot's rng values so FULL and LOD stay in step.
- **2026-09-19 Skyline towers reuse the building shader** through `Landmarks._facade_box()`, so
  they get windows and lit floors like everything else; the mirrored drums use a metallic
  StandardMaterial3D instead because the shader assumes box faces.

- **2026-09-19 Landmarks are fixed, not seeded**, and built by `Landmarks` (`scripts/world/landmarks.gd`)
  from primitives. The chunk containing a landmark's anchor builds the detailed version with
  collision; `CityStreamer` builds a cheap far version of every landmark once and hides it while
  the detailed one is loaded, so the sign and the wheel are visible from across the city.
- **2026-09-19 Sign text is "RANDOWOOD" and the pier is "RANDO PIER"**: original, on-brand, and
  clearly not the trademarked real ones. Letters are a 5 x 7 block font, 6 m per cell, on legs
  down to the slope; you can climb them.
- **2026-09-19 Spawn override takes a look direction** (`?spawn=x,z,yaw,pitch`) so screenshots
  can be aimed. Fog density halved to 0.0006 so the hills read as green, not white.

- **2026-09-19 The map is a function, not data.** `MacroMap` answers coast x, land height, zone and
  district for any world position from a few numbers plus FastNoiseLite, so the endless plan still
  works and chunks stay independent. Roads simply stop at the ocean and at the hills.
- **2026-09-19 Water is solid.** The ocean is a static slab 0.6 m below sea level, so you can run
  and boost across it. Silly, and it avoids swimming code for now.
- **2026-09-19 Terrain tiles are per chunk** (14 x 14 quads at full detail, 6 x 6 for LOD) with a
  HeightMapShape3D scaled to the chunk. Seams with flat city chunks are accepted; the height
  function is 0 everywhere the city is, so they are small.

- **2026-09-19 Chunk = block + its +X road + its +Z road + the corner intersection.** Every road
  segment and intersection is owned by exactly one chunk, so there is no double drawing and no gap
  once neighbours are loaded.
- **2026-09-19 Re-centering shifts every 3D child of the scene root** (chunks, player, rockets,
  debris) by the player's XZ offset when the player passes `recenter_distance`. Chunks are placed at
  `-WorldState.world_offset` so chunk-internal coordinates stay true world coordinates. Anything
  that needs the true position asks `WorldState.to_world()`.
- **2026-09-19 Destruction is recorded by chunk key and prop id**, where the id is the prop kind
  plus its generation order in the chunk (deterministic). On rebuild a destroyed id is skipped.
  Moved-but-not-destroyed props (trash cans) are not persisted; they respawn in place.
- **2026-09-19 LOD chunks use `Building.plan_only()`**, which runs the same seeded picks and layout
  as `generate()` without creating nodes, so far boxes match the buildings that appear up close.
- **2026-09-19 Headless gotcha:** `root.add_child()` from a SceneTree script's `_initialize()` is
  deferred to the next frame. Await a frame before touching the scene.

- **2026-09-19 City plan is data, city builder is nodes.** `CityPlan` is a RefCounted with roads,
  blocks and intersections; `CityBuilder` builds nodes from it. Milestone 5 will build and free
  blocks from the same plan as the player moves, and a themed macro map (the LA request) can drive
  `district_at()` instead of the distance rule.
- **2026-09-19 Districts are parameter ranges** in `CityPlan.DISTRICTS`: height, lot size, gap,
  allowed shapes and finishes, lit ratio, park/plaza chance, tree density, courtyard chance.
  Downtown is r < 0.32 of the city radius, midtown r < 0.68, suburbs beyond; one seeded quadrant
  beyond r > 0.5 is industrial.
- **2026-09-19 Small repeated props are MultiMeshes** (lamps, trees, dashes, stripes, signs) with
  box colliders on one shared StaticBody3D. Trees have no collision yet. Trash cans are RigidBody3D
  props under the PhysicsBudget cap (raised to 500).
- **2026-09-19 The center intersection is always signals, never a roundabout**, because the player
  spawns there.
- **2026-09-19 The smoke test script compiles before autoloads exist**, so it must not name a
  class that references `PhysicsBudget` at class level (use untyped vars for those). The check
  script now fails on any "SCRIPT ERROR" in the output so a crashed test cannot pass.

- **2026-09-19 One ShaderMaterial per building part.** The web build uses the Compatibility
  renderer, which has no per-instance shader uniforms, so each box part gets its own material with
  its exact size, window pitch and floor height baked in. Fine for a block; when the city gets big
  (milestone 5) far buildings should move to MultiMesh with INSTANCE_CUSTOM data.
- **2026-09-19 Floors count from world Y, columns from local axes.** Ground is flat, so world Y
  keeps floors aligned across parts and rotated buildings still get straight window columns.
- **2026-09-19 Window grid is fitted, never cut.** The Building script rounds the box size to a
  whole number of columns and floors and passes the exact pitch to the shader, so no window is ever
  sliced by an edge.

- **2026-09-19 Rifle is an AK-47.** Owner's request. Low-poly silhouette built from primitives
  (wood furniture, curved magazine). Named "AK-47" in the HUD; it is a real-world rifle, not another
  game's character or brand.
- **2026-09-19 Boost replaces sprint.** Owner asked for a Rocket League style unlimited boost. Shift
  and gamepad B. Ground: thrust along the move direction up to `boost_max_speed`. Air: thrust along
  the camera pitch with `boost_gravity_scale` gravity, so you can fly. Letting go on the ground bleeds
  speed off gently (`boost_bleed_off`) instead of braking.
- **2026-09-19 Weapons are built in code, no weapon scenes.** Each weapon's model is a few boxes and
  cylinders in `_build_model()`. Adding a weapon = one script, then append it in `WeaponManager`.
- **2026-09-19 Aim ray starts at the head pivot**, not the camera, so a wall behind the camera can
  never eat a shot. Shots and tracers still originate at the muzzle.
- **2026-09-19 The body faces the camera for 1.5 s after firing or while holding something**, and
  faces the move direction otherwise. The gun tilts with the camera pitch.
- **2026-09-19 AK impact force is 12** (one bullet adds 6 m/s to a 2 kg crate). The first value, 30,
  sent a crate 26 m in one burst, which was too much even for this game.

- **2026-09-19 Godot 4.7.2.** Latest stable at project start. `config/features` pins 4.7 and
  Forward Plus.
- **2026-09-19 Jump feel is defined by height and time-to-apex, not raw gravity.** `jump_height`
  and `jump_time_to_apex` derive gravity and jump velocity; `fall_gravity_multiplier` makes the
  fall faster than the rise so big jumps do not float. Defaults: 12 m in 0.65 s up, 1.6x on the way
  down. Double jump is 9 m. Releasing jump early cuts the rise (variable height).
- **2026-09-19 Camera.** Spring arm on a pivot 1.6 m up, 6.5 m long, collides with `world` only so
  crates never shove the camera. The camera rig is a child of the player body; the body itself never
  rotates, only the `Visual` node turns to face the move direction.
- **2026-09-19 Physics at 60 Hz, no physics interpolation yet.** Simplest option. If motion looks
  juddery on a 120 Hz ProMotion display, enable `physics/common/physics_interpolation` and move the
  camera update to physics ticks.
- **2026-09-19 The test level is generated in code from a seed** even though it is a greybox, so
  the "no hand-placed content" rule holds from day one and lighting/environment stay in the `.tscn`.
- **2026-09-19 Character pushes rigid bodies manually** via impulses in `_push_props` (Godot does
  not push rigid bodies from a CharacterBody3D by default). Bodies under the player are not pushed.
- **2026-09-19 Distance sleeping freezes far props in place.** A prop frozen mid-air stays there
  until the player gets close again. Accepted for now; chunk streaming (milestone 5) will replace it.
- **2026-09-19 Extra folders beyond the brief:** `scripts/ui/` for HUD scripts and `tests/` for the
  headless smoke test and check script.
- **2026-09-19 CI runs the headless check** on every push via GitHub Actions, so a push that
  fails to load is visible before playtesting.
- **2026-09-19 Mac builds come from GitHub Actions.** The owner does not want to use Terminal, so
  every push to `main` exports a universal macOS app and publishes it as a GitHub Release
  (`releases/latest`). Ad-hoc signed only; notarization would need a paid Apple developer account,
  so first launch needs "Open Anyway" in Privacy & Security.
- **2026-09-19 Web build now, not later.** The owner wants to test in a browser, so the workflow
  also exports a web build (single-threaded so it runs on GitHub Pages without cross-origin
  isolation headers) and deploys it to GitHub Pages once the repo is public. Forward+ stays the
  desktop renderer; web falls back to Compatibility automatically.
- **2026-09-19 Exposure tuned down** after the first browser screenshot: sun energy 1.0, sky
  ambient 0.45, darker ground checker. The original values washed the ground out to white.
- **2026-09-19 Push to main always.** The owner asked for all work to go directly to `main` with no
  branches or pull requests. Milestone 1 was the only PR (#1); everything after lands on `main`.
