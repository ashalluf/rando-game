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
| Grass004 | https://ambientcg.com/a/Grass004 | CC0 1.0 | parks, ground; on the hills its blades recoloured to dry straw | 2026-09-19 |
| Ground054 | https://ambientcg.com/a/Ground054 | CC0 1.0 | beach sand | 2026-09-19 |
| MetalPlates006 | https://ambientcg.com/a/MetalPlates006 | CC0 1.0 | warehouses, glass tower spandrels | 2026-09-19 |
| PavingStones138 | https://ambientcg.com/a/PavingStones138 | CC0 1.0 | sidewalks, plazas | 2026-09-19 |
| Rock064 | https://ambientcg.com/a/Rock064 | CC0 1.0 | (kept, no longer on hills) | 2026-09-19 |
| AerialGrassRock (Poly Haven `aerial_grass_rock`, Diffuse/nor_gl/Rough renamed to Color/NormalGL/Roughness) | https://polyhaven.com/a/aerial_grass_rock | CC0 1.0 | hills: its light and dark only, a large-tile mottle over the dry grass (terrain.gdshader) | 2026-09-19 |
| DryGroundRocks (Poly Haven `dry_ground_rocks`, Rob Tuytel; 1K Diffuse/nor_gl/Rough renamed to Color/NormalGL/Roughness) | https://polyhaven.com/a/dry_ground_rocks | CC0 1.0 | hills: bare dirt / decomposed granite on cuts, banks and trails | 2026-09-24 |
| RockFace (Poly Haven `rock_face`, Greg Zaal / Dario Barresi; 1K, renamed as above) | https://polyhaven.com/a/rock_face | CC0 1.0 | hills: rock outcrops on the steepest faces (recoloured buff-grey) | 2026-09-24 |
| RedBrick, Brick4, RedBrick03 (Poly Haven `red_brick`, `brick_4`, `red_brick_03`) | https://polyhaven.com/a/red_brick etc. | CC0 1.0 | brick facades (one per building) | 2026-09-19 |
| PaintedPlasterWall, BeigeWall001, WhitePlaster02, ConcreteWall003 (`painted_plaster_wall`, `beige_wall_001`, `white_plaster_02`, `concrete_wall_003`) | https://polyhaven.com/a/painted_plaster_wall etc. | CC0 1.0 | flat facades | 2026-09-19 |
| CrackedConcreteWall, ConcreteLayers02 (`cracked_concrete_wall`, `concrete_layers_02`) | https://polyhaven.com/a/cracked_concrete_wall etc. | CC0 1.0 | concrete panel facades, glass tower spandrels | 2026-09-19 |
| CorrugatedIron, FactoryWall (`corrugated_iron`, `factory_wall`) | https://polyhaven.com/a/corrugated_iron etc. | CC0 1.0 | warehouses | 2026-09-19 |
| AerialAsphalt01 (`aerial_asphalt_01`) | https://polyhaven.com/a/aerial_asphalt_01 | CC0 1.0 | second asphalt look, per road | 2026-09-19 |
| LargeSquarePattern01, GravelConcrete03 (`large_square_pattern_01`, `gravel_concrete_03`) | https://polyhaven.com/a/large_square_pattern_01 etc. | CC0 1.0 | sidewalk pavers and plain concrete sidewalks, per block | 2026-09-19 |
| Fabric036 (1K JPG: Color, NormalGL, Roughness) | https://ambientcg.com/a/Fabric036 | CC0 1.0 | facade kit: shop awning canvas (`fabric`) | 2026-09-24 |
| Metal016 | https://ambientcg.com/a/Metal016 | CC0 1.0 | facade kit: painted steel - AC units, rooftop units, vents, fire escapes, railings (`metal_painted`); detail on the street clutter's painted steel (news boxes, racks, A-frames) | 2026-09-24 |
| Planks023A | https://ambientcg.com/a/Planks023A | CC0 1.0 | facade kit: rooftop water tank staves and roof (`planks`) | 2026-09-24 |
| ClayRoofTiles02 (Poly Haven `clay_roof_tiles_02`, 1K JPG, Diffuse/nor_gl/Rough renamed to Color/NormalGL/Roughness) | https://polyhaven.com/a/clay_roof_tiles_02 | CC0 1.0 | Esplanade replica: the houses' hipped and gabled barrel-tile roofs (`roof_clay`, tinted per house) | 2026-09-24 |
| Fabric048 | https://ambientcg.com/a/Fabric048 | CC0 1.0 | encampment kit: tent nylon, camp chair and duffel canvas (`camp_nylon`) | 2026-09-24 |
| Fabric015 | https://ambientcg.com/a/Fabric015 | CC0 1.0 | encampment kit: woven poly tarps (`camp_tarp`) | 2026-09-24 |
| Cardboard001 | https://ambientcg.com/a/Cardboard001 | CC0 1.0 | encampment kit: flattened boxes and cartons (`camp_cardboard`) | 2026-09-24 |
| Fabric040 | https://ambientcg.com/a/Fabric040 | CC0 1.0 | encampment kit: mattress ticking (`camp_ticking`) | 2026-09-24 |
| Fabric031 | https://ambientcg.com/a/Fabric031 | CC0 1.0 | encampment kit: blankets and quilts (`camp_wool`) | 2026-09-24 |
| Plastic006 | https://ambientcg.com/a/Plastic006 | CC0 1.0 | encampment kit: trash-bag film (`camp_plastic`) | 2026-09-24 |
| Climbing plants and garden accents atlas (`assets/textures/climbers/climbers_albedo.png`, `climbers_normal.png`) | original, painted procedurally by `tools/make_climbers.py` (parametric leaf outlines, bracts, flowers, agave / aloe blades; no photo or third-party art) | project | `ClimbingPlants` (bougainvillea, ivy, creeping fig, star jasmine, wisteria, grape, trumpet vine, agave, aloe, red-hot poker, lavender, lantana) | 2026-10-05 |
| Street HDRI for reflections (`assets/textures/sky/street_hdri.png`, 1024 x 512 RGBA: the scene relative to its street's mean, its own sky cut out in alpha; made by `tools/reflections/make_street_hdri.py` from the 2K .hdr, fetched from the three.js mirror `raw.githubusercontent.com/mrdoob/three.js/dev/examples/textures/equirectangular/san_giuseppe_bridge_2k.hdr` because polyhaven.com is blocked here) | Poly Haven `san_giuseppe_bridge`, https://polyhaven.com/a/san_giuseppe_bridge | CC0 1.0 | `sky.gdshader` `street_hdri` (Forward+ only): what reflections out of every reflection probe's reach mirror under the horizon | 2026-10-05 |

Texture sets are from ambientCG and Poly Haven (both CC0 1.0 Universal, no attribution required,
attribution given anyway). Only the Color, NormalGL and Roughness maps at 1K are kept, under `assets/textures/<Set>/`.

## Generated 3D models (Meshy)

Made with the owner's Meshy account through the API (`python3 tools/meshy.py gen ...`): Meshy's
latest standard model, ~8000 faces after remesh, refined with 2K PBR textures, then shrunk to 1K
JPEG with `tools/shrink_glb.py`. Every prompt asks for the most realistic result (owner's rule). Rights follow the owner's Meshy plan (paid plans: owner owns the output;
free plan: CC BY 4.0). Each `.json` next to a model records its prompt, Meshy task ids and credits.

| Model | Files | Credits | Used for | Added |
|---|---|---|---|---|
| Sedan | `assets/models/car_sedan.glb` | 30 (+15 for a first low-poly take) | nothing since 2026-09-27 (replaced by `road_sedan.glb`) | 2026-09-19 |
| Pickup | `assets/models/car_pickup.glb` | 30 (+15) | nothing since 2026-09-27 (replaced by `road_pickup.glb`) | 2026-09-19 |
| Van | `assets/models/car_van.glb` | 30 (+15) | nothing since 2026-09-27 (replaced by `road_van.glb`) | 2026-09-19 |
| Sports | `assets/models/car_sports.glb` | 30 (+15) | `Vehicle` body, SPORTS | 2026-09-19 |
| Pedestrian A (man, t-shirt) | `assets/models/pedestrian_a.glb`, `pedestrian_a_anim.glb` (rigged: Idle, Casual_Walk_inplace, run_fast_3_inplace) | 44 (+29) | **unused** | 2026-09-19 |
| Pedestrian B (woman, hoodie) | `pedestrian_b.glb`, `pedestrian_b_anim.glb` (same clips) | 44 (+29) | **unused** | 2026-09-19 |
| Pedestrian C (older man, shirt) | `pedestrian_c.glb`, `pedestrian_c_anim.glb` (same clips) | 44 (+29) | **unused** | 2026-09-19 |
| Pedestrian D (young man, vest, white sneakers) | `pedestrian_d_anim.glb` (rigged, same clips, 16k faces) | 44 | the clip source the hero and the crowd are retargeted from (not loaded since 2026-09-27) | 2026-09-22 |
| Pedestrian E (woman, denim jacket) | `pedestrian_e_anim.glb` (same) | 44 | **unused** since 2026-09-27 (the crowd below) | 2026-09-22 |
| Pedestrian F (older man, grey suit) | `pedestrian_f_anim.glb` (same) | 44 | **unused** since 2026-09-27 (the crowd below) | 2026-09-22 |
| Pedestrian G (woman, white top, ponytail) | `pedestrian_g_anim.glb` (same) | 44 | **unused** since 2026-09-27 (the crowd below) | 2026-09-22 |
| Pedestrian H (older man, jacket, khakis) | `pedestrian_h_anim.glb` (same) | 44 | **unused** since 2026-09-27 (the crowd below) | 2026-09-22 |
| Pedestrian I (young man, cap) | `pedestrian_i_anim.glb` (same) | 44 | **unused** since 2026-09-27 (the crowd below) | 2026-09-22 |
| Pedestrian J (Black man, grey hoodie, jeans) | `pedestrian_j_anim.glb` (same) | 44 | **unused** since 2026-09-27 (the crowd below) | 2026-09-22 |
| Pedestrian K (Black woman, yellow blazer) | `pedestrian_k_anim.glb` (same) | 44 | **unused** since 2026-09-27 (the crowd below) | 2026-09-22 |
| Pedestrian L (Latino man, navy shirt, cargo trousers) | `pedestrian_l_anim.glb` (same) | 44 | **unused** since 2026-09-27 (the crowd below) | 2026-09-22 |
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
brightened (`tools/shrink_glb.py --desaturate`) so the seeded paint tint gives the color, and
their normals re-smoothed by angle (`tools/smooth_normals.py`, 45 degrees; the export split
them at 30 degrees and on every UV seam, which shaded the bodies as facets).

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
## Traffic signals (our own tool, no external source)

`assets/models/traffic_signal.glb` is written by `tools/make_signals.py`, run headless in Blender
4.2 (`blender -b --factory-startup --python tools/make_signals.py`); the script is the model and
the `.glb` is build output (rerun it, then `godot --headless --path . --import`). Seven pieces,
one node each, every hard edge bevelled with face-area weighted normals. No textures of its
own: `PropFactory.signal_material()` puts the CC0 `metal_painted` and `concrete` sets above on
the named glTF materials, and the lenses are `shaders/traffic_signal.gdshader` (LED lamps, and
the pedestrian glyphs - an original raised hand and walking figure - drawn from distance
fields). Original design; no real signal maker's hardware or symbol artwork is copied.

| Piece | Triangles | Used for | Added |
| --- | --- | --- | --- |
| `sig_pole` | 1,376 | tapered galvanised pole, bolted base plate and cover, handhole, arm collar | 2026-09-24 |
| `sig_arm` | 404 | the mast arm (8 m, scaled along its length per approach) | 2026-09-24 |
| `sig_head` | 2,132 | three-lamp vehicle head: tunnel visors, bezels, domed lenses, yellow-bordered backplate, hanger | 2026-09-24 |
| `sig_bracket` | 128 | side-mount arm for the head low on the pole | 2026-09-24 |
| `sig_ped` | 980 | pedestrian head: hood, glyph panel and countdown panel | 2026-09-24 |
| `sig_button` | 328 | push-button station with its sign | 2026-09-24 |
| `sig_cabinet` | 740 | signal controller cabinet on a concrete pad | 2026-09-24 |

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
| `tools/make_road_cars.py` | `road_sedan.glb` | 53k tris + 8k far twin | `BodyType.SEDAN` (and the police cruiser) | 2026-09-27 |
| `tools/make_road_cars.py` | `road_crossover.glb` | 50k tris + 8k far twin | `BodyType.CROSSOVER` | 2026-09-27 |
| `tools/make_road_cars.py` | `road_pickup.glb` | 56k tris + 8k far twin (reworked the same day: tall square cab, high flat bonnet, 1.71 m bed) | `BodyType.PICKUP` | 2026-09-27 |
| `tools/make_road_cars.py` | `road_van.glb` | 51k tris + 8k far twin | `BodyType.VAN` (and the police tactical van) | 2026-09-27 |
| `tools/make_more_cars.py` | `road_hatchback.glb` | 51k tris + 8k far twin | `BodyType.HATCHBACK` | 2026-10-05 |
| `tools/make_more_cars.py` | `road_suv.glb` | 48k tris + 8k far twin | `BodyType.SUV` | 2026-10-05 |
| `tools/make_more_cars.py` | `road_minivan.glb` | 52k tris + 8k far twin | `BodyType.MINIVAN` | 2026-10-05 |
| `tools/make_more_cars.py` | `road_taxi.glb` | 54k tris + 8k far twin (the sedan + a lit roof sign, `taxi_sign` slot) | `BodyType.TAXI` | 2026-10-05 |
| `tools/make_more_cars.py` | `road_beater.glb` | 51k tris + 8k far twin (a dent and a cracked, taped tail lamp in the geometry) | `BodyType.BEATER` | 2026-10-05 |
| `tools/make_emergency_vehicles.py` | `road_fire_engine.glb` | 35k tris + 10k far twin (Type 1 pumper: crew cab, pump panel, roll-ups, hose bed, ladders, light bar, Q-siren; original, no department's marks) | `BodyType.FIRE_ENGINE` (EmergencyCar) | 2026-10-04 |
| `tools/make_emergency_vehicles.py` | `road_ambulance.glb` | 23k tris + 10k far twin (Type III: cutaway cab, modular box, striping, chevrons, warning lamps; original) | `BodyType.AMBULANCE` (EmergencyCar) | 2026-10-04 |
| `tools/make_school_bus.py` | `road_school_bus.glb` | 54k tris + 10k far twin (Type D transit-style school bus: split-sash windows, eight-way warning lamps, rub rails, STOP arm, crossing arm, rear emergency door, the invented RANDO UNIFIED SCHOOL DISTRICT lettering; Blender's built-in font; original, no maker's shapes or badges) | `BodyType.SCHOOL_BUS` (Schools) | 2026-10-05 |
| `tools/make_service_vehicles.py` | `road_garbage.glb` | 44k tris + 10k far twin (side loader on the box truck's cab: hopper, ribbed packer body, tailgate, the arm as `rig_boom` / `rig_lift`; original, no fleet's marks) | `BodyType.GARBAGE_TRUCK` (ServiceVehicles) | 2026-10-05 |
| `tools/make_service_vehicles.py` | `road_sweeper.glb` | 47k tris + 10k far twin (debris hopper, water tank, gutter brooms `rig_brush_r/l`, main broom `rig_broom`; original) | `BodyType.STREET_SWEEPER` | 2026-10-05 |
| `tools/make_service_vehicles.py` | `road_tow.glb` | 40k tris + 10k far twin (rollback deck `rig_bed` with headboard and winch, toolboxes, wheel-lift; original) | `BodyType.TOW_TRUCK` | 2026-10-05 |
| `tools/make_service_vehicles.py` | `road_ice_cream.glb` | 22k tris + 10k far twin (the ambulance's cutaway cab with a box: serving window, awning, menu boards, cone sign, horn; original) | `BodyType.ICE_CREAM_TRUCK` | 2026-10-05 |
| code (`ServiceSounds`) | the service vehicles' sounds | synthesised at load: hydraulic whine, a cart's bang, brushes, winch, and the ice-cream chime - an original tune (`ServiceSounds.TUNE`) | ServiceVehicles | 2026-10-05 |
| code (`KerbBins.mesh()`) | the wheelie carts | 582 / 24 tris, built in code, `shaders/kerb_bin.gdshader` | ServiceFleet | 2026-10-05 |

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

The `road_*` bodies (2026-09-27) are the everyday cars: original generic 2020s designs (a
midsize fastback sedan, a compact crossover, a crew-cab full-size pickup, a high-roof panel van),
no source asset at
all - Blender 4.2 run headless on our own script (`tools/road_cars_setup.sh` fetches it). They
are the `hifi_*` idea with the shape driven by profile curves (side view, plan view, section
insets) instead of a key table, the arches, windows, pockets and panel gaps cut after
subdivision, a seventh slot (`chrome`), no wheel in the full model (the game draws its generated
wheels there) and a two-surface far twin with the far wheel (see CLAUDE.md, car paint note).

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

## Port kit (built in code)

The container terminal's pieces (2026-09-27, roadmap #35) are generated at run time by
`scripts/world/port_kit.gd` - no model files, no textures, no external input. ISO 668 container
dimensions; the shipping lines on the boxes and the ship (RANDO, KAVELL, TORVAN, ZEPRA, OLVANA,
MERIDU, two leasing pools), their marks, owner codes and colour schemes are invented for this
game, drawn by `shaders/container.gdshader` / `port_steel.gdshader` from the stroke font in
`shaders/port_lettering.gdshaderinc`.

| Mesh | Built by | Triangles (LOD ladder) | Used for | Added |
|---|---|---|---|---|
| ISO container (20/40 ft, high-cube by instance scale) | `PortKit.container_mesh()` | 568 / 142 / 12, box shadow twin | port stacks, the ship's deck cargo, crane spreaders | 2026-09-27 |
| Ship-to-shore gantry crane | `PortKit.sts_mesh()` | 3.8k / 1.7k / 0.7k per pose | the south quay | 2026-09-27 |
| Rubber-tyred yard gantry | `PortKit.rtg_mesh()` | 1.4k / 0.7k / 0.4k | over the yard's stacks | 2026-09-27 |
| Container ship hull, accommodation, hatch covers | `PortKit.ship_mesh()` | see `_ship_level()` | `cargo_ship` landmark | 2026-09-27 |
| High mast, bollard, cell fender | `PortKit.mast_mesh()` etc. | 158, 110, 52 | yard and quay | 2026-09-27 |

## Airport kit (built in code)

The airport's hardware and markings (2026-10-04) are generated at run time - no model files, no
textures, no external input. `scripts/world/airport_kit.gd` builds the ground service equipment
and field hardware at real size on `shaders/airport_kit.gdshader`; `scripts/world/airport.gd`
lays the paint (the street paint batch) and the field's lights (one billboard mesh on
`shaders/aircraft_lights.gdshader`); `scripts/world/airport_terminal.gd` builds the buildings
with `LandmarkGeo` on the landmark shaders and the CC0 sets above (`concrete`, `planks`). The six
airlines' liveries (`shaders/airliner_livery.gdshader`, painted on the existing
`jet_airliner.glb` by region of the model) and the terminal's name (RANDO INTERNATIONAL) are
invented for this game; no real carrier's scheme, mark or name.

| Mesh | Built by | Triangles | Used for | Added |
|---|---|---|---|---|
| Pushback tug, baggage tug, baggage cart, belt loader, catering truck (scissor lift raised), fuel truck, ground power unit | `AirportKit.vehicle()` | 400, 418, 432, 400, 442, 466, 356 | round every attended gate | 2026-10-04 |
| Cone, apron floodlight mast, elevated edge light, inset light | `AirportKit.cone()` etc. | 90, 178, 76, 50 | the apron, the runways and taxiways | 2026-10-04 |
| Perimeter fence (post + barbed outrigger, chain-link panel), blast fence panel, localizer element, glide-slope mast, windsock, PAPI unit | `AirportKit.fence_post()` etc. | 72 + 4, 88, 106, 222, 170, 54 | the field's edges and navaids | 2026-10-04 |

## The hero (Blender + MPFB2, CC0 assets)

`assets/models/hero.glb` (and the `hero_hero_*` textures Godot extracts from it, plus the
`hero_x_*` maps beside it that `HeroLook` loads) is the player's body, built by `tools/hero/` in
Blender 4.2 LTS with the MPFB 2.0.17 add-on (https://extensions.blender.org/add-ons/mpfb/, code
GPLv3; its bundled assets and its output are CC0, LICENSE.md sections C and D). Nothing of
MPFB's code ships: `tools/hero/setup.sh` downloads Blender, the add-on and the asset pack into
the ignored `build/hero_src/` on the machine that builds.

| Part | Source | License |
|---|---|---|
| Base mesh, body/face shape targets, "mixamo" rig and weights | MPFB 2.0.17 | CC0 |
| Skin `middleage_caucasian_male` (re-tinted, stubble, scalp and complexion zones painted over it), eyes `high-poly` + `brown`, `eyebrow009`, `eyelashes02`, `shoes05` mesh (uppers only; tongue, eyelets and laces are ours) | MakeHuman system asset pack, https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip | CC0 |
| Hair (about 700 cards grown along a combed flow, strand atlas), tracksuit, piping, zip, rib bands, tank, rope chain, watch, ring, laces, every fold, wrinkle, pore, pile and mask map | Our own scripts (`tools/hero/*.py`) | ours |
| Shoe texture | Painted from scratch (the pack's photo texture was of a branded three-stripe shoe and was discarded) | ours |
| Idle / walk / run clips | Retargeted from our own `pedestrian_d_anim.glb` | ours |

Triangles (LOD0; Godot generates the LODs on import): skin 60.8k, tracksuit 18.0k, rib bands
2.9k, piping 1.6k, zip 0.8k, tank 1.6k, gold (chain, watch case and bracelet, ring) 14.3k, watch
glass and dial 0.4k, eyes 1.1k, brows and lashes 0.6k, hair 12.7k, shoes 2.4k, laces 3.0k: 120.1k
in 15 surfaces, one skinned mesh. His shadow is `hero_shadow`, 9.0k triangles in one surface.
Textures: 2K skin albedo and wrinkle normal, 2K tracksuit albedo and rest and bent fold
normals; 1K or smaller for everything else (skin roughness and mask, hair atlas, shoes), plus
the tiling `hero_x_skin_detail` (pores, stubble) and `hero_x_pile` (velour).

## The crowd (Blender + MPFB2, CC0 assets)

`assets/models/crowd_a.glb` .. `crowd_t.glb` (and the `crowd_*_body.jpg`, `_body_nrm.jpg` and
`_hair.png` Godot extracts from them) are the pedestrians (`Pedestrian.MODELS`), built by
`tools/crowd/` with the hero's toolchain: Blender 4.2 LTS, the MPFB 2.0.17 add-on and the CC0
MakeHuman system asset pack, which `tools/hero/setup.sh` downloads into the ignored
`build/hero_src/` (nothing of MPFB's GPL code ships; its assets and output are CC0). They replace
the nine Meshy pedestrians (`pedestrian_d..l`, rows above), which are no longer loaded.

| Part | Source | License |
|---|---|---|
| Base mesh, body/face shape targets, "mixamo" rig and weights | MPFB 2.0.17 | CC0 |
| Skins, eyes (`low-poly` + an eye material), eyebrows, eyelashes, clothes (`male_casualsuit01..06`, `male_elegantsuit01`, `male_worksuit01`, `female_casualsuit01/02`, `female_elegantsuit01`, `female_sportsuit01`), shoes (`shoes01..06`), hair (`afro01`, `braid01`, `long01`, `ponytail01`, `short01..04`) and their textures | MakeHuman system asset pack, https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip | CC0 |
| Skin blends, garment dyes, printed logos painted out, the painted scalp and crops, skin relief maps, the atlases, relaxed hands, bind pose, the region colours | Our own scripts (`tools/crowd/*.py`) | ours |
| Our own garments (tee, jeans / slim / chinos / leggings / denim shorts / joggers, button shirt and polo, zip jacket / hoodie / cardigan, skirt, hi-vis vest, headscarf): the meshes modelled on each body (`tools/crowd/garments.py`) and every texel of their colour and relief painted procedurally, no source images (`tools/crowd/garment_paint.py`) | Our own scripts | ours |
| Idle / walk / run clips | Retargeted from our own `pedestrian_d_anim.glb` (`tools/hero/retarget_lib.py`) | ours |
| Everyday "life" clips (`assets/models/crowd_life/crowd_*_life.res`, one AnimationLibrary per rig): `Idle_Loop`, `Idle_Talking_Loop`, `Sitting_Enter`, `Sitting_Idle_Loop`, `Sitting_Talking_Loop`, `Sitting_Exit`, `Jog_Fwd_Loop`, `Idle_Torch_Loop` from Universal Animation Library [Standard]; `Idle_TalkingPhone_Loop`, `Idle_FoldArms_Loop`, `Consume`, `Yes`, `Idle_No_Loop`, `Idle_Rail_Loop` from Universal Animation Library 2 [Standard] (Quaternius; the free Standard downloads, License.txt in each zip: CC0 1.0). Retargeted in Godot by `tools/crowd/life_clips.gd` (the jog's leg swing scaled to a jogger's stride, the standing clips' legs settled to the rig's stance); the sources are fetched by `tools/crowd/fetch_life_clips.sh` into the ignored `build/ual_src/` and do not ship | https://quaternius.itch.io/universal-animation-library , https://quaternius.itch.io/universal-animation-library-2 | CC0 1.0 (added 2026-10-04) |
| The hero's moves (`assets/models/hero_moves.res`, one AnimationLibrary added to hero.glb's player as "moves"): `Idle_Loop`, `Jump_Start`, `Jump_Loop`, `Jump_Land`, `Roll`, `Sprint_Loop` from Universal Animation Library [Standard], `NinjaJump_Land` from Universal Animation Library 2 [Standard] (Quaternius, CC0 1.0), retargeted onto the hero's 54-bone rig in Godot by `tools/hero/hero_clips.gd`, with the hero Idle's own finger keys; the four idle variants (`idle_look`, `idle_neck`, `idle_watch`, `idle_stretch`) are keyed in that script over the library's idle. Sources fetched by `tools/crowd/fetch_life_clips.sh`, not shipped | https://quaternius.itch.io/universal-animation-library , https://quaternius.itch.io/universal-animation-library-2 | CC0 1.0 (added 2026-10-05) |
| The dog (`assets/models/dog_shiba.glb`, `CrowdDog`): `ShibaInu.gltf` from Quaternius' Ultimate Animated Animals (glTF folder; License.txt in the pack: CC0 1.0), rewritten as a .glb by Godot's GLTFDocument, unchanged | https://quaternius.com/packs/ultimateanimatedanimals.html | CC0 1.0 (added 2026-10-04) |
| Held props (phone, paper coffee cup, shopping bag, cigarette) | Built in code (`CrowdLife.prop_mesh()`) | ours |

| Model | Person | MakeHuman assets |
|---|---|---|
| `crowd_a.glb` | young Black man, slim and athletic: white tee, mid-wash jeans, white sneakers, close crop | young_african_male, eyes `low-poly` + brown, eyebrow001, eyelashes01, shoes05, no hair mesh (a painted crop); our own tee and jeans |
| `crowd_b.glb` | Latino man in his forties, heavy-set: work overalls over a tee, boots, short dark hair | middleage_caucasian_male 45% + middleage_african_male 35% + middleage_asian_male 20%, eyes `low-poly` + brown, eyebrow010, eyelashes01, male_worksuit01, shoes03, short04 |
| `crowd_c.glb` | white woman in her seventies, slight and short: striped blouse, grey skirt, flat shoes, short grey hair | old_caucasian_female, eyes `low-poly` + lightblue, eyebrow007, eyelashes01, female_elegantsuit01, shoes04, short03; skin toned down |
| `crowd_d.glb` | young East Asian woman: fitted rust tee, black slim jeans, navy sneakers, ponytail | young_asian_female, eyes `low-poly` + brown, eyebrow002, eyelashes01, shoes06, ponytail01; our own tee and slim jeans |
| `crowd_e.glb` | Black woman in her forties, heavy: mustard tee, denim shorts, white sneakers, natural hair | middleage_african_female, eyes `low-poly` + brown, eyebrow003, eyelashes01, shoes05, afro01; our own tee and denim shorts |
| `crowd_f.glb` | young white man, tall: olive field jacket, jeans, grey sneakers, short brown hair | young_caucasian_male, eyes `low-poly` + bluegreen, eyebrow006, eyelashes01, male_casualsuit05, shoes02, short04 |
| `crowd_g.glb` | Black man in his seventies: dark suit, dress shoes, short grey hair | old_african_male, eyes `low-poly` + brown, eyebrow009, eyelashes01, male_elegantsuit01, shoes04, short01 |
| `crowd_h.glb` | East Asian man in his forties: blue-and-white pinstripe button shirt, grey jeans, brown leather shoes, short side part | middleage_asian_male, eyes `low-poly` + brown, eyebrow004, eyelashes01, shoes01, short03; our own shirt and jeans |
| `crowd_i.glb` | young white woman, slim: fitted heather-grey tee, black leggings, white sneakers, long hair | young_caucasian_female, eyes `low-poly` + green, eyebrow005, eyelashes01, shoes05, long01; our own tee and leggings |
| `crowd_j.glb` | white man in his fifties, heavy, close-cropped: chambray shirt with the sleeves rolled, dark jeans, brown shoes | middleage_caucasian_male, eyes `low-poly` + blue, eyebrow011, eyelashes01, shoes01, no hair mesh (a painted crop); our own shirt and jeans |
| `crowd_k.glb` | young Latina woman: fitted teal tee, light-wash jeans, navy sneakers, braid | young_caucasian_female 45% + young_african_female 35% + young_asian_female 20%, eyes `low-poly` + brown, eyebrow002, eyelashes01, shoes06, braid01; our own tee and jeans |
| `crowd_l.glb` | East Asian man in his seventies: maroon long-sleeve tee, charcoal chinos, black shoes, short grey hair | old_asian_male, eyes `low-poly` + brown, eyebrow008, eyelashes01, shoes04, short01; our own long-sleeve tee and chinos |
| `crowd_m.glb` | white man in his seventies, tall and thin, a little stooped: navy windbreaker, stone chinos, brown shoes, thin grey hair | old_caucasian_male, eyes `low-poly` + lightblue, eyebrow005, eyelashes01, shoes01, short02; our own zip jacket (as a windbreaker) and chinos (added 2026-10-05) |
| `crowd_n.glb` | South Asian woman in her sixties, short and heavy: buttoned crew-neck cardigan, mid-calf A-line skirt, flat shoes, short grey-streaked hair | middleage_asian_female 45% + middleage_african_female 30% + middleage_caucasian_female 25%, eyes `low-poly` + brown, eyebrow009, eyelashes01, shoes04, short03; our own cardigan and skirt |
| `crowd_o.glb` | Black teenage boy, slim: pullover hoodie (hood down, drawcords, kangaroo pocket), black joggers with rib cuffs, grey sneakers, short hair | young_african_male, eyes `low-poly` + brown, eyebrow002, eyelashes01, shoes02, short02; our own hoodie and joggers |
| `crowd_p.glb` | white teenage girl, slim: fitted lilac tee, olive A-line skirt above the knee, white sneakers, auburn ponytail | young_caucasian_female2, eyes `low-poly` + green, eyebrow006, eyelashes01, shoes05, ponytail01; our own tee and skirt |
| `crowd_q.glb` | Latino man in his thirties, tall and heavy: navy pique polo, khaki chino shorts, grey sneakers, short black hair | young_caucasian_male 40% + young_african_male 30% + young_asian_male 30%, eyes `low-poly` + brown, eyebrow010, eyelashes01, shoes02, short04; our own polo and shorts |
| `crowd_r.glb` | young North African woman: dusty rose headscarf worn hijab-style, long cream tee, navy wide trousers, navy sneakers | young_caucasian_female 60% + young_african_female 28% + young_asian_female 12%, eyes `low-poly` + brown, eyebrow001, eyelashes01, shoes06, no hair mesh (the headscarf covers it); our own headscarf, tee and trousers |
| `crowd_s.glb` | Filipino man in his thirties, very short and stocky: hi-vis safety vest over a heather-grey tee, charcoal work trousers, boots, short black hair | young_asian_male 70% + young_african_male 20% + young_caucasian_male 10%, eyes `low-poly` + brown, eyebrow004, eyelashes01, shoes03, short01; our own vest, tee and trousers |
| `crowd_t.glb` | very tall Black woman in her thirties: red-striped white shirt with the sleeves rolled, black slim trousers, white sneakers, a braid | young_african_female, eyes `low-poly` + brown, eyebrow003, eyelashes01, shoes05, braid01; our own shirt and slim trousers |

Each is ONE skinned `Body` (skin, eyes, clothes, shoes; 10.5-13.8k triangles, one 2K colour atlas
and a 1K normal atlas, the vertex colour carrying the skin / top / bottom / hair split) and a
`Hair` mesh of cut-out cards, brows and lashes (0.4-3.8k triangles, one 1K RGBA atlas): 11-17.7k
triangles a person, 24 bones, the three clips. The MakeHuman T-shirts carry the MakeHuman logo;
it is painted out of every atlas (`crowd_config.json` "garments" -> "erase").

The crowd's tiling surface detail, `assets/textures/crowd/crowd_detail.png` (1024 px, four
512 px tiles: skin pores, jersey knit, denim twill, plain weave), is drawn procedurally by
`tools/crowd/make_detail.py` (numpy, no source images; ours). The garment folds baked into each
`crowd_*_body_nrm.jpg` come from our own fold field (`tools/hero/folds.py`), the stubble and
beards painted into the atlases from our own code (`tools/crowd/crowd_atlas.py`).

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
| Impact Sounds (Kenney) | https://kenney.nl/assets/impact-sounds | CC0 1.0 | `assets/audio/hit_concrete_0..2` (impactMining 000/002/004), `hit_metal_0..2` (impactMetal_light 000/002/004), `hit_glass_0..2` (impactGlass_light 000/002/004), `hit_wood_0..2` (impactPlank_medium 000/002/004), `hit_dirt_0..2` (impactSoft_medium 000/002/004), `hit_flesh_0..2` (impactPunch_medium 000/002/004), `casing_0..1` (impactMetal_light 001/003, played pitched up) - as supplied | 2026-09-28 |
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
| Generator Loop (YCbCr), "low frequency motor sound" | https://opengameart.org/content/generator-loop | CC0 1.0 | `assets/audio/generator_0` (the taco trucks' generators, StreetVendors): 0.05 s trimmed off each end, the last 0.8 s cross-faded into the first (it does not loop natively), levelled to -20 dBFS RMS, mono 44.1 kHz Vorbis | 2026-10-04 |
| car alarm dying out (ramas26), a real car alarm cycling its tones | https://freesound.org/people/ramas26/sounds/165257/ | CC0 1.0 | `assets/audio/car_alarm_0` (15.3-22.6 s of the HQ preview: the pulsing tone) and `car_alarm_1` (24.6-57.2 s: the multi-tone warble cycle); high-passed 300 Hz, levelled to -20 dBFS RMS, the last 0.4 s cross-faded into the first, mono 44.1 kHz Vorbis (CarAlarm) | 2026-10-05 |
| 230707 Car alarm horn honks, roof, EM272s Toronto (TRP) | https://freesound.org/people/TRP/sounds/717865/ | CC0 1.0 | `assets/audio/car_alarm_2` (1.4-38.4 s of the HQ preview: a horn honking in time), high-passed 200 Hz, levelled, cross-faded into a loop, mono 44.1 kHz Vorbis (CarAlarm) | 2026-10-05 |
| American police siren in Washington DC (lezer, via pdsounds.org) | https://commons.wikimedia.org/wiki/File:American_police_siren_i.ogg | Public domain | `assets/audio/siren_0` (one wail cycle, 17.62-22.78 s of the recording, band-passed 380 Hz - 6 kHz, level flattened, cross-faded into a seamless loop, mono 44.1 kHz; the Ogg Skeleton track dropped) | 2026-09-24 |
| jacaranda_tree | `tree_jacaranda.glb` | 60k tris, 10.2 MB | street and park trees; recoloured to lavender blossom (see shaders/foliage_tex.gdshader) | 2026-09-21 |
| island_tree_03 | `tree_d.glb` | 38k tris, 3.6 MB | street and park trees | 2026-09-21 |
| fir_tree_01 | `tree_fir.glb` | 54k tris, 5.2 MB | hill conifers | 2026-09-21 |
| pine_tree_01 | `tree_pine.glb` | 48k tris, 3.5 MB | hill conifers | 2026-09-21 |
| quiver_tree_01 | `tree_quiver.glb` | 42k tris, 2.5 MB | dry hill trees | 2026-09-21 |
| searsia_burchellii | `tree_searsia.glb` | 16k tris, 1.8 MB | dry hill scrub; the hills' chaparral stands (`model_chaparral()`, cut to ~3k) | 2026-09-21 |
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
| island_tree_01 | `tree_a.glb` | 44k (from 1.6M, `tools/decimate_tree.py`) | street and park trees; hill oaks in the gullies (`model_hill_oak()`, cut to ~20k) | 2026-09-19 |
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

## Light rail audio (Wikimedia Commons CC0, radio aporee public domain)

The Coral Line's sounds (`Sfx` `rail_bell`, `rail_horn`, `rail_gong`, `rail_roll`), added 2026-10-04.
Each file's own page checked: Commons' licence field CC0, the Internet Archive items marked Public
Domain Mark 1.0. Processed like the city ambience (4th-order zero-phase band-pass; loops cross-faded
0.5 s and levelled to -22 dB RMS, one-shots faded, peak -1 dB; 44.1 kHz mono Vorbis). No CC0 tram
gong was found, so the gong is single strikes of a German crossing barrier bell; the rolling loop is
recorded on board a tram.

| Recording (author) | Source URL | License | Clips (span used) | Added |
|---|---|---|---|---|
| Level crossing Belgium 2022 (Bert76, Wikimedia Commons) | https://commons.wikimedia.org/wiki/File:Level_crossing_Belgium_2022.ogg | CC0 | `rail_bell_0` (8.50-12.96 s, loop), `rail_bell_1` (4.00-7.52 s, loop); 250 Hz-12 kHz | 2026-10-04 |
| BÜ DE, Schrankensignal, 5 (Renardo la vulpo, Wikimedia Commons) | https://commons.wikimedia.org/wiki/File:B%C3%9C_DE,_Schrankensignal,_5.ogg | CC0 | `rail_gong_0` (0.12-2.32 s), `rail_gong_1` (2.51-4.71 s), `rail_gong_2` (4.91-7.11 s); 300 Hz-12 kHz | 2026-10-04 |
| Xtrapolis 100 horn sound audio (MrActiniuM, Wikimedia Commons) | https://commons.wikimedia.org/wiki/File:Xtrapolis_100_horn_sound_audio.wav | CC0 | `rail_horn_0` (0-1.79 s); 120 Hz-10 kHz | 2026-10-04 |
| light rail near miss, Baltimore (cenglish, radio aporee via Internet Archive) | https://archive.org/details/aporee_61665_70921 | Public Domain Mark 1.0 | `rail_horn_1` (63.05-64.10 s); 150 Hz-10 kHz | 2026-10-04 |
| Poznan, PST line - line 12 (maciej janasik, radio aporee via Internet Archive) | https://archive.org/details/aporee_23637_27482 | Public Domain Mark 1.0 | `rail_roll_0` (18.0-25.0 s, loop), `rail_roll_1` (110.0-117.0 s, loop); 40 Hz-11 kHz | 2026-10-04 |

## Light rail car (Blender, code-built)

`assets/models/light_rail_car.glb` (one section of the Coral Line's articulated car, ~6.3k triangles
with its doors, bogie and pantograph) is modelled from scratch by `tools/make_light_rail.py`; no
external asset. Original design and livery.
## City birds (our own code and painter; public-domain recordings)

The birds (`scripts/world/birds.gd`, VISUAL_ROADMAP #53) are built in code by
`scripts/world/bird_mesh.gd` (lofted bodies, feather cards, legs, eyes at real size; no external
model) and wear plumage atlases painted procedurally by `tools/birds/make_bird_textures.py`
(original art, no source photos): `assets/textures/birds/<pigeon|gull|crow|sparrow>_albedo.png`,
`_normal.png`, `_mask.png`, 1024 px. Added 2026-10-04.

Sounds: freesound.org is blocked from the build box, so these come from field recordings their
recordists released into the public domain (radio aporee ::: maps uploads on archive.org, each
item's licence the Creative Commons Public Domain Mark 1.0) and one public-domain Wikimedia
Commons file. Cut, filtered, peak-normalised mono OGGs; loudest-50 ms levels in
`Sfx.SAMPLE_LOUDNESS_DB`.

| Recording (author) | Source URL | License | Clips (span used, s) | Added |
|---|---|---|---|---|
| Saint-Gilles - Pigeons on the balcony (Flavien Gillié) | https://archive.org/details/aporee_18918_82147 | Public Domain Mark 1.0 | `pigeon_coo_0` 67.35-69.00; `pigeon_coo_1` 43.70-45.65; `pigeon_coo_2` 106.60-108.75; `pigeon_coo_3` 118.70-121.30; `wings_0` 502.62-504.05; `wings_1` 387.10-388.75; `wings_2` 60.60-63.00 | 2026-10-04 |
| Heraklion, Ekteleseos Martiron square - pigeons (maciej janasik) | https://archive.org/details/aporee_15173_17699 | Public Domain Mark 1.0 | `wings_3` 147.55-149.05 | 2026-10-04 |
| Chediston Hall Farm - loud crows (Peter Cusack) | https://archive.org/details/aporee_64966_75047 | Public Domain Mark 1.0 | `crow_0` 9.79-11.79; `crow_1` 31.90-34.55 | 2026-10-04 |
| Crows roost by the River Oker, Braunschweig (Peter Cusack) | https://archive.org/details/aporee_60107_69041 | Public Domain Mark 1.0 | `crow_2` 60.40-62.70 | 2026-10-04 |
| File:American Crow.ogg (G McGrane) | https://commons.wikimedia.org/wiki/File:American_Crow.ogg | Public domain | `crow_3` 2.15-3.85 | 2026-10-04 |
| Rue Keyenveld - Sparrows (Flavien Gillié) | https://archive.org/details/aporee_71526_83445 | Public Domain Mark 1.0 | `sparrow_0` 3.85-5.90; `sparrow_1` 8.95-10.95 | 2026-10-04 |
| Seagull Chatter, The Hague (Thijs Geritz) | https://archive.org/details/aporee_10517_42365 | Public Domain Mark 1.0 | `gull_close_0` 60.55-62.60; `gull_close_1` 105.20-107.80 | 2026-10-04 |

## City acoustics audio (Freesound CC0, Kenney CC0)

The city's newer sounds (`Sfx` footsteps by surface, the bus, the light rail's chime, a basketball;
`Ambience` river, fountain, playground and construction), added 2026-10-05. Every Freesound page
checked by `tools/ambience_audio.py get` (its licence link the CC0 1.0 deed only, the description
read: `415151`, a stream whose description adds a "Licence: Music by ..." credit line, was dropped
for that). Cut by `tools/city_audio.py build` from the HQ previews (mono one-shots peak -1 dB at
44.1 kHz; loops levelled to -22 dB RMS at 32 kHz, cross-faded; footsteps and bounces split at their
onsets automatically, the loudest kept). Kenney's Impact Sounds (`kenney_impact-sounds.zip`,
License.txt: CC0 1.0) re-encoded mono 44.1 kHz, peak -1 dB. The light rail's traction-motor whine
(`rail_motor`) and wire hum (`rail_hum`) are synthesized in `Sfx` (two candidate uploads, 721022
and 733737, measured as perfectly steady synthesized tones, so making our own was the same thing).
`bus_kneel` reuses `bus_hiss_1` / `bus_hiss_2` (City ambience section). About 1.6 MB.

| Recording (author) | Source URL | License | Clips (span used) | Added |
|---|---|---|---|---|
| Impact Sounds (Kenney) | https://kenney.nl/assets/impact-sounds | CC0 1.0 | `footstep_concrete_0..4` (footstep_concrete_000..004), `footstep_grass_0..4` (footstep_grass_000..004), `footstep_wood_0..4` (footstep_wood_000..004) | 2026-10-05 |
| footsteps shoes walk road asphalt hard.flac (kyles) | https://freesound.org/s/637556/ | CC0 1.0 | `footstep_asphalt_0..3` (3.10-3.42, 4.30-4.62, 4.91-5.18, 5.46-5.68 s) | 2026-10-05 |
| Foot_Step_grit_Sand.wav (savataivanov) | https://freesound.org/s/384082/ | CC0 1.0 | `footstep_sand_0..3` (1.67-1.87, 6.05-6.20, 9.34-9.53, 14.12-14.45 s) | 2026-10-05 |
| Footsteps On Metal (IENBA) | https://freesound.org/s/834029/ | CC0 1.0 | `footstep_metal_0..3` (0.57-0.99, 1.09-1.51, 1.58-2.00, 3.71-4.13 s) | 2026-10-05 |
| bus_door_opening and closing at bus stop .wav (13FPanska_Sychra_Petr) | https://freesound.org/s/379373/ | CC0 1.0 | `bus_door_0` 1.15-3.65 s (opening), `bus_door_1` 8.10-10.35 s (closing, under the warning beeper) | 2026-10-05 |
| bus door (zombiechick) | https://freesound.org/s/380320/ | CC0 1.0 | `bus_door_2` 0.25-3.60 s | 2026-10-05 |
| D# and F chime (Sadiquecat; a sine chime made by its author) | https://freesound.org/s/845146/ | CC0 1.0 | `bus_chime_0` 0.00-1.90 s, `bus_chime_1` 3.12-5.00 s | 2026-10-05 |
| Bus Engine Idling (bikesnbassboi) | https://freesound.org/s/540398/ | CC0 1.0 | `diesel_idle_0` 1.0-9.3 s (7.5 s loop) | 2026-10-05 |
| R142/R142A Door Chime (nickymastro25) | https://freesound.org/s/249835/ | CC0 1.0 | `rail_chime_0` 0.00-0.92 s | 2026-10-05 |
| Subway MTA Door Close Chime (cbrews; a marimba chime played by its author) | https://freesound.org/s/434085/ | CC0 1.0 | `rail_chime_1` 0.00-1.70 s | 2026-10-05 |
| basketball ext dribble bounce hard surface.flac (kyles) | https://freesound.org/s/453757/ | CC0 1.0 | `ball_dribble_0..3` (1.72-2.12, 3.25-3.65, 4.84-5.25, 22.66-23.07 s) | 2026-10-05 |
| Stream River Water Up Close (jackthemurray) | https://freesound.org/s/433589/ | CC0 1.0 | `amb_river_0` 0.0-24.5 s (left) and 27.5-52.0 s (right) | 2026-10-05 |
| fountain (martats) | https://freesound.org/s/156969/ | CC0 1.0 | `amb_fountain_0` 3.0-27.5 s (against itself half a turn later) | 2026-10-05 |
| Kids Playing (brunoboselli) | https://freesound.org/s/469613/ | CC0 1.0 | `amb_playground_0` 22.0-50.5 s | 2026-10-05 |
| Jack Hammer breaking up concrete (short burst) (thomaspettigrew) | https://freesound.org/s/273697/ | CC0 1.0 | `construction_0` 0.05-3.60 s, `construction_1` 3.90-7.60 s | 2026-10-05 |
| hammering 2.wav (cognito perceptu) | https://freesound.org/s/17012/ | CC0 1.0 | `construction_2` 0.00-1.55 s | 2026-10-05 |

## Murals and ghost signs (our own code)

| Asset | Source | License | Used for | Added |
|---|---|---|---|---|
| `assets/textures/murals/ghost_signs.png` (sixteen invented period ads as field / lettering / shadow masks) | Our own script `tools/make_murals.py`; lettering rasterised from the system's DejaVu (Bitstream Vera licence) and Liberation (SIL OFL 1.1) fonts, no font file ships | ours | ghost signs on old brick (`scripts/world/murals.gd`, `shaders/mural.gdshader`) | 2026-10-05 |
| Every mural scene, frieze, crosswalk pattern and cabinet wrap | Painted procedurally in `shaders/mural.gdshader` | ours | murals | 2026-10-05 |

## Los Angeles trees and accents (built in code)

Ten species built at run time by `scripts/world/la_trees.gd` (2026-10-05) - no model files, no
textures: a seeded skeleton (trunk, limbs, branches, twigs), leaf cards whose outlines, bark
patterns and flowers are drawn by `shaders/la_tree.gdshader`. Poly Haven has none of these
species. Original work for this game.

| Mesh | Built by | Triangles (full detail / coarsest) | Used for | Added |
|---|---|---|---|---|
| Eucalyptus (blue gum), Italian cypress, olive, Indian laurel fig, California sycamore, coral tree; two variants each | `LaTrees.mesh()` | 6k-17k / 0.4-1.1k | street rows, parks, plazas, yards, the freeway's right of way, hill gullies, cypress pairs by houses | 2026-10-05 |
| Bird of paradise, agave (plain and variegated), yucca, dragon tree | `LaTrees.mesh()` | 0.8k-3.5k / 20-400 | front gardens, yard beds, forecourt planters | 2026-10-05 |

## Dogs (built in code; CC0 recordings)

The dogs (`DogMesh`, `DogRig`; 2026-10-05) are built in code: no model file. Their coats
(`assets/textures/dogs/*.jpg`, 14 colourways) are painted by `tools/dogs/make_dog_coats.py`
(numpy + PIL), original. The Quaternius Shiba (`dog_shiba.glb`) they replace is removed.

| File | Source | License | Cut | Date |
|---|---|---|---|---|
| Dog Bark (aunrea) | https://freesound.org/s/495658/ | CC0 1.0 | `bark_big_0` 0.13-0.55 s; `bark_big_1` 1.43-1.88 s; `bark_big_2` 3.45-3.87 s | 2026-10-05 |
| Barking Dog (SuperStudioBR) | https://freesound.org/s/180977/ | CC0 1.0 | `bark_big_3` 0.69-1.11 s; `bark_big_4` 2.51-2.91 s; `bark_big_5` 10.73-11.23 s | 2026-10-05 |
| Pomeranian Small Dog Barking.mp3 (yunjish) | https://freesound.org/s/608732/ | CC0 1.0 | `bark_small_0..4` 6.89, 8.19, 11.65, 12.81, 9.43 s (0.32-0.36 s each) | 2026-10-05 |
| bark yelp dog small int.flac | https://freesound.org/s/452180/ | CC0 1.0 | `dog_yelp_0` 0.73-1.28 s | 2026-10-05 |
| Dog's Yelping 7 | https://freesound.org/s/160478/ | CC0 1.0 | `dog_yelp_1` 3.13-3.75 s; `dog_yelp_2` 7.73-8.33 s | 2026-10-05 |

## Micromobility (built in code)

The shared e-scooters, the BASIN BIKE share bikes, docks and solar kiosk, the bike racks, the bike
lanes' delineator posts and the riders' road bike, beach cruiser and longtail cargo bike
(2026-10-05) are generated at run time by `scripts/world/micro_mesh.gd` on
`shaders/micromobility.gdshader`, and the lane paint (green, lines, hatching, the bike stencil and
arrow) is drawn by `shaders/bike_lane.gdshader` - no model files, no textures. The riders' helmets
are built round each crowd rig's head by `scripts/npc/bike_helmet.gd` from CrowdHatTable. The
scooter operators (SKOOTA, KWIKR) and the share scheme (BASIN BIKE) are invented for this game;
no real operator's name, colours or mark.

## Fonts

| Font | Source URL | License | Used for | Added |
|---|---|---|---|---|
| Inter 4.1 SemiBold and Medium (`extras/woff-hinted/Inter-SemiBold.woff2`, `Inter-Medium.woff2` from the release zip) | https://github.com/rsms/inter/releases/tag/v4.1 | SIL Open Font License 1.1 (text in `assets/fonts/Inter-OFL.txt`) | weapon wheel names and hints (`scripts/ui/weapon_wheel.gd`); falls back to Godot's default font if missing | 2026-09-24 |

## Map data

| Data | Source | License | Used for | Added |
|---|---|---|---|---|
| Coordinates of 40 landmark points (40 queries, 68 results, the first of each used) and 517 street / freeway centre-line points (53 queries) in downtown Los Angeles (93 Nominatim search queries in all, cached in `tools/downtown_relay/geocode_cache.json`) | https://nominatim.openstreetmap.org (OpenStreetMap) | © OpenStreetMap contributors (ODbL 1.0) | the fitted downtown street grid and landmark positions in `scripts/world/downtown_real.gd` | 2026-09-24 |
| Footprint (7-point outline), height 15.7 m and start date 1993 of Masjid Omar ibn Al-Khattab, OSM way 412475901 (one Nominatim lookup) | https://nominatim.openstreetmap.org (OpenStreetMap) | © OpenStreetMap contributors (ODbL 1.0) | the replica's plan and heights in `scripts/world/landmark_masjid_omar.gd` (`W_*`, `E_*`, `REAL_LATLON`); the detail is modelled from the owner's six photographs | 2026-09-24 |

## Freight rail audio and rolling stock (Wikimedia Commons CC0; code-built)

The freight line's sounds (`Sfx` `freight_horn`, `freight_horn_blast`, `freight_roll`,
`freight_engine`), added 2026-10-05. Each file's Commons page checked: licence field CC0. Cut with
ffmpeg (mono 44.1 kHz Vorbis; the horn high-passed at 90 Hz and faded, the pass at 30-35 Hz);
loudness in `Sfx.SAMPLE_LOUDNESS_DB` (the loops at their RMS, the horn at its loudest 50 ms). The
horn recording is itself the grade-crossing pattern (long, long, short, long). The crossing bells
are the light rail's `rail_bell`. The locomotives and cars (`scripts/vehicles/freight_stock.gd`)
and the yard and track (`freight_kit.gd`, `freight_yard.gd`) are built in code: no external model.
The containers are PortKit's. Railroad, marks and livery invented (Arroyo Pacific, APXR).

| Recording (author) | Source URL | License | Clips (span used) | Added |
|---|---|---|---|---|
| Nathan M5 (HarveyHenkelmann, Wikimedia Commons) | https://commons.wikimedia.org/wiki/File:Nathan_M5.ogg | CC0 | `freight_horn_0` (0.35-16.9 s, the crossing pattern), `freight_horn_blast_0` (7.05-11.45 s) | 2026-10-05 |
| Freight train passes Phelan, startles Canadian geese (Extemporalist, Wikimedia Commons) | https://commons.wikimedia.org/wiki/File:Freight_train_passes_Phelan,_startles_Canadian_geese.flac | CC0 | `freight_roll_0` (100-112 s, loop), `freight_roll_1` (266-278 s, loop), `freight_engine_0` (304-312 s, loop) | 2026-10-05 |
