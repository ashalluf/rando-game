# traffic-behaviour-2 stills (opengl3 / Compatibility, 1280x720)

Staged with `TB2=wreck|bus` on tools/glshot/still_shot.gd (TRAFFIC_STEPS advance the staged traffic)
and `OCCUPANT=pair OCC_LOOK=...` on tools/glshot/car_shot.gd. `TRAFFIC_BEHAVIOUR=0` is the before.

- 01 before: a dented car stands across the lane; the traffic behind drives straight into it.
- 02-04 after: the car behind signals left and edges out toward the centre line once the oncoming
  side is clear, passes 2.35 m to the wreck's side at rubbernecking speed, the next one follows.
- 05/06/07 the traced driver behind the side glass: before looking ahead (hair to the camera),
  after turned to the camera (the eye band) - occupant_look on the car's own glass.
- 08/09 front view, driver and passenger, before / after (passenger glancing at the driver after).
- 10/11 a bus done at its stop: left indicator on, still at its stop shift, then pulling out
  still signalling (shift 1.4 -> 0.78 m), the indicator off once back in the lane.
Not shown in stills (proved by tests/traffic_behaviour_2_checks.gd): the creep at a red, the
queue inching and the brake lamps going off and on, the left turn waiting for an oncoming gap,
the car waiting back from a busy crosswalk.
