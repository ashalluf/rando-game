# shots/perf-audit-4

Perf audit 4 (wt/perf-audit-4): the ten refcams' frame cost against wave 2. opengl3 + llvmpipe,
1280x720, `refcams.py --strict` (people, cars, particles hidden; shader TIME held). BEFORE = main
behaviour (HORIZON_TILES=0 FAR_COVER_HIDE=0, the other cuts did not exist yet), AFTER = the branch.

- 01_before_after_beach.jpg - beach: 0.72 M -> 0.55 M triangles (the horizon plane and far ring culled); 02_diff_beach.jpg = pixels over 8 levels in red (129)
- 03_before_after_sunset.jpg - sunset: 2.73 M / 1,786 draws -> 2.45 M / 1,119 draws (ground-cover plants merged); 04_diff_sunset.jpg (2,563 px; an A/A pair differs by 1,390)
- 05_before_after_macarthur.jpg - MacArthur Park: 5.66 M / 3,373 -> 5.10 M / 3,027; 06_diff_macarthur.jpg - the palm-shadow speckle on the lawn (the one cut that moves pixels)
- 07_before_after_hills.jpg - hills: -10 % triangles
- 08_before_after_street_noon.jpg - street at noon: -4 % triangles, -4 % draws, 53 px changed
- 09_refcams_sheet_main.jpg - main's plain refcams sheet (8 cameras; the run was OOM-killed at the 9th with SPLIT on)
- 10_refcams_sheet_branch.jpg - the branch's plain refcams sheet (all ten)
- 11_compare_strict.jpg - refcams compare of the strict pair (flagged = triangles or draws moved > 10 %)
