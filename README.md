# shots/rc5-rush-hour

The `rush_hour` reference camera (tools/refcams/cameras_w8.json): the 105 at 17:40 clear from the
caged footbridge east of the 110 (fb_f_1_213), looking west down the carriageways into the low sun.
opengl3 stills (the Compatibility renderer, not the Mac's Forward+), 1280x720.

- `01_before_rush_hour_main.jpg` - main (or `RUSH_HOUR=0 RC5_RUSH_LOOK=0`): the freeway is EMPTY at
  5:40 pm. The freeway upkeep returned before spawning whenever PhysicsBudget sat at its cap, which a
  busy city always does.
- `02_after_rush_hour_traffic.jpg` - RushHour, first pass: jammed lanes, stop-and-go waves, brake
  lamps (the carriageway driving away from the lens still thin).
- `03_after_rush_hour_final.jpg` - final: the cap spent ahead of the camera, both carriageways full.
- `04_after_rush_hour_brake_lights_crop.jpg` - 3x crop at the gantry: brake lamps in clusters on the
  westbound lanes, trucks in the slow lanes, the sign backs of the eastbound gantry.
- `05_before_deck_patches_crop.jpg` - the bottom of the before: the deck's asphalt patches as black
  tiles in a concrete deck shining into the sun (RcRushHour's `patch_aged`; in the after the patches
  are mostly under cars).
- `06_ten_cameras_before_over_after.jpg` - the ten original cameras, before (RUSH_HOUR=0
  RC5_RUSH_LOOK=0) over after, one tree: only `freeway` is flagged, and that is its traffic (a semi
  filled the lens in the before; the after has more cars now that freeway spawns do not wait on the
  physics cap). The rest within noise (triangles -1.1..+0.2 %).
