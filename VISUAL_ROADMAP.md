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
| 6 | Hill vegetation density: chaparral scrub clumps and dry grass tufts on the slopes, LOD'd | Hills (city_chunk _scatter_hills) | 4 | 3 | 1.5 | 8.0 | in-progress | wave 4 |
| 7 | Street clutter: newspaper boxes, bollards, utility boxes, sandwich boards, litter decals | Density (street_detail.gd) | 3 | 4 | 1.3 | 9.2 | done | merged 20e2169: news boxes, magazine racks, A-frames, gutter litter (+1% draws). Weak spots: rack header card dark, litter reads only within ~15 m |
| 8 | Neon and shop-front glow at night: signage emission, light spill on the pavement | Lighting (building.gdshader shop band, light_pool) | 4 | 3 | 1.2 | 10.0 | todo | |
| 9 | Puddles and wet decals after rain: persistent dark wet patches, gutter water | Materials (road.gdshader) | 3 | 4 | 1 | 12.0 | todo | road already has mirror puddles when soaked |
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
| 21 | Car bodies are visibly faceted (flat-shaded low-poly panels in every close-up): smooth the normals / weld the generated bodies, or higher-poly bodies | Vehicles (Vehicle.BODY_MODELS, the .glb bodies) | 5 | 3 | 1.1 | 13.6 | in-progress | wave 4. Seen in the grime close-ups (`<scratchpad>/grime/m2/z_sedan.png`) |

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
