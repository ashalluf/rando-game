# Wave 4 task: crowd-closeup-3 (kind: new)

Branch `wt/crowd-closeup-3`, stills on `shots/crowd-closeup-3`.

The crowd at 2-6 m, third pass: the garments' edges and seams, the shoes (one flat slab today: real trainers / boots with laces and soles on the crowd rigs through tools/crowd), hands with a thumb (no finger bones: a better hand mesh and texture), hair card edges, the walk's foot slide. Judge with crowd_lineup.gd and a Forward+ small scene. The crowd rig contract in CLAUDE.md (one Body surface, the region colours, 24 bones) must hold; rerun hat_fit.gd, life_clips.gd, gait_clips.gd, busk_clips.gd and face_fit.gd after any rig rebuild.

If `origin/wt/crowd-closeup-3` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/crowd-closeup-3`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
