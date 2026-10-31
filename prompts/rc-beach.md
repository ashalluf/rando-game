# Wave 4 task: rc-beach (kind: refcam)

Branch `wt/rc-beach`, stills on `shots/rc-beach`.

Reference camera beach (the waterline at z 800, 14:00 clear): what reads fake on the beach at two in the afternoon. The sand's grain and footprints, the swash, the people (BeachFigures) and their towels, the pier, the surf's foam, the sky over the sea, the bike path. Fix the worst three to five, hold the other nine cameras. Another session (water-review) owns the ocean and beach_sand shaders' water look; you own the rest of the frame.

If `origin/wt/rc-beach` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/rc-beach`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
