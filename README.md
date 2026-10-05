# Occluders (wt/occluders) - stills

opengl3 (Compatibility) under Xvfb, 1280x720, one load of the city, `tools/occluders/measure.sh`
(still_shot.gd `DIFF=1 OCC_AB=1`). Each image: left, the frame with the new occluders; right, its
pixel difference against the SAME held frame rendered with occlusion culling OFF (red = a pixel
differs). Anything culled in plain sight would show as a red shape; the only red is on people and
cars that keep moving between the captures (the "before" pair - building occluders only vs no
culling - shows the same noise).

Frame cost (draws / triangles), building occluders only -> with the new ones (no culling at all):

| still | camera | draws | triangles |
|---|---|---|---|
| 01_river_channel | down in the LA River | 873 -> 737 (-16 %) (879) | 1.45 M -> 1.29 M (-11 %) |
| 02_sound_wall_street | suburban street by the freeway's sound wall | 2,282 -> 2,070 (-9 %) (2,283) | 5.30 M -> 4.94 M (-7 %) |
| 03_on_the_110_deck | on the 110 by downtown | 2,660 -> 2,554 (-4 %) (3,052) | 4.78 M -> 4.64 M (-3 %) |
| 04_valley_toward_front_range | valley floor looking south at the range | 3,433 -> 3,298 (-4 %) (3,436) | 7.12 M -> 7.04 M (-1 %) |
| 05_front_range_over_valley | front range looking north | 710 -> 698 (-2 %) (710) | 1.74 M -> 1.73 M |
| 06_under_the_110 | under the deck on 5th St | 2,484 -> 2,476 (2,611) | 4.61 M -> 4.60 M |
| 07_downtown_noon | Flower at Olympic | 2,943 -> 2,937 (3,078) | 6.36 M -> 6.35 M |
| 08_basin_street_north | basin street toward the range | 3,044 -> 3,044 (3,371) | 6.08 M (no change) |
