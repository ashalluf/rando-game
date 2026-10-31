# Wave 4 task: dawn-review (kind: refcam)

Branch `wt/dawn-review`, stills on `shots/dawn-review`.

The golden-hour review for 05:00-08:30: sunrise over the east range, the marine layer burning off, long cool shadows, the east sun low across the basin. Shoot the street_noon, golden_aerial, hills and beach cameras at 06:15, 07:00 and 08:00 (refcams_shot.gd takes the hour) before and after. Fix: the sky's dawn palette (sunset_sky / sky.gdshader: a cooler, pinker dawn than the dusk, less smog), the grade (HourGrade's weights at dawn), the street lamps going off at the right time, dew / morning haze, the sun's colour at 5 degrees up. Nothing at noon or at night may change (bit-identical).

If `origin/wt/dawn-review` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/dawn-review`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
