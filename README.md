# shots/traffic-motion

Kinematic street traffic before (`TRAFFIC_MOTION=0`) and after, opengl3 stills at 15:30, staged with
`TMOTION=brake|pull|turn TMOTION_STEPS=...` on tools/glshot/still_shot.gd (tools/traffic_motion/stage.gd).

- `sheet_brake_m1.jpg` / `sheet_brake_m0.jpg`: a sedan at 13 m/s brakes to a stop behind a standing crossover,
  seen from the empty oncoming lane. After: the nose dives (peak -1.0 deg) and rocks back level as it stops.
- `sheet_pull_m1.jpg` / `sheet_pull_m0.jpg`: a queue of three at a red pulls away on green, seen from behind.
  After: squat on pull-away (+0.5 deg), each car a beat behind the one in front.
- `sheet_turn_m1.jpg` / `sheet_turn_m0.jpg`: a car turns at the junction (camera on the far corner; a stop sign
  is in the frame). `crop_turn_a.jpg` / `crop_turn_b.jpg`: frames 2-7 cropped on the car, before | after.
  After: the car follows a fillet arc with the front wheels steered (12.9 deg) and the body leaned (2.0 deg);
  before: it snaps 90 degrees at the junction's centre. (The car's paint differs between the two runs.)

GEO (whole frame): brake 6,294,447 -> 6,265,163 tris; turn 7,425,756 -> 7,461,103; pull 8,667,838 both.
The motion adds no geometry: the differences are where the staged cars stand in each frame.
