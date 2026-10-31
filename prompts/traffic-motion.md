# Wave 4 task: traffic-motion (kind: resume)

Branch `wt/traffic-motion`, stills on `shots/traffic-motion`.

Resume wt/traffic-motion (4e5b1307): wheel spin, steering, brake dive / roll on kinematic traffic cars. 39 checks were passing, no stills pushed, no final gate. Merge origin/main, finish, gate, shoot before/after stills of a street queue and a turning car (STREET=queue on still_shot.gd and a chase view), push wt/traffic-motion and shots/traffic-motion.

If `origin/wt/traffic-motion` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/traffic-motion`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
