# Backyard life (wt/backyards) - stills

Suburbs south of downtown on the default seed (1337), opengl3 (the Compatibility renderer, not the
Mac's Forward+). Each "before" is `BACKYARDS=0`, the same camera and hour as the "after" next to it.
Nothing is forced: the grill smoking at 18:30 is a household that cooks that night (55 % do).

| files | view |
|---|---|
| 01 / 02, 03 / 04 | 150 m over block (21,31), noon / 21:00 (`EYE=2097,150,4278,0,-55`) |
| 05 / 06, 07 / 08 | 45 m over the same back yards, noon / 21:00 (`EYE=2097,45,4218,0,-50`) |
| 09 / 10, 11, 12 / 13 | over the fence onto one patio (teak set, umbrella, kettle grill, string lights): noon, 18:30 (smoke, the fire at the lid), 21:00 (bulbs, the patio's glow) (`EYE=1513.8,6,3987.6,0,-22`, 6 m above the ground) |
| 14 / 15 | a 12 ft trampoline with its net, a bistro set under an umbrella (`EYE=1532.3,6,3905.1,180,-22`) |
| 16 / 17 | loungers by a pool, a kettle grill against the house (`EYE=1526.4,6,3903.3,90,-22`) |
| 18 / 19 | 40 m over that patio at 21:00 (`EYE=1513.8,40,4012,0,-55`) |

Frame cost (triangles / draws, before -> after): 150 m 2.91 M / 1,387 -> 3.09 M / 1,408; 45 m
3.63 M / 1,569 -> 3.77 M / 1,622; patio 7.50 M / 2,759 -> 7.61 M / 2,847.

## Wave 3 (merged with main 95bd13f; sunbathers)

| files | view |
|---|---|
| 20 / 21 | two sunbathers on a lawn lounger pair, 14:00 (`EYE=956,6,3739.3,90,-22`, 6 m above the ground) |
| 22 / 23 | 30 m over that yard, 14:00 (`EYE=947,30,3760,0,-55`) |
| 24 / 25 | 45 m over block (21,31), 14:00, after the merge (apartments next door) |
| 26 / 27, 28 / 29 | 150 m over block (21,31), noon / 21:00, after the merge |

Frame cost (triangles / draws, `BACKYARDS=0` -> on): lounger 5.11 M / 2,340 -> 5.29 M / 2,462;
30 m 4.64 M / 2,387 -> 4.58 M / 2,452; 45 m 3.71 M / 1,475 -> 3.82 M / 1,532; 150 m noon 3.13 M /
1,431 -> 3.28 M / 1,448; 21:00 3.11 M / 1,421 -> 3.25 M / 1,440.
