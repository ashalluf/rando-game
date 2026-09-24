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
| Fabric036 (1K JPG: Color, NormalGL, Roughness) | https://ambientcg.com/a/Fabric036 | CC0 1.0 | facade kit: shop awning canvas (`fabric`) | 2026-09-24 |
| Metal016 | https://ambientcg.com/a/Metal016 | CC0 1.0 | facade kit: painted steel - AC units, rooftop units, vents, fire escapes, railings (`metal_painted`) | 2026-09-24 |
| Planks023A | https://ambientcg.com/a/Planks023A | CC0 1.0 | facade kit: rooftop water tank staves and roof (`planks`) | 2026-09-24 |
| Fabric048 | https://ambientcg.com/a/Fabric048 | CC0 1.0 | encampment kit: tent nylon, camp chair and duffel canvas (`camp_nylon`) | 2026-09-24 |
| Fabric015 | https://ambientcg.com/a/Fabric015 | CC0 1.0 | encampment kit: woven poly tarps (`camp_tarp`) | 2026-09-24 |
| Cardboard001 | https://ambientcg.com/a/Cardboard001 | CC0 1.0 | encampment kit: flattened boxes and cartons (`camp_cardboard`) | 2026-09-24 |
| Fabric040 | https://ambientcg.com/a/Fabric040 | CC0 1.0 | encampment kit: mattress ticking (`camp_ticking`) | 2026-09-24 |
| Fabric031 | https://ambientcg.com/a/Fabric031 | CC0 1.0 | encampment kit: blankets and quilts (`camp_wool`) | 2026-09-24 |
| Plastic006 | https://ambientcg.com/a/Plastic006 | CC0 1.0 | encampment kit: trash-bag film (`camp_plastic`) | 2026-09-24 |

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

## Facade detail kit (our own tool, no external source)

`assets/models/facade_kit.glb` is written by `tools/facade_kit.py`, run headless in Blender 4.2
(`blender -b --python tools/facade_kit.py`), so like the cars below the script *is* the model and
the `.glb` is build output: rerun it, then `godot --headless --path . --import` before looking at
anything (a cached import is served otherwise). Seventeen pieces, one node each, modelled from
profiles and bevelled solids, with ambient occlusion baked in Cycles against a stand-in wall or
roof and stored in UV2. Materials are the CC0 sets above (`concrete` for stone, and the three
ambientCG sets added for it); the glTF materials only carry names, which
`PropFactory.kit_material()` maps to `shaders/facade_kit.gdshader`.

| Piece | Triangles | Used for | Added |
| --- | --- | --- | --- |
| `kit_cornice_classic` | 292 per 2 m | brick and stucco rooflines: bead, frieze, cove, dentils, ovolo, corona with drip, cyma crown | 2026-09-24 |
| `kit_cornice_bracket` | 526 per 2 m | brick rooflines: Italianate cornice on scroll consoles | 2026-09-24 |
| `kit_cornice_simple` | 42 per 2 m | stucco, precast and low buildings | 2026-09-24 |
| `kit_coping` | 42 per 2 m | parapet coping stones, with drips both sides | 2026-09-24 |
| `kit_surround_brick_a` / `_b` | 78 / 94 | brick punched and slot windows: stone sill with lugs and drip, keystone lintel / lintel with end blocks | 2026-09-24 |
| `kit_surround_stucco` | 194 | stucco windows: moulded architrave, frieze, hood cornice, sill on corbels | 2026-09-24 |
| `kit_ac_window` | 362 | window air conditioners on residential punched windows | 2026-09-24 |
| `kit_awning` | 50 | shop awnings, one per shop run (plain or striped) | 2026-09-24 |
| `kit_balcony` | 524 | balconies: moulded slab on corbels, iron railing | 2026-09-24 |
| `kit_fe_stair_l` / `_r` / `kit_fe_bottom` | 668 / 668 / 576 | fire-escape landings with stairs (both hands) and the drop-ladder landing | 2026-09-24 |
| `kit_water_tank` | 998 | timber rooftop tank on a braced steel stand | 2026-09-24 |
| `kit_vent_mushroom` / `kit_vent_turbine` | 188 / 238 | roof vents | 2026-09-24 |
| `kit_hvac` | 942 | packaged rooftop units on big roofs | 2026-09-24 |

## Encampment kit (our own Blender generator)

`assets/models/encampment_kit.glb` is written by `tools/encampment_kit.py`, run headless in
Blender 4.2 (`blender -b -t 2 --factory-startup --python tools/encampment_kit.py`, `-- --no-bake`
skips the AO bake for a fast shape loop), then `godot --headless --path . --import`. Like the
facade kit the script is the model: every piece is bmesh in metres, UVs in metres (the shader
tiles the CC0 sets above at their real scale), ambient occlusion baked in Cycles against a
ground plane into UV2.x. The glTF materials only carry names, which `PropFactory.camp_material()`
maps to `shaders/encampment.gdshader` / `encampment_2side.gdshader` (colour per instance, faded
by the sun per instance, grime, stains). For the downtown encampments (`Encampment`).

| Piece | Triangles | Used for | Added |
| --- | --- | --- | --- |
| `camp_tent_dome` | 2696 | two-pole dome tent with a sagging fly, door zipped half open, guy lines | 2026-09-24 |
| `camp_tent_pop` | 2624 | pop-up tent, lower and rounder, with a bathtub floor | 2026-09-24 |
| `camp_tarp_canopy` | 1516 | tarp roped from a wall to two sticks over a pitch | 2026-09-24 |
| `camp_tarp_mound` | 2280 | tarp thrown over a heap of belongings, tied down | 2026-09-24 |
| `camp_cart` | 2164 | wire shopping cart with a bagged load | 2026-09-24 |
| `camp_bag_trash` / `camp_bag_duffel` / `camp_bags_pile` | 480 / 368 / 1808 | trash bags, a duffel, a heap of both | 2026-09-24 |
| `camp_mattress` | 1928 | sagging stained mattress | 2026-09-24 |
| `camp_bedding` | 1488 | rucked blankets and a pillow | 2026-09-24 |
| `camp_cardboard` / `camp_box` | 144 / 68 | flattened cardboard bed, a carton | 2026-09-24 |
| `camp_chair` | 680 | folding camp chair | 2026-09-24 |
| `camp_bicycle` | 2772 | whole bicycle leant on its side | 2026-09-24 |
| `camp_bike_wheel` / `camp_bike_frame` | 916 / 940 | loose wheels and stripped frames | 2026-09-24 |

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

## Civic landmark models (our own Blender generator)

The concert hall of the downtown civic centre (2026-09-24, landmark `concert_hall`, named SYMPHONY
HALL in game). Written by `tools/make_concert_hall.py`, run in Blender 4.2 (`blender -b
--factory-startup --python tools/make_concert_hall.py`), so the script is the model and the `.glb`
is build output; no external input at all. The FORM of downtown's steel concert hall - curving
sails round an auditorium box - composed for this game, not traced from the real building's
drawings. Untextured: three material slots bound by name in `LandmarkCivicCenter._concert_hall()`
(`steel` -> `shaders/brushed_steel.gdshader`, `glass` -> `shaders/curtain_glass.gdshader`, `stone`
-> `shaders/landmark_facade.gdshader`), UVs in metres so the shader lays the panel seams. Godot
generates the LODs on import. Every other civic landmark (the arena, the entertainment plaza, the
hotel, the convention centre, city hall, the park, the museum, the station) is built in code by
`LandmarkGeo` and uses only the CC0 texture sets already listed above.

| Model | Nodes | Triangles | Used for | Added |
|---|---|---|---|---|
| `concert_hall.glb` | `ConcertHall` (12 sails, the auditorium core and its base, the entrance glazing), `Collision` (never drawn: a trimesh shape) | 36.2k drawn; 0.7k collision | `LandmarkCivicCenter` (`concert_hall`) | 2026-09-24 |

## The hero (Blender + MPFB2, CC0 assets)

`assets/models/hero.glb` (and the `hero_hero_*` textures Godot extracts from it) is the player's
body, built in Blender 4.2 with the MPFB 2.0.17 add-on (https://extensions.blender.org/add-ons/mpfb/,
code GPLv3; its bundled assets and its output are CC0, LICENSE.md sections C and D).

| Part | Source | License |
|---|---|---|
| Base mesh, body/face shape targets, "mixamo" rig and weights | MPFB 2.0.17 | CC0 |
| Skin `middleage_caucasian_male` (re-tinted, stubble and scalp painted), eyes `high-poly` + `brown`, `eyebrow009`, `eyelashes02`, hair `short04`, `shoes05` mesh | MakeHuman system asset pack, https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip | CC0 |
| Tracksuit, piping, zip, rib bands, tank, gold rope chain, watch, ring, all fold maps and procedural textures | Our own Blender scripts | ours |
| Shoe texture | Painted from scratch (the pack's photo texture was of a branded three-stripe shoe and was discarded) | ours |
| Idle / walk / run clips | Retargeted from our own `pedestrian_d_anim.glb` | ours |

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
| American police siren in Washington DC (lezer, via pdsounds.org) | https://commons.wikimedia.org/wiki/File:American_police_siren_i.ogg | Public domain | `assets/audio/siren_0` (one wail cycle, 17.62-22.78 s of the recording, band-passed 380 Hz - 6 kHz, level flattened, cross-faded into a seamless loop, mono 44.1 kHz; the Ogg Skeleton track dropped) | 2026-09-24 |
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

## City ambience audio (Freesound, CC0)

The layered city sound (`scripts/util/ambience.gd`, `Sfx.AMBIENCE_SAMPLES`), added 2026-09-24.
Every clip is a Freesound recording whose own page states **Creative Commons 0** and links only
the CC0 1.0 deed (checked page by page, saved with the download); descriptions were read too,
and two first picks were dropped on them: `160570` (a San Gabriel mockingbird, whose page says
CC0 but whose description makes credit a condition of use) and `705395` (a distant police siren
whose description says it is AI-generated). CC0 asks for no attribution; it is given here anyway.

Processing (a scratch tool, not in the repo; numpy + scipy + soundfile): the HQ preview (128 kbps
MP3) of each recording, 4th-order zero-phase high/low-pass, resampled, then either **a loop** -
the steadiest stretch (least level variance, no spike 6 dB over its median; gusty wind and big
surf also want matching levels at both ends), cross-faded over its last 2.5 s into its start
(equal power), levelled to -22 dB RMS with a soft knee on the peaks, 32 kHz Vorbis - or **a
one-shot** - the stated span, faded, peak -1 dB, 44.1 kHz mono Vorbis (the far sirens 32 kHz).
Pass-bys are cut so their loudest instant sits 1.2 s in (`Ambience.pass_peak_seconds`). Mono
sources for stereo beds are made wide by two different stretches of the same recording, one per
side ("left/right" below), or by the loop against itself half a turn later (birds). Emitters
(freeway, surf, airport, port) and one-shots are mono. Total added: about 5 MB.

| Recording (Freesound user) | Source URL | License | Clips (span of the recording used) | Added |
|---|---|---|---|---|
| 11 minutes of city sounds (LookIMadeAThing) | https://freesound.org/s/250270/ | CC0 1.0 | `amb_city_0` 351.5-382.0 s (left) and 385.0-415.5 s (right) | 2026-09-24 |
| Downtown LA, Little Tokyo, late night semi distant traffic.wav (janbezouska) | https://freesound.org/s/330427/ | CC0 1.0 | `amb_city_far_0` 33.0-63.5 s | 2026-09-24 |
| Shopping Street Ambience (florianreichelt) | https://freesound.org/s/451734/ | CC0 1.0 | `amb_crowd_0` 0.0-28.5 s | 2026-09-24 |
| GoldenGatePark_Birds.mp3 (Andron827) | https://freesound.org/s/142938/ | CC0 1.0 | `amb_birds_0` 12.0-40.5 s | 2026-09-24 |
| AMBIENCE NIGHT FIELD CRICKET 01.wav (sengjinn) | https://freesound.org/s/175020/ | CC0 1.0 | `amb_crickets_0` 19.0-45.5 s | 2026-09-24 |
| Strong wind blowing in the plain in Anatolia (Turkey) (felix.blume) | https://freesound.org/s/167684/ | CC0 1.0 | `amb_gale_0` 0.0-30.5 s | 2026-09-24 |
| Heavy Rain Sound - Inu Etc.mp3 (inuetc) | https://freesound.org/s/507902/ | CC0 1.0 | `amb_rain_heavy_0` 15.0-41.5 s (left) and 0.0-26.5 s (right) | 2026-09-24 |
| Rain falling on a metal roof - 96 kHz / 24 Bit (GregorQuendel) | https://freesound.org/s/239939/ | CC0 1.0 | `amb_rain_roof_0` 21.0-45.5 s | 2026-09-24 |
| Hard Rain on Car Roof.wav (eRobb4) | https://freesound.org/s/344460/ | CC0 1.0 | `amb_rain_car_0` 0.0-24.5 s | 2026-09-24 |
| Hwy 134 in Burbank (Binaural).wav (courter) | https://freesound.org/s/448092/ | CC0 1.0 | `amb_freeway_0` 77.5-108.0 s | 2026-09-24 |
| Big waves hit land.wav (straget) | https://freesound.org/s/412308/ | CC0 1.0 | `amb_surf_0` 5.5-38.0 s | 2026-09-24 |
| Newark airport outside.wav (dncnbwrs) | https://freesound.org/s/369508/ | CC0 1.0 | `amb_airport_0` 22.0-50.5 s | 2026-09-24 |
| Distant harbour noise in a windy night, Hamburg Landungsbrücken (Pfannkuchn) | https://freesound.org/s/342878/ | CC0 1.0 | `amb_port_0` 49.5-80.0 s | 2026-09-24 |
| car_idle_ext_loop.wav (AndrewAlexander) | https://freesound.org/s/369054/ | CC0 1.0 | `car_roll_0` 0.2-4.2 s | 2026-09-24 |
| car horn.wav (keweldog) | https://freesound.org/s/182474/ | CC0 1.0 | `horn_far_0` 0.55-2.20 s | 2026-09-24 |
| Car Honking (MicktheMicGuy) | https://freesound.org/s/434878/ | CC0 1.0 | `horn_far_1` 0.00-0.75 s | 2026-09-24 |
| Car horn beep beep two beeps honk honk (AmishRob) | https://freesound.org/s/423990/ | CC0 1.0 | `horn_far_2` 0.05-0.70 s | 2026-09-24 |
| 05 Horn.wav (15HPanska_Ruttner_Jan) | https://freesound.org/s/461679/ | CC0 1.0 | `horn_far_3` 0.45-2.50 s | 2026-09-24 |
| Car Horn Honk.wav (DeVern) | https://freesound.org/s/349922/ | CC0 1.0 | `horn_far_4` 1.40-3.10 s | 2026-09-24 |
| Angry big dog barking - Far [d15].wav (v23) | https://freesound.org/s/440865/ | CC0 1.0 | `dog_0` 0.70-2.80 s; `dog_1` 4.95-7.10 s; `dog_2` 8.55-9.90 s | 2026-09-24 |
| distant_dog.wav (Heigh-hoo) | https://freesound.org/s/54545/ | CC0 1.0 | `dog_3` 2.85-5.35 s | 2026-09-24 |
| bus coach ext pull up brake air release idle.wav (kyles) | https://freesound.org/s/454420/ | CC0 1.0 | `bus_hiss_0` 3.90-6.40 s; `bus_hiss_1` 10.60-12.80 s | 2026-09-24 |
| air brake sound effect (okpato123) | https://freesound.org/s/801435/ | CC0 1.0 | `bus_hiss_2` 0.90-2.30 s | 2026-09-24 |
| Distant Ambulance Siren (brunoboselli) | https://freesound.org/s/469363/ | CC0 1.0 | `siren_far_0` 1.80-17.80 s | 2026-09-24 |
| 200829 Sirens, distant, ambulence, police, urban echoes roof, stops 9am.flac (TRP) | https://freesound.org/s/568814/ | CC0 1.0 | `siren_far_1` 1.50-17.50 s | 2026-09-24 |
| Gull.wav (nigelcoop) | https://freesound.org/s/73497/ | CC0 1.0 | `gull_0` 0.30-3.50 s | 2026-09-24 |
| Seagulls_short.wav (Lydmakeren) | https://freesound.org/s/510917/ | CC0 1.0 | `gull_1` 3.90-6.40 s; `gull_2` 6.40-9.00 s | 2026-09-24 |
| Seagull on beach (squashy555) | https://freesound.org/s/353416/ | CC0 1.0 | `gull_3` 0.00-2.60 s; `gull_4` 9.00-11.60 s | 2026-09-24 |
| coyote barks and howls (dkaufman) | https://freesound.org/s/256533/ | CC0 1.0 | `coyote_0` 12.50-19.20 s; `coyote_1` 0.25-2.60 s | 2026-09-24 |
| coyotes howling (SamsterBirdies) | https://freesound.org/s/640060/ | CC0 1.0 | `coyote_2` 20.00-28.00 s | 2026-09-24 |
| ship horn.wav (monotraum) | https://freesound.org/s/208714/ | CC0 1.0 | `ship_horn_0` 11.00-17.50 s | 2026-09-24 |
| Ship Horn.mp3 (Grotelue) | https://freesound.org/s/64601/ | CC0 1.0 | `ship_horn_1` 0.00-6.20 s | 2026-09-24 |
| Ship Horn - Fog Horn - Cruise Ship Grand Princess (coalcon) | https://freesound.org/s/636075/ | CC0 1.0 | `ship_horn_2` 0.00-6.00 s | 2026-09-24 |
| Four quiet distant clangs.aiff (Danjocross) | https://freesound.org/s/507465/ | CC0 1.0 | `crane_0` 1.45-3.30 s; `crane_1` 5.65-7.40 s; `crane_2` 9.60-11.30 s | 2026-09-24 |
| backing up beep.wav (C-V) | https://freesound.org/s/523413/ | CC0 1.0 | `crane_3` 0.25-3.80 s | 2026-09-24 |
| Car passing by.wav (hinzebeat) | https://freesound.org/s/171447/ | CC0 1.0 | `car_pass_0` 0.35-3.15 s | 2026-09-24 |
| One car passing by (JPBILLINGSLEYJR) | https://freesound.org/s/465397/ | CC0 1.0 | `car_pass_1` 4.10-6.90 s | 2026-09-24 |
| Car Passing (Johnnyfarmer) | https://freesound.org/s/209767/ | CC0 1.0 | `car_pass_2` 0.51-3.31 s | 2026-09-24 |
| PassingCar01.wav (Pingel) | https://freesound.org/s/3179/ | CC0 1.0 | `car_pass_3` 3.45-6.25 s | 2026-09-24 |
| Passing Car (Wet road) (Breviceps) | https://freesound.org/s/462862/ | CC0 1.0 | `car_pass_wet_0` 1.40-4.20 s | 2026-09-24 |

## Fonts

| Font | Source URL | License | Used for | Added |
|---|---|---|---|---|
| Inter 4.1 SemiBold and Medium (`extras/woff-hinted/Inter-SemiBold.woff2`, `Inter-Medium.woff2` from the release zip) | https://github.com/rsms/inter/releases/tag/v4.1 | SIL Open Font License 1.1 (text in `assets/fonts/Inter-OFL.txt`) | weapon wheel names and hints (`scripts/ui/weapon_wheel.gd`); falls back to Godot's default font if missing | 2026-09-24 |
