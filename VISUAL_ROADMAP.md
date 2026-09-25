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
| 5 | Golden hour / LA haze: warmer low sun, orange-pink horizon band, brown-grey smog layer at the basin edge | Lighting (day_night.gd, sky.gdshader) | 4 | 3 | 1 | 12.0 | in-progress | wave 2. NEEDS MAC CHECK - Forward+ only via lavapipe |
| 6 | Hill vegetation density: chaparral scrub clumps and dry grass tufts on the slopes, LOD'd | Hills (city_chunk _scatter_hills) | 4 | 3 | 1.5 | 8.0 | todo | after #1 |
| 7 | Street clutter: newspaper boxes, bollards, utility boxes, sandwich boards, litter decals | Density (street_detail.gd) | 3 | 4 | 1.3 | 9.2 | in-progress | wave 2. Wires, signals, lamps, meters, shelters already exist |
| 8 | Neon and shop-front glow at night: signage emission, light spill on the pavement | Lighting (building.gdshader shop band, light_pool) | 4 | 3 | 1.2 | 10.0 | todo | |
| 9 | Puddles and wet decals after rain: persistent dark wet patches, gutter water | Materials (road.gdshader) | 3 | 4 | 1 | 12.0 | todo | road already has mirror puddles when soaked |
| 10 | Vehicle damage: dents / scratches where hit, cracked glass | Vehicles | 3 | 2 | 1.2 | 5.0 | todo | |
| 11 | Pedestrian skin / cloth: SSS and cloth sheen like the hero, per-look roughness | Characters (character.gdshader) | 3 | 3 | 1.2 | 7.5 | todo | |
| 12 | Post: restrained motion blur and DOF in aim / wheel | Post | 3 | 2 | 2 | 3.0 | todo | Forward+ only |
| 13 | Land the downtown 1:1 re-lay patch (tools/downtown_relay/relay.patch) | Downtown | 4 | 2 | 1 | 8.0 | todo | HANDOFF 9p; big and risky, give it a wave of its own |
| 14 | Interiors for key buildings (lobbies behind street-level glass) | Interiors | 2 | 2 | 1.5 | 2.7 | todo | |
| 15 | Park lawns: less saturated, drier LA-autumn variation, worn paths under trees; jacaranda reads navy in the harness | Materials (lawn.gdshader, grass) | 3 | 4 | 1 | 12.0 | todo | seen in the MacArthur Park stills |
| 16 | Road patch decals read as dark square holes (seen at Westlake, `park_camp.png`): feather their edges, match the asphalt tone | Materials (street_detail.gd `_road_wear`, road.gdshader) | 3 | 5 | 1 | 15.0 | todo | quick fix |

## NEEDS MAC CHECK

Forward+-dependent looks never seen on the owner's Mac (the harness is opengl3 or lavapipe):
- Masjid Omar ibn Al-Khattab exterior and interior (build 252).
- The hero AAA pass: skin SSS, hair anisotropy, cloth folds (build 250).
- Anything under "Lighting" or "Post" above.

## WAITING ON ASH

- An F1 screenshot (FULL mode: the frame-time line) on the Mac downtown at noon and at night in
  rain, for the real frame rate against the 60 / 30 fps targets.
