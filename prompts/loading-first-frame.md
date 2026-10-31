# Wave 4 task: loading-first-frame (kind: infra)

Branch `wt/loading-first-frame`, stills on `shots/loading-first-frame`.

The first minute of play: the loading screen's time (LoadClock), what pops in after the shade lifts (chunks still building, the far city tiles, traffic filling), the first-use stutters (WarmRehearsal: anything new in wave 3 that compiles on first sight). Measure on both renderers with tools/load_time and shader_warm; fix the three biggest. LoadCache gained a per-shard directory (LoadCache.dir()); keep its rules.

If `origin/wt/loading-first-frame` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/loading-first-frame`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
