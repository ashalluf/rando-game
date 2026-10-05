# shots/sky (branch wt/sky)

Forward+ (lavapipe), sky alone over a flat ground (`tools/sky/sky_shot.gd`; the whole city does not fit lavapipe):
- 01 / 02 midday cumulus, 13:00 looking north: before (painted deck) / after (volumetric cumulus)
- 03 / 04 golden hour 17:24 toward the sun, coverage 0.5: before / after (silver linings, crepuscular rays)
- 05 a contrail sky, 10:00 (CONTRAILS=7)
- 06 the full moon at 23:00 (moon age 14.8), moonlit clouds
- 07 a crescent at 19:40 (moon age 4), earthshine, stars, a forced light dome tinting the cloud bases

opengl3 (the Compatibility path the web runs: painted clouds, the new moon / stars / dome), the city via `tools/glshot/still_shot.gd`:
- 08 the full moon from the pier at 23:00
- 09 the light dome over the city from the pier, 23:00
- 10 a crescent over downtown, 19:40
- 11 midday over the hills (painted clouds on this renderer)

Follow-up ("less stylised cumulus"), Forward+ sky-only via `tools/sky/sky_shot.gd`, before / after:
- 12 / 13 midday from the street (13:00, north)
- 14 / 15 golden hour from the street (17:24, toward the sun)
- 16 / 17 midday from the air (1,250 m)
- 18 / 19 golden hour from the air (1,250 m)

Second follow-up ("make the clouds read photographic", wave 2), Forward+ sky-only via `tools/sky/sky_shot.gd` on lavapipe, before / after (TAA on, 24 frames):
- 20 / 21 noon from the street (13:00, north): flat dark bases, turreted crowns, torn edges
- 22 / 23 golden hour toward the sun (17:24, west): grey-violet bodies with lit rims, no beige puffs
- 24 / 25 golden hour away from the sun (17:24, east): front-lit bodies, darker undersides, fragments
- 26 / 27 dusk toward the sun (18:09)
- 28 / 29 dusk away from the sun (18:09)
- 30 / 31 noon from the air (1,250 m): crowns broken into turrets of different heights (the old ones were solid domes)
- 32 / 33 golden hour from the air (1,250 m)
- 34 opengl3 (Compatibility) noon: the painted cumulus, untouched by this change
