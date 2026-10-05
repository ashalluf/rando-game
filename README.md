# shots/parks - rec parks, schoolyards and sports grounds (branch wt/parks, HANDOFF 9bn)

All opengl3 (Compatibility) stills, 1280x720, seed 1337, `tools/glshot/still_shot.gd` unless noted.
"Before" is the same commit with `PARKS=0`.

| File | What | How |
|---|---|---|
| 00_BEFORE_aerial_suburb_PARKS0.jpg | BEFORE: the suburb aerial with parks off (houses on the school block, leafy lawn parks) | `PARKS=0 EYE=1911,150,4260,0,-42 EYE_AGL=1 --hour=12.5` |
| 01_aerial_suburb_school_and_parks_day.jpg | AFTER: an elementary school in full detail (wings, drop-off, car park, courts, playground, bungalow, yard), rec parks with courts, fields and diamonds in the LOD ring behind | same eye, parks on |
| 02_aerial_rec_park_diamond_day.jpg | A rec park from the air: the diamond in its corner with its mowing, backstop, dugouts | `EYE=354,140,-2640,0,-42` 13:00 |
| 03_aerial_high_school_track_day.jpg | The high school (block 10,4): a 337 m 4-lane track round a football field, bleachers, floodlights, wings, car park (early turf colour, before the backstop fix) | `EYE=966,90,860,0,-42` |
| 04_courts_pickup_basketball.jpg | Eye level: two courts with pickup players, hoops, floodlights | `EYE=-252,1.7,-2486,20,-5` |
| 05_diamond_from_the_bleachers.jpg | The diamond from the first-base bleachers: fielders, dugout, infield chalk | `EYE=50.5,2.6,-17.5,-38,-5` 15:00 |
| 06_track_and_football_field.jpg | From the stands: lanes, yard lines and hash marks, the end zone in the school colour | `EYE=1001,5.5,700,90,-9` 17:00 |
| 07_diamond_at_night_floodlights.jpg | The rec park at 21:18: the diamond under its floodlights, lit pools | `EYE=95,30,5,40,-32` |
| 08_pool_traced_water.jpg | The 25 m pool from above: the traced tank (tiles, lane T-lines, caustics), lane ropes, coping, guard chair | `tools/glshot/block_shot.tscn EYE=-205.8,12,-2468,0,-38` |
| 09_pool_eye_level.jpg | The pool at eye level: refraction, waterline band, rec centre behind | `block_shot.tscn EYE=-200,1.7,-2480,350,-14` |
| 10_rec_park_playground_rec_centre.jpg | Playground, rec centre, picnic shelters, car park, a diamond (early: before the backstop fix) | `EYE=52,70,-10,0,-45` |
| 12_track_night.jpg | The high school's track at 21:18 (corner of the frame) | `EYE=975,30,640,40,-30` |

Coverage (`tools/lot_coverage.gd RECT=-1500,-3600,3000,5100`): REC blocks (39) bare 0 %, sport 52.8 %,
garden 40.7 %; SCHOOL blocks (4) bare 0 %, sport 80.1 %; SUBURBS bare 8.3 -> 7.2 %.
Frame cost: see HANDOFF 9bn (geo_count: -5 % to -41 % triangles, -2 % to -12 % draws at three spawns).
