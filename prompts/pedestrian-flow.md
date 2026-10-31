# Wave 4 task: pedestrian-flow (kind: new)

Branch `wt/pedestrian-flow`, stills on `shots/pedestrian-flow`.

The crowd's flow: people walk in pairs and small groups, step round each other and round props without stopping dead, slow in a crowd, cross at the lights in a bunch, walk out of shop doors and into them, wait at the kerb for a car to pass. The Pedestrian ring walk + CrowdFeet are the base; local avoidance (a cheap reciprocal velocity step on the near crowd only), group walking (two or three sharing a leader) and door traffic (StreetErrands has shop doors). Hooks in pedestrian.gd small and at the end of its lists; a new file for the logic; all timing on the physics clock.

If `origin/wt/pedestrian-flow` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/pedestrian-flow`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
