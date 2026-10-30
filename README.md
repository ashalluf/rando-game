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

**Re-shot after the lead's review (same eyes):** the flake is ~1 mm, tilted per flake and lit only
where its mirror catches the sun (no white specks; a faint lift past a pixel); the whitewall is a
17 mm off-white band with the black tyre wall round it; the chrome stand-in on opengl3 is a darker
satin, so the rim lip no longer reads as part of the whitewall. The pale splotches and crack lines
on the road in 02 are road wear and are in 01 (LOWRIDERS=0) too: not the meet.

**Wave 3 (2026-10-30, after merging main 95bd13f):**
- 18_after_meet_chairs_coolers_golden_1736 - the kerb at golden hour: folding chairs and red coolers in the gaps between the cars (MeetKit), a hardtop hopping, a coupe three-wheeling (`EYE=829,7.7,600.5,-161,-2`)
- 19_after_meet_chairs_night_2100 - the row from above at 21:00 (`826,13.0,597,-115,-10`; GEO 5.95 M triangles / 2,649 draws)
- 20_after_meet_kerb_close_night_2112 - the close kerb at 21:12
- 21_after_meet_across_street_1736 - from across the boulevard at 17:36
- 22/23 - **Forward+** (lavapipe, `car_shot.gd`): the hardtop and the coupe's wire wheel. The candy reads deep and saturated on the flanks; the top panels mirror the harness's grey sky at a grazing angle, and the chrome is grey there for the same reason (nothing to mirror but a plain sky).
- 24 - Forward+: an everyday sedan, the hardtop in lime gold, the hardtop in teal (`LOOK=3`, `LOOK=11`)

A Forward+ still of the meet block (fwd_block_shot.tscn) does not fit this box: lavapipe passed 13.6 GB and was killed.
The player's switch (X in a lowrider: tap a hop, hold a lift, + A / D a three-wheel) is checked, not shot (a still cannot press the key).
