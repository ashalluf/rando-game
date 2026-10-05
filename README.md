# shots/fwd-review-b - Forward+ review of the marina, blast aftermath, climbers, building damage, new crowd rigs, schools

All Forward+ stills are the real Forward+ pipeline under lavapipe (software Vulkan), SMALL scenes only:
`tools/glshot/block_shot.tscn` (a few FULL blocks), `tools/glshot/damage_shot.gd`, `tools/glshot/crowd_lineup.gd`,
and three probe scenes (a crater alone, the four boat types, a palm / charred palm / smoke column). Pairs are
left = before (or Forward+), right/bottom = after (or opengl3) as named.

| file | what |
| --- | --- |
| 01_crater_before_after_fwdplus | crater decal, sun from the south: before the pit read as a dome (normal map's green inverted); after its north wall takes the light |
| 02_blast_hole_day_before_after_fwdplus | rocket hole in brick, noon: before the hole room drew pale on Forward+; after it is the dark burnt room the opengl3 stills show |
| 03_blast_hole_night_before_after_fwdplus | the same at night: before a washed beige blob through AgX; after deep ember orange |
| 04_blast_hole_night_opengl3_reference | the opengl3 look the hole was tuned on (the target) |
| 05/06_smoke_column_{day,night}_before_after_fwdplus | smoke column: sky_tint now decoded, the plume darker / oilier |
| 07_marina_night_water_before_after_fwdplus | marina at night: before the whole basin a flat orange-brown sheet; after dark water, glints near the lamps |
| 08_marina_day_before_after_fwdplus | marina by day (water mirror after the sky decode) |
| 09_boats_backfaces_before_after_fwdplus | the four boat types (top before, bottom after the back-face normal fix) |
| 10_school_glass_before_after_fwdplus | Jacaranda elementary's classroom glass (sky mirror no longer re-encoded; small at this angle) |
| 11_crowd_m_to_t_fwdplus_vs_opengl3 | the eight new rigs m..t, Forward+ top, opengl3 bottom: consistent, no fix needed |
| 12_climbers_fwdplus_vs_opengl3 | beach-town street with bougainvillea: consistent, no fix needed |
| 13_storefront_damage_fwdplus_vs_opengl3 | crazed / shattered shop glass: consistent |
| 14_charred_palm_fwdplus_vs_opengl3 | living palm, charred palm, charred tree, smoke column (before the column fix) |
