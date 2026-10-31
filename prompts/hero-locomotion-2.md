# Wave 4 task: hero-locomotion-2 (kind: new)

Branch `wt/hero-locomotion-2`, stills on `shots/hero-locomotion-2`.

The hero's movement animation: walk / run / sprint transitions, a start and a stop animation, a turn in place, the strafe, the lean into a sprint turn, the land-and-run blend. The clips are Quaternius UAL (tools/hero/hero_clips.gd retargets them; add clips there). Blend trees in Avatar; no pop between clips; the gun stays in the hand through every move (HeroMotion's rules). Prove with tools/glshot/hero_moves_shot.gd strips. Another session (hero-closeup-2) owns the hero's materials and face; stay off those.

If `origin/wt/hero-locomotion-2` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/hero-locomotion-2`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
