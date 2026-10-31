# Wave 4 task: fwd-review-f (kind: infra)

Branch `wt/fwd-review-f`, stills on `shots/fwd-review-f`.

Forward+ review of what wave 3's batches 21-25 merged (aerial-review, lawns-closeup, web-review-3, house-nights, car-paint-2, night-street-review, street-clutter-2, downtown-street-closeup, storm-drama, golden-hour-review): shoot each on a small Forward+ scene under lavapipe (block_shot.tscn, the room tools) and fix what the opengl3 stills hid (colour space, additive clipping, SSR, volumetric fog). The handoff's fwd-review-d / e notes list the traps. apt-get install mesa-vulkan-drivers; never the whole city on lavapipe.

If `origin/wt/fwd-review-f` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/fwd-review-f`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
