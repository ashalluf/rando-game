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
- [ ] **4. Seeded city generator.** Road grid with varied block sizes, a few intersection types,
  occasional parks and plazas, and districts defined by parameter ranges (downtown tall glass,
  midtown mixed, suburbs low brick, industrial warehouses). Sidewalk props and street trees
  scattered by the same seed.
- [ ] **5. Chunk streaming.** Generate chunks around the player and free distant ones. Cheap box
  LODs for the far skyline. Persist a list of destroyed objects per chunk so destruction survives
  leaving and returning. Origin re-centering to avoid floating-point jitter far from the origin.
- [ ] **6. Vehicles.** Drivable cars using VehicleBody3D with bouncy, overpowered arcade handling.
  Enter and exit. Modular car variety: a few body types, random paint, small add-ons. Parked cars
  spawned by the city generator.
- [ ] **7. NPCs and traffic.** Simple wandering pedestrians that ragdoll when hit, basic traffic
  following road lanes. Strict caps on active counts.
- [ ] **8. Foliage and polish.** Code-generated low-poly trees and bushes with random variation,
  MultiMesh grass with a wind shader in parks, day/night cycle, sound effects, pause menu with a
  seed input field.

## Current state

Milestones 1 to 3 are in. `shaders/building.gdshader` turns any BoxMesh into a facade: window
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
