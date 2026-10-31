# wet-road-mirror stills

The wet road at night (21:30, rain): road.gdshader's mirrored city drew lit windows on a fixed grid
(squares across the carriageway); now streaks and smears under shop fronts, blurred mostly in
elevation by a per-pixel roughness field, glints fixed to the road, sharp-ish only in puddles.

- 01 / 02: the street_night refcam before (main) / after (opengl3, the whole city).
- 03: its road, before over after (crop).
- 04: tools/wet_road_mirror/mirror_shot.gd on opengl3, the OLD mirror - the grid of window tiles.
- 05 / 06: the same small scene on Forward+ (lavapipe), old / new (SSR blend kept on top).
- 07 / 08: the downtown and Wilshire FULL blocks (fwd_block_shot on opengl3), old over new.

Dry road: bit-identical on Forward+ (0 pixels differ, WET=0 both switches).
