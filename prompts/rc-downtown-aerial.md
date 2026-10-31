# Wave 4 task: rc-downtown-aerial (kind: refcam)

Branch `wt/rc-downtown-aerial`, stills on `shots/rc-downtown-aerial`.

Reference camera downtown_aerial (the civic centre, 60 m up, 12:30 clear): what reads fake in the civic centre from 60 m. City hall and its park, the roofs and roof plant, the street grid's paint, the parked cars, the trees' crowns from above, the LOD handover a few blocks out. Fix the worst three to five, hold the other nine cameras.

If `origin/wt/rc-downtown-aerial` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/rc-downtown-aerial`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
