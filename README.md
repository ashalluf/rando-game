# Perf audit stills (branch wt/perf-audit, HANDOFF "Frame cost after the 2026-10-05 wave")

opengl3 (Compatibility) stills from `tools/glshot/still_shot.gd` with `DIFF=1` (cars, people,
particles hidden so two runs render the same frame), 1280x720, noon, `--quality=0`; before = main
885795c, after = wt/perf-audit. Heatmaps from `tools/glshot/img_diff.py` (red = pixels that moved).
Not the Mac's Forward+.

| File | What |
|---|---|
| 01_downtown_before.jpg / 02_downtown_after.jpg / 03_downtown_diff.jpg | Flower at Olympic (`--spawn=2359.4,880,0,12,2`): 6.41 -> 6.10 M triangles, 3,413 -> 3,050 draws; 167 pixels moved |
| 04_masjid_before.jpg / 05_masjid_after.jpg / 06_masjid_diff.jpg | The masjid aerial with the Coral Line's structure: 7.87 -> 7.41 M, 4,627 -> 3,974; 0.48 % moved - the overhead wires' dotted shadows on the deck and the street |
| 07_beachtown_before.jpg / 08_beachtown_after.jpg / 09_beachtown_diff.jpg | The beach town (`--spawn=-648,60,140,-3`): 7.40 -> 4.55 M (the lawn grass in 32 m cells), 1,856 -> 1,611; 67 pixels moved |
| 10_rail_sleepers_dropped_variant.jpg | Top: before. Bottom: the first version, which also took the rails and sleepers out of the shadow pass - their shadow edges on the ballast went, so it was not kept (the shipped cut is the wires only) |
