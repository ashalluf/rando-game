# Assets

External assets: CC0 texture sets (below), CC0 models from Poly Haven (trees, plants, flowers,
grass, rocks and street props), and 3D models generated with the owner's Meshy account
(`tools/meshy.py`, retired 2026-09-19). Buildings, lamps and signs are still primitives and code.

Everything on Poly Haven is CC0. Fetch one with `python3 tools/fetch_polyhaven.py <id> <dir>`,
reduce trees and bushes with `tools/decimate_tree.py`, pack with `tools/pack_gltf.py`, shrink
textures with `tools/shrink_glb.py`, then run Godot's `--import` and
`python3 tools/fix_texture_imports.py assets/models` before committing - Godot writes every new
texture .import with `compress/mode=0` and `detect_3d/compress_to=1`, and the second of those
makes the editor silently rewrite the file the first time the texture is used in 3D.

When assets are added, only CC0 or free-for-commercial-use packs are allowed (for example Kenney,
Quaternius). Record every pack here.

| Asset / pack | Source URL | License | Used for | Added |
|---|---|---|---|---|
| `icon.svg` | original, drawn for this project | project | project icon | 2026-09-19 |
| Asphalt033 (1K JPG: Color, NormalGL, Roughness) | https://ambientcg.com/a/Asphalt033 | CC0 1.0 | roads, runways | 2026-09-19 |
| Bricks104 | https://ambientcg.com/a/Bricks104 | CC0 1.0 | brick facades | 2026-09-19 |
| Concrete034 | https://ambientcg.com/a/Concrete034 | CC0 1.0 | concrete facades, port yard | 2026-09-19 |
| Grass004 | https://ambientcg.com/a/Grass004 | CC0 1.0 | parks, ground, hills | 2026-09-19 |
| Ground054 | https://ambientcg.com/a/Ground054 | CC0 1.0 | beach sand | 2026-09-19 |
| MetalPlates006 | https://ambientcg.com/a/MetalPlates006 | CC0 1.0 | warehouses, glass tower spandrels | 2026-09-19 |
| PavingStones138 | https://ambientcg.com/a/PavingStones138 | CC0 1.0 | sidewalks, plazas | 2026-09-19 |
| Rock064 | https://ambientcg.com/a/Rock064 | CC0 1.0 | (kept, no longer on hills) | 2026-09-19 |
| AerialGrassRock (Poly Haven `aerial_grass_rock`, Diffuse/nor_gl/Rough renamed to Color/NormalGL/Roughness) | https://polyhaven.com/a/aerial_grass_rock | CC0 1.0 | hill ground | 2026-09-19 |
| RockyTerrain02 (Poly Haven `rocky_terrain_02`) | https://polyhaven.com/a/rocky_terrain_02 | CC0 1.0 | hill slopes | 2026-09-19 |
| RedBrick, Brick4, RedBrick03 (Poly Haven `red_brick`, `brick_4`, `red_brick_03`) | https://polyhaven.com/a/red_brick etc. | CC0 1.0 | brick facades (one per building) | 2026-09-19 |
| PaintedPlasterWall, BeigeWall001, WhitePlaster02, ConcreteWall003 (`painted_plaster_wall`, `beige_wall_001`, `white_plaster_02`, `concrete_wall_003`) | https://polyhaven.com/a/painted_plaster_wall etc. | CC0 1.0 | flat facades | 2026-09-19 |
| CrackedConcreteWall, ConcreteLayers02 (`cracked_concrete_wall`, `concrete_layers_02`) | https://polyhaven.com/a/cracked_concrete_wall etc. | CC0 1.0 | concrete panel facades, glass tower spandrels | 2026-09-19 |
| CorrugatedIron, FactoryWall (`corrugated_iron`, `factory_wall`) | https://polyhaven.com/a/corrugated_iron etc. | CC0 1.0 | warehouses | 2026-09-19 |
| AerialAsphalt01 (`aerial_asphalt_01`) | https://polyhaven.com/a/aerial_asphalt_01 | CC0 1.0 | second asphalt look, per road | 2026-09-19 |
| LargeSquarePattern01, GravelConcrete03 (`large_square_pattern_01`, `gravel_concrete_03`) | https://polyhaven.com/a/large_square_pattern_01 etc. | CC0 1.0 | sidewalk pavers and plain concrete sidewalks, per block | 2026-09-19 |

Texture sets are from ambientCG and Poly Haven (both CC0 1.0 Universal, no attribution required,
attribution given anyway). Only the Color, NormalGL and Roughness maps at 1K are kept, under `assets/textures/<Set>/`.

## Generated 3D models (Meshy)

Made with the owner's Meshy account through the API (`python3 tools/meshy.py gen ...`): Meshy's
latest standard model, ~8000 faces after remesh, refined with 2K PBR textures, then shrunk to 1K
JPEG with `tools/shrink_glb.py`. Every prompt asks for the most realistic result (owner's rule). Rights follow the owner's Meshy plan (paid plans: owner owns the output;
free plan: CC BY 4.0). Each `.json` next to a model records its prompt, Meshy task ids and credits.

| Model | Files | Credits | Used for | Added |
|---|---|---|---|---|
| Sedan | `assets/models/car_sedan.glb` | 30 (+15 for a first low-poly take) | `Vehicle` body, SEDAN | 2026-09-19 |
| Pickup | `assets/models/car_pickup.glb` | 30 (+15) | `Vehicle` body, PICKUP | 2026-09-19 |
| Van | `assets/models/car_van.glb` | 30 (+15) | `Vehicle` body, VAN | 2026-09-19 |
| Sports | `assets/models/car_sports.glb` | 30 (+15) | `Vehicle` body, SPORTS | 2026-09-19 |
| Pedestrian A (man, t-shirt) | `assets/models/pedestrian_a.glb`, `pedestrian_a_anim.glb` (rigged: Idle, Casual_Walk_inplace, run_fast_3_inplace) | 44 (+29) | `Pedestrian` | 2026-09-19 |
| Pedestrian B (woman, hoodie) | `pedestrian_b.glb`, `pedestrian_b_anim.glb` (same clips) | 44 (+29) | **unused** | 2026-09-19 |
| Pedestrian C (older man, shirt) | `pedestrian_c.glb`, `pedestrian_c_anim.glb` (same clips) | 44 (+29) | `Pedestrian` | 2026-09-19 |
| Pedestrian D (young man, vest, white sneakers) | `pedestrian_d_anim.glb` (rigged, same clips, 16k faces) | 44 | `Pedestrian`, the player's body | 2026-09-22 |
| Pedestrian E (woman, denim jacket) | `pedestrian_e_anim.glb` (same) | 44 | `Pedestrian` | 2026-09-22 |
| Pedestrian F (older man, grey suit) | `pedestrian_f_anim.glb` (same) | 44 | `Pedestrian` | 2026-09-22 |
| Pedestrian G (woman, white top, ponytail) | `pedestrian_g_anim.glb` (same) | 44 | `Pedestrian` | 2026-09-22 |
| Pedestrian H (older man, jacket, khakis) | `pedestrian_h_anim.glb` (same) | 44 | `Pedestrian` | 2026-09-22 |
| Pedestrian I (young man, cap) | `pedestrian_i_anim.glb` (same) | 44 | `Pedestrian` | 2026-09-22 |
| Pedestrian J (Black man, grey hoodie, jeans) | `pedestrian_j_anim.glb` (same) | 44 | `Pedestrian` | 2026-09-22 |
| Pedestrian K (Black woman, yellow blazer) | `pedestrian_k_anim.glb` (same) | 44 | `Pedestrian` | 2026-09-22 |
| Pedestrian L (Latino man, navy shirt, cargo trousers) | `pedestrian_l_anim.glb` (same) | 44 | `Pedestrian` | 2026-09-22 |
| Private jet | `assets/models/jet_private.glb` | 30 | `Aircraft` PRIVATE | 2026-09-19 |
| Airliner | `assets/models/jet_airliner.glb` | 30 | `Aircraft` AIRLINER | 2026-09-19 |

Pedestrian B is not loaded by anything (2026-09-20). Its texture came back as bare skin with no
clothing anywhere, so the garment recolour in `shaders/character.gdshader` has nothing to act on,
and its rig does not take the walk clip (it stands with its arms over its head). It walked the
city as a naked orange mannequin. The files stay in the repo so the decision is visible.

**The second generation of people (2026-09-22).** Meshy is retired for everything except
characters (owner: "we need entirely new assets for the humans"); there is no CC0 source of
realistic rigged humans. D to L replace A and C in `Pedestrian.MODELS`: they are made at
`--polycount 16000` where the first set was 8000, and next to them A and C looked like a lower
tier of model. Only the rigged `_anim.glb` is committed for these - nothing loads the unrigged
`.glb`, and every file in the project ships in the app. Each has a baked
`pedestrian_X_nrm.png` from `tools/make_character_maps.py` (the `_mask.png` it also writes is
not loaded at runtime and is not committed). The rest pose is a palms-up shrug, which is why
`Pedestrian.fix_arm_pose()` rebuilds the arm keys from the rig rather than rotating them.
D to I followed their prompts poorly on skin tone and clothing colour, which traced to the tool
sending a subject-free texture prompt; J, K and L were made after the fix and match theirs.

All seven were first made as low-poly cartoon models (147 credits) and then regenerated with the
owner's realism rule on Meshy's standard model (252 credits). Car base colors are greyscaled and
brightened (`tools/shrink_glb.py --desaturate`) so the seeded paint tint gives the color.

Godot extracts each model's textures next to it on import (`<model>_N.jpg` + `.import`); those
files are committed like any other import output.

## Procedurally generated cars (our own tools, no external source)

Not downloaded and not Meshy: these are written by Python generators in `tools/` using `bpy`
(Blender as a module, `pip install bpy`), so the model *is* the script and the `.glb` is build
output. Original shapes and original marque names throughout - no real manufacturer's design,
badge or trade dress, which is why a request to copy one is answered with a car in the same
class instead.

| Generator | Model | Size | Used for | Added |
| --- | --- | --- | --- | --- |
| `tools/make_exotic_super.py` | `exo_super_coupe.glb` | 32k tris, 0.8 MB | `BodyType.SUPER` | 2026-09-21 |
| `tools/make_exotic_super.py` | `exo_super_spider.glb` | 34k tris, 0.8 MB | `BodyType.SPIDER` | 2026-09-21 |
| `tools/make_exotic_hyper.py` | `exo_hyper_a.glb` | 0.8 MB | `BodyType.HYPER` | 2026-09-21 |
| `tools/make_exotic_hyper.py` | `exo_hyper_b.glb` | 0.9 MB | `BodyType.TRACK` | 2026-09-21 |
| `tools/make_hifi_super.py` | `hifi_super_coupe.glb` | 223k tris, 4.9 MB | not wired in yet | 2026-09-21 |
| `tools/make_hifi_hyper.py` | `hifi_hyper_coupe.glb` | 217k tris, 5.7 MB | not wired in yet | 2026-09-21 |

The `hifi_*` pair are a different construction from the `exo_*` ones and are the direction to
carry forward. Each body is ONE all-quad control cage indexed by (longitudinal station, position
round the section) with Catmull-Clark subdivision at level 2 on top, so every feature is an
operation on that grid rather than a shape placed by eye: shut lines are three grid lines 3.2 mm
apart with the middle one pushed 4.5 mm in; an opening is cut by deleting an (f, g) rectangle,
extruding the border inward twice, capping it and creasing the cut loop, which is what gives the
intakes, lamp recesses and vents real inner walls; a wheel arch is the same cut snapped onto the
arch circle with the skin just outside it pushed 14 mm proud to make a lip.

That last one matters. The `exo_*` bodies have no wheel arches at all - their own critic measured
the front tyre standing 11.8 cm proud of the bodywork with bare sky above its outer 12 cm, and
called it "wheels bolted onto the outside of a slab". Anything new should follow the `hifi_*`
method.

Every car model must expose these six material slots, because `Vehicle._add_body_model()` binds
by name: `paint`, `glass`, `trim`, `tyre`, `light_front`, `light_rear`. Only bodywork goes in
`paint` - the per-car colour and the clearcoat shader are applied to that slot alone.

## Weapon models (our own Blender generator)

The guns in the hero's hands (2026-09-24, replacing a dozen boxes each). Like the `hifi_*` cars
these are written by a script, `tools/make_weapons.py`, run in Blender 4.2 (`blender -b -t 2
--factory-startup -P tools/make_weapons.py -- [ak47] [rocket_launcher] [shotgun]`), so the model
is the script and the `.glb` is build output. Modelled in millimetres from real dimensions,
bevelled with weighted normals, UV-unwrapped and baked to 1K maps per material (colour, glTF
metal/roughness, OpenGL normal) from procedural finishes. The only external input is the wood
grain: Poly Haven `dark_wood` (https://polyhaven.com/a/dark_wood, CC0 1.0; 1K diffuse,
displacement and roughness), downloaded into `build/weapon_src/` by the script and never
shipped raw - it is baked into the wood maps below. Original designs with no maker's marks or
text; the rifle is the AKM pattern, the launcher an RPG-style tube, the shotgun a classic
walnut pump gun. Godot generates the LODs on import (`meshes/generate_lods`) and extracts the
embedded maps as `weapon_<gun>_<material>_<map>.jpg`.

| Model | Nodes | Triangles | Maps (1K each) | Used for | Added |
|---|---|---|---|---|---|
| `weapon_ak47.glb` | `Body`, `Muzzle` | 15.1k | `metal`, `wood` (x3) | `AssaultRifle` | 2026-09-24 |
| `weapon_rocket_launcher.glb` | `Body`, `Warhead`, `Muzzle` | 11.9k (10.2k + 1.7k) | `body`, `warhead`, `wood` (x3) | `RocketLauncher` | 2026-09-24 |
| `weapon_shotgun.glb` | `Body`, `Pump`, `Shell`, `Muzzle`, `PumpBack`, `EjectPort` | 8.2k (5.3k + 2.6k + 0.4k) | `metal`, `wood` (x3) | `Shotgun` | 2026-09-24 |

## Aircraft models (our own Blender generator)

The helicopter the air traffic flies (2026-09-24), police and news liveries in one file.
Written by `tools/make_helicopter.py`, run in Blender 4.2 (`blender -b --factory-startup
--python tools/make_helicopter.py [-- --render out.png]`), so the model is the script and the
`.glb` is build output; no external input at all. An original light helicopter in the 10 m class,
a class study rather than a copy of any type. Clean painted materials (no textures), bound by
name in `Helicopter._paint()`: `paint`, `paint2`, `stripe` (re-coloured per livery), `glass`,
`trim`, `metal`, `blade`, `lens`, `nav_red`, `nav_green`, `decal_police`, `decal_news`. The
lettering ("POLICE"; "RANDO 5" and "NEWS" for the invented station) is Blender's bundled font
converted to geometry. Godot generates the LODs on import.

| Model | Nodes | Triangles | Used for | Added |
|---|---|---|---|---|
| `helicopter.glb` | `Body`, `MainRotor` (`MainRotorHub`, `MainRotorBlades`), `TailRotor` (`TailRotorHub`, `TailRotorBlades`), `Searchlight`, `CameraBall`, `LiveryPolice`, `LiveryNews` | 7.2k in the file; 5.7k drawn as police (body 3.6k), 5.8k as news | `Helicopter` (air traffic) | 2026-09-24 |

The airliners and private jets of the air traffic reuse the Meshy jets above (`Aircraft.MODELS`).

## Street prop models (Poly Haven, CC0)

Downloaded from the open Poly Haven API (`https://api.polyhaven.com/files/<id>`, glTF at 1K) and
packed into one `.glb` each with `tools/pack_gltf.py`. CC0 1.0, no attribution required; credit to
Poly Haven and its artists given anyway (https://polyhaven.com). Godot extracts the textures next
to each `.glb` on import (`prop_<name>_<map>.jpg` + `.import`); those are committed too.

| Poly Haven asset | File | Triangles | Used for | Added |
|---|---|---|---|---|
| fire_hydrant (fresh + aged) | `assets/models/prop_hydrant.glb` | 43k per variant | sidewalk hydrants | 2026-09-19 |
| metal_trash_can (clean + rusty) | `prop_trash_can.glb` | 7k per variant | `TrashCan` physics prop | 2026-09-19 |
| modular_street_seating | `prop_bench_kit.glb` | 25k (kit) | `PropFactory.model_bench()` assembles a bench | 2026-09-19 |
| concrete_road_barrier | `prop_barrier.glb` | 61k | industrial clutter | 2026-09-19 |
| Barrel_01 | `prop_barrel.glb` | 2.7k | industrial clutter (physics) | 2026-09-19 |
| old_tyre | `prop_tyre.glb` | 2.9k | industrial clutter, tyre stacks (physics) | 2026-09-19 |
| planter_box_01 | `prop_planter.glb` | 8k | sidewalk planters | 2026-09-19 |
| outdoor_table_chair_set_01 | `prop_cafe_set.glb` | 10k | cafe tables downtown and midtown | 2026-09-19 |
| street_lamp_01 | `prop_lamp.glb` | 31k | every street lamp (bulb and glass made emissive in code) | 2026-09-19 |
| shrub_02 (4 variants) | `prop_shrub.glb` | 7k each | sidewalk and park bushes, hill shrubs | 2026-09-19 |
| water_manhole_cover | `prop_manhole.glb` | 6k | manhole covers in the lanes | 2026-09-19 |
| concrete_road_barrier_02 | `prop_barrier_b.glb` | 24k | tall barrier variant, industrial clutter | 2026-09-19 |
| Gunshots (kurt) | https://opengameart.org/content/gunshots | CC0 1.0 | `assets/audio/shot_0..2` | 2026-09-21 |
| The Free Firearm Sound Library (Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney; posted by bart) | https://opengameart.org/content/the-free-firearm-sound-library | CC0 1.0 | `assets/audio/shotgun_0..2` (takes H_21P, K_22P and O_21P: three 12-gauge pump guns, near the shooter), trimmed to 1.6 s with the tail faded, mono 44.1 kHz | 2026-09-24 |
| Shotgun reload sound effects (zer0_sol) | https://opengameart.org/content/shotgun-reload-sound-effects | CC0 1.0 | `assets/audio/pump_0` (Rack) | 2026-09-24 |
| Chunky Explosion (Joth) | https://opengameart.org/content/chunky-explosion | CC0 1.0 | `assets/audio/explosion_0` | 2026-09-21 |
| Explosion (TinyWorlds) | https://opengameart.org/content/explosion-0 | CC0 1.0 | `assets/audio/explosion_1` | 2026-09-21 |
| Rocket Engine (theMinesAreShakin) | https://opengameart.org/content/rocket-engine | CC0 1.0 | `assets/audio/rocket_0, boost_loop_0` | 2026-09-21 |
| 75 CC0 breaking/falling/hit SFX (rubberduck) | https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx | CC0 1.0 | `assets/audio/break_0..2, glass_0..2` | 2026-09-21 |
| Crash collision (qubodup) | https://opengameart.org/content/crash-collision | CC0 1.0 | `assets/audio/crash_0` | 2026-09-21 |
| Impact Sounds (Kenney) | https://kenney.nl/assets/impact-sounds | CC0 1.0 | `assets/audio/crash_1..2` | 2026-09-21 |
| 37 hits/punches (qubodup) | https://opengameart.org/content/37-hitspunches | CC0 1.0 | `assets/audio/land_0..1, thud_0..1` | 2026-09-21 |
| Fantozzi's Footsteps (qubodup) | https://opengameart.org/content/fantozzis-footsteps-grasssand-stone | CC0 1.0 | `assets/audio/footstep_0..5` | 2026-09-21 |
| Car sound effects pack (GGBotNet) | https://opengameart.org/content/car-sound-effects-pack-low-quality | CC0 1.0 | `assets/audio/horn_0, engine_loop_0` | 2026-09-21 |
| Rain loop (Kresiek The Furry) | https://opengameart.org/content/amb-rain-loop-1 | CC0 1.0 | `assets/audio/rain_0` | 2026-09-21 |
| Mild wind background noise (Bashar3A) | https://opengameart.org/content/mild-wind-background-noise | CC0 1.0 | `assets/audio/wind_0` | 2026-09-21 |
| High traffic road sounds (IgnasD) | https://opengameart.org/content/high-traffic-road-sounds | CC0 1.0 | `assets/audio/ambience_city_0` | 2026-09-21 |
| Rain long thunder (WuxiaScrub) | https://opengameart.org/content/rain-long-thunder | CC0 1.0 | `assets/audio/thunder_0` | 2026-09-21 |
| Female high-pitched scream SFX | https://opengameart.org/content/female-high-pitched-scream-sfx | CC0 1.0 | `assets/audio/scream_0..3` (the four takes, cut apart) | 2026-09-23 |
| Female Scream 1 (AuraVoice) | https://opengameart.org/content/female-scream-1 | CC0 1.0 | `assets/audio/scream_4` | 2026-09-23 |
| Male grunt/yelling sounds | https://opengameart.org/content/male-gruntyelling-sounds | CC0 1.0 (dual CC0 / OGA-BY) | `assets/audio/scream_5..11` (yell11, yell2, 3yell13, 3yell1, 3yell14, 2yell5, 1yell4) | 2026-09-23 |
| Grunts: male death and pain | https://opengameart.org/content/grunts-male-death-and-pain | CC0 1.0 | `assets/audio/yelp_0..3` | 2026-09-23 |
| Man hurt sounds | https://opengameart.org/content/man-hurt-sounds | CC0 1.0 | `assets/audio/yelp_4..6` | 2026-09-23 |
| Fleshy bone break/snap SFX | https://opengameart.org/content/fleshy-bone-breaksnap-sfx | CC0 1.0 | `assets/audio/gore_0..4` (Wet Break 1, 3, 5, 7, 9) | 2026-09-23 |
| 8 wet squish, slurp impacts | https://opengameart.org/content/8-wet-squish-slurp-impacts | CC0 1.0 | `assets/audio/gore_5..6` | 2026-09-23 |
| airliner_ascend.aif (Heigh-hoo), a real airliner take-off | https://freesound.org/people/Heigh-hoo/sounds/51091/ | CC0 1.0 | `assets/audio/jet_loop_0` (19.6-29.6 s of the HQ preview, mono, crossfaded into a seamless loop) | 2026-09-24 |
| cop helicopter flying (Atilio_Sanchez), a real police helicopter overhead | https://freesound.org/people/Atilio_Sanchez/sounds/721300/ | CC0 1.0 | `assets/audio/rotor_loop_0` (139.1-147.1 s, crossfaded loop; the 20 Hz blade-pass chop kept) | 2026-09-24 |
| jacaranda_tree | `tree_jacaranda.glb` | 60k tris, 10.2 MB | street and park trees; recoloured to lavender blossom (see shaders/foliage_tex.gdshader) | 2026-09-21 |
| island_tree_03 | `tree_d.glb` | 38k tris, 3.6 MB | street and park trees | 2026-09-21 |
| fir_tree_01 | `tree_fir.glb` | 54k tris, 5.2 MB | hill conifers | 2026-09-21 |
| pine_tree_01 | `tree_pine.glb` | 48k tris, 3.5 MB | hill conifers | 2026-09-21 |
| quiver_tree_01 | `tree_quiver.glb` | 42k tris, 2.5 MB | dry hill trees | 2026-09-21 |
| searsia_burchellii | `tree_searsia.glb` | 16k tris, 1.8 MB | dry hill scrub | 2026-09-21 |
| shrub_01 | `bush_a.glb` | 16k tris, 1.1 MB | street and park bushes | 2026-09-21 |
| shrub_03 | `bush_b.glb` | 8k tris, 0.6 MB | street and park bushes | 2026-09-21 |
| shrub_04 | `bush_c.glb` | 27k tris, 1.1 MB | street and park bushes | 2026-09-21 |
| shrub_sorrel_01 | `bush_sorrel.glb` | 3k tris, 0.4 MB | street and park bushes | 2026-09-21 |
| fern_02 | `plant_fern.glb` | 6k tris, 0.4 MB | courtyard and doorway planting | 2026-09-21 |
| pachira_aquatica_01 | `plant_pachira.glb` | 77k tris, 2.8 MB | courtyard and doorway planting | 2026-09-21 |
| anthurium_botany_01 | `plant_anthurium.glb` | 67k tris, 2.1 MB | courtyard and doorway planting | 2026-09-21 |
| calathea_orbifolia_01 | `plant_calathea.glb` | 17k tris, 0.8 MB | courtyard and doorway planting | 2026-09-21 |
| nettle_plant | `plant_nettle.glb` | 31k tris, 1.4 MB | rough ground planting | 2026-09-21 |
| flower_gazania | `flower_orange.glb` | 14k tris, 1.4 MB | flowering ground cover in parks and gardens | 2026-09-21 |
| flower_ursinia | `flower_ursinia.glb` | 25k tris, 1.1 MB | flowering ground cover in parks and gardens | 2026-09-21 |
| flower_empodium | `flower_yellow.glb` | 3k tris, 0.3 MB | flowering ground cover in parks and gardens | 2026-09-21 |
| leipoldtia_schultzei | `flower_purple.glb` | 7k tris, 0.5 MB | flowering ground cover in parks and gardens | 2026-09-21 |
| periwinkle_plant | `flower_periwinkle.glb` | 34k tris, 2.1 MB | flowering ground cover in parks and gardens | 2026-09-21 |
| dandelion_01 | `flower_dandelion.glb` | 55k tris, 2.1 MB | flowering ground cover in parks and gardens | 2026-09-21 |
| celandine_01 | `flower_celandine.glb` | 9k tris, 0.6 MB | flowering ground cover in parks and gardens | 2026-09-21 |
| grass_bermuda_01 | `grass_bermuda.glb` | 941 tris, 0.4 MB | grass clumps in parks and gardens | 2026-09-21 |
| grass_medium_02 | `grass_medium.glb` | 8k tris, 0.4 MB | grass clumps in parks and gardens | 2026-09-21 |
| street_lamp_01 | `prop_streetlamp.glb` | 31k tris, 1.2 MB | street lamps | 2026-09-21 |
| trashbag | `prop_trashbag.glb` | 4k tris, 0.5 MB | street clutter | 2026-09-21 |
| outdoor_table_chair_set_01 | `prop_patio_set.glb` | 10k tris, 1.2 MB | cafe and patio seating | 2026-09-21 |
| island_tree_01 | `tree_a.glb` | 44k (from 1.6M, `tools/decimate_tree.py`) | street and park trees | 2026-09-19 |
| island_tree_02 | `tree_b.glb` | 40k (from 890k) | street and park trees | 2026-09-19 |
| tree_small_02 | `tree_c.glb` | 40k (from 2.0M) | street and park trees | 2026-09-19 |
| namaqualand_boulder_02 | `rock_a.glb` | 3.5k (from 98k) | hill boulders (flat) | 2026-09-19 |
| namaqualand_boulder_04 | `rock_b.glb` | 3.5k (from 59k) | hill boulders (tall) | 2026-09-19 |
| wild_rooibos_bush (5 variants) | `plant_rooibos.glb` | 1k to 13k | dry scrub on the hills | 2026-09-19 |
| grass_medium_02 (5 variants) | `grass_tuft.glb` | 0.7k to 2.5k | grass tufts on the hills | 2026-09-19 |
| exterior_aircon_unit (clean + rusted) | `prop_ac.glb` | 9.5k per variant | rooftop air conditioning units | 2026-09-20 |

Trees and rocks are reduced with `tools/decimate_tree.py` (pymeshlab quadric decimation that keeps
the UVs for trunks, twigs and rocks; every kept leaf becomes one textured card in its best-fit
plane, scaled up to keep the canopy full). Poly Haven's `boulder_01` and `searsia_burchellii`
would not decimate below 40k (UV seams on every edge) and were dropped.

## Fonts

| Font | Source URL | License | Used for | Added |
|---|---|---|---|---|
| Inter 4.1 SemiBold and Medium (`extras/woff-hinted/Inter-SemiBold.woff2`, `Inter-Medium.woff2` from the release zip) | https://github.com/rsms/inter/releases/tag/v4.1 | SIL Open Font License 1.1 (text in `assets/fonts/Inter-OFL.txt`) | weapon wheel names and hints (`scripts/ui/weapon_wheel.gd`); falls back to Godot's default font if missing | 2026-09-24 |
