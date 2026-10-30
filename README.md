# driving-camera stills (DriveCam, the chase camera)

Scripted drive up Flower St at 16:00 (tools/driving_camera/drive_strip.gd, opengl3 under Xvfb,
`--fixed-fps 60`, so every frame is 1/60 s of game time). Motion blur is Forward+ only and is not
in these stills.

- 01-03: straight at 30 / 80 / 150 km/h, frames 0.4 s apart: 6.3 / 7.1 / 8.3 m back, pitch
  -11 / -9 / -6 deg, FOV 75 / 76.6 / 82.
- 04: a 35 km/h right turn onto Olympic: the view lags the turn (18-22 deg, the cap) so the car
  shows its flank, then comes back behind (the scripted car ends the turn against the kerb).
- 05: an 80 km/h hop: rising, apex, 0.06 s after touch-down (the landing dip: 6.0 m and lower),
  0.22 s after (back at 7.1 m).
- 06-09: single frames at full size.
- 10-11: BEFORE (`DRIVE_CAM=0`, the old free camera) at 80 km/h and in the same corner: the view
  stays where the mouse left it, so the turn drives the car out of the shot in profile; no pull-back
  or FOV with speed.
