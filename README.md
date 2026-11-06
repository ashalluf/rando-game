# shots/rc5-stunt-jump

Wave 8 refcam `stunt_jump` (tools/refcams/cameras_w8.json): a car mid-flight off the freeway
stunt pair's launch kicker over the 105 at 16:30 clear. opengl3 (Compatibility) stills from
`REFCAMS_JSON=tools/refcams/cameras_w8.json python3 tools/refcams/refcams.py run <dir> --only stunt_jump`.

- `01_before_stunt_jump.jpg` - main's code, the first framing (low eye on the run-up): the car
  is inside a eucalyptus crown of the right of way's tree row, a speck; the landing is hidden
  behind the freeway; no dust; the tread plate a flat blue-grey sheet.
- `02_before_stunt_jump_same_frame.jpg` - the final camera (a crane-style eye beside the launch
  kicker's lip, 10.5 m over its foot) with `RC5_STUNT_JUMP=0` (main's look): the car flies
  through the right of way's eucalyptus row, wheels tucked up as if parked, no dust, the landing
  across the 105 a plain orange box under the deck, the tread plate a blue-grey sheet.
- `03_after_stunt_jump.jpg` - the same frame on the branch: the tree crowns in the jump's flight
  box are gone, a dust plume off the lip and a stream of it off the wheels up toward the car, dirt
  clods thrown with it, the wheels hanging to their stops, the landing's front hazard-banded so
  it reads as the landing, the plate as welded zinc sheets with rubber and dirt.
- `04_after_car_and_dust_crop.jpg` / `05_before_car_crop.jpg` - 2x crops of the car and the lip.
- `06_ten_cameras_compare_off_vs_on.jpg` - the ten original cameras, RC5_STUNT_JUMP=0 over on:
  7 ok; street_noon, street_night and freeway flagged on pixels only.
- `07_diff_street_night_live_traffic.jpg` - that flag's difference: buses, walkers and raindrops
  placed differently run to run (and the wet street's reflections of them); nothing of this
  branch is in the view.
