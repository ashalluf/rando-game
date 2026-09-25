# Visual roadmap (orchestrator loop)

North star: 2026 PS5-tier street-level photorealism that stays playable - 60 fps at 1440p on the
owner's Mac, 30 fps absolute floor. A gorgeous screenshot at 12 fps is a regression.

Score = (visual impact 1-5 x feasibility 1-5) / perf cost (1 = free, 3 = heavy). Re-rank every
3 waves, and whenever the owner's Mac screenshots or F1 numbers come in (they are ground truth).
Statuses: todo, in-progress, done, reverted, blocked. Judge every item on the fixed bookmarks
(`tools/glshot/bookmarks.sh`: downtown noon, downtown night + rain, hills, freeway, masjid,
esplanade sunset, hero close-up). History and numbers are in LOOP_LOG.md.

## Ranked backlog

| # | Item | Area | Impact | Feas. | Perf | Score | Status | Notes |
|---|------|------|--------|-------|------|-------|--------|-------|
| 1 | Hill ground splat: slope/height/noise mix of dry grass, chaparral, rock, dirt, with macro variation | Hills (terrain.gdshader, PropFactory.terrain_material) | 5 | 4 | 1.2 | 16.7 | done | merged dfdeefa. Terrain shader ~1.8-2x its old cost (7 fetches, 9 noises) |
| 2 | Vehicle grime: dirt on the lower body and wheel arches, dust on glass, per-car amount | Vehicles (car_paint.gdshader, vehicle.gd) | 3 | 5 | 1 | 15.0 | reverted | seeded grime (sills, wheel spray, dust, glass film) was real but subtle at the median car and +190 ALU/fragment on every car: not clearly better. Branch wt/vehicle-grime kept for reference. The bigger tell is #21 |
| 3 | Walls and pavements: grime streaks under sills, rain stains, damp kerb line, graffiti tags on low walls | Materials (building.gdshader) | 4 | 4 | 1.1 | 14.5 | reverted | sill run-off, soot under ledges, damp foot band: clearly better only within ~15 m, invisible across the street, +90-120 ALU on most wall pixels: not clearly better. Branch wt/wall-weathering kept |
| 4 | MacArthur Park on (build 253) | Density / landmark | 3 | 3 | 1 | 9.0 | done | build 254. Three causes found (forced turn; tests re-centring outside the physics tick; seed-rebuild check zeroing the offset) |
| 5 | Golden hour / LA haze: warmer low sun, orange-pink horizon band, brown-grey smog layer at the basin edge | Lighting (day_night.gd, sky.gdshader) | 4 | 3 | 1 | 12.0 | done | merged ffc19f8. Blue sky until the sun is low, smog band, warm haze. NEEDS MAC CHECK: no Forward+ city shot possible here (lavapipe OOM at 13.9 GB) |
| 6 | Hill vegetation density: chaparral scrub clumps and dry grass tufts on the slopes, LOD'd | Hills (city_chunk _scatter_hills) | 4 | 3 | 1.5 | 8.0 | done | merged 75902af: shrubs/oaks from the terrain's own brush field; clearly better on the slopes, neutral at the bookmark and from the basin (the range still does not read brush-covered from the city - south faces are grass by design). +4.5 % tris hills, +1.2 % city |
| 7 | Street clutter: newspaper boxes, bollards, utility boxes, sandwich boards, litter decals | Density (street_detail.gd) | 3 | 4 | 1.3 | 9.2 | done | merged 20e2169: news boxes, magazine racks, A-frames, gutter litter (+1% draws). Weak spots: rack header card dark, litter reads only within ~15 m |
| 8 | Neon and shop-front glow at night: signage emission, light spill on the pavement | Lighting (building.gdshader shop band, light_pool) | 4 | 3 | 1.2 | 10.0 | done | merged 5340b9b: per-shop night (open/closed, warm/cool, neon, shutters, lit channel letters, pavement spill), +1 draw. NEEDS MAC CHECK for glow/neon under AgX and spill on wet SSR road |
| 9 | Puddles and wet decals after rain: persistent dark wet patches, gutter water | Materials (road.gdshader) | 3 | 4 | 1 | 12.0 | in-progress | wave 6. Road already has mirror puddles when soaked |
| 10 | Vehicle damage: dents / scratches where hit, cracked glass | Vehicles | 3 | 2 | 1.2 | 5.0 | todo | |
| 11 | Pedestrian skin / cloth: SSS and cloth sheen like the hero, per-look roughness | Characters (character.gdshader) | 3 | 2 | 1.2 | 5.0 | reverted | warmer faces, per-look fabric: modest, not clearly better; the plastic look is baked into the source photos (lighting and highlights), which shading cannot remove. Needs new textures (delit albedo) instead. Only the character_shot.gd LOOK fix was kept |
| 12 | Post: restrained motion blur and DOF in aim / wheel | Post | 3 | 2 | 2 | 3.0 | todo | Forward+ only |
| 13 | Land the downtown 1:1 re-lay patch (tools/downtown_relay/relay.patch) | Downtown | 4 | 2 | 1 | 8.0 | in-progress | wave 4. HANDOFF 9s; big and risky, give it a wave of its own. As of 2026-09-25 the patch no longer applies cleanly (city_plan, city_streamer, landmarks, macro_map moved): it needs a re-port, not a `git apply` |
| 14 | Interiors for key buildings (lobbies behind street-level glass) | Interiors | 2 | 2 | 1.5 | 2.7 | todo | |
| 15 | Park lawns: less saturated, drier LA-autumn variation, worn paths under trees; jacaranda reads navy in the harness | Materials (lawn.gdshader, grass) | 3 | 3 | 1 | 9.0 | reverted | a drier, greyer park lawn tint barely moved the frame: the blade-grass multimesh (its own colour, chunk._add_grass) is what fills the near lawn. Redo as a blade-colour + lawn pass together |
| 16 | Road patch decals read as dark square holes (seen at Westlake, `park_camp.png`): feather their edges, match the asphalt tone | Materials (street_detail.gd `_road_wear`, road.gdshader) | 3 | 5 | 1 | 15.0 | done | build 257 (ec65e50): road_patch.gdshader |
| 17 | Hill road cuts and the pass are sheer vertical terrain walls with black holes at their feet (hills bookmark, `base_18c1bcb/hills2.png`): slope the cut banks, close the gaps | Hills (city_chunk _build_terrain / HillRoads.carve) | 5 | 3 | 1 | 15.0 | done | merged 42bf864: carved cells steeper than 60 deg 32 % -> 0.6 %. Cost: front-range roads that could not be graded were trimmed (mansions 468 -> 318) - see #20 |
| 18 | Mipmaps on: about a dozen Poly Haven sets (facade and street sets) are imported with mipmaps off, against the CLAUDE.md rule - shimmer at distance and wasted bandwidth. Switch the .imports (compress/mode=2, mipmaps/generate=true), drop the unused RockyTerrain02 | Materials / perf (assets/textures/*.import) | 4 | 5 | 0.8 | 25.0 | done | merged cb4e4e3; brick at distance is an even tone instead of red speckle |
| 19 | Hill chaparral stands read as cloud shadows at mid distance; the gold still leans orange (opengl3). Tune `chaparral_amount`, `north_brush`, `chaparral_color` against a Mac/Forward+ look | Hills (terrain.gdshader) | 3 | 4 | 1 | 12.0 | todo | NEEDS MAC CHECK first |
| 20 | Front range roads and estates back: switchback roads that follow the contours (HillRoads), so the range has drives and mansions again without trench cuts | Hills (hill_roads.gd) | 3 | 2 | 1.2 | 5.0 | todo | owner may miss the ~150 front-range mansions the cut-bank fix dropped |
| 21 | Car bodies are visibly faceted (flat-shaded low-poly panels in every close-up): smooth the normals / weld the generated bodies, or higher-poly bodies | Vehicles (Vehicle.BODY_MODELS, the .glb bodies) | 5 | 3 | 1.1 | 13.6 | done | merged 331e450: angle-smoothed normals (tools/smooth_normals.py) on sedan/pickup/van/sports. Silhouettes still polygonal -> #22. Seen in the grime close-ups (`<scratchpad>/grime/m2/z_sedan.png`) |
| 22 | Everyday car bodies at a higher polycount (Meshy regen at 16k+, or Blender-built like the exotics): polygonal arch lips, bumper corners, the pickup's chunky nose; the baked texture's mottled front | Vehicles (car_*.glb) | 4 | 2 | 1.2 | 6.7 | in-progress | wave 6: Blender-built hi-fi sedan (bpy module installed), ~30k tris with LODs |
| 23 | PERF: trees and palms are the biggest triangle cost (freeway 3.40 M of 8.68 M, 1.95 M of it shadow): a MultiMesh batch takes ONE LOD for all its instances, so every tree in the camera's chunk draws at full detail (40-60k tris). Split tree batches by distance ring / per-instance LOD, or impostors past ~80 m | Perf (multimesh_batch.gd, PropFactory trees) | 3 | 3 | 0.5 | 18.0 | in-progress | wave 6 (PERF). From the perf pass baseline (HANDOFF 9x) |
| 24 | PERF: pedestrians at 60-140 m sit on the models' 4,150-triangle floor (1.88 M downtown): extend the welded far body (`Pedestrian.far_mesh()`) down to ~60 m | Perf (pedestrian.gd) | 2 | 4 | 0.5 | 16.0 | done | merged 35efe0a: welded middle body (~2.1k tris) past 50 m; crowd -42 %, frame -9.5 % triangles, draws unchanged; +415 ms loading |
| 25 | A hill chunk's contents float tens of metres in the air near --spawn=430,-1630 (boulders, now shrubs and oaks too): chunk placed off the carved height? Pre-existing on main | Hills (city_chunk hill build / MacroMap.height_at) | 4 | 4 | 1 | 16.0 | done | merged 2106e3e: the hill build steps placed at height_at() (relief included) and the batch added _gy() again. 700 of 1,597 hill chunks basin-wide, worst +144 m; now worst 1.2 m, smoke check added. Found by the hill vegetation agent; see `<scratchpad>/veg/m6/slope_single.png` |
| 26 | Every car's headlight beam quad sits below the road (`vehicle_lights()` at 0.12 - y) so the night beams never show; the `_dims()` cabin collision box floats ~0.5 m above every roof | Vehicles (prop_factory vehicle_lights, vehicle.gd _dims) | 3 | 5 | 1 | 15.0 | todo | found by the sedan agent (HANDOFF 9z); asked it to fix in its styling pass |
| 27 | Street-level wear: graffiti tags, wheat-paste posters, stickers on poles and boxes, faded paint on walls and shutters (hash-seeded decals, original art only) | Density (street_detail / street_clutter / building shader) | 4 | 4 | 1 | 16.0 | in-progress | wave 6 |
| 28 | Crowd animation blending: walk/run/idle cross-fades, turn-in-place, start/stop, head look-at nearby action | Characters (pedestrian.gd, avatar.gd) | 4 | 3 | 1 | 12.0 | todo | seed item 4 |

## NEEDS MAC CHECK

Forward+-dependent looks never seen on the owner's Mac (the harness is opengl3 or lavapipe):
- Masjid Omar ibn Al-Khattab exterior and interior (build 252).
- The hero AAA pass: skin SSS, hair anisotropy, cloth folds (build 250).
- Anything under "Lighting" or "Post" above.
- Golden hour / LA smog (ffc19f8): judged on a Forward+ stand-in scene only. Try `--hour=17.5` on
  the Mac, facing away from the sun and toward it; knobs `smog_amount`, `smog_color`,
  `golden_blue_top`, `golden_fog_gain` in DayNight's Golden hour group.

## WAITING ON ASH

- Forward+ city renders do not fit in this box's 14.3 GB (lavapipe peaks at 13.9 GB), so every
  Forward+ look is judged on the Mac. A Mac screenshot at 17:30 game time, toward and away from the
  sun, would settle the golden-hour change.

- An F1 screenshot (FULL mode: the frame-time line) on the Mac downtown at noon and at night in
  rain, for the real frame rate against the 60 / 30 fps targets.
