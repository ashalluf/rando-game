# Wave 4 task: sky-day-review (kind: new)

Branch `wt/sky-day-review`, stills on `shots/sky-day-review`.

The daytime sky at street level and from the air: the sun disc's size and glare, the horizon's brightness against the buildings (today often too bright and washes the frame), the cumulus volume's look at noon from the ground (bases, tops, their number), the haze gradient. Hold the sunset / dawn colours (dawn-review and rc-sunset own them): change only 09:00-16:00's sky and prove the other hours bit-identical with sky_shot.gd. Prove the other hours bit-identical with tools/sky/sky_shot.gd HOLD_TIME=1 pixel diffs.

If `origin/wt/sky-day-review` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/sky-day-review`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
