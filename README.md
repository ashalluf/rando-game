# Freeway kit stills (wt/freeway-kit, VISUAL_ROADMAP #43, HANDOFF 9ba)

opengl3 (Compatibility) under Xvfb, 1280x720, `tools/glshot/still_shot.gd`, one load per side:

    OUT=x.png FOV=60 EYE=1989,12.0,160,-6,-3 \
    SHOTS="1989,12.0,160,-6,-3@22@60;1990,12.5,82,-6,10@13@40;1980.5,12.1,27,174,10@13@45;1980.5,12.1,27,174,10@22@45;2045,1.7,2,60,10@13@60;2045,1.7,2,60,10@22@60" \
    xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
      --audio-driver Dummy --path . --script tools/glshot/still_shot.gd --resolution 1280x720 \
      -- --spawn=1989,160,-6,-3,12 --hour=13 --weather=clear --nohud

`_before` is main without the kit (040beaf), `_after` the branch (the two `under_*_after` from
after the rebase onto 306274c, so they also show the yard pass's chain-link fence under the
deck). Traffic and people differ run to run.

| still | where |
|---|---|
| drive_noon_before / _after | on the 110 by downtown heading north, 13:00 |
| drive_night_before / _after | the same at 22:00: the median lights' pools (sodium amber on the 110), the markers glinting ahead |
| sign_guide_before / _after | the gantry at (1986.7, 55.6) from 26 m, northbound guide signs (shield 33 NORTH, destinations, a down arrow per lane) |
| sign_exit_noon_before / _after | the same gantry southbound: guide sign and the exit sign (Oak Blvd, 1/2 MILE, the exit tab) |
| sign_exit_night_before / _after | the same at 22:00: sign faces lit, sodium pools on the deck |
| under_noon_before / _after | the deck from 5th St, 28 m east of it: box girder, formwork soffit, a bent. The "before" shows the old bent caps all standing in a row near z 0 (the old `_pillar()` used the ground height as z), read as a staircase of beams overhead |
| under_night_before / _after | the same at 22:00 |
