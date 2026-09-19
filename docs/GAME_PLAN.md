# Game plan

3D open-world chaos sandbox. Godot 4.7.2, GDScript, Forward+. Overpowered player, unlimited guns,
seeded low-poly city to wreck. Silly and over the top. See `CLAUDE.md` for working rules.

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
- [ ] **8. Foliage and polish.** Code-generated low-poly trees and bushes with random variation,
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

## Current state

Milestones 1 to 7 are in, plus the west-coast map with its landmarks.

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
