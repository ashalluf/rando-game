# Freight rail stills (branch wt/freight-trains)

All opengl3 (Compatibility) stills from `tools/glshot/still_shot.gd` and `tools/freight/stock_shot.tscn`,
not the Mac's Forward+. Docs: docs/HANDOFF.md, the freight rail section (VISUAL_ROADMAP #63).

| File | What | How |
|---|---|---|
| crossing_gates_down.jpg | A train over Maple St, gates down, from the pavement | `FREIGHT_CROSS=0:0:-25 FREIGHT_HOLD=1 EYE=3428,14.5,4478,50,-4`, 15:00 |
| stack_train_golden_hour.jpg | A double-stack train over Pacific Blvd at golden hour, gates down | `FREIGHT_CROSS=1:0:-18`, EYE 3418,12.4,4529,76,-2, 17:48 |
| stack_train_aerial.jpg | The same train from the air | EYE 3446,40,4562,48,-32, 17:48 |
| trench_from_above.jpg | The trench under decked cross streets, a manifest in it | `FREIGHT_KIND=0 FREIGHT_S=1400:0:-25`, EYE 3412,38,3640,20,-28 |
| trench_close.jpg | Looking down into the trench by a bridged junction | EYE 3400,24,3500,10,-50 |
| trench_night.jpg | The trench at night | 20:30 |
| yard_night.jpg | The yard from the south-east at night: masts, tower, stacks, trailers | `FREIGHT_YARD=60`, EYE 3500,62,2850,12,-24, 21:30 |
| loco_closeup_yard.jpg | A lead unit at the buffer stops, the yard behind | EYE 3397.5,13,2316,167,-2, 16:30 |
| loco_closeup_showroom.jpg | The locomotive: cab, number boards, lamps | stock_shot.tscn |
| loco_front_showroom.jpg | Nose, pilot, plow, ditch lights | stock_shot.tscn |
| consist_showroom.jpg | Two units and the cars behind them | stock_shot.tscn |

The thin stripe over the trench in trench_close is the far city's plate still dithering out under
the still's frozen clock, not geometry.

## Wave-2 review pass (after merging fleet/base; opengl3 stills, 1280x720)

| File | What | How |
|---|---|---|
| 12_after_merge_crossing_gates_down_1500.jpg | A stack train over Maple St on the merged city, gates down | `FREIGHT_CROSS=0:0:-25 FREIGHT_HOLD=1 EYE=3424,12.6,4446,90,-2`, 15:00 |
| 13_after_river_yard_freightstock_cars_1500.jpg | The LA River yard's freight track: the line's own FreightStock tank car, boxcar and hopper | `EYE=4425,9,4345,31,-8`, 15:00 |
| 14_before_river_yard_old_boxcars_FREIGHT0_1500.jpg | The same view with `FREIGHT=0`: the old IndustrialKit boxes | same EYE |
| 15_after_merge_trench_from_above_1500.jpg | The trench and its decks on the merged city | `EYE=3412,38,3640,20,-28` |
| 16_after_bridged_street_over_trench_1500.jpg | Pacific Blvd crossing Alameda on its deck (its invisible trench walls are gone; collision, not visible) | `EYE=3355,12.6,3089,-90,-2` |
| 17_after_merge_yard_night_2130.jpg | The yard at night | `EYE=3500,62,2850,12,-24`, 21:30 |
