# Wave 4 task: rc-golden-aerial (kind: refcam)

Branch `wt/rc-golden-aerial`, stills on `shots/rc-golden-aerial`.

Reference camera golden_aerial (downtown from the south-west, 140 m up, 18:18 clear): what reads fake in the aerial at golden hour. The towers' glass (skyline-glass-day owns the curtain glass by DAY; you own the low-sun look and everything else), the roofs, the far city's handover, the haze, the freeway, the hills behind. Fix the worst three to five, hold the other nine cameras.

If `origin/wt/rc-golden-aerial` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/rc-golden-aerial`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
