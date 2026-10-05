# Road wear stills (session road-wear, branch wt/road-wear)

opengl3 (Compatibility) stills; the Mac draws Forward+.

First batch (work in progress):
- 01-03 `before`: the downtown avenue, an old midtown street and an industrial street at 13:00, before RoadWear (the road shader's own procedural patches and crack net only).
- 04 `wip`: four block shots from chase-camera height (midtown, industrial x2, a midtown avenue) with the first tuning of the stamps.
- 05 `wip`: the 25-stamp library laid on a strip of real road (tools/road_wear/showroom.tscn).
- 06 `wip`: deep potholes with parallax occlusion (the same stamp eight times: thresholds, mirror, age).

Final batch (after, branch head 29a000f; `tools/road_wear/shots.sh` places, `still_shot.gd` city stills, the car park a `block_shot.tscn`):
- 10 the downtown avenue (2239.5, 640) - light wear by design (DOWNTOWN_AVENUE 0.55): sealed joints, a few patches.
- 11 an old midtown street (1786.3, 2100) - patches, sealed transverse cracks, alligator in the wheel path, edge break.
- 12 an industrial street (2493.6, 2320) - the heaviest level: ruts, shoving, oil, utility cuts.
- 13 a surface car park (1768, 2100, 7 m up) - sparse cracks and stains. The pale soft rectangles are LotFill's own lot ground (there with ROAD_WEAR=0).
- 14 a deep pothole close up at 13:00 (1967.3, 2350.9): parallax depth, cracked surround, standing water in the hollow.
- 15 the same at 13:00 in rain: the hollow a mirror with rain rings.
- 16 the midtown street in rain.
- 17 the midtown street from 30 m up.
