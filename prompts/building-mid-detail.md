# Wave 4 task: building-mid-detail (kind: new)

Branch `wt/building-mid-detail`, stills on `shots/building-mid-detail`.

Generated buildings from 20-80 m: balconies with railings and furniture on midtown apartments, window AC units and satellite dishes, drainpipes and vents, roof edges' flashing, fire escapes, painted signs on side walls, a few windows open. Per-building hashes, the kit batch (per building) or the facade detail MultiMesh; LOD ring / far city untouched or cheaply mirrored. Measure with geo_count at the street_noon and golden_aerial refcams. Never Building._rng; keep the frame close to flat.

If `origin/wt/building-mid-detail` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/building-mid-detail`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
