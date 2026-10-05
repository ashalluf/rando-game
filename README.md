# shots/stadium - the ballpark in the ravine (wt/stadium, HANDOFF "The ballpark in the ravine")

opengl3 stills at 1280 x 720 (tools/glshot/still_shot.gd). `_before` is the same EYE with
`BALLPARK=0` (the hills as they were), `_after` with the park.

| still | EYE (x, y, z, yaw, pitch @ hour @ fov) |
|---|---|
| aerial_noon | 2150,360,-2560,29,-35 @ 12 (the far copy: the anchor's chunk is not FULL from there) |
| stands_to_downtown_golden | 2017.9,198,-2690,-164,-3 @ 17.6 @ 55 (from the top of the stands behind home toward downtown) |
| night_game_from_hills | 1560,250,-2905,-97.5,-9 @ 21.5 @ 40 |
| field_from_home_plate | 2008.2,143.9,-2776,6.4,1 @ 15 @ 60 |
| bowl_from_centre_field | 1997.4,153,-2872.4,-173.6,6 @ 15 @ 60 |
| bowl_from_centre_field_night | 1997.4,153,-2872.4,-173.6,6 @ 21.5 @ 60 |

Frame cost (GEO, triangles / draws), before -> after: aerial 716 k / 139 -> 613 k / 63; stands to
downtown 3.52 M / 928 -> 3.47 M / 759; night from the hills 1.34 M / 415 -> 1.22 M / 291; home plate
1.21 M / 502 -> 1.50 M / 253; centre field 3.12 M / 854 -> 3.45 M / 629; centre field at night
3.09 M / 808 -> 3.44 M / 626.

## Wave 2 (merge with fleet/base, fixes) - `w2_*`

opengl3, 1280 x 720, `tools/glshot/still_shot.gd` with `--spawn=2010,-2600,0,0`. `before` is the
merged branch with the old road profiles (f07c1f99's `ballpark.gd`), `after` the fix.

| still | EYE (x, y, z, yaw, pitch @ hour) |
|---|---|
| w2_01 / w2_02 sunridge_dr_valley_end | 2010,175,-3300,99,-31 @ 15 - before: the drive sunk 5-8 m in a ditch where it reaches the valley's streets; after: flush |
| w2_03 / w2_04 stadium_way_hill_st_end | 2835,45,-2095,-24,-25 @ 15 - the road's foot at Hill St (the first shot of a load streams round the spawn, so the blocks there are far city: the flat plates and lilac canopy blobs are the far tier seen close, not the park) |
| w2_05 aerial_noon | 2150,360,-2560,29,-35 @ 12 (the far copy) |
| w2_06 bowl_from_centre_field | 1997.4,153,-2872.4,-173.6,6 @ 15 |
| w2_07 night_game_from_hills | 1560,250,-2905,-97.5,-9 @ 21.5 |
| w2_08 valley_toward_ballpark | 1960,143.5,-3385,175,1 @ 15 |

GEO (triangles / draws): aerial 1.41 M / 322, bowl 3.39 M / 586, night 1.43 M / 463, valley 4.51 M / 1309.
