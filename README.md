# Lowriders - stills (wt/lowriders)

opengl3 (the Compatibility renderer, what the web build draws), not the Mac's Forward+.

The meet: Z#4 at x 810-900, z ~612 on the default seed (`LOWRIDER_MEET=1` forces it on;
`LOWRIDER_POSE=1:hop:0.7,3:three:2.0,6:dance:1.6` freezes cars mid-routine).

- 01_before_meet_kerb_night_2100 - the boulevard kerb with LOWRIDERS=0, 21:00, `EYE=826,13.0,597,-115,-10`
- 02_after_meet_row_night_2100 - the same frame on a meet night: the row of lowriders, the crowd round them
- 03_after_meet_street_level_threewheel_2100 - from across the street: a car three-wheeling, one dancing
- 04_after_meet_dusk_1824 - the same row at dusk
- 05/06/07 - the hardtop and the coupe (car_shot.gd)
- 08/09 - the hardtop mid-hop (front wheels off the road, the rear squatting)
- 10 - the coupe three-wheeling
- 11 - bonnet pinstripe scroll and the lace-patterned roof
- 12 - the flank's double pinstripe and the deep flake
- 13 - the 13" wire wheel: 72 spokes, gold hub and knock-off, thin whitewall
- 14_meet_golden_hour_hop_threewheel_1736 - from the kerb across, 17:36: a hardtop mid-hop (left), a coupe three-wheeling, the crowd on the pavement (`EYE=829,7.7,600.5,-161,-2`)
- 15_meet_close_night_2112 - the same at 21:12
- 16_meet_row_across_street_1736 - the row from across the boulevard at 17:36 (`EYE=846,8.4,600,-150,-6`)
- 17_cruising_in_traffic_threewheel_1724 - lowriders in the street traffic at a red, three-wheeling (STREET=queue STREET_MIX=25,8,26,0,25 LOWRIDER_HYD=three:2.0:1)

Frame cost at the meet EYE (opengl3 1280x720, 21:00): LOWRIDERS=0 6.449 M triangles / 2,840 draws,
a meet night 6.980 M / 3,102 (+8 %, +262 draws: ten cars and twenty people at a kerb that was empty).
