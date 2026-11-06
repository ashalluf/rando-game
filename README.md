# Perf audit 6 stills

All opengl3 refcams in `--strict` mode (shader TIME held; people, cars, aircraft, particles hidden),
1280x720. "before" = every perf-audit-6 cut off (ROOF_UNIT_SHADOW=0 PROP_SHADOW_LOD=0 CANOPY_LOD=0,
i.e. main's behaviour), "after" = the branch. Same tree, same box.

- 01-10: before / after for street_noon, golden_aerial, hills, freeway, macarthur.
- 11-13: |before - after| x8 (golden_aerial, hills, street_noon): scattered single pixels at the far
  canopies' edges (the canopy's sub-pixel coarse level) and shadow texels of rooftop AC units.
  Pixels changed (any / > 8 levels): street_noon 1,125 / 289, golden_aerial 2,840 / 292,
  hills 5,264 / 711, freeway 5 / 1, macarthur 1,010 / 79 of 921,600; the A/A pair (two "before"
  runs) differs by 897 / 54, 443 / 0, 1,813 / 825, 22 / 9, 446 / 85.
- 14: golden_aerial's far city and range at 3x, before over after.
