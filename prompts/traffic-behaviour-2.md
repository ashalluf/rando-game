# Wave 4 task: traffic-behaviour-2 (kind: new)

Branch `wt/traffic-behaviour-2`, stills on `shots/traffic-behaviour-2`.

Traffic that reads alive at eye level: cars that creep at a red, drivers' heads that turn, brake lights that flicker on and off in a queue, a bus pulling out with its indicator, cars giving way to a pedestrian mid-crossing, a car waiting to turn left across traffic, cars dodging a wreck. On TrafficManager + TrafficAI's hooks only; coordinate with traffic-motion (which owns wheel spin / steering / body motion of kinematic cars): do not touch those. Every per-car-per-tick cost must be O(1) (CLAUDE.md, perf audit 2).

If `origin/wt/traffic-behaviour-2` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/traffic-behaviour-2`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
