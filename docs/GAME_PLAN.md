# Game plan

3D open-world chaos sandbox. Godot 4.7.2, GDScript, Forward+. Overpowered player, unlimited guns,
seeded low-poly city to wreck. Silly and over the top. See `CLAUDE.md` for working rules.

## Roadmap

Build in this order, one milestone per PR or a few PRs.

- [x] **1. Player and test box.** Third-person CharacterBody3D controller: run, sprint, super-high
  jump, double jump, strong air control, no fall damage. Spring-arm follow camera with mouse look
  that does not clip through walls. Gamepad and keyboard/mouse input mapped. Greybox test level:
  large flat ground, ramps, tall boxes of varied heights, and a pile of RigidBody3D crates.
- [ ] **2. Guns.** Weapon system with instant switching and unlimited ammo. Start with three: a
  hitscan rifle that shoves physics objects, a rocket launcher with an explosion that applies radial
  impulse, and a gravity gun that grabs and launches objects. Simple crosshair HUD.
- [ ] **3. Building shader.** A single shader that makes a plain box look like a building:
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

Milestone 1 is in. Main scene: `scenes/levels/test_box.tscn`. The level script
(`scripts/world/test_level.gd`) generates a 400 m checkered ground, a jump gauge (boxes of 4 to
30 m with height labels), six ramps, forty tall boxes (some with a step on top), and ninety-five
crates (a pyramid and a wall) from `world_seed = 1337`. `PhysicsBudget` autoload caps props at 300,
freezes props more than 90 m from the player, and frees debris after 12 s. A debug HUD (F1) shows
FPS, speed, last jump peak, and prop counts.

Input actions for weapons (`fire`, `alt_fire`, `next_weapon`, `prev_weapon`, `weapon_1..3`) are
already mapped so milestone 2 is script-only.

## Decisions log

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
- **2026-09-19 CI runs the headless check** on every push and PR via GitHub Actions, so a PR that
  fails to load is visible before playtesting.
