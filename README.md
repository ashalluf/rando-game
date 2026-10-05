# far-landmarks: the landmarks' far copies against their detailed copies

Each still is one landmark rendered twice from the SAME camera, 260 m off (about where the FULL
ring hands it over), with nothing else in the scene: top row BEFORE (detailed | far copy), bottom
row AFTER (detailed | far copy). The far copy is what the whole city sees until the chunk round
the landmark builds it in detail, so anything that differs between the two right-hand and
left-hand tiles is a visible jump at the hand-over.

Made with `tools/glshot/far_landmark_shot.gd` + `tools/glshot/far_landmark_pair.py` (opengl3 /
Compatibility under Xvfb, a fixed sun and sky - judge the pairs against each other, not the light;
the owner's Mac draws Forward+).

| still | what changed in the far copy |
|---|---|
| 01_day_venice_boardwalk | every palm (was every other one, as box sticks), the shops with windows, shutters, awnings, signs and murals (were pale boxes), the art wall |
| 02_day_masjid_omar | the frontage palms and trees, the white plinth and car park, the arched lattice windows and green surrounds, the minaret balcony |
| 03_day_arena | the palms, groves, berm trees and the surface lot with its parked cars and plaza paving |
| 04_day_verde_cafe | its own plaster / concrete materials (was flat white, 3.4x as bright), glazing, awnings, signs, the two street trees |
| 05_day_lattice_museum | the veil at the near cell size (was a dark grid, 0.41 as bright), the plaza grove |
| 06_day_redondo_pier | the real shop row with colours, awnings, upper windows and the ROUNDWOOD hoarding (was one pale bar) |
| 07_day_concert_hall | the podium's paving and garden (bare stone was 1.6x as bright) |
| 08_day_skyhook | the ring of palms |
| 09_day_civic_park | the planter trees |
| 10_day_live_plaza | the plaza paving, planter trees and grove |
| 11_day_rental_lot | the parked cars and island trees |
| 12-17 night (21:00) | boardwalk, Lattice, civic park (lamp pools), Verde Cafe (window glow, lit letters), masjid, Symphony Hall |
| 18_day_dt_sail_tower | unchanged: every downtown tower's far copy is already the same mesh (IoU 1.00, brightness 1.00) |

Far / near brightness over the pixels both copies cover (1.00 = no jump), before -> after, noon:
boardwalk 1.62 -> 0.99, masjid 1.43 -> 1.22, arena 1.46 -> 0.99, Verde 3.41 -> 0.96, Lattice
0.41 -> 0.90, Redondo 1.58 -> 0.99, Symphony Hall 1.60 -> 1.01, rental lot 0.65 -> 0.90.
21:00: boardwalk 0.44 -> 1.00, Lattice 0.50 -> 0.99, civic park 0.55 -> 0.97, Symphony Hall 1.20 ->
1.00, Verde 0.98 (dark far box vs dark shop, by luck) -> 1.10.
