# shots/rc5-coast-highway

The new `coast_highway` refcam (tools/refcams/cameras_w8.json): the coast highway at 17:00 clear from the seawall apron looking north. opengl3 stills (Compatibility renderer).

- `00_first_framing_against_a_garage.jpg` - the first eye tried (at the south end of the houses): a garage door filled the left of the frame, so the eye moved onto the apron by the open beach.
- `01_before_coast_highway.jpg` - main (6f5af3d2), the final eye (`RC5_COAST=0`).
- `02_after_coast_highway.jpg` - after (branch, `RC5_COAST` on): the bluff fluted by gullies, a palm and the glazed end wall on the first house, more cars on the road, the warmer apron.
- `03_before_house_end.jpg` / `04_after_house_end.jpg` - a second view from the apron at z -1176 (not a refcam): the end wall of the first house of a run, blank before, glazed after; the corner palm and planter.
- `05_bluff_before_after_crop.jpg` - the bluff, before (left) and after (right), the same crop of the refcam.
- `06_before_house_fronts.jpg` / `07_after_house_fronts.jpg` - a third view (not a refcam) from the bluff-side shoulder across the road at the house fronts: the painted garage leaf becomes timber slats (and four raised sections on a pale door), planters of agave, bird of paradise and yucca, lanterns by the garages, a passing car from the first fill.
- `08_ten_refcams_compare_rc5_off_vs_on.jpg` - the ten original refcams, `RC5_COAST=0` (top) against the branch (bottom): only street_noon, street_night and freeway flag, and only where live traffic stands (buses and cars moved between the two loads); nothing on them comes near the coast.

Numbers (refcams, opengl3 1280x720):

| view | p5/p50/p95 before | after | tris before -> after | draws |
|---|---|---|---|---|
| coast_highway | 41/138/177 | 36/136/177 | 1.88 M -> 2.01 M | 918 -> 998 |
| coast_fronts (z -1176) | 40/109/176 | 37/105/177 | 1.50 M -> 1.66 M | 762 -> 846 |
| coast_frontage (house fronts) | 35/65/221 | 34/64/221 | 0.89 M -> 1.00 M | 354 -> 399 |
