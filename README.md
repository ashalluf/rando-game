# Car dealerships (branch wt/car-dealers, HANDOFF 9bu)

opengl3 stills (the Compatibility renderer, not the Mac's Forward+), 1280x720, default seed,
`tools/glshot/still_shot.gd` with `EYE_AGL=1`. The new dealer is HALDRIC on block 9,-1, the used lot
DOS AMIGOS AUTO SALES on block 10,-2 (`tools/car_dealers/probe.gd` lists every site).

| File | What | EYE |
|---|---|---|
| 01_before_street_noon_dealers_off.jpg | `CAR_DEALERS=0`: the same block as shops (the before) | 918,1.7,-100,68,-3 @12 |
| 02_auto_row_street_noon.jpg | the auto row from across the street: portal, showroom, service canopy, pennants, tube man, real cars mid front row | 918,1.7,-100,68,-3 @12 |
| 03_along_the_lot_pavement_noon.jpg | along the lot from the pavement: bollards, feather flags, pennant strings (the static lot cars are boxy this close) | 899,1.7,-92,8,4 @12 |
| 04_showroom_and_pylon_2100.jpg | 21:00: the lit pylon and badge, the portal, the lit showroom, floodlit cars, the tube man's face | 914,2.2,-122,128,-4 @21 |
| 05_new_dealer_from_above.jpg | the lot from above: showroom under its roof, portal, service canopy, rows of cars, two tube men | 929.8,38,-119.3,90,-42 @12 |
| 06_used_lot_street_noon.jpg | a used lot: rainbow pennants, the trailer, grease-pencil prices, yellow bollards | 905,1.7,-298,-60,-3 @12 |
| 07_used_lot_from_above.jpg | the used lot from above: trailer, mast, chain-link, the board | 893.8,38,-314.9,-90,-42 @12 |
| 08_used_lot_2100.jpg | the used lot at 21:00 under its floods | 905,2.2,-298,-60,-3 @21 |

The used shots were taken before the last commit capped a grease-pencil price at four figures
(one car shows "0995").
