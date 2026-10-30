# far-ranges stills

opengl3 1280x720 (`still_shot.gd` SHOTS from one load, `--hour=15`), FAR_RANGES before / after:
- 01/02 the hills refcam (300, 275, -650) north, 15:00; 03/04 the same at 17:18 (golden hour)
- 05/06 downtown looking north (2600, 120, -450), 15:00; 07/08 the same at 17:18
- 09/10 the 110 deck by downtown, looking north
- 11/12 the east range from downtown (2800, 150, 100) looking east
- 13/14 Forward+ (lavapipe, `hill_ground_shot.tscn GROUND=1 DAYNIGHT=1`, EYE 600,180,-1000,0,2): the horizon plane and the hill tiles alone (no city), FAR_RANGES=0 vs 1
- 15/16 `tools/far_ranges/probe.tscn` panoramas of raw heights (no shader): the old skyline vs the first pass, and the final downtown (top) and hills (bottom) skylines
Note: 13/14 "after" predates the last haze-tone change (bluer, darker: range_haze_tone 0.66, 0.78, 0.95); 02-12 have the final shape and ring but the older tone too.
