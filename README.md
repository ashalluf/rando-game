# rc2-canyon-road stills

Refcam `canyon_road` (tools/refcams/cameras_w5.json): a front-range switchback (Switchback 35), eye
1.7 m over the uphill lane at (545, -1927.6) looking SSE down the road, 17:40 clear: the road, the
guardrail on the fill side, a hill home, chaparral, downtown in the smog. opengl3 (Compatibility)
through refcams.py (occlusion culling off: see the HANDOFF section on the engine hang).

- `01_before_canyon_road.jpg` - main (CANYON_ROAD=0): a plain tiled strip, no markings, a hard edge,
  pale boulders sat on the bank like eggs.
- `02_after_canyon_road.jpg` - the canyon road: worn double yellow, white edge lines, sealed joints,
  a gravel shoulder, a W-beam guardrail on timber posts along the drop, boulders gathered and bedded.
- `03_along_the_road_before_after.jpg` - small scene (hill_ground_shot), looking along the
  switchback: before (top), after (bottom).
- `04_ten_cameras_compare.jpg` - refcams.py compare, all ten cameras + canyon_road, CANYON_ROAD=0 against
  on (one load each): only canyon_road changes; freeway is flagged for moved traffic only.
- `05_hills_refcam_before_after.jpg` - the hills refcam (260 m) off / on: unchanged within a level.
