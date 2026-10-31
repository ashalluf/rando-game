# hero-locomotion-2 stills (opengl3, test room, six frames of one staged move each, left to right)

`before` = HERO_LOCO=0 (main's clip swaps), `after` = this branch. Camera follows his yaw.

- start: from standing to 12 m/s (the gait fades in from a foot down, chest driven forward)
- stop: running, then stopping at 1 s (the stride runs on to a foot down, then settles)
- accel: 0 to 12 m/s over 3 s (walk -> run -> sprint by phase-synced weights)
- turn: turning on the spot (feet planted, then a step round; before: the walk in place)
- strafe_r: facing the aim, moving to his right (hips turned toward the travel; before: running forward clip sideways)
- back: facing the aim, moving away (backpedal: the gait backward)
- sprint_turn: 12 m/s round a 2.5 rad/s left turn (leans into it)
- land_run: landing from a 40 m/s fall at a run (runs on with a dip; before: the landing clip, cut)
