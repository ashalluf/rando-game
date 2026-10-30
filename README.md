# shots/crowd-lookat - the crowd's heads (CrowdLook)

Lab stills (`tools/crowd/crowd_lab.tscn SCENARIO=heads STEP=10 FRAMES=90`, opengl3 under Xvfb,
1280x720, cropped to the row): six people at a kerb facing the road; each image is the same
physics tick with `CROWD_LOOK=0` (top, the old head turn) and with CrowdLook (bottom).

- `01_calm_before_after.jpg` - tick 40: nothing happening; idle glances, head-down posture.
- `02_crash_left_before_after.jpg` - tick 120: a car crashes off frame to the left (their right):
  heads and a little of the chest turn to it, each person by their own angle to it.
- `03_boost_behind_before_after.jpg` - tick 360: the player boosts past behind the row: heard, so
  they look round over the shoulder (head 72 deg cap + chest 22).
- `04_busker_right_before_after.jpg` - tick 580: a busker (a `crowd_look_magnet`, the cylinder
  off frame right) - seen only by those it is in front of, watched while it plays.
- `05_far_blast_left_before_after.jpg` - tick 800: a blast 45 m off behind-left: the whole row
  looks back over the right shoulder.
- `06_crash_reaction_every_10_ticks.jpg` - ticks 60-120 after the crash, every 10 ticks: the
  eased, staggered turn (each person reacts on its own 0.22-0.4 s scan).
