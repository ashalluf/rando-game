# Wave 4 task: rc-sunset (kind: refcam)

Branch `wt/rc-sunset`, stills on `shots/rc-sunset`.

Reference camera sunset (the Esplanade down the coast, 18:36, clear): what reads fake at sunset on the coast. The sea's colour and glitter, the sand, the bluff and its houses, the sky's bands, the far headland, the lamps coming on. Batch 25 (golden-hour review) just landed here: start from its stills on shots/golden-hour-review. Fix the worst three to five, hold the other nine cameras. GoldenHour lives in day_night.gd / golden_hour.gd; read its HANDOFF section.

If `origin/wt/rc-sunset` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/rc-sunset`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
