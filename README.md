# car-panic stills (wt/car-panic)

opengl3 (Compatibility) stills from `tools/glshot/still_shot.gd PANIC=<kind> PANIC_STEPS=...`, 15:00, clear.
A traffic car on a one-lane street, a shot by the far kerb ahead of it, the camera on the road ahead looking back.

- 01_abandon_0.4s_hard_stop.jpg - the driver stamps on the brake.
- 02_abandon_2.5s_door_open_driver_out.jpg - stopped; the driver's door swings open, the driver gets out.
- 03_abandon_5s_driver_runs_car_behind_goes_round.jpg - the driver runs for the pavement; the car behind honked and goes round on the wrong side.
- 04_abandon_12s_left_with_door_open.jpg - the car stays where it stopped, door open, cabin empty, lamps off.
- 00_before_CAR_PANIC0_same_shot_cars_drive_on.jpg - the same staging with CAR_PANIC=0: nobody reacts, the cars have driven through.
- 05/06/07_kerb_* - KERB: swings over the parking lane where the kerb is clear and up with two wheels on the hazards (out of the lane's queue: the car behind drives past), then back down into its lane.
- 08/09_reverse_* - REVERSE: the shot is ahead, so it backs away on the reversing lamps, short of the car behind.
- 10/11/12_night_2100_* - ABANDON at 21:00.

Frame cost (still_shot GEO, the abandon frame vs CAR_PANIC=0 at the same eye): 4.18 M tris / 2,290 draws vs 3.98 M / 2,238 - the difference is the cars and people in view (the before frame has the two cars driven out of it), not the system, which adds one door panel and one walker.
