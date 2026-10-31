# Wave 4 task: rc-freeway (kind: refcam)

Branch `wt/rc-freeway`, stills on `shots/rc-freeway`.

Reference camera freeway (the 110's deck by downtown, 13:00 clear): what reads fake on the freeway. The deck's concrete and joints (freeway-closeup landed), the traffic's spacing and speed, the barriers, signs and lights, the towers behind, the ramps. Fix the worst three to five, hold the other nine cameras.

If `origin/wt/rc-freeway` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/rc-freeway`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
