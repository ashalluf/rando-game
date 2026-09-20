# Assets

External assets: CC0 texture sets (below), CC0 street prop models from Poly Haven, and 3D models
generated with the owner's Meshy account (`tools/meshy.py`). Buildings, lamps, signs and trees are
still built-in primitives and code.

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
| Private jet | `assets/models/jet_private.glb` | 30 | `Aircraft` PRIVATE | 2026-09-19 |
| Airliner | `assets/models/jet_airliner.glb` | 30 | `Aircraft` AIRLINER | 2026-09-19 |

Pedestrian B is not loaded by anything (2026-09-20). Its texture came back as bare skin with no
clothing anywhere, so the garment recolour in `shaders/character.gdshader` has nothing to act on,
and its rig does not take the walk clip (it stands with its arms over its head). It walked the
city as a naked orange mannequin. `Pedestrian.MODELS` lists A and C only; the files stay in the
repo so the decision is visible.

All seven were first made as low-poly cartoon models (147 credits) and then regenerated with the
owner's realism rule on Meshy's standard model (252 credits). Car base colors are greyscaled and
brightened (`tools/shrink_glb.py --desaturate`) so the seeded paint tint gives the color.

Godot extracts each model's textures next to it on import (`<model>_N.jpg` + `.import`); those
files are committed like any other import output.

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
