# rc5-friday-lights stills

New refcam5 view `friday_lights` (tools/refcams/cameras_w8.json): Harbor Crest High's stadium on a
game night, 20:00 clear, from the north-east corner of its car park.

- `01_before_friday_lights.jpg` - the refcam on main (RC5_FRIDAY_LIGHTS=0, opengl3): the lot is
  bare asphalt (no stalls, no cars: it straddles a chunk border), the field lit by six additive
  pools, empty stands, no game.
- `02_after_friday_lights.jpg` - the refcam after (opengl3): the lot built and full, the field
  floodlit by the standards' real spotlights, glare over the lens banks, the home stands full, the
  teams at a line of scrimmage.
- `03_before_fwdplus_field.jpg` / `04_after_fwdplus_field.jpg` - the stadium alone on Forward+
  (lavapipe, fwd_block_shot BLOCKS=home, 90 frames) from the south end of the track: the Mac's
  renderer. Luma p5/p50/p95 12/26/58 -> 26/49/135.
- `05_after_lot_eye_small_scene.jpg` - the camera's eye in the small scene (block_shot, opengl3).
- `06_ten_cameras_off_vs_on.jpg` - the ten original refcams with RC5_FRIDAY_LIGHTS=0 vs on: two
  flagged (street_noon, freeway), both only moving traffic.

`02_after_friday_lights.jpg` is the final run, on the branch merged with main batch 58.
