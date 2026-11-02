# perf-audit-5 stills

- `01_wheel_side_ab.jpg` - one sedan in car_shot, side view crop x3: top main (near wheel 12-14k triangles casting its own shadow, no LODs), bottom branch (40-segment shadow twin, wheel LODs). Frame 207k -> 114k triangles, 295 pixels differ.
- `02_wheel_side_full_ab.jpg` - the same pair, whole frame.
- `03_compare_street_noon.jpg` - refcam street_noon: main | branch | difference (only the bus and walkers that moved between runs). -4.1 % triangles.
- `04_compare_freeway.jpg` - refcam freeway: main | branch | difference (traffic moved). -11.9 % triangles.
- `05_refcams_sheet_main.jpg` - main's eight cameras (the ninth OOM-killed on the box's first-ever run).
- `06_refcams_sheet_branch.jpg` - the branch's ten cameras with their costs.
