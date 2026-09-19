# Assets

External assets: CC0 texture sets (below) and 3D models generated with the owner's Meshy account
(`tools/meshy.py`). Buildings and the street furniture are still built-in primitives and code.

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
| Rock064 | https://ambientcg.com/a/Rock064 | CC0 1.0 | hill slopes | 2026-09-19 |

All texture sets are from ambientCG (CC0 1.0 Universal, no attribution required, attribution given
anyway). Only the Color, NormalGL and Roughness maps at 1K are kept, under `assets/textures/<Set>/`.

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
| Pedestrian B (woman, hoodie) | `pedestrian_b.glb`, `pedestrian_b_anim.glb` (same clips) | 44 (+29) | `Pedestrian` | 2026-09-19 |
| Pedestrian C (older man, shirt) | `pedestrian_c.glb`, `pedestrian_c_anim.glb` (same clips) | 44 (+29) | `Pedestrian` | 2026-09-19 |

All seven were first made as low-poly cartoon models (147 credits) and then regenerated with the
owner's realism rule on Meshy's standard model (252 credits). Car base colors are greyscaled and
brightened (`tools/shrink_glb.py --desaturate`) so the seeded paint tint gives the color.

Godot extracts each model's textures next to it on import (`<model>_N.jpg` + `.import`); those
files are committed like any other import output.
