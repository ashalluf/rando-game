# shots/more-cars (wt/more-cars, HANDOFF 9bp)

All opengl3 (Compatibility) renders unless noted; nothing here is Forward+.

- `hatchback_*`, `suv_*`, `minivan_*`, `taxi_*`, `beater_*` (`front3`, `rear3`, `side`, `close`): `tools/glshot/car_shot.gd --type=14..18`, parked, no occupant.
- `street_queue_mix.jpg`: `still_shot.gd STREET=queue STREET_EYE=1 STREET_MIX=14,15,17,16,18,0,8,14` on the downtown avenue (hatchback, SUV, taxi, minivan, beater in one queue at a red).
- `avenue_before_main.jpg` / `avenue_after.jpg`: the avenue bookmark `--spawn=2359.4,880,0,12,2` on main a0ee161 and on this branch (GEO 7.53 M / 3,720 draws -> 7.39 M / 3,805). The parked white sports car became a hatchback (its roll was in the hatchbacks' slice); the rest of the row did not move.
- `taxi_night_front3.jpg`, `taxi_night_street.jpg`: `--night`, the roof sign lit by lamp_factor, a cabbie and a fare (`OCCUPANT=npc:3`, seats 5).
- `taxi_fare_lettering.jpg`: BASIN CAB on the front door, the fleet number on the rear, the fare's head in the rear glass.
- `beater_left_odd_door.jpg`: the left front door from another car, chalky roof and bonnet. `beater_right_dent_primer.jpg`: the primer patch on the wing. `beater_cracked_tail_lamp.jpg`: the right tail lamp in pieces with tape. `beater_tail_cycles_preview.jpg`: Blender Cycles preview of the same lamp (`make_more_cars.py --render`).
