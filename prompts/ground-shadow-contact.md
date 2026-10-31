# Wave 4 task: ground-shadow-contact (kind: new)

Branch `wt/ground-shadow-contact`, stills on `shots/ground-shadow-contact`.

Everything that stands on the ground meets it: ambient occlusion and contact shadow under cars (ContactShadows landed), bins, benches, people (a soft blob under each near pedestrian's feet), trees' trunks, planters, poles; darkened dirt / wear round the base of poles and hydrants (kerb_marks). No floating props: a probe that rays every FULL chunk prop to the ground and lists what floats more than 3 cm, then fix the placements. The probe lists what floats more than 3 cm or sinks more than 5 cm; fix the lift, never the roll.

If `origin/wt/ground-shadow-contact` already exists (an earlier launch of this task, or a paused session, pushed it), CONTINUE it: check it out and merge origin/main into it. Same for `shots/ground-shadow-contact`.
Push your branch as soon as you have a first commit and at least every hour; before the final push merge origin/main and pass `SHARDS=3 tests/headless_check.sh`. End with the report the brief asks for.
