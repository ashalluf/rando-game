# shots/rc2-marine: the new reference camera `marine_morning`

The beach town at 08:00 under the marine layer (June gloom), 11th St looking west toward the sand
(`tools/refcams/cameras_w5.json`, eye -585, 1.7 agl, 1205, yaw 91, pitch 0.5, fov 55). opengl3 stills
(Compatibility renderer) from tools/refcams/refcams.py.

- 00_candidate_venice_blvd.jpg - a candidate framing not taken (Venice Blvd toward the sea).
- 01_before_marine_morning.jpg - main (bb03d731): bone-dry street, a flat featureless grey ceiling
  (the deck's underside varies by ~3 grey levels), the end of the street at the sand as crisp as the
  foreground.
- 02_after_marine_morning.jpg - wt/rc2-marine: the street damp from the mist (soaked dark and matte,
  a sheen only far off), the deck's underside as stratocumulus cells, the coast's mist softening the
  sand and the headland at the end of the street.
- 03_tried_patchy_drying.jpg - tried and dropped: the damp as the after-rain drying patches (they read
  as hard-edged oil stains).
- 04_tried_even_film_too_light.jpg - tried and dropped: the damp as a shower's even film (the grey sky
  in it made the street LIGHTER than dry). The kept look is road.gdshader's new `road_mist`.
- 05_forward_plus_deck_before.jpg / 06_forward_plus_deck_after.jpg - Forward+ (lavapipe), the sky
  alone (fwd_block_shot BLOCKS=0, pitch 12): MARINE_MORNING=0 vs on. Same cells, neutral cool grey.
- 07_before_over_after.jpg - before (top) over after (bottom), same camera.
