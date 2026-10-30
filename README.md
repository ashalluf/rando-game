# police-night stills (wave 3)

Police at night (PoliceNightLook). Before = `POLICE_NIGHT_LOOK=0`.

- 01/02 city, downtown (Flower at Olympic), STARS=3 POLICE=pursuit, 23:00, opengl3 (Compatibility: washes only). Blue pool and lens glare on the cruisers.
- 03/04 city, STARS=3 POLICE=standoff AIR=police, 00:30, rain, opengl3. The white road is in BOTH (an existing opengl3 rain-night issue, not this branch).
- 05/06 small street (tools/police_night/police_shot.gd), Forward+ on lavapipe, rain: before/after (real red/blue OmniLights on road, walls, cars).
- 07 Forward+ at road level, wet road. 08 Forward+ the roadblock with its burning flares.
- 09 frame strip of the flash pattern, 0.05 s apart (opengl3 small street): red and blue alternate, pool, facade washes, lens flares and streaks.
- 10 opengl3 small street, rain.

Frame cost during the pursuit (still_shot GEO, opengl3): 4,312 -> 4,323 draws, 9.174 M -> 9.182 M triangles.
