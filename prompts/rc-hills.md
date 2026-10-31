# Wave 4 task: rc-hills (kind: refcam)

Branch `wt/rc-hills`, stills on `shots/rc-hills`.

Reference camera hills (the front range from 260 m, 15:00 clear): what reads fake in the hills. The ground's stands and rock, the shrub clumps' silhouettes, the estates, the fire roads, the far ranges' haze, the sign ridge. Fix the worst three to five, hold the other nine cameras. rock-outcrops and hill-ground-3 landed in wave 3: start from their HANDOFF sections.

If `origin/wt/rc-hills` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/rc-hills`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
