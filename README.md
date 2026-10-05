# shots/stadium - the ballpark in the ravine (wt/stadium, HANDOFF 9bs)

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
