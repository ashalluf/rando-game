# shots/freeway-incidents

Freeway incidents (fleet wave 2, branch `wt/freeway-incidents`). opengl3 stills (the Compatibility
renderer, not the Mac's Forward+), the 110 by downtown, route 3 t 1904, forced with
`FW_INCIDENT=stall FW_INCIDENT_AT=3:1904:1 FW_INCIDENT_T=...` on `tools/glshot/still_shot.gd`.

- `01_after_stall_coasting_onto_shoulder_1400.jpg` - a car breaking down coasts out of the slow lane onto the shoulder, right indicator on.
- `02_after_stall_patrol_behind_driver_out_1400.jpg` - the BASIN HIGHWAY PATROL car (invented) parked behind it, bar on; the driver out.
- `03_after_stall_tow_winching_car_on_1400.jpg` - the rollback tow ahead, bed tilted, the car being winched on; traffic in the slow lane.
- `04_after_stall_tow_loaded_from_ahead_1400.jpg` - from ahead: the tow with the car on its bed, about to drive off.
- `05_after_mattress_in_lane_3_1400.jpg` - a mattress in lane 3 (mid-frame), traffic round it.
- `06_after_tyre_tread_car_swerving_1400.jpg` - shredded truck tread in lane 2 of the other carriageway, an SUV signalling out of its lane.
- `07_after_cms_stalled_vehicle_ahead_1400.jpg` - a changeable message sign on a gantry: STALLED VEHICLE / RIGHT SHOULDER / AHEAD.
- `08_after_cms_move_over_night_2100.jpg` - the same sign's second page at 21:00.
- `09_after_stall_tow_gone_1400.jpg` - after: the scene cleared, the curled tread strips on the shoulder (they were two boxes).
- `10_after_stall_road_flares_behind_patrol_2200.jpg` - wave 3: the patrol officer's road flares, a taper of burning fusees on the shoulder behind the patrol car (red glow, pool, smoke), 22:00. EYE `1951.0,11.5,222.0,167.0,-4.0`, `FW_INCIDENT_T=80`.
- `11_after_stall_road_flares_dusk_2036.jpg` - the same at 20:36.
- `12_after_stall_road_flares_day_1400.jpg` - the same by day (the glow is dimmer by day, as a real flare).
- `13_after_stall_patrol_close_wave3_merge_1400.jpg` / `14_after_stall_patrol_close_night_2200.jpg` - the stall after the wave-3 merge of main: patrol car, driver, stalled car; by day and at night (the flares are behind this camera).
- (10-12 were shot before the glow was made a little larger and brighter, `size` 0.42 and the halo x0.7.)
- `00_before_*` - the same three views with FREEWAY_INCIDENTS=0 (the second guide board where the CMS hangs).

Frame cost (still_shot GEO, 1280x720, traffic differs run to run): stall view 5.34 M tris / 2,961 draws before, 5.92 M / 3,105 with the stall (three vehicles and the driver); debris view 5.50 M / 2,694 -> 5.28 M / 2,707; CMS view 3.64 M / 1,247 -> 3.66 M / 1,260.
