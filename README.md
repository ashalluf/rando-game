# rc5-surf-dawn stills (refcam5 `surf_dawn`, tools/refcams/cameras_w8.json)

07:00 clear, from the water on the wave's shoulder just past the break off the beach town (z ~790),
looking down the line at a surfer riding a set wave in. Shot with
`REFCAMS_JSON=tools/refcams/cameras_w8.json python3 tools/refcams/refcams.py run <dir> --only surf_dawn`.

- 01_before_surf_dawn.jpg: main 8c0de652 with BEACH_STAGE=806, the first eye (water past the break
  looking ENE): no rider in frame (the ride did not know where the drawn waves are), a flat sea,
  dotted rectangles of sparkle on the water.
- 02_before_ab_off_surf_dawn.jpg: the final eye with RC5_SURF_DAWN=0 (the A/B: everything of this
  branch off but the row's staging): the wave there, nobody riding it, no spray.
- 03_after_surf_dawn.jpg: the final eye, this branch: the surfer on the set wave's face (SurfRide),
  the rail spray and the lip mist blown back by the offshore breeze, a dawn lineup sitting outside.
- 04_wip_lattice_sparkles_on_the_sea.jpg: a mid-session frame showing the dotted grid on the water
  (value-noise lattice zeros lit by the sun's sparkle) that ripple_rot / capillary_rot remove.
- 05_after_surf_dawn_rider_crop.jpg: 3x crop of 03 round the rider.
