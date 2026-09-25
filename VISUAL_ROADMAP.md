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
| 1 | Hill ground splat: slope/height/noise mix of dry grass, chaparral, rock, dirt, with macro variation | Hills (terrain.gdshader, PropFactory.terrain_material) | 5 | 4 | 1.2 | 16.7 | in-progress | wave 1. Today: one grass texture, rock by slope, snow by height |
| 2 | Vehicle grime: dirt on the lower body and wheel arches, dust on glass, per-car amount | Vehicles (car_paint.gdshader, vehicle.gd) | 3 | 5 | 1 | 15.0 | in-progress | wave 1. Every car is showroom clean today |
| 3 | Walls and pavements: grime streaks under sills, rain stains, damp kerb line, graffiti tags on low walls | Materials (building.gdshader) | 4 | 4 | 1.1 | 14.5 | in-progress | wave 1 |
| 4 | MacArthur Park on (build 253) | Density / landmark | 3 | 3 | 1 | 9.0 | done | build 254. Three causes found (forced turn; tests re-centring outside the physics tick; seed-rebuild check zeroing the offset) |
| 5 | Golden hour / LA haze: warmer low sun, orange-pink horizon band, brown-grey smog layer at the basin edge | Lighting (day_night.gd, sky.gdshader) | 4 | 3 | 1 | 12.0 | done | merged ffc19f8. Blue sky until the sun is low, smog band, warm haze. NEEDS MAC CHECK: no Forward+ city shot possible here (lavapipe OOM at 13.9 GB) |
| 6 | Hill vegetation density: chaparral scrub clumps and dry grass tufts on the slopes, LOD'd | Hills (city_chunk _scatter_hills) | 4 | 3 | 1.5 | 8.0 | todo | after #1 |
| 7 | Street clutter: newspaper boxes, bollards, utility boxes, sandwich boards, litter decals | Density (street_detail.gd) | 3 | 4 | 1.3 | 9.2 | done | merged 20e2169: news boxes, magazine racks, A-frames, gutter litter (+1% draws). Weak spots: rack header card dark, litter reads only within ~15 m |
| 8 | Neon and shop-front glow at night: signage emission, light spill on the pavement | Lighting (building.gdshader shop band, light_pool) | 4 | 3 | 1.2 | 10.0 | todo | |
| 9 | Puddles and wet decals after rain: persistent dark wet patches, gutter water | Materials (road.gdshader) | 3 | 4 | 1 | 12.0 | todo | road already has mirror puddles when soaked |
| 10 | Vehicle damage: dents / scratches where hit, cracked glass | Vehicles | 3 | 2 | 1.2 | 5.0 | todo | |
| 11 | Pedestrian skin / cloth: SSS and cloth sheen like the hero, per-look roughness | Characters (character.gdshader) | 3 | 3 | 1.2 | 7.5 | in-progress | wave 3 |
| 12 | Post: restrained motion blur and DOF in aim / wheel | Post | 3 | 2 | 2 | 3.0 | todo | Forward+ only |
| 13 | Land the downtown 1:1 re-lay patch (tools/downtown_relay/relay.patch) | Downtown | 4 | 2 | 1 | 8.0 | todo | HANDOFF 9p; big and risky, give it a wave of its own. As of 2026-09-25 the patch no longer applies cleanly (city_plan, city_streamer, landmarks, macro_map moved): it needs a re-port, not a `git apply` |
| 14 | Interiors for key buildings (lobbies behind street-level glass) | Interiors | 2 | 2 | 1.5 | 2.7 | todo | |
| 15 | Park lawns: less saturated, drier LA-autumn variation, worn paths under trees; jacaranda reads navy in the harness | Materials (lawn.gdshader, grass) | 3 | 3 | 1 | 9.0 | reverted | a drier, greyer park lawn tint barely moved the frame: the blade-grass multimesh (its own colour, chunk._add_grass) is what fills the near lawn. Redo as a blade-colour + lawn pass together |
| 16 | Road patch decals read as dark square holes (seen at Westlake, `park_camp.png`): feather their edges, match the asphalt tone | Materials (street_detail.gd `_road_wear`, road.gdshader) | 3 | 5 | 1 | 15.0 | done | build 257 (ec65e50): road_patch.gdshader |
| 17 | Hill road cuts and the pass are sheer vertical terrain walls with black holes at their feet (hills bookmark, `base_18c1bcb/hills2.png`): slope the cut banks, close the gaps | Hills (city_chunk _build_terrain / HillRoads.carve) | 5 | 3 | 1 | 15.0 | in-progress | wave 3. High priority: the first thing you see flying into the hills |

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
