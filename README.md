# Chinatown stills (wt/chinatown)

First batch, 2026-10-05. opengl3 (Compatibility) via tools/glshot/block_shot.tscn: only the
FULL blocks round each eye are built (no far city, no traffic), NIGHT=1 is block_shot's crude
night (lamp globals on, no DayNight). Not Forward+.

| file | what |
|---|---|
| 01_before_broadway_north_of_cesar_chavez_noon.jpg | N Broadway north of Cesar Chavez before (CHINATOWN=0), EYE=2994,1.7,-1755,0,14 |
| 02_after_broadway_gate_noon.jpg | the same eye after: the gate, lantern strings, tiled-roof shop rows (tents here were turned off afterwards) |
| 03_after_broadway_gate_night.jpg | the same at night: lanterns lit, shops lit, light pools |
| 04_before_plaza_block_aerial.jpg | the Hill-Broadway block before, EYE=2950,55,-2050,10,-35 |
| 05_after_plaza_aerial_noon.jpg | the plaza: pagoda-roofed hall, shop rows round the court, two gates, pond, lantern masts |
| 06_after_plaza_hall_from_walk_noon.jpg | the hall from the walk (before the court's side rows were added) |
| 07_after_plaza_hall_night.jpg | the hall at night |
| 08_before_district_aerial.jpg | the district's south blocks before, EYE=2940,55,-1850,10,-32 |
| 09_after_district_aerial_noon.jpg | after |
| 10_after_plaza_aerial_night.jpg | the plaza from the air at night |
| 11_after_side_street_noon.jpg | a shop's side and blade sign from a side street |

## Final set (after: deferred build jobs, side windows, stepped-back deep lots, court rows, the plaza crowd)

| file | what |
|---|---|
| 12_final_broadway_gate_noon.jpg | up Broadway through the gate, EYE=2994,1.7,-1755,0,14 |
| 13_final_broadway_gate_night.jpg | the same at night (lanterns, signs, shops, light pools) |
| 14_final_plaza_hall_with_people_noon.jpg | the Hall of Spring Wind from the walk, people in the court |
| 15_final_plaza_hall_night.jpg | the same at night |
| 16_final_plaza_aerial_noon.jpg | the plaza from the air: hall, rows round the court, gates, pond, masts |
| 17_final_district_aerial_noon.jpg | the district's south blocks from the air |
| 18_final_side_street_noon.jpg | a side street: a shop's side windows and blade sign |
| 19_final_side_street_night.jpg | the same at night |

## Night light pass (lead review), re-shot 12-15, 18, 19

Shot with `tools/glshot/still_shot.gd` (opengl3, full city, `--spawn=2994,-1745,0,4`), EYEs:
gate `2994,1.7,-1755,0,14`, hall `2927.7,9.8,-2095,0,10`, side street `2984,8.3,-1975,0,6`;
21:00 and 13:00. The lantern strings now hang over the street (they were displaced in the
earlier 12-19). Luma p5/p50/p95 at 21:00: gate 8/35/189 (the street below the skyline
7/73/199; the night sky is ~40 % of the frame), hall 15/42/189, side street 10/52/201
(were 9/13/70 at the gate before).
