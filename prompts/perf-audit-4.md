# Wave 4 task: perf-audit-4 (kind: infra)

Branch `wt/perf-audit-4`, stills on `shots/perf-audit-4`.

Frame cost after wave 3: run tools/geo_count.gd and still_shot.gd SPLIT=1 at the ten refcams, list the ten most expensive systems per camera, and cut what is over budget without a visible change (DIFF=1 pairs, img_diff.py). Targets: triangles and draws at each camera back under the wave-2 numbers in tools/refcams' report. Memory: peak RSS under 3,600 MB in the gate. CI 394's shards peaked 2,984-3,489 MB. Read CLAUDE.md's measurement traps before measuring anything.

If `origin/wt/perf-audit-4` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/perf-audit-4`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
