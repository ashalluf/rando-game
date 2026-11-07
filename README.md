# drive-steer: before / after charts

Headless probe `tools/drive_steer/probe.tscn` (TRACE=1, sedan, flat slab, simulated keys, `--fixed-fps 60`).
Red = main (`DRIVE_HANDLING=0 DRIVE_FIX=0`), blue = DriveHandling (with wt/drive-fix merged).
Top: yaw rate; bottom: heading change.

- `slalom60.jpg`: full-lock slalom at 60 km/h. Main whips the car to 105 deg/s (3.1 g); DriveHandling 46 deg/s (1.3 g) and settles at once.
- `junctionL.jpg` / `junctionR.jpg`: a 90 deg turn at 40 km/h, left and right alike.
- `kick.jpg`: a 4 rad/s yaw kick at 80 km/h, hands off. Main's tyres (grip 10.5, ~10 g) never let go, so main shrugs it off (8.7 deg) - but the same tyres snap into a spin at full lock at 108 km/h. With DriveHandling's progressive tyres the kick slides the car round 128 deg without the assist; the counter-steer assist holds it within ~4 deg.
