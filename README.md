# shots/drive-assist (wave 9)

Top-down paths from the headless probe `tools/drive_assist/probe.tscn TRAJ=1` (a car outline
every few physics ticks; red = rolled past 30 degrees; white dot = the nose). Left: main
(DRIVE_ASSIST=0); right: with the assist.

- `01_sedan_full_lock_100kmh_off_vs_on.jpg` - full right lock at 28 m/s: on main the inner wheels
  lift, the car rolls onto its side and the flight code spins it round; with roll stability it
  carves a circle at 4.6 g.
- `02_sedan_nitro_corner_off_vs_on.jpg` - nitro and full lock from 20 m/s: rolled vs held.
- `03_police_slalom_old_law_vs_ai_drive.jpg` - PoliceCar._pursue's old law (full lock at any
  speed: tips over between gates) vs DriveAssist.ai_drive (all six gates, 8 degrees of slip).
- `04_police_uturn_old_law_vs_ai_drive.jpg` - a U-turn from 18 m/s.
