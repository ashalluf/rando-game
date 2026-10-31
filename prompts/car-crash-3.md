# Wave 4 task: car-crash-3 (kind: new)

Branch `wt/car-crash-3`, stills on `shots/car-crash-3`.

Crashes at speed: windows that burst in a spray of cubes on impact (not only when shot), bumpers that hang and drag with sparks, bonnets that fly open, airbags (a white bag in the cabin trace), a wheel torn off rolling away, the car's body rolling over realistically (centre of mass), debris that stays. CarDamage / CrashDeform; car_shot.gd DAMAGE= stills. Read CLAUDE.md's car damage and crumple notes (one entry point take_hit, the crash watch, the shadow twins' shaders). Another session (car-exterior-closeup) owns the car bodies' meshes.

If `origin/wt/car-crash-3` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/car-crash-3`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
