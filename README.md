# perf-audit-3 stills

DIFF=1 pairs (opengl3 / llvmpipe, 960x540; cars, people and particles hidden, the clock held):
main 149fbb5 ("before") against wt/perf-audit-3 ("after"). They should look the same - that is
the point: the triangles went, the pixels did not.

- 01_before_downtown_noon.jpg / 02_after_downtown_noon.jpg: 7.54 M -> 6.84 M triangles, 63 pixels differ (none by more than 3 levels).
- 03_before_hills.jpg / 04_after_hills.jpg: 2.71 M -> 2.19 M; 1,199 pixels differ, the same as two runs of main (1,166).
- 05_before_macarthur.jpg / 06_after_macarthur.jpg: 6.86 M -> 6.21 M; 7 pixels differ.
- 07_hills_crop_before_left_after_right.jpg: the hills' differing area, 3x, before left, after right
  (the same distant-detail jitter shows between two runs of main).
