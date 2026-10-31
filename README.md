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

## Wave 4 (after merging main, build 395+), opengl3 1280x720 at 15:30, spawn 2359.4,880 (Flower at Olympic)

- `10_before_street_queue.jpg` / `11_after_street_queue.jpg`: `STREET=queue STREET_EYE=1` on still_shot.gd, a queue
  standing at the red from the pavement. A standing queue looks the same either way (the bodies are at rest, level);
  the queue's cars differ because the live traffic that fills it differs run to run.
- `12_before_chase_turn_sheet.jpg` / `13_after_chase_turn_sheet.jpg`: `TMOTION=chase TMOTION_STEPS=2.0,0.8,0.6,0.6,0.6,0.8`,
  frames 3-6 from a chase camera. Before (`TRAFFIC_MOTION=0`): the car runs straight into the junction and snaps
  90 degrees at its centre later. After: it follows the fillet arc, front wheels steered 13.2 deg, body leaned 2.0 deg.
- `14_before_chase_turn_frame6.jpg` / `15_after_chase_turn_frame6.jpg`: frame 6 alone, full size.
