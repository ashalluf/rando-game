# shots/rc2-night-aerial

New reference camera `night_aerial` (tools/refcams/cameras_w5.json): downtown and the basin from
the south-west, 350 m up, 22:30, clear. opengl3 (Compatibility) stills via refcams.py; the
before / after pairs are the same build with `NIGHT_AERIAL=0` / on (one city load each).

- 01_before_night_aerial.jpg - main (bb03d731), before any change.
- 02_before_night_aerial_ab_off.jpg - the branch with NIGHT_AERIAL=0 (= main's look).
- 03_after_night_aerial.jpg - the branch, NIGHT_AERIAL on.
- 04_before_after_freeways_crop.jpg - left before, right after: the near freeways were a solid cream
  slab with a row of white discs; now rivers of single headlights / tail lights, the far streets too.
- 05_before_after_floodlit_boxes_crop.jpg - the orange "ember" boxes (floodlit masonry on 60 % of
  brick / render) down to a fifth, cooler.
- 06_refcams_all11_compare.jpg - the ten refcams + night_aerial, off over on (refcams.py compare):
  only freeway (traffic moved, noise) and night_aerial flagged.
