# Ridges stills (wt/ridges, VISUAL_ROADMAP #63, HANDOFF 9bu)

Rendered with `tools/ridges/ridge_shot.tscn` on the Compatibility renderer (opengl3, Xvfb, llvmpipe): the real chunks around a piece, the far node and the horizon plane, without the whole city. This is NOT what the Mac's Forward+ renderer draws.

- `ridges_line_over_ridge_golden_hour.jpg`: the Northern 220 kV line over the east range at 17:42 (`TOWER=5 DIST=95 AZ=283 UP=6 AIM=0.75 FOV=62 GROUND=1 BLOCKS=2 LOD=5 -- --hour=17.7`). `_BEFORE` is the same view with `RIDGES=0`.
- `ridges_antenna_farm_from_basin_2200.jpg`: the antenna farm's red lights seen from the basin at 22:00 (`EYE=2350,210,-150,1.1,3.5 FOV=32`). `_BEFORE` is the same view with `RIDGES=0`.
- `ridges_tower_close_up.jpg`: a 72 m suspension tower from its foot at 10:30.
- `ridges_fire_road_from_the_air.jpg`: a fire road along an east-range crest at 09:30.
- `ridges_substation.jpg`: the Vernon substation and the right of way at 11:00.
- `ridges_antenna_farm_day.jpg`: the farm's masts on their benches at 15:30. Only the farm's chunks are built here, so the basin behind it is empty.

## After merging fleet/base (2026-10-05, wave 2 update)

Same harness (`tools/ridges/ridge_shot.tscn`, opengl3, not Forward+), after the merge with fleet/base (the new sky is fleet/base's):

- `10_merged_line_over_ridge_golden_hour_1742.jpg`: the first still's view again (`TOWER=5 DIST=95 AZ=283 UP=6 AIM=0.75 FOV=62 GROUND=1 BLOCKS=2 LOD=5 -- --hour=17.7`); unchanged but for the sky.
- `11_merged_antenna_farm_from_basin_2200.jpg` / `_BEFORE` (`RIDGES=0`): the farm's red lights from the basin (`EYE=2350,210,-150,1.1,3.5 FOV=32 GROUND=1 -- --hour=22`).
- `12_merged_tower_close_up_1030.jpg`: tower 4 from near its foot (`TOWER=4 DIST=28 AZ=200 UP=1.7 AIM=0.55 FOV=70`).
- `13_merged_substation_1100.jpg`: the Vernon substation from the street (`SUB=1`).
- `14_merged_antenna_farm_day_1530.jpg`: the farm's masts and guys (`MAST=0 DIST=160 UP=20 AIM=0.4`).
