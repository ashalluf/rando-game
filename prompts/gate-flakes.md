# Wave 4 task: gate-flakes (kind: infra)

Branch `wt/gate-flakes`, stills on `shots/gate-flakes`.

The gate's intermittent failures: run `SHARDS=3 tests/headless_check.sh` five times in a row on main (SMOKE_SHUFFLE=<seed> with a different seed each run), collect every FAIL and script error, and fix each cause (a check that leans on a live system, a race between shards, a tolerance too tight for a soft constraint) so five runs pass clean. Report the list. CI 394's four were fixed on main already (traffic _group_clear, heli strike in clear air, wildlife staged on the pavement, the ragdoll box).

If `origin/wt/gate-flakes` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/gate-flakes`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
