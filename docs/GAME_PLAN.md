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

## Road to GTA-level graphics (owner, 2026-09-23)

The owner asked what it will take to reach GTA-level graphics, "exactly step by step", with no
limit on time or tokens. This is the plan every session works from. The honest framing: the
gap is mostly CONTENT, not rendering tech - AgX, SSIL, SDFGI, volumetric fog and TAA are
roughly where GTA V's PC renderer was. The target is **GTA V (PS5 version) at a glance** in a
showcase slice (downtown, the beach, the hills); GTA VI level (ray tracing, strand hair,
film faces) is past Godot 4 today, and would mean Unreal 5, which breaks the phone-only
text-file workflow. About a year of steady work for the slice; the whole map takes longer.

**2026-09-24, owner: "It must be the same quality as Red Dead Redemption 2."** RDR2 raises the
bar past GTA V mainly in three places, so they move up the list: people and animation (G5 -
mocap-grade movement, faces, fingers, weapon handling; the hero now holds guns by IK and a
Blender-built hero is being prototyped), lighting and weather (G4 - volumetric clouds, fog and
rain that light and shadow the world), and hand-authored density (G2/G3). The honest limit is
unchanged: RDR2 is eight years of a studio of thousands; the aim is that a showcase slice holds
up next to it in screenshots and in motion, one weakest-thing-first fix at a time.

What only the owner can supply, and why each one multiplies everything below:
- **A real GPU in the loop.** Claude sees one lavapipe frame every 6-10 minutes and never a real
  frame rate. A self-hosted GitHub Actions runner on the owner's Mac (one-time setup) would
  render Metal screenshots and an FPS benchmark on every push.
- **An asset budget.** Two or three professional city kits licensed for any engine skip months
  of generating buildings and props from nothing; CC0 alone cannot fill a GTA-dense city.
- **Playtesting.** Every build or two: what reads as fake.

- [ ] **G1. Feedback loop and targets (1-2 weeks).** Mac runner; ten fixed reference cameras
  (street noon, night, sunset, aerial, beach, hills) matched to GTA V compositions; every push
  measured against them (luminance spread, saturation, FPS), not judged by eye.
- [ ] **G2. Buildings (2-4 months; the biggest gap).** Real facade geometry instead of shaded
  boxes (window recesses are done per pixel, 2026-09-24: `window_recess`; still to do as real
  geometry near the camera): frames, sills, ledges, cornices, balconies, storefronts with glass
  and interiors, awnings, fire escapes, roof clutter. About eight LA styles (stucco apartments,
  art deco, glass towers, strip malls, bungalows, warehouses...) as kits from Blender scripts,
  like the car generators, assembled from the seed. Then grime, streaks and edge wear, and a
  LOD chain down to impostors.
- [ ] **G3. Streets and ground (1-2 months).** Curbs, gutters, cracked and patched asphalt,
  puddles, decals, tyre marks, dense street clutter, alleys, car parks, better trees and weeds.
- [ ] **G4. Lighting art direction (1-2 months, alongside).** Reflection probes per block, wet
  roads, volumetric clouds, neon and storefronts that light the street, headlights that cast
  light, and a grade tuned per hour against the G1 references.
- [ ] **G5. People (2-4 months).** Properly rigged humans with finger and face bones, a real
  animation library (about fifty clips: idles, turns, phone, talking, waiting to cross), foot
  placement on uneven ground, skin, hair and cloth shaders. The weakest area today.
- [ ] **G6. Cars (1-2 months).** Interiors, real glass, damage, lights; extend tools/make_*.
- [ ] **G7. Performance, throughout.** Generated occluders, far-building impostors, texture
  streaming, profiled on the owner's Mac every push: the look at 60 fps, not 15.
- [ ] **G8. Polish, ongoing.** Side-by-sides against the references; fix what reads fake first.

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

- **90s cinematic colour grade** (asked 2026-09-21, deferred by the owner the same minute:
  "we can explore that later tho"): the whole game graded like 90s cinema, Tarantino
  specifically - Pulp Fiction, Reservoir Dogs. Not a period setting, a *look*. What that
  actually means, so a later session does not just crank saturation: those films are shot on
  50 ASA Kodak stock with warm key light and let the blacks go genuinely black and slightly
  warm rather than crushed-blue; skin stays ruddy, whites go a touch cream, and the saturation
  lives in a few loud objects (a red car, a yellow sign) against desaturated surroundings, not
  everywhere at once. There is visible halation around highlights and a fine grain.
  The implementation is a post ColorCorrection pass, not per-material edits: a 3D LUT on the
  city Environment (`adjustment_color_correction`, a Texture3D built in code so it needs no
  editor step), plus tone curve, a slight highlight bloom already present in glow, and a grain
  term. It must be one global switch so the owner can turn it off, and it must degrade on the
  Compatibility web build (Environment adjustments do work there).

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

- **2026-09-24 GTA-style aim (owner: "GTA style aiming that auto locks onto targets").** Hold
  right mouse / left trigger with the rifle or rocket launcher: over-the-shoulder camera, lock on
  the person (or traffic car) nearest the crosshair with line of sight, camera tracks it, flick
  to switch, shots go at the lock (rockets lead it), next target taken after a kill. The gravity
  gun keeps right click for its throw.

- **2026-09-23 Rainy nights are dark and warm; sand at its real scale.** An overcast night over a
  city is its own sodium light on the cloud base: the rain night used the daytime storm grey and
  a moonlit grey fog veil and read as dusk (sky 133/134/136, now 129/118/110 with the frame's
  median 74). Far streets' lamp pools sit at the kerbs, staggered. The beach sand is tiled at 2 m
  - its scan is trodden sand, and at 5 m the footprints were half a metre and read as ripples.

- **2026-09-23 The far city has ground, and lit streets at night.** The far chunks' merged
  ground lost its colour in `SurfaceTool.append_from()`, so every street, pavement and lawn past
  the near blocks was black in every aerial ever rendered. It now carries a linear vertex
  colour, and its carriageways glow with sodium light after dark (the near chunks' roads do the
  same past 90-200 m, where their real lamps stop reading), so a night flight is an orange grid.

- **2026-09-23 Reflections see the street, not more sky; glass reflections are emitted.** White,
  silver - and dark red and navy - cars all read as pale-blue ice in Forward+ because the sky's
  lower hemisphere was pale haze for 27 degrees, and that is what a car door mirrors. The cubemap
  pass now puts a warm street grey under the horizon (the visible sky is untouched). Glass
  towers in shade were black because their reflection was mixed into the albedo and lit like
  paint; most of it is now emission that follows the sky's brightness. Crosswalk wear is
  speckled instead of smudged. Parking order is seeded, so the same seed parks the same cars.

- **2026-09-23 A 48-minute day (owner: "the day/night cycle is too fast it should be
  slower").** `DayNight.day_length_seconds` 480 -> 2880: two real seconds per game minute, the
  pace the big open-world games use, so a sunset lasts minutes instead of seconds.

- **2026-09-23 The GPU side: shadows from lighter twins (owner: "playable ... without taking away
  from graphics at all").** Per-pass GPU profile (`tools/gpu_profile.gd`) showed the frame is
  triangle-bound - opaque, depth pre-pass and sun shadows ~90 % - not effect-bound; per-category
  measurement (`tools/tri_split.gd`) showed the planting's shadows were the largest single cost.
  Foliage, imported props and car bodies now cast their shadows from coarse twins, palms got LODs
  and lettering stopped casting: 9.4 M -> 7.7 M triangles on a downtown street with matching
  before/after renders. Quality's lower levels also loosen the LOD error threshold
  (`Quality.lod_threshold`, 1.5 / 2.5 / 4 px) before they drop effects; HIGH keeps 1 px.

- **2026-09-23 Rainy nights and fire (store stills).** Streets start as wet as the weather,
  soaked roads are near-mirrors with puddles, the lens rain is a few drops at the edges instead
  of 1,800 over the frame; the fireball drops fast from white-hot to deep orange (AgX washes
  anything bright to beige), smoke draws behind the fire, puffs vary in age and heat.

- **2026-09-23 Explosions had lost their fireball.** Found while framing store stills (owner:
  "the sickest screenshots ... gameplay stills in steam"). The heat shimmer is a sphere that
  reads the screen, and Godot copies the screen before drawing transparent things; sorted in
  front of the fireball it sat in, it painted the street as it looked before the fire over the
  fire and the smoke. Before: a small brown smoke puff; after: a rolling orange fireball.
  Fixed with the shimmer material's `render_priority` at minimum, so it bends what is behind
  the blast and the fire draws on top.

- **2026-09-23 Playable without losing anything (owner: "I need the game to be playable and not
  slow without taking away from graphics or quality at all").** The frame was CPU-bound in the
  physics step, not the GPU: headless, the simulation needed 2.3-2.9 s of wall time per game
  second on this (slow, shared) test machine, so every frame ran Godot's cap of eight catch-up
  physics steps - the spiral that makes a game feel like it is wading. Three causes, fixed without
  touching anything you can see: (1) useless collision pairs. GodotPhysics pairs two objects
  when EITHER mask has the other's layer, and a moving body is re-paired against everything its
  bounds cross; static bodies had mask 7, detector areas were monitorable, and far pedestrians
  and traffic cars carried masks they never use. Pairs 3,600 -> 1,200-1,500. (2) Far crowd:
  past 35 m a pedestrian walks the pavement by position on the chunk's own ground height, at a
  stride of 2/4/8 steps with distance, with no collision solve and no hit zone. (3) Parked cars
  past 100 m stop their per-step script (the body is untouched), traffic cars are placed in one
  transform write and read ground height from the road lattice instead of the mountain noise.
  Result, two rounds each against the previous commit: standing 2287/2445 -> 1524/1658 ms per
  game second, flying 2874/2847 -> 1808/1570, worst frame while flying 1230/1344 -> 604/611 ms.
  Also: occlusion culling (one occluder per chunk from its building boxes, inset so it never
  sticks out; on/off shots identical except for moving traffic and people), and streaming in
  slices - a chunk is now a list of build steps run inside `build_budget_ms` a frame and swapped
  in when complete, where it used to be ~100 ms built inside a single frame.
  Second pass the same day, from a perf profile of a symbol-carrying release build: 16 % of all
  CPU was parked cars' suspension rays. Godot Physics cannot sleep a VehicleBody3D (its state
  callback's `apply_impulse` wakes it right after the step sleeps it, while `sleeping` reads
  true), so every parked car was simulated every step. `Vehicle.settle()` from PhysicsBudget's
  physics tick fixes it: 290 of 293 parked cars truly asleep, from about none. Two real bugs
  under it: empty cars held a brake of 2.0 and rolled down every slope (91 rolling after a
  minute), and the kerb traffic lane ran 13 cm from the parked cars because the parking lane was
  4.4 m wide, so traffic plowed through them and flung them; now a 2.6 m bay
  (`CityPlan.PARKING_LANE`) and lanes laid out in what is left. Standing 1552/1668 -> 1210/1245
  ms per game second, flying 1791/1635 -> 1361/1342: about half of this morning's figures.
  Third pass: the cars still woke in the release build, all 293 at once - the ground follower's
  collision box was re-placed eight times a second, and moving a static body wakes everything
  touching it. Split into a sliding drawn plane and a still collision box. Then the hitches:
  a block's parked cars were one build step (up to 590 ms) and the traffic upkeep built up to 34
  cars in one tick; now one car per step, at most one traffic build per frame, and a pool of
  retired traffic cars. Standing 1214/1256 -> 1003/1010 (real time on this machine, worst frame
  530-591 -> 66-69 ms), flying 1488/1476 -> 1057/1030 (worst frame 659-770 -> 355-370 ms).

- **2026-09-23 Why the game was slow (owner: "why is the game so slow").** Measured rather than
  guessed. (1) Resolution: the window opens maximised and Godot draws every physical Retina
  pixel - 7.7 million on a 16-inch MacBook, through SDFGI, SSR, SSIL and volumetric fog - and
  `Quality` left HIGH and MEDIUM at native. Now each level has a pixel budget (2.6 MP at HIGH)
  and FSR 2.2 scales up to the window. (2) The crowd: on a downtown street 650 pedestrians were
  6.4 of 15.7 million triangles and 891 draws a frame - the 16k-triangle rigs of 2026-09-22,
  drawn again into every shadow cascade. Shadows now only inside 45 m and coarser LODs with
  distance: 2.4 million and 343 draws. (3) Shadow reach at HIGH 700 -> 500 m: 700 -> 450 had
  measured 800 draws and a million triangles. Still heavy and next: about 5,000 draws a frame,
  mostly buildings built from many separate parts. GPU time itself cannot be measured here
  (lavapipe); the owner's F1 stats line, or a Mac runner (G1), is what would.
  Second pass the same day: the Poly Haven street props were film assets - a lamp 30,610
  triangles, a hydrant 43,158, a concrete barrier 60,928 - and a MultiMesh batch draws all its
  instances at the LOD of its nearest point. `PropFactory.TRI_BUDGET` now makes a generated LOD
  the base mesh when a prop is over budget (lamp 3.8k, hydrant 10.8k, barrier 3.8k; checked
  close up against the originals): the lamps across the streamed blocks went from 11.0 to 1.4
  million triangles. Cars got the pedestrians' treatment (`Vehicle.body_shadow_distance` 70 m,
  `BODY_LOD_BIAS`): 3.6 -> 1.7 million triangles on the street. Trees (about 47k each, with
  leaf cards that a simplifier would collapse) are the largest thing left.

- **2026-09-23 A warmer grade, measured in Forward+ (owner: "fix the grade").** Six gameplay
  frames measured before touching anything: contrast was fine on the street at noon (p5/p50/p95
  29/128/190) but the colour was nearly grey (median saturation 20 of 255), the aerial and
  beach frames carried a blue cast (mean B 14 over R), and at night the lit bays were a flat
  220 - solid glowing panels. A first pass that only moved the fog colour and density changed
  almost nothing measurable, which is the lesson: on a street frame the haze is a small term.
  What moved it was the light and the curve: `day_sun_color` (1.0, 0.94, 0.82), a warmer look
  LUT through the mids with a slightly cool toe (luminance held per stop so exposure does not
  shift), `adjustment_saturation` 1.32, `day_haze` 0.16. Street saturation 20 -> 33 at the
  same spread. The day fog is a warm grey now rather than blue, clear-weather depth fog 0.0001,
  aerial perspective 0.22. Lit windows 1.2 -> 0.8 (and the LOD term 2.9 -> 1.9, in step):
  night p95 219 -> 209, p5 35 -> 26. Stars follow `moonlight` squared, not `night_factor`,
  which had a full star field over a lit dusk sky at 18:24.

- **2026-09-23 Far hill trees floated above every ridge.** Seen in the first Forward+ gameplay
  shots: a swarm of dark dots over each mountain skyline, like birds. Skyline placed its
  planting at `MacroMap.height_at()`, but past the streamed chunks the visible ground is the
  ground follower - a 62 m bake plus synthesized crags - which on a ridge runs tens of metres
  below the real height. Fixed by moving the plane's height code into
  `shaders/macro_relief.gdshaderinc` and giving the planting its own MultiMesh on
  `shaders/far_canopy.gdshader`, which seats each clump on that exact surface, following the
  plane's own triangles (seating on the smooth function alone still left a few clumps standing
  clear of ridges, because the drawn ridge is a 70 m chord). One more draw per hill tile. The
  same look turned up an off-by-one in the ground snap: PlaneMesh's 200 subdivisions are 201
  quads, so the 70 m snap slid the mountain vertices 35 cm a step. A second pass, hiding node
  groups one at a time in `city_shot.gd`, found the same fault in the far hill houses and in the
  far SHALLUFERWOOD sign, which hung in the sky beside the peak from the beach; both are seated
  by the same shader now (the sign in one piece, so it stays level).

- **2026-09-22 The first arm rebuild was measured and was still wrong in three ways (owner:
  "why are their arms weird?").** Sampling the rebuilt pose bone by bone: the clips hold the
  collarbones 8-20 degrees below level (slumped, squared shoulders); the arms rode the chest's
  seven-degree forward lean, so the swing ran -25 to +5 and they trailed behind the body; and
  the forearm carried the upper arm's spread, leaving the hands a hand's width off the thighs.
  Now the collarbone keys are turned until their average is the rig's own (level) rest, the
  arms take only the chest's turn, and the forearm comes back in by `ARM_GAIT`'s last value.
  The palm turn was A/B'd at 60, 85, 120 and 150 degrees: more than 60 turns the palms to
  face forward, which is the open-fan hand that was showing.

- **2026-09-22 New people, and arms rebuilt from the rig instead of guessed (owner: "the
  characters look stupid, their arms are floppy", then "we need entirely new assets for the
  humans").** Meshy is un-retired for characters only - there is no CC0 source of realistic
  rigged humans (Poly Haven has none, Quaternius' are stylised). Nine new rigs, d to l, at
  `--polycount 16000` (the first three were 8000 and looked it); a, b and c are no longer
  loaded. The player's body is now pedestrian_d.
  The arms were the real problem and new models alone would not have fixed them: the clips
  assume a straight-armed rest pose, each rig is bound in the pose its mesh came out in, and
  the new ones came out in a palms-up shrug, so with the old fixed shoulder correction they
  walked with their hands up by their ears. `Pedestrian.fix_arm_pose()` now rebuilds the arm
  keys from each rig's own rest pose (hang, spread, swing opposite the same-side thigh, forward
  elbow bend, palms to the thighs, in the chest's frame) and needs no per-model numbers; it
  is right on all eleven rigs (a, c and d to l), walk, run and idle, front and side.
  **Generator trap:** `tools/meshy.py` sent a generic texture prompt with no subject in it, and
  the refine pass paints from the texture prompt alone - so a "Black man in a grey hoodie" and a
  "worker in an orange hi-vis vest" came back pale and in grey. The tool now carries the subject
  into the texture prompt when `--texture-prompt` is not given; j, k and l were made after the
  fix and came back as asked. With nine real models the outfit recolour now leaves half the
  crowd in its own clothes and the skin tints are within a few percent (they used to go to
  0.56, which turns a pale face grey rather than making anyone darker).

- **2026-09-21 The frame had no contrast, and it was not the fog.** Every wide shot read as
  pastel. The instinct was to blame the haze; measuring the frame said otherwise. A midday
  downtown aerial through the real Forward+ pipeline had a luminance p5/p50/p95 of 78/103/137 -
  **the whole city inside 59 of the 255 available levels** - while the same scene through the
  opengl3 path measured 51 to 185. The difference is the tonemapper. **AgX rolls an enormous
  range into the screen and, unlike ACES, expects a "look" - a contrast curve - to be applied
  after it.** There was none, so every frame came out as the flat middle of the AgX ramp.
  The fix is a look LUT: a `Gradient` / `GradientTexture1D` pair in `city.tscn` wired to
  `Environment.adjustment_color_correction`, which Godot runs each channel through separately
  after tonemapping - so it is a per-channel curve, not a tint. An S with a slope of about 1.6
  about a 0.45 pivot, cool in the toe and warm in the shoulder. `adjustment_contrast` went back
  to 1.0: stacking a second curve on the LUT crushes the toe.
  Four things went with it. `tonemap_exposure` is now driven by `DayNight` (1.25 by day, 2.1 at
  night) so the punchier curve does not turn a lamplit street into mud - note the player camera
  *also* runs auto exposure underneath that, which is why a night value that looks right at
  21:00 is a stop hot at 18:30. The key light was made to out-run the fill (sun 1.0 -> 1.3,
  ambient 0.55 -> 0.30, SSIL 1.0 -> 0.5): a real midday shadow is a fifth as bright as the lit
  side, not two thirds. Shadows reach 700 m on HIGH instead of 320, so the far half of an aerial
  has contrast available at all. And the haze was pulled back into the distance rather than
  sitting over everything.
  Same frame afterwards: 87/123/175. **Measure the frame; do not squint at it.**
  `python3 -c "from PIL import Image; import numpy as np; g=np.asarray(Image.open('shot.png').convert('L')).astype(float); print([round(float(np.percentile(g,p))) for p in (1,5,50,95,99)])"`

- **2026-09-21 Twilight is not midnight.** `night_factor` reaches 1.0 the moment the sun is three
  degrees under the horizon. That is right for switching the street lamps and the lit windows on
  and wrong for the light itself: at 18:30 the sky is still bright and still warm, but the sun's
  colour, the ambient and the new exposure were all driven straight off it, so the city was lit
  by a blue moon under a pink sky. `DayNight._apply()` now computes a second, slower ramp
  (`moonlight`, smoothstep 0.02 -> -0.34 on sun elevation) for the light, and keeps
  `night_factor` for the lamps, the windows and the shader global.

- **2026-09-21 Downtown was pixel art, and one line did it.** Every tower rendered as a random
  checkerboard of gold and black rectangles, one per window bay, with no glass in it - no
  highlight, no sky in the panes, no mullion. All the machinery was already there (interior
  mapping into a virtual room, a Schlick fresnel sky reflection, spandrel panels). Four things
  were burying it, found by a three-agent diagnostic fleet:
  `float on = 0.12 + 0.88 * night_factor` in the `lit` branch gave every window the lit roll
  picked a warm emission at ten in the morning, and `lit_ratio` runs to half the bays - **that is
  the checkerboard**, half of every facade glowing gold in full sun, painted over the interior
  and the reflection. The inset shadow that sets a pane back into the wall was measured against
  `max(du - 0.2, dv - 0.18)` whatever the style, and those two numbers are exactly `win_h - 0.07`
  for the punched window and for nothing else, so a curtain wall got 86 % of the pane darkened by
  45 %. Curtain-wall `frame_color` was 0.14, darker than the panes it frames, so the grid a glass
  tower is made of was drawn and then invisible. And window pitch took exactly four values, with
  two thirds of downtown sharing 1.8 m.

- **2026-09-21 Everyone in the city was wearing black, and it took two goes.** The first attempt
  widened the wardrobe ranges and kept the mechanism; the mechanism was the bug. `cloth_value`
  multiplied the SOURCE texture's own brightness, and `pedestrian_a`'s garments measure 0.21-0.32
  with its trousers lower still - **there is no multiple of near-black that is a white shirt.**
  `cloth_value` / `pants_value` are the garment's own brightness now, 0 to 1, with the source's
  value kept as *shading* around it. `CLOTH_VALUE_BAND` also moved to 0.030..0.075, because the
  rigs' trousers at about 0.10 sat halfway up the old band and so took barely half the recolour -
  colour above the waist, black below it. Both were found by reading a number out of the ASSET
  rather than out of the source.

- **2026-09-21 Numbers that live in two files.** An audit fanned out over the repo for pairs of
  constants that have to agree across a file boundary with nothing in code connecting them - the
  class of bug where nothing errors and the picture is just wrong. Fifteen survived an adversarial
  second pass. The worst: `shaders/ocean.gdshader` carries a hand-transcribed, sRGB-decoded copy
  of `MacroMap`'s sea palette, because past `handover_start` the water chunks stop drawing their
  own sea and re-draw the far plane's; re-tune the bake alone and a hard-edged rectangle of
  differently coloured water follows the player around the bay. Three were removed by making the
  number a field (`coast_wobble`, `coast_period`, `peninsula_bulge`, all pushed to the shader by
  `Weather`); six are guarded in `tests/smoke_test.gd`, which reads the second copy out of the
  other file's source (`Shader.code`, `GDScript.get_script_constant_map()`) rather than writing
  the number a third time. Every guard was proved by breaking the value and watching the right
  one fail. **When you add a number another file has to know, make it a field and push it, or add
  the guard in the same commit.**

- **2026-09-21 The colour and foliage pass (owner: "we need this city to have more color and be
  more gta", "PS5 level foliage and trees", "go and scour the internet for the absolute best
  assets").** Poly Haven turned out to have 521 CC0 models including 20 trees, 57 plants, 9
  flowers and 4 grasses, so twenty-eight of them were fetched, decimated and packed in parallel
  (`tools/fetch_polyhaven.py` is new; the pipeline is fetch -> `decimate_tree.py` ->
  `pack_gltf.py` -> `shrink_glb.py` -> Godot `--import` -> `fix_texture_imports.py`).
  City trees went from three to five, the hills got four of their own, and four bushes, five
  tropical plants, seven flowering ground covers and two grass clumps now fill the knee height
  that used to be bare lawn.
  Three things are worth remembering from it.
  (1) *The jacaranda is green.* It is the iconic Los Angeles street tree and the single biggest
  colour win available, but Poly Haven's scan is photographed out of bloom. It blooms in the
  shader instead: each leaf is taken to its own luminance and recoloured, per leaf card. It took
  three passes - electric ultramarine, then navy, then right - because multiplying green by
  violet gives mud, and scaling by leaf luminance alone drags every shaded leaf to black-blue.
  (2) *Weighting, not avoidance.* The wall palette had been pulled back to neutrals after an
  earlier attempt "came out looking like a colour picker". Going all-neutral is the other
  failure. Neutrals are now repeated three or four times each in `FLAT_COLORS` and each painted
  stucco once, which gives a street that is mostly stone with a mint or peach block every so
  often. Same idea for planting: one flowering species dominates a patch.
  (3) *A real bug, found by adding a fourth tree.* The per-block dominant species was picked by
  indexing `tree_weights[0]`, `[1]`, `[2]` by hand. Any fourth entry would have been placed only
  by the 30% fallback roll - no error, no warning, just a tree that almost never appeared.

- **2026-09-21 Real sound.** The game's audio was 100% synthesized at runtime and sounded it.
  Thirty-two CC0 clips (OpenGameArt and Kenney, every licence checked individually, all CC0 so no
  attribution obligation falls on the owner) now cover shots, explosions, rockets, breaking,
  glass, crashes, landings, footsteps, horn, engine and boost loops, rain, wind, city ambience and
  thunder. `Sfx` keeps its exact public API and keeps the synthesis as a fallback, so a missing
  file degrades to a tone rather than to silence. Each name holds several takes and `play()` picks
  one, which is what stops the rifle sounding like one file on repeat. Loop flags are set on the
  stream in code rather than in the `.import`, because a regenerated `.import` can silently drop
  the flag.

- **2026-09-21 Global illumination was switched off.** `Quality.start_level` was MEDIUM, which
  disables SDFGI, volumetric fog and depth of field - the single biggest difference between this
  and a modern-looking game, simply not running. It starts at HIGH now and the adaptive stepper
  still falls back on a machine that cannot hold it. That exposed a flaw in the stepper worth
  keeping fixed: the measurement window is thrown away across an origin re-centering, because the
  streamer moving every node in the scene by a kilometre is a one-off hitch at any quality level
  and counting it permanently demoted a machine that was running fine.

- **2026-09-21 Three bugs the screenshots and the new checks caught.** Worth recording because
  each one looked like something it was not.
  (1) *A grey wall round the valley.* The horizon plane's lift faded in with distance, which is
  correct only while the ground the player stands on is at sea level; over a city 130 m up the
  plane stayed at zero and cut across the hillsides. The lift now applies everywhere and it is
  the crag detail that fades in, which is what actually needed keeping off the streamed chunks.
  (2) *A wall along every city/hills seam.* The city's rolling relief faded out over the first
  2.5 m of mountain, and at the foot of a range the height climbs 0 to 3 m in twenty metres of
  ground, so it switched off in one step and left four to six metres of cliff. The fade runs
  over 60 m of mountain now. That put relief on the lower slopes, so `height_at()` adds relief
  and *then* carves the hill roads (the other order lifts every road off its own bed), and
  `HillRoads` profiles against the surface including relief.
  (3) *A freeway with no lane markings.* Not z-fighting and not a missing mesh:
  `CityChunk._ribbon()`'s plain vertex order makes a horizontal quad face DOWN, so every lane
  line and barrier cap was built back-facing and culled. The deck top happened to use the
  opposite order, which is why it drew and nothing lying on it did. Flat things on the deck pass
  `flip = true` now.
  Also in this batch: the baked horizon map's mountain bands were retimed to match what
  `terrain.gdshader` does on the streamed chunks (dry gold over most of the height, rock only on
  the high back range), because the two disagreed and put a tide-line across every range.

- **2026-09-21 Traffic on the freeways.** Empty decks read as scenery rather than road.
  `TrafficManager` drives them the way it drives the airport drop-off loops, with the three
  differences the routes force: they are open polylines, so a car carries a signed direction and
  is recycled at the ends instead of wrapping; they have a height profile, so cars ride the deck;
  and there are two carriageways, so cars are grouped by route, direction and lane and follow
  only the car actually in front of them. All of it is driven by distance along the route rather
  than point index - the points are a fixed step along the *drawn* curve, which is not a fixed
  step along the ground once the curve bends - so `Freeway` gained a cumulative-length table
  behind `point_at()`, `length_of()` and `nearest_on()`. Cars only exist within `freeway_range`
  of the player, so a three-kilometre deck costs what a short one does.

- **2026-09-21 Mountains around the basin and a valley at altitude (owner: "don't forget that LA
  is covered by mountains in Palos Verdes, the valley").** The map had one low hill range north of
  the city and flat nothing everywhere else, so the basin had no edges. `MacroMap.raw_height_at()`
  was rewritten to be *mountains only*: a front range north of the city that fades out on its
  inland side so it reads as a wall from the city and a slope from behind, a higher back range
  beyond the valley, an east range, and the peninsula headland, composed with `max()` rather than
  added - adding ranges gives one smooth dome, `max()` gives ridges where they meet. Two noise
  octaves on top for crags.
  Two things only showed up once the smoke checks went in. The front range's fade-out window and
  the valley's fade-in window are the same window, so the valley floor is *past* `valley_to_z` -
  inside the window you are on the range's own flank, which is why the first check read 300 m of
  mountain where it expected a valley. And with a 560 m ridge in the way the valley was
  unreachable on the ground, so `pass_center_x` / `pass_width` / `pass_floor` notch a canyon pass
  through the front range: about 55 m in the pass against 400 m on the flank a kilometre away.
  The inland valley then had to be a *city floor at altitude*, which height alone cannot express:
  if the valley is high, `zone_at()` calls it mountain and no blocks build; if it is low, it is
  not a valley. Split in two: `plateau_at()` is the valley floor elevation and `_relief_at()`
  starts from it, so `CityChunk._gy()` lifts the whole city - ground, buildings, props, shapes -
  onto the plateau, while `zone_at()` still reads CITY off `raw_height_at()`.
  The distant ranges also needed the horizon plane to *displace*, not just be coloured: a flat
  plane has no silhouette and the silhouette is the entire point of a mountain. `macro_ground.gdshader`
  now lifts its vertices by the baked height, faded in with distance so the near ground still
  meets the streamed chunks flush, with ridged noise breaking up the 256 px bake.
  `GROUND_SUBDIVISIONS` went to 200 to have vertices to move, and the plane is snapped to its own
  vertex grid in world space - without that the peaks swim as the follower slides under the player.
  Terrain gained a snowline above the new heights.

- **2026-09-21 Freeways: the first roads that are not on the grid (owner: "every street is just
  straight, there's no curved streets, there's no highways").** `Freeway`
  (`scripts/world/freeway.gd`) plans three long curved routes - Coast (north-south, bending with
  the shoreline), Cross (west-east with a long sweep) and Valley (climbing through a pass into the
  valley) - as seeded polylines with a smoothed, grade-limited deck height. Same shape of data as
  `HillRoads`, deliberately, so the chunk code already knew how to consume it.
  `CityChunk._build_freeway()` builds the deck, underside, fascias, barriers, lane paint, pillars,
  overhead sign gantries and the off-ramps into three meshes per chunk plus one collision body, so
  a chunk's worth of freeway is three draws. It bypasses `MultiMeshBatch` on purpose: the batch
  adds ground relief to every instance origin and the deck is nine metres above the ground.
  Two traps found while building it. A segment is built by the chunk its **midpoint** falls in, or
  neighbouring chunks each build the shared segment and it z-fights. And `PILLAR_SPACING` is
  rounded to whole `STEP` segments: at 32 m with a 24 m step that rounds to 1, a bent landed on
  every single segment, and from the street the elevated section read as a continuous retaining
  wall instead of a deck on legs. Both spacings are now multiples of `STEP`.
  A third trap, caught by the smoke check rather than by eye: smoothing and grade-limiting a
  height profile never look at the ground, so where the terrain rose faster than the grade limit
  allowed, the deck ended up *inside* the hill - one route ran up the peninsula cliffs 128 m
  under the surface. Fixed in two parts. `_drivable()` trims a drawn route to its longest run
  over ground below `MAX_GROUND`, so routes end where the basin does instead of trying to scale
  a range. `_clear_ground()` then builds the lowest profile that clears the ground and still
  obeys the grade - propagate the needed clearance forwards and backwards, relaxing by
  `MAX_GRADE` each step - and takes the higher of that and the smoothed profile. The maximum of
  two grade-feasible profiles is itself grade-feasible, so the result is provably both clear and
  drivable.
  **Honest limit:** the surface street grid is still axis-aligned. `CityPlan.road_pos(axis, index)`
  is one scalar per axis, and blocks, lots, traffic lanes and the minimap all assume axis-aligned
  rects, so curving the grid itself is a rewrite of the city plan rather than an addition. The
  freeways and the hill roads are the curved roads for now. Freeway traffic is not implemented
  either; `TrafficManager` already follows polylines for the airport loops, but those are closed
  loops at ground level and the deck is neither.

- **2026-09-20 The sea was a broken plane, for three separate reasons.** (1) The Gerstner waves
  moved the vertices but never touched NORMAL, so the surface was lit flat and all you saw was a
  painted pattern sliding about; the vertex shader now takes the cross product of the wave sum
  evaluated at two more points. (2) The sea-floor box sat with its top just under the surface,
  and at wave_scale 1 the swell is already +-1.2 m, so every trough dipped below it and the
  floor's flat top drew *over* the water in hard-edged grey patches; the visual box is at -14 m
  now, with the collision left where it was so the sea still holds you up. (3) The horizon plane
  sits 15 cm under the sea surface and a metre or more ABOVE its troughs, so it drew through the
  waves in smooth grey patches, and at a kilometre the 15 cm is below depth precision so the two
  z-fought as well; the plane's vertex shader now drops it 24 m wherever the baked map says
  water, and only a few metres with distance over land, so the coastline keeps its shape. Any one of these on its own is enough to make
  water look wrong.

- **2026-09-20 Water is mostly the sky seen in it.** The ocean shader had Gerstner swells, foam
  and a fresnel term feeding SPECULAR, but nothing actually reflected, so the sea was a flat
  blue-green field whatever the hour. It now mixes toward a sky gradient by fresnel and adds a
  glare path along the line to the sun, from two new shader globals `DayNight` publishes -
  `sky_tint` (the colour the sky meets the horizon with) and `sun_direction`. Globals rather
  than uniforms because every water chunk owns its own material; this way one write a frame
  serves all of them, and anything else that needs to reflect the sky can read the same two.

- **2026-09-20 Palms move.** Nothing in the city moved except the grass, and a boulevard of
  palms standing dead still is one of the things that reads as "model" rather than "place".
  `shaders/foliage.gdshader` bends each palm in the vertex shader, growing with the square of
  the height above the instance's own origin (so the trunk base is still and the crown swings),
  phased by world position so a row does not sway in step, with an extra flutter on the parts
  furthest from the trunk axis - the leaflets. It costs nothing on the CPU and the whole
  boulevard is still one MultiMesh draw. The downloaded trees followed in the next build with
  `shaders/foliage_tex.gdshader`, which is the same vertex sway plus the leaf texture, UV scale
  and alpha scissor. Only the leaf surfaces are converted: the trunk and branches stay opaque
  and still, which is close enough at these amplitudes and keeps the trunks out of the
  transparent pass.

- **2026-09-20 The HUD starts clean.** Six lines of developer text across the top and five
  lines of control hints across the bottom is what the game looked like in every screenshot.
  F1 now cycles CLEAN (crosshair, minimap, weapons), FULL (everything, including the frame-time
  line to screenshot when reporting lag) and HIDDEN, and it starts CLEAN. `-- --stats` starts
  it in FULL, `-- --nohud` in HIDDEN.

- **2026-09-20 The hills were an English meadow.** The source texture is a lush northern green
  and it covered the whole range. `shaders/terrain.gdshader` now burns broad patches to gold and
  tan, drier on the high sunny ground and greener in the folds, which is what the hills above
  this kind of basin look like for most of the year.

- **2026-09-20 The lamps come on in a storm.** The light pools and the lamp lights keyed off
  `night_factor`, so a storm at one in the afternoon - dark enough that the sky goes grey and
  the headlights are on - left the street unlit. There is now a `lamp_factor` shader global,
  `max(night_factor, weather_darken * 0.85)`, which the light-pool shader and the lamp energy
  both read.

- **2026-09-20 The horizon plane was painting grass over the sea.** `macro_ground.gdshader`
  blended the grass texture's own colour back in near the camera, so the beach and the water
  got a green verge. It now takes only the texture's light and shade and leaves the zone colour
  from the baked map in charge.

- **2026-09-20 Skin tones.** Three character models meant three complexions for the whole city.
  `shaders/character.gdshader` takes a `skin_tint` multiplier on whatever the source texture
  has, spread across the looks (`Pedestrian.SKIN_TINTS`). After everyone walking in step, one
  complexion is the loudest tell that a crowd is three people copied a thousand times.

- **2026-09-20 Shop signs.** The storefront sign bands were blank stripes of colour, which is
  what stops a street reading as a street full of businesses. `Building` now decides the shop
  runs (how many bays make one shop, per face) and passes them to the shader as `shop_span`
  instead of the shader hashing its own, so the bands and the names line up exactly, and places
  a `TextMesh` per run. One mesh per name, shadows off, draw distance 75 m, skipped on web.
  The next step, if the draw count becomes a problem or the names are wanted at distance, is to
  rasterise the whole name list into one atlas at load and sample it in the fascia branch: no
  geometry at all, every band named, at any distance.

- **2026-09-20 The city had no lights.** At night the streets were pitch black, because nothing
  in the world was a light source: the sun, and emissive materials on lit windows, and that was
  all. Street lamps now carry a real `OmniLight3D` (FULL chunks, distance-faded, no shadows) in
  the `lamp_light` group, and every lamp and car also carries the additive night quad
  (`shaders/light_pool.gdshader`), which reads `night_factor` itself and so costs nothing by
  day: a pool on the pavement under each lamp, headlights, tail lights and a beam on the road
  in front of every car. Two traps: setting the lights only when the value moves leaves every
  lamp that streamed in since the last change sitting at zero (refresh on a slow tick instead),
  and `Vehicle._box()` skips every primitive once a generated body model is in use, which is
  why the modelled cars had no lamps at all.

- **2026-09-20 Everyone in the city walked like a scarecrow.** The generated walk and idle clips
  animate the arms, but on top of an A-pose rest, so every pedestrian and the player walked
  around with their arms out at 45 degrees. Fixed by rotating the shoulder rotation keys once on
  the shared animation resource (`Pedestrian.fix_arm_pose`), which costs nothing at runtime and
  fixes every instance of the model at once. A skeleton pose override does not work here: the
  clips animate the shoulders, so it is overwritten every frame. The correction is per model
  (-46 degrees for A, -76 for C): the two rigs do not share a rest pose.

- **2026-09-20 The AK-47 was a 1.31 m orange plank.** It is on screen in every single frame of
  this game and it was eight boxes long enough to be a rifle and a half, in a wood colour that
  blew out to bright orange in sunlight. Rebuilt at real proportions (880 mm, butt to muzzle)
  with a receiver and top cover, walnut furniture, gas tube, gas block, front and rear sights,
  a curved three-segment magazine, trigger and guard, safety lever and charging handle.

- **2026-09-20 The horizon is the ground plane, so the ground plane became the map.** From any
  height, everything outside the streamed chunks was a 4 km flat green plane whose own edge was
  the skyline, with a grey band of sky-below-horizon above it. `MacroMap.bake()` now paints the
  whole basin into one 256 px image once at load (about 270 ms): RGB is the ground colour per
  zone and district, alpha is height / 400 m and exactly zero on water. The plane is 14 km
  across and wears `shaders/macro_ground.gdshader`, which shades from that image with relief
  from the baked height, noise to break up the bilinear smear, the grass texture blended back
  in within ~300 m, water shaded as water (dark, sky in it, a glare path toward the sun) and
  haze that hands the far land over to the sky. `DayNight` keeps the haze colour and the sun
  direction in step and now also sets the sky's below-horizon colour, so there is no grey band.
  Tuning note: the baked colours are albedos, not the finished look. The renderer lights the
  plane like anything else and brightens them by about half again, so colours picked by eye
  from a photograph come out washed out.

- **2026-09-20 Clouds are lit by looking toward the sun.** The sky's cumulus were one flat white
  density field with a `pow(cos_sun)` term on top, which reads as paper. The shader now steps
  across the same noise field toward the sun and darkens where there is more cloud in the way,
  which is what gives cumulus bright shoulders and grey undersides, plus a silver lining on
  thin edges with the sun behind them and a sheared cirrus deck above. It costs three extra
  noise taps, so `Quality` clears `cloud_detail` on the web and below MEDIUM.

- **2026-09-20 One of the three pedestrian models had no clothes on.** `pedestrian_b`'s texture
  came back from the generator as bare skin head to foot, so `shaders/character.gdshader`, which
  only recolours pixels already off the skin hue, had nothing to act on; its rig does not take
  the walk clip either. A third of the crowd was a naked orange mannequin standing with its arms
  over its head. It is out of `Pedestrian.MODELS`. The smoke test now measures how much of each
  character texture sits away from its own average colour (0.31 and 0.71 for the two in use,
  0.001 for the nude one), because a hue test cannot catch this: brown clothing is a skin hue.

- **2026-09-20 The road and the pavement were the same grey.** Measured off a screenshot, both
  came out at 110,123,127. Asphalt tints ran 0.60 to 0.85; sun-bleached asphalt is still only
  about a quarter as bright as a kerb, so they now run 0.31 to 0.49. This is the kind of thing
  that makes a whole street read as one flat field no matter how much detail is layered on it.

- **2026-09-20 Glass reflects, and rooms are dark.** Windows were pale cards with an evenly lit
  room behind them. The pane now mixes toward a sky gradient above the horizon and the dark
  street below it, weighted by a Schlick fresnel, computed in the shader from the reflected ray
  rather than by raising METALLIC (which is what turned curtain-wall towers into see-through
  cages in build 60). Rooms are exposed for daylight outside, so they read almost black from the
  street. Second tuning note: "horizon" for a pane on a wall is the buildings opposite, not the
  sky at the horizon; a pale sky blue there turned every shop window into milk glass.

- **2026-09-20 Worn road surfaces.** The road fills the bottom third of almost every shot and a
  single tiled texture read as a flat grey plane whatever the lighting did.
  `shaders/road.gdshader` layers what actually makes tarmac look used, all from world position
  so it tiles across chunks and never visibly repeats: slow mottling, resurfacing patches on a
  jittered grid each with its own tone, smoothness and a darker seam, cracks from folded ridged
  noise, and sparse oil and rubber staining. Wetness moved to a `road_wetness` global so Weather
  sets one value instead of walking every cached material.
  Tuning note: crack and stain noise below about 0.4 frequency reads as wandering tendrils of
  damp rather than cracks in asphalt; keep the frequency high and the threshold narrow.

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

## Correction: what build 135 (0ce833f) actually contained

That commit's subject says "denser grass, real palm fronds, finer ground". It also shipped a
complete generated wheel system into `PropFactory` - `car_wheel()`, `car_caliper()`,
`wheel_material()`, `_wheel_tyre()`, `_wheel_barrel()`, `_wheel_brake()`, `_wheel_face()`,
`_wheel_tread()`, `WHEEL_KITS`, `WHEEL_FACES`, `WHEEL_SLOTS` and the `WheelSlot` enum - and the
message does not mention any of it.

The cause is worth recording because it is cheap to repeat: the commit picked up 1,091 lines of
orphaned work from a fleet whose agents were all killed mid-build, and the diff was surveyed with
a `grep ... | head -30`. The wheel constants sat past the cut, so they were never read. **Survey a
large inherited diff with no truncation, or do not claim to know what is in it.**

Two things that follow, both checked rather than assumed:

- The "4.65M -> 10.7M triangles for twelve extra draw calls" measurement in that commit is still
  correct and is still attributable to the grass, palms and subdivision. `car_wheel()` was called
  from nowhere at that commit - the mesh shipped as dead code, so it could not have contributed a
  triangle.
- A wheels fleet was then launched to build a wheel that already existed. Its reviewer caught
  this independently. The mesh was the half that existed; `Vehicle` wiring it up was the half that
  was actually missing.

## Graphics references (owner, 2026-09-21)

Four images the owner sent as the target. What each one actually asks for, so a later session
tunes toward something specific rather than "make it prettier":

**1. Horizon Zero Dawn, forest floor.** Visible light shafts through the canopy; ground cover in
three or four layers (fern, grass, shrub, litter) all the way to the camera; warm bounce under a
strong back sun; every surface carrying texture at every scale. The ask: *volumetric light* and
*layered undergrowth*, not just more trees.

**2. A skyline above a cloud sea at sunrise.** Towers as flat silhouettes against a huge soft sun
and a warm gradient filling the whole sky. The ask: *a sun that is an event in the frame* - disc,
halo, bloom - rather than a bright dot.

**3. GTA V, the Los Angeles overlook. This is the closest to what this game is.** Read the value
structure: dark dry-gold foreground hillside with scrub, rock and a dirt path; the whole basin in
a STRATIFIED warm-blue smog layer the towers rise out of; mountains receding in separate blue
layers behind it; the sun a soft bloom on the right. Note what it is NOT: it is not uniformly
hazy - the haze has a top, and the air above it is clear. Our fog was one flat curtain, then it
was cut back to almost nothing; neither is this. The ask: *height fog with a defined top*,
*aerial perspective in layers*, and *a foreground that is darker than the distance*.

**4. Miami, Ocean Drive at sunset.** Neon on every frontage, reflected in a wet road; a structured
pink-and-orange cloud sky; palms lit from below; dense crowds and headlights. The ask: *neon
signage as a light source*, *wet road reflections*, and *sky with cloud STRUCTURE at sunset* -
this project has shaders/neon_sign.gdshader and a `road_wetness` global already and uses almost
none of either.
