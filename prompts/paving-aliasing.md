# Wave 4 task: paving-aliasing (kind: resume)

Branch `wt/paving-aliasing`, stills on `shots/paving-aliasing`.

Resume wt/paving-aliasing (7115dec9; shots/paving-aliasing aa9dde2b): red brick / herringbone pavement and forecourt paving shimmer with moire at eye level. Forecourt and pavement fixes were pushed, its gate was running. Merge origin/main, make sure every paved pattern (lot_ground, kerbs, plaza paving, the replica's walks, the Esplanade) fades its pattern to its average under about two pixels (fwidth-based, like the vinyl lettering), gate, before/after stills at eye level 2 m and 20 m, push.

If `origin/wt/paving-aliasing` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/paving-aliasing`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
