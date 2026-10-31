# Wave 4 task: wet-road-mirror (kind: new)

Branch `wt/wet-road-mirror`, stills on `shots/wet-road-mirror`.

The wet road at night mirrors the lit windows as a regular GRID OF SQUARES across the carriageway (road.gdshader mirrored_city(), the night street refcam street_night). A real wet street shows long vertical streaks under lamps and shop fronts, broken up by the asphalt's micro relief, sharp only in standing water. Rework mirrored_city() so the reflection is streaks and smears (stretched along the view direction, varying by a per-pixel roughness field, the shop fronts dominant, no visible cell grid), keep Forward+'s SSR blend (mirror_forward) and the dry road bit-identical. Prove with the street_night refcam before/after and a small Forward+ scene under lavapipe.

If `origin/wt/wet-road-mirror` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/wet-road-mirror`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
