# busy-streets stills

opengl3 (Compatibility) stills from tools/glshot/still_shot.gd, 1280x720, free camera at street level
(EYE, 1.7 m AGL; the freeway one 30 m up), FRAMES=90 (freeway 45). "before" = `BUSY_STREETS=0`
(the code on main), "after" = the branch. Each log's CENSUS line (tools/busy_streets/census.gd):

| still | moving cars <150 m (in view) | queued <150 m | parked <150 m | walkers <60 m | tris / draws |
|---|---|---|---|---|---|
| 01_before_downtown_noon (Flower at Olympic, north) | 21 (5) | 6 | 11 | 33 | 6.45 M / 3,017 |
| 02_after_downtown_noon | 36 (7) | 7 | 11 | 33 | 6.63 M / 3,146 (+2.8 % / +4.3 %) |
| 03_before_broadway_2200 (Broadway south from 6th) | 20 (6) | 4 | 22 | 57 | 6.52 M / 3,476 |
| 04_after_broadway_2200 | 23 (7) | 11 | 37 | 57 | 6.60 M / 3,519 (+1.3 % / +1.2 %) |
| 05_before_midtown_noon (Wilshire, midtown, west) | 16 (2) | 5 | 36 | 35 | 5.14 M / 2,691 |
| 06_after_midtown_noon | 49 (7) | 13 | 60 | 35 | 5.35 M / 2,711 (+4.1 % / +0.7 %) |
| 07_before_freeway (frame cost) | 5 | 1 | 43 | 8 | 4.20 M / 1,985 |
| 08_after_freeway | 24 | 2 | 60 | 8 | 4.29 M / 2,039 (+2.2 % / +2.7 %) |

The 01 "before" (one car on Flower at noon) is the bug: PhysicsBudget full of the kerbs' parked cars
at load dropped every queued street spawn, and the spawns that ran landed 60-260 m off in a 380 m
circle. A still is a single instant; the census over ten minutes of play (headless) at the downtown
bookmark went from 37 cars within 150 m (26 moving, 5-9 in view) to 53-61 (35-41 moving, 7-17 in view).
