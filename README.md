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

## Wave 2: the cuts re-measured on the merged tree (wt/perf-audit + fleet/base 92945c7)

`wave2/`: before = origin/fleet/base, after = the merge, same 960x540 `DIFF=1` frames (one load,
`SHOTS=` chain, `EYE_AGL=1`), noon. Shot as PNG, saved as JPG here.

| File | What |
|---|---|
| 01/02 downtown_noon | 6.40 -> 6.09 M triangles, 3,418 -> 3,055 draws; 255 pixels moved (0.03 %) |
| 03/04 masjid | 5.52 -> 5.15 M, 2,935 -> 2,480; 1.1 % moved: the rail wires' dotted shadows (see 11) |
| 05/06 police_station_lawns | Police HQ (EYE 3652,1.7,-1079): 5.87 -> 3.99 M (-32 %: the lawn grass cells), 1,530 -> 1,432; 0.1 % moved |
| 07/08 macarthur_aerial | 4.14 -> 4.01 M, 2,601 -> 2,111; 0.15 % moved (furniture shadows past their reach, see 12) |
| 09/10 stack | The four-level stack: 3.16 -> 3.08 M, 1,974 -> 1,824; 0.03 % moved |
| 11 masjid_diff_merged, 12 macarthur_diff_merged | where the pixels moved (red) |
